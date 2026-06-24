#!/usr/bin/env bash
# install-hami.sh - install HAMi on the single-node cluster and verify it advertises
# shareable GPU memory. Run AFTER host-setup.sh + set-default-runtime.sh, with helm +
# kubectl on PATH and KUBECONFIG pointing at the cluster (from your laptop after
# fetch-kubeconfig.sh, or on the VM with KUBECONFIG=/etc/rancher/k3s/k3s.yaml).
#
# HAMi brings its OWN device plugin and must NOT coexist with NVIDIA's official one /
# the GPU Operator - this script refuses to run if it finds one. See:
#   https://project-hami.io/docs/v2.4.1/installation/prerequisites
#   https://github.com/Project-HAMi/HAMi/issues/1708   (Operator+HAMi: undocumented)
#
# The HAMi scheduler runs a kube-scheduler sidecar whose image tag must match the
# cluster's Kubernetes SERVER version - the #1 HAMi failure. This auto-detects it.
#
# VERSION-SENSITIVE - confirm against upstream before trusting:
#   HAMi install:  https://project-hami.io/docs/get-started/deploy-with-helm
#   HAMi releases: https://github.com/Project-HAMi/HAMi/releases
#
# Usage:
#   ./install-hami.sh
#   HAMI_VERSION=2.9.0 IMAGE_TAG=v1.31.5 ./install-hami.sh   # pin explicitly
set -euo pipefail

HAMI_VERSION="${HAMI_VERSION:-2.9.0}"
log() { printf '\n=== %s ===\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# On the VM, default to the k3s kubeconfig if none is set (host-setup.sh writes it 644).
if [[ -z "${KUBECONFIG:-}" && -r /etc/rancher/k3s/k3s.yaml ]]; then
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  echo "Using KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
fi

# helm: install it if missing (official installer; needs root/sudo to write /usr/local/bin).
if ! command -v helm >/dev/null; then
  log "helm not found - installing it (https://helm.sh/docs/intro/install/)"
  SUDO=""; [[ $EUID -ne 0 ]] && command -v sudo >/dev/null && SUDO="sudo"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | $SUDO bash \
    || die "helm install failed - install it manually then re-run."
fi

command -v kubectl >/dev/null || die "kubectl not found on PATH"
kubectl get nodes >/dev/null  || die "kubectl can't reach the cluster - set KUBECONFIG (see fetch-kubeconfig.sh)"

# --- refuse to coexist with another GPU device plugin ------------------------
log "Checking no NVIDIA device plugin / GPU Operator is present (HAMi must own it)"
if kubectl get pods -A 2>/dev/null | grep -iqE 'nvidia-device-plugin|gpu-operator|gpu-feature-discovery'; then
  kubectl get pods -A | grep -iE 'nvidia-device-plugin|gpu-operator|gpu-feature-discovery' || true
  die "found an existing NVIDIA device plugin / GPU Operator above. HAMi must not coexist with it.
       Use a fresh cluster (just host-setup.sh + set-default-runtime.sh), or remove it, then re-run."
fi
echo "none found - good."

# --- detect the Kubernetes server version for the scheduler image tag --------
if [[ -z "${IMAGE_TAG:-}" ]]; then
  if command -v jq >/dev/null; then
    raw="$(kubectl version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion')"
  else
    raw="$(kubectl version 2>/dev/null | sed -n 's/.*Server Version: \(v[0-9.]*\).*/\1/p' | head -1)"
  fi
  IMAGE_TAG="${raw%%+*}"   # strip k3s suffix, e.g. v1.35.5+k3s1 -> v1.35.5
fi
[[ "$IMAGE_TAG" == v* ]] || die "could not detect server version; set IMAGE_TAG=vX.Y.Z explicitly"
echo "Kubernetes server version → HAMi scheduler imageTag = $IMAGE_TAG"

# --- clear a stuck/failed previous release so a retry is clean ---------------
# A dropped connection (common when driving a remote API over a flaky link) can leave
# the release in pending-install/failed. helm upgrade --install won't recover from that,
# so remove it first.
if helm -n kube-system list -a --filter '^hami$' -o json 2>/dev/null | grep -qiE 'pending|failed'; then
  log "Previous 'hami' release is stuck (pending/failed) - removing before retry"
  helm -n kube-system uninstall hami 2>/dev/null || true
fi

# --- install HAMi ------------------------------------------------------------
log "Installing HAMi $HAMI_VERSION (kube-scheduler image tag $IMAGE_TAG)"
helm repo add hami-charts https://project-hami.github.io/HAMi >/dev/null
helm repo update hami-charts >/dev/null
helm upgrade --install hami hami-charts/hami \
  --version "$HAMI_VERSION" \
  -n kube-system \
  --set scheduler.kubeScheduler.imageTag="$IMAGE_TAG" \
  --wait --timeout 5m \
  || die "helm install failed. Inspect what went wrong:
       helm -n kube-system status hami
       kubectl -n kube-system get pods | grep -i hami
       Then fix the cause (often a scheduler imageTag mismatch) and re-run - this script
       auto-clears the failed release on the next run."

log "HAMi pods"
kubectl -n kube-system get pods | grep -i hami || echo "(no hami pods yet - check 'kubectl -n kube-system get pods')"

# --- verify HAMi registered the GPU -----------------------------------------
# HAMi advertises nvidia.com/gpu (= physical GPUs x deviceSplitCount, default 10) and
# records the shareable memory in the hami.io/node-nvidia-register annotation. It does
# NOT put nvidia.com/gpumem in node allocatable - the HAMi scheduler + webhook account
# gpumem/gpucores from that annotation, and HAMi-core enforces them per-pod.
log "Waiting for HAMi to register the GPU (nvidia.com/gpu + node-nvidia-register)"
gpu=""; reg=""
for _ in $(seq 1 30); do
  gpu="$(kubectl get nodes -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}' 2>/dev/null || true)"
  reg="$(kubectl get nodes -o jsonpath='{.items[0].metadata.annotations.hami\.io/node-nvidia-register}' 2>/dev/null || true)"
  [[ -n "$gpu" && "$gpu" != "0" && -n "$reg" ]] && break
  sleep 8
done
if [[ -n "$gpu" && "$gpu" != "0" && -n "$reg" ]]; then
  echo "OK: nvidia.com/gpu = $gpu (physical GPUs x split count)"
  echo "    node-nvidia-register: $reg"
else
  die "HAMi did not register the GPU (gpu='$gpu'). Check the device-plugin logs:
       kubectl -n kube-system get pods | grep -i hami      # find the device-plugin pod
       kubectl -n kube-system logs <hami-device-plugin-pod> --all-containers --tail=50
       Common causes: node not labelled gpu=on (host-setup.sh sets it), or the plugin
       can't access the GPU (driver/default runtime). The annotation should list devmem."
fi

cat <<EOF

=== HAMi ready ===
The node advertises nvidia.com/gpu and HAMi registered the card's memory (node-nvidia-register
annotation). gpumem/gpucores are accounted by the HAMi scheduler + enforced by HAMi-core,
not shown in node allocatable. Run the isolation exercises:
    kubectl apply -f manifests/share-two-pods.yaml
    kubectl wait --for=condition=Ready pod/hami-share-a pod/hami-share-b --timeout=300s
    ./scripts/probe-memory.sh hami-share-a
    ./scripts/probe-memory.sh hami-share-b
    kubectl apply -f manifests/oversubscribe-pending.yaml   # size per the manifest comment
    ./scripts/probe-mechanism.sh hami-share-a
Or capture all of it at once:  ./scripts/capture-evidence.sh
EOF

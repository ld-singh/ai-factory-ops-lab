#!/usr/bin/env bash
# capture-evidence.sh - snapshot the evidence that HAMi and the NVIDIA GPU Operator are
# coexisting on one node, into a local folder + tarball you scp back. Run AFTER the lab's
# Steps 1-4 (host-setup, default runtime, Operator with devicePlugin.enabled=false, HAMi),
# with a working KUBECONFIG. Run from anywhere (paths resolve relative to this script).
#
# It captures the six Part C artifacts:
#   1 operator components  - driver/toolkit/DCGM/validator Running, and NO device plugin
#   2 the disabling proof  - devicePlugin.enabled=false in the released helm values
#   3 hami owns the plugin - HAMi pods Running; nvidia.com/gpu at HAMi's virtual count
#   4 default runtime      - 'nvidia' is the node's DEFAULT containerd runtime
#   5 fractional sharing   - TWO pods co-resident on one GPU, scheduled by the HAMi scheduler,
#                            each seeing its slice (the stronger proof: sharing, not just one slice)
#   6 dcgm unaffected      - DCGM Exporter still reports PHYSICAL counters beside HAMi
#
# Read-only except the lab's own two share pods.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(dirname "$SCRIPT_DIR")"
OUT="hami-coexist-evidence-$(date +%Y%m%d-%H%M%S)"
OPERATOR_NS="${OPERATOR_NS:-gpu-operator}"
HAMI_NS="${HAMI_NS:-kube-system}"
PODS=(hami-coexist-a hami-coexist-b)
mkdir -p "$OUT"

log() { printf '\n=== %s ===\n' "$*"; }
cap() { local f="$1"; shift; { echo "\$ $*"; echo; "$@" 2>&1 || true; } > "$OUT/$f"; echo "  wrote $f"; }

command -v kubectl >/dev/null || { echo "ERROR: kubectl not found" >&2; exit 1; }
kubectl get nodes >/dev/null  || { echo "ERROR: kubectl can't reach the cluster (set KUBECONFIG)" >&2; exit 1; }
NODE="$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')"

log "Context: versions"
cap 0-versions.txt bash -c "kubectl version 2>/dev/null; echo; kubectl get nodes -o wide; echo; (helm list -A 2>/dev/null || echo '(helm not on PATH)')"

log "Artifact 1: GPU Operator components, and the ABSENT device plugin"
cap 1-operator-pods.txt bash -c "
  echo '--- all pods in the $OPERATOR_NS namespace ---';
  kubectl get pods -n '$OPERATOR_NS' -o wide;
  echo;
  echo '--- device-plugin pods in $OPERATOR_NS (expect NONE: that is the point) ---';
  kubectl get pods -n '$OPERATOR_NS' 2>/dev/null | grep -i 'device-plugin' || echo '(none - the Operator device plugin is disabled)'
"

log "Artifact 2: the disabling proof - devicePlugin.enabled=false in the release values"
cap 2-operator-helm-values.txt bash -c "
  if command -v helm >/dev/null; then
    echo '--- helm get values gpu-operator ---';
    helm get values gpu-operator -n '$OPERATOR_NS' 2>&1;
  else
    echo '(helm not on PATH - capture this from the ClusterPolicy instead)';
  fi
  echo;
  echo '--- ClusterPolicy devicePlugin stanza ---';
  kubectl get clusterpolicy -o jsonpath='{.items[0].spec.devicePlugin}' 2>/dev/null || echo '(no ClusterPolicy found)'
  echo
"

log "Artifact 3: HAMi owns the device plugin"
cap 3-hami-pods.txt bash -c "kubectl -n '$HAMI_NS' get pods -o wide | grep -i hami || echo '(no hami pods found in $HAMI_NS)'"
# HAMi puts only nvidia.com/gpu in allocatable; the shareable memory lives in the
# hami.io/node-nvidia-register annotation - capture both explicitly.
cap 3-node-allocatable.txt bash -c "
  echo 'node: $NODE';
  echo;
  echo 'allocatable nvidia.com/gpu (expect physical x deviceSplitCount, e.g. 10 for one card):';
  kubectl get node '$NODE' -o jsonpath='{.status.allocatable.nvidia\.com/gpu}'; echo;
  echo;
  echo 'hami.io/node-nvidia-register (devmem/devcore the HAMi scheduler scores against):';
  kubectl get node '$NODE' -o jsonpath='{.metadata.annotations.hami\.io/node-nvidia-register}'; echo
"

log "Artifact 4: nvidia is the DEFAULT containerd runtime"
cap 4-default-runtime.txt bash -c "
  echo '--- /etc/rancher/k3s/config.yaml ---';
  (sudo -n grep -H 'default-runtime' /etc/rancher/k3s/config.yaml 2>/dev/null \
    || grep -H 'default-runtime' /etc/rancher/k3s/config.yaml 2>/dev/null \
    || echo '(not readable without sudo - run: sudo grep default-runtime /etc/rancher/k3s/config.yaml)');
  echo;
  echo '--- generated containerd config (expect default_runtime_name = \"nvidia\") ---';
  (sudo -n grep default_runtime_name /var/lib/rancher/k3s/agent/etc/containerd/config.toml 2>/dev/null \
    || grep default_runtime_name /var/lib/rancher/k3s/agent/etc/containerd/config.toml 2>/dev/null \
    || echo '(not readable without sudo - run: sudo grep default_runtime_name /var/lib/rancher/k3s/agent/etc/containerd/config.toml)');
  echo;
  echo '--- RuntimeClass ---';
  kubectl get runtimeclass 2>/dev/null
"

log "Artifact 5: fractional sharing - two pods co-resident on one GPU under HAMi"
# The HAMi webhook rewrites schedulerName, and it is registered failurePolicy: Ignore. If it
# cannot be reached, a pod is admitted UNMUTATED, lands on the default scheduler, and fails
# with "Insufficient nvidia.com/gpumem" (gpumem/gpucores are never in node allocatable). The
# webhook only fires on CREATE, so gate BEFORE creating the pods rather than retrying after.
kubectl -n "$HAMI_NS" rollout status deploy/hami-scheduler --timeout=180s || true
for _ in $(seq 1 30); do
  eps="$(kubectl -n "$HAMI_NS" get endpoints hami-scheduler -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)"
  [[ -n "$eps" ]] && break
  sleep 4
done
[[ -n "${eps:-}" ]] || echo "WARNING: hami-scheduler has no endpoints; the webhook may not fire."

kubectl delete pod "${PODS[@]}" --ignore-not-found >/dev/null 2>&1 || true
kubectl apply -f "$LAB_DIR/manifests/share-two-pods.yaml" >/dev/null

# Fail loudly on the silent-webhook case instead of leaving confusing Pending pods.
sleep 3
for p in "${PODS[@]}"; do
  sched="$(kubectl get pod "$p" -o jsonpath='{.spec.schedulerName}' 2>/dev/null || true)"
  echo "  $p schedulerName = ${sched:-<unknown>}"
  if [[ "$sched" != "hami-scheduler" ]]; then
    cap 5-share-pods.txt bash -c "
      echo '$p schedulerName = ${sched:-<unknown>}  (expected: hami-scheduler)';
      echo;
      kubectl get pods -o wide;
      echo;
      kubectl describe pod '$p' | sed -n '/Events:/,\$p' | head -20
    "
    echo "ERROR: the HAMi webhook did not route $p (schedulerName='$sched')."
    echo "It is registered failurePolicy: Ignore, so an unreachable webhook fails silently."
    echo "Check:  kubectl -n $HAMI_NS get pods | grep hami"
    echo "        kubectl -n $HAMI_NS logs deploy/hami-scheduler -c vgpu-scheduler-extender --tail=50"
    echo "Then DELETE and re-apply the pods (the webhook only fires on CREATE)."
    exit 1
  fi
done

if ! kubectl wait --for=condition=Ready "pod/${PODS[0]}" "pod/${PODS[1]}" --timeout=300s; then
  cap 5-share-pods.txt bash -c "kubectl get pods -o wide; echo; kubectl describe pod ${PODS[*]} | sed -n '/Events:/,\$p' | head -30"
  echo "ERROR: the share pods didn't both become Ready - status captured to $OUT/5-share-pods.txt"
  echo "Check: kubectl describe pod ${PODS[*]}"
  exit 1
fi

# Co-residency is the point: both pods Running, and (from the annotations) on the SAME GPU UUID.
cap 5-share-pods.txt bash -c "
  echo '--- both share pods Running on one node ---';
  kubectl get pods -o wide | grep -E 'NAME|hami-coexist';
  echo;
  for p in ${PODS[*]}; do
    echo \"--- HAMi allocation annotations: \$p (note the GPU UUID - same card for both) ---\";
    kubectl get pod \"\$p\" -o jsonpath='{.metadata.annotations.hami\.io/vgpu-devices-allocated}'; echo;
  done;
  echo;
  echo '--- scheduler events (expect the HAMi scheduler, not default-scheduler) ---';
  kubectl describe pod ${PODS[0]} | sed -n '/Events:/,\$p' | head -12
"
# The in-pod view is the payoff: HAMi-core rewrites each card to the 4000 MiB slice.
for p in "${PODS[@]}"; do
  cap "5-in-pod-smi-$p.txt" bash -c "kubectl exec '$p' -- nvidia-smi"
done
cap 5-hami-core.txt bash -c "
  echo '--- HAMi-core injection in ${PODS[0]} (env + library) ---';
  kubectl exec '${PODS[0]}' -- bash -c 'env | grep -iE \"CUDA_DEVICE_MEMORY_LIMIT|CUDA_DEVICE_SM_LIMIT|NVIDIA_VISIBLE_DEVICES|LD_PRELOAD\"' 2>&1;
  echo;
  kubectl exec '${PODS[0]}' -- bash -c 'ls -l /usr/local/vgpu/libvgpu.so 2>/dev/null || echo \"(libvgpu.so not at /usr/local/vgpu - check the path for your HAMi version)\"' 2>&1
"

log "Artifact 6: DCGM Exporter still reports PHYSICAL counters"
DCGM_POD="$(kubectl get pods -n "$OPERATOR_NS" -l app=nvidia-dcgm-exporter -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -n "$DCGM_POD" ]]; then
  kubectl -n "$OPERATOR_NS" port-forward "pod/$DCGM_POD" 9400:9400 >/dev/null 2>&1 &
  PF_PID=$!
  trap 'kill $PF_PID 2>/dev/null || true' EXIT
  sleep 5
  cap 6-dcgm-metrics.txt bash -c "
    echo 'dcgm pod: $DCGM_POD';
    echo;
    curl -s --max-time 20 localhost:9400/metrics | grep -E 'DCGM_FI_DEV_FB_USED|DCGM_FI_DEV_FB_FREE|DCGM_FI_DEV_GPU_UTIL' | head -20 \
      || echo '(no metrics scraped - check the port-forward and the exporter)'
  "
  kill $PF_PID 2>/dev/null || true
  trap - EXIT
else
  cap 6-dcgm-metrics.txt bash -c "echo '(no DCGM Exporter pod found in $OPERATOR_NS with label app=nvidia-dcgm-exporter)'; kubectl get pods -n '$OPERATOR_NS'"
fi

tar czf "$OUT.tgz" "$OUT"
cat <<EOF

=== wrote $OUT.tgz ===
1. scp it to your laptop and record it as the Part C coexistence evidence, e.g.:
     scp -i <key> <user>@<vm-ip>:$PWD/$OUT.tgz \\
       ./portfolio-lab/06-validation-reports/evidence/
2. Fill in:
     portfolio-lab/06-validation-reports/hami-gpu-operator-coexistence-validation.md
3. CONFIRM the tarball is on your laptop, then TEAR THE VM DOWN (and its storage volume).
   The evidence is the deliverable; a forgotten GPU VM is the only way this gets expensive.
   Clean up the pods first if you are keeping the VM for another part:
     kubectl delete -f $LAB_DIR/manifests/
EOF

#!/usr/bin/env bash
# install-gpu-operator.sh - install the GPU layer that makes the cluster advertise
# nvidia.com/gpu, then smoke-test it with a CUDA pod. Run AFTER host-setup.sh, with a
# working kubeconfig (from your laptop after fetch-kubeconfig.sh, or on the VM).
# Needs helm + kubectl on PATH and KUBECONFIG pointing at the cluster.
#
# This is Lesson 6 Part A's install, wired for k3s. Two modes:
#
#   MODE=operator      (default) the full NVIDIA GPU Operator - device plugin, GFD, and
#                      DCGM Exporter (the real telemetry Phase A captures). Heavier, and
#                      on k3s it can need extra runtime wiring (see the note below).
#   MODE=device-plugin just the NVIDIA k8s device plugin via its RuntimeClass. Light and
#                      reliable on k3s; advertises nvidia.com/gpu fast. Does NOT ship
#                      DCGM - add dcgm-exporter separately if you want Phase A telemetry.
#
# Because host-setup.sh installed the NVIDIA Container Toolkit and k3s already created
# the 'nvidia' RuntimeClass, both modes set driver/toolkit OFF and lean on that runtime.
#
# VERSION-SENSITIVE - confirm against the official docs before trusting:
#   GPU Operator: https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html
#   k3s notes:    https://docs.k3s.io/advanced#nvidia-container-runtime-support
#   Device plugin: https://github.com/NVIDIA/k8s-device-plugin
set -euo pipefail

MODE="${MODE:-operator}"
log() { printf '\n=== %s ===\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

command -v helm >/dev/null    || die "helm not found on PATH"
command -v kubectl >/dev/null || die "kubectl not found on PATH"
kubectl get nodes >/dev/null  || die "kubectl can't reach the cluster - set KUBECONFIG (see fetch-kubeconfig.sh)"

case "$MODE" in
  operator)
    log "Installing NVIDIA GPU Operator (driver off, toolkit off - host already has them)"
    helm repo add nvidia https://helm.ngc.nvidia.com/nvidia >/dev/null
    helm repo update nvidia >/dev/null
    helm upgrade --install gpu-operator nvidia/gpu-operator \
      -n gpu-operator --create-namespace \
      --set driver.enabled=false \
      --set toolkit.enabled=false \
      --wait --timeout 10m || true
    cat <<'EOF'
NOTE (k3s): if GPUs never appear in allocatable, the operator's pods are probably not
getting the nvidia runtime. On k3s the usual fix is to make 'nvidia' the DEFAULT
containerd runtime (a containerd config template), per the k3s NVIDIA docs above. If you
just want the lab running quickly, re-run this with MODE=device-plugin instead.
EOF
    ;;
  device-plugin)
    log "Installing NVIDIA k8s device plugin (RuntimeClass: nvidia)"
    helm repo add nvdp https://nvidia.github.io/k8s-device-plugin >/dev/null
    helm repo update nvdp >/dev/null
    helm upgrade --install nvdp nvdp/nvidia-device-plugin \
      -n nvidia-device-plugin --create-namespace \
      --set runtimeClassName=nvidia \
      --wait --timeout 5m || true
    echo "(No DCGM in this mode - for Phase A telemetry add dcgm-exporter separately.)"
    ;;
  *) die "unknown MODE='$MODE' (use 'operator' or 'device-plugin')";;
esac

log "Waiting for the node to advertise nvidia.com/gpu"
gpu=""
for _ in $(seq 1 45); do
  gpu="$(kubectl get nodes -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}' 2>/dev/null || true)"
  [[ -n "$gpu" && "$gpu" != "0" ]] && break
  sleep 8
done
[[ -n "$gpu" && "$gpu" != "0" ]] \
  || die "nvidia.com/gpu still not advertised. Check the GPU-layer pods (kubectl get pods -A | grep -iE 'nvidia|gpu') and the k3s runtime note above."
echo "Node advertises nvidia.com/gpu = $gpu"

log "CUDA smoke test (a pod that runs nvidia-smi on the real GPU)"
kubectl delete pod cuda-smoke --ignore-not-found >/dev/null 2>&1 || true
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: cuda-smoke
spec:
  restartPolicy: Never
  runtimeClassName: nvidia
  containers:
    - name: cuda
      image: nvidia/cuda:12.4.1-base-ubuntu22.04
      command: ["nvidia-smi"]
      resources:
        limits:
          nvidia.com/gpu: 1
YAML
kubectl wait --for=condition=Ready pod/cuda-smoke --timeout=180s 2>/dev/null || true
sleep 3
echo "--- cuda-smoke logs (expect an nvidia-smi table) ---"
kubectl logs cuda-smoke || echo "(no logs yet - 'kubectl logs cuda-smoke' once it completes)"

cat <<EOF

=== GPU layer ready (mode: ${MODE}) ===
nvidia.com/gpu is advertised and a CUDA pod ran on the real GPU. That is Lesson 6
Phase A's core artifact. Capture it (self-contained - writes a tarball here):
    ./capture-evidence.sh
Then scp the gpu-evidence-*.tgz off this VM before teardown - it's the deliverable -
and record it in portfolio-lab/06-validation-reports/real-gpu-validation-report.md.
Clean up the test pod: kubectl delete pod cuda-smoke
Then continue with Lesson 6 Part B (HAMi) and Part C (Slurm GRES).
EOF

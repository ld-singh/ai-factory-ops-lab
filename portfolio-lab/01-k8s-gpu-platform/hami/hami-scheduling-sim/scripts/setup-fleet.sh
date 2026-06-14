#!/usr/bin/env bash
# setup-fleet.sh - make the cluster's worker nodes advertise nvidia.com/gpu with no
# hardware, using run.ai's fake-gpu-operator (the approach in the official HAMi
# local-fake-gpu tutorial). The operator's status-updater patches nvidia.com/gpu into
# each labeled node's status directly via the API (no kubelet/driver needed).
#
# Why this chart source: the run.ai JFrog 'prod' chart patches nvidia.com/gpu. The
# ghcr.io OCI build is DRA-oriented and does not, so the scheduler would see 0 GPUs.
set -euo pipefail

FGO_VERSION="${FGO_VERSION:-0.0.59}"
FGO_NS="${FGO_NS:-gpu-operator}"
FGO_REPO="${FGO_REPO:-https://runai.jfrog.io/artifactory/api/helm/fake-gpu-operator-charts-prod}"
GPU_PRODUCT="${GPU_PRODUCT:-NVIDIA-H100-80GB-HBM3}"
GPU_COUNT="${GPU_COUNT:-8}"
GPU_MEMORY="${GPU_MEMORY:-81920}"

echo "Installing fake-gpu-operator ${FGO_VERSION} (pool 'default': ${GPU_COUNT}x ${GPU_PRODUCT})..."
helm repo add fake-gpu-operator "$FGO_REPO" --force-update >/dev/null
helm repo update fake-gpu-operator >/dev/null
helm upgrade -i gpu-operator fake-gpu-operator/fake-gpu-operator \
  -n "$FGO_NS" --create-namespace \
  --version "$FGO_VERSION" \
  --set "topology.nodePools.default.gpuCount=${GPU_COUNT}" \
  --set "topology.nodePools.default.gpuProduct=${GPU_PRODUCT}" \
  --set "topology.nodePools.default.gpuMemory=${GPU_MEMORY}" \
  --wait --timeout 4m
kubectl -n "$FGO_NS" rollout status deploy/status-updater --timeout=120s

echo "Waiting for nvidia.com/gpu to appear on the pool nodes..."
for _ in $(seq 1 30); do
  got=$(kubectl get nodes -l run.ai/simulated-gpu-node-pool=default \
        -o jsonpath='{range .items[*]}{.status.allocatable.nvidia\.com/gpu}{" "}{end}' 2>/dev/null)
  [[ "$got" == *"${GPU_COUNT}"* ]] && break
  sleep 4
done
kubectl get nodes -l run.ai/simulated-gpu-node-pool=default \
  -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\\.com/gpu --no-headers

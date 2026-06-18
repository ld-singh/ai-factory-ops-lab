#!/usr/bin/env bash
# install-fake-gpu-operator.sh - install run.ai's fake-gpu-operator with the lesson's
# three GPU pools. The operator advertises nvidia.com/gpu on the KWOK fake nodes
# (no hardware), runs a KWOK-aware device plugin, and stands up a per-node DCGM
# exporter that emits DCGM_FI_* metrics with per-pod GPU attribution. That metrics
# stream is the bridge to Lesson 3 (observability).
#
# fake-gpu-operator is DESIGNED to sit on top of KWOK: KWOK provides the kubelet-less
# nodes at scale, the operator provides the GPU simulation layer. They are
# complementary, not alternatives.
#
# SIMULATION SCOPE: still no GPU. The advertised GPUs, the device plugin, and the
# DCGM metrics are all synthetic. Pods on KWOK nodes are simulated (no real container
# runtime), so there is no real nvidia-smi or CUDA. This proves the control plane
# and the observability pipeline shape, nothing below the kubelet.
set -euo pipefail

FGO_VERSION="${FGO_VERSION:-0.0.59}"
FGO_NS="${FGO_NS:-gpu-operator}"
FGO_REPO="${FGO_REPO:-https://runai.jfrog.io/artifactory/api/helm/fake-gpu-operator-charts-prod}"

echo "Installing fake-gpu-operator ${FGO_VERSION} with pools a100 / h100 / l40s ..."
helm repo add fake-gpu-operator "$FGO_REPO" --force-update >/dev/null
helm repo update fake-gpu-operator >/dev/null

# Topology pools must match the run.ai/simulated-gpu-node-pool labels the node script
# sets. gpuMemory is MiB. Use the JFrog 'prod' chart: the ghcr.io OCI build is
# DRA-oriented and does not populate nvidia.com/gpu.
helm upgrade -i gpu-operator fake-gpu-operator/fake-gpu-operator \
  -n "$FGO_NS" --create-namespace --version "$FGO_VERSION" \
  --set 'topology.nodePools.a100.gpuCount=8' \
  --set 'topology.nodePools.a100.gpuProduct=NVIDIA-A100-SXM4-80GB' \
  --set 'topology.nodePools.a100.gpuMemory=81920' \
  --set 'topology.nodePools.h100.gpuCount=8' \
  --set 'topology.nodePools.h100.gpuProduct=NVIDIA-H100-80GB-HBM3' \
  --set 'topology.nodePools.h100.gpuMemory=81920' \
  --set 'topology.nodePools.l40s.gpuCount=4' \
  --set 'topology.nodePools.l40s.gpuProduct=NVIDIA-L40S' \
  --set 'topology.nodePools.l40s.gpuMemory=46068' \
  --wait --timeout 5m

kubectl -n "$FGO_NS" rollout status deploy/status-updater --timeout=120s
echo "fake-gpu-operator ready."

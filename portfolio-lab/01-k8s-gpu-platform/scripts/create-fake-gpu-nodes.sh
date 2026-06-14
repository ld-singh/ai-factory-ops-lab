#!/usr/bin/env bash
# create-fake-gpu-nodes.sh - stamp out fake GPU node pools (idempotent: kubectl apply).
#
# Pools (must match the topology in install-fake-gpu-operator.sh):
#   a100: 2 nodes x 8 GPU   (NVIDIA-A100-SXM4-80GB)
#   h100: 1 node  x 8 GPU   (NVIDIA-H100-80GB-HBM3)
#   l40s: 2 nodes x 4 GPU   (NVIDIA-L40S)
#   Total: 5 nodes, 32 GPUs.
#
# These are KWOK fake nodes (pure API objects, no kubelet). We do NOT hand-write
# nvidia.com/gpu here: the fake-gpu-operator advertises it from each pool's topology,
# keyed off the run.ai/simulated-gpu-node-pool label below. That makes the
# advertisement operator-shaped (a device plugin, like production) and gives us a
# per-node DCGM exporter for free (the bridge to Lesson 4). The gpu-pool label is what
# the demo workloads' nodeSelectors target.
#
# SIMULATION SCOPE: KWOK fake nodes + synthetic GPU advertisement. Proves scheduler
# behaviour and the observability pipeline shape only. No kubelet, driver, CUDA, or
# real telemetry; pods on KWOK nodes are simulated (no real nvidia-smi).
set -euo pipefail

create_pool() {
  local pool="$1" count="$2" product="$3"
  for i in $(seq 0 $((count - 1))); do
    local name="kwok-gpu-${pool}-${i}"
    kubectl apply -f - <<NODE
apiVersion: v1
kind: Node
metadata:
  name: ${name}
  annotations:
    kwok.x-k8s.io/node: fake
    node.alpha.kubernetes.io/ttl: "0"
  labels:
    kubernetes.io/arch: amd64
    kubernetes.io/os: linux
    kubernetes.io/hostname: ${name}
    node-role.kubernetes.io/gpu-worker: ""
    type: kwok
    gpu-pool: ${pool}
    # The operator advertises GPUs for nodes carrying this pool label:
    run.ai/simulated-gpu-node-pool: ${pool}
    # GFD-style product label (the operator advertises the count; we keep this for
    # pool targeting/display, matching what GPU Feature Discovery sets on real nodes):
    nvidia.com/gpu.product: ${product}
spec:
  taints:
    - key: kwok.x-k8s.io/node
      value: fake
      effect: NoSchedule
status:
  allocatable:
    cpu: "96"
    memory: 1024Gi
    pods: "110"
  capacity:
    cpu: "96"
    memory: 1024Gi
    pods: "110"
  nodeInfo:
    architecture: amd64
    operatingSystem: linux
    kubeletVersion: fake
    kubeProxyVersion: fake
    containerRuntimeVersion: fake
NODE
  done
}

#           pool  count product
create_pool a100  2     NVIDIA-A100-SXM4-80GB
create_pool h100  1     NVIDIA-H100-80GB-HBM3
create_pool l40s  2     NVIDIA-L40S

echo
echo "Waiting for the fake-gpu-operator to advertise nvidia.com/gpu on the pools..."
ok=0
for _ in $(seq 1 30); do
  if [[ -n "$(kubectl get node kwok-gpu-a100-0 -o jsonpath='{.status.allocatable.nvidia\.com/gpu}' 2>/dev/null)" ]]; then
    ok=1; break
  fi
  sleep 5
done

echo
echo "Fake GPU fleet:"
kubectl get nodes -l type=kwok \
  -o custom-columns='NAME:.metadata.name,POOL:.metadata.labels.gpu-pool,PRODUCT:.metadata.labels.nvidia\.com/gpu\.product,GPUS:.status.allocatable.nvidia\.com/gpu'
if [[ "$ok" -ne 1 ]]; then
  echo
  echo "WARN: GPUs not advertised yet. Is the operator installed? (install-fake-gpu-operator.sh)"
  echo "Check: kubectl -n gpu-operator get pods"
fi

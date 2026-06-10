#!/usr/bin/env bash
# create-fake-gpu-nodes.sh — stamp out fake GPU node pools (idempotent: kubectl apply).
#
# Pools (see ../kwok/README.md):
#   a100: 2 nodes x 8 GPU   (NVIDIA-A100-SXM4-80GB)
#   h100: 1 node  x 8 GPU   (NVIDIA-H100-80GB-HBM3)
#   l40s: 2 nodes x 4 GPU   (NVIDIA-L40S)
#
# SIMULATION HONESTY: these are KWOK fake nodes. They prove scheduler behaviour
# only — no kubelet, no driver, no CUDA, no DCGM.
set -euo pipefail

create_pool() {
  local pool="$1" count="$2" gpus="$3" product="$4" cpu="$5" mem="$6"
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
    nvidia.com/gpu.product: ${product}
    nvidia.com/gpu.count: "${gpus}"
spec:
  taints:
    - key: kwok.x-k8s.io/node
      value: fake
      effect: NoSchedule
status:
  allocatable:
    cpu: "${cpu}"
    memory: ${mem}
    pods: "110"
    nvidia.com/gpu: "${gpus}"
  capacity:
    cpu: "${cpu}"
    memory: ${mem}
    pods: "110"
    nvidia.com/gpu: "${gpus}"
  nodeInfo:
    architecture: amd64
    operatingSystem: linux
    kubeletVersion: fake
    kubeProxyVersion: fake
    containerRuntimeVersion: fake
NODE
  done
}

#           pool  count gpus product                     cpu   mem
create_pool a100  2     8    NVIDIA-A100-SXM4-80GB       96    1024Gi
create_pool h100  1     8    NVIDIA-H100-80GB-HBM3       112   2048Gi
create_pool l40s  2     4    NVIDIA-L40S                 64    512Gi

echo
echo "Fake GPU fleet:"
kubectl get nodes -l type=kwok \
  -o custom-columns='NAME:.metadata.name,POOL:.metadata.labels.gpu-pool,PRODUCT:.metadata.labels.nvidia\.com/gpu\.product,GPUS:.status.allocatable.nvidia\.com/gpu'

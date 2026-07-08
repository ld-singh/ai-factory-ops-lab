#!/usr/bin/env bash
set -euo pipefail

TOPOLOGY="${TOPOLOGY:-${1:-topology/small.json}}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LESSON_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

if [[ "$TOPOLOGY" != /* && ! -f "$TOPOLOGY" && -f "${LESSON_DIR}/${TOPOLOGY}" ]]; then
  TOPOLOGY="${LESSON_DIR}/${TOPOLOGY}"
fi

if [[ ! -f "$TOPOLOGY" ]]; then
  echo "Topology file not found: $TOPOLOGY" >&2
  exit 1
fi

total_nodes="$(jq '[.pools[].nodes] | add' "$TOPOLOGY")"
total_gpus="$(jq '[.pools[] | (.nodes * .gpusPerNode)] | add' "$TOPOLOGY")"

echo "Creating KWOK fake GPU nodes from $TOPOLOGY"
echo "Planned scale: ${total_nodes} fake nodes, ${total_gpus} fake GPUs"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

jq -r '
  .pools
  | to_entries[]
  | [
      .key,
      (.value.nodes | tostring),
      (.value.product),
      ((.value.cpu // 96) | tostring),
      ((.value.memory // "1024Gi") | tostring)
    ]
  | @tsv
' "$TOPOLOGY" | while IFS=$'\t' read -r pool count product cpu memory; do
  for i in $(seq 0 $((count - 1))); do
    name="kwok-scale-${pool}-${i}"
    cat >> "$tmp" <<NODE
---
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
    ai-factory-ops-lab/lesson: "7"
    ai-factory-ops-lab/scale-sim: "true"
    run.ai/simulated-gpu-node-pool: ${pool}
    nvidia.com/gpu.product: ${product}
spec:
  taints:
    - key: kwok.x-k8s.io/node
      value: fake
      effect: NoSchedule
status:
  allocatable:
    cpu: "${cpu}"
    memory: ${memory}
    pods: "110"
  capacity:
    cpu: "${cpu}"
    memory: ${memory}
    pods: "110"
  nodeInfo:
    architecture: amd64
    operatingSystem: linux
    kubeletVersion: fake
    kubeProxyVersion: fake
    containerRuntimeVersion: fake
NODE
  done
done

kubectl apply -f "$tmp"

echo
echo "Waiting for fake-gpu-operator to advertise nvidia.com/gpu..."
ok=0
for _ in $(seq 1 60); do
  advertised="$(kubectl get nodes -l ai-factory-ops-lab/scale-sim=true -o json \
    | jq '[.items[] | select(.status.allocatable["nvidia.com/gpu"] != null)] | length')"
  if [[ "$advertised" == "$total_nodes" ]]; then
    ok=1
    break
  fi
  sleep 5
done

echo
kubectl get nodes -l ai-factory-ops-lab/scale-sim=true \
  -o custom-columns='NAME:.metadata.name,POOL:.metadata.labels.gpu-pool,PRODUCT:.metadata.labels.nvidia\.com/gpu\.product,GPUS:.status.allocatable.nvidia\.com/gpu' | head -50

if [[ "$total_nodes" -gt 50 ]]; then
  echo "... output truncated; total fake scale nodes: $total_nodes"
fi

if [[ "$ok" -ne 1 ]]; then
  echo
  echo "ERROR: not every scale node has nvidia.com/gpu yet."
  echo "Check: kubectl -n gpu-operator get pods"
  echo "Set ALLOW_PARTIAL_GPU_ADVERTISE=1 to keep going for debugging."
  if [[ "${ALLOW_PARTIAL_GPU_ADVERTISE:-0}" != "1" ]]; then
    exit 1
  fi
fi

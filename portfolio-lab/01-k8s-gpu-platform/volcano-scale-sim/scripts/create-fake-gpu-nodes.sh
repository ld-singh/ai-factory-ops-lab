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
planned="$(mktemp)"
trap 'rm -f "$tmp" "$planned"' EXIT

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
    ai-factory-ops-lab/lesson: "1D"
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

# Fake nodes from a previous run of a *different* topology keep the scale-sim
# label, so they stay part of this fleet: they inflate the GPU pool until the
# overflow scenario (sized from the topology file) fits and schedules instead of
# staying Pending, which silently destroys the point of the lesson. Switching
# topologies is a documented workflow, so reconcile rather than refuse.
awk '/^  name: /{print $2}' "$tmp" | sort -u > "$planned"
stale="$(kubectl get nodes -l ai-factory-ops-lab/scale-sim=true \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
  | sort -u | comm -23 - "$planned" || true)"

if [[ -n "$stale" ]]; then
  stale_count="$(echo "$stale" | wc -l | tr -d ' ')"
  echo
  echo "Found ${stale_count} fake scale node(s) from a previous topology:"
  echo "$stale" | sed 's/^/  /' | head -10
  [[ "$stale_count" -gt 10 ]] && echo "  ... and $((stale_count - 10)) more"
  if [[ "${KEEP_STALE_NODES:-0}" == "1" ]]; then
    echo "KEEP_STALE_NODES=1: leaving them in place."
    echo "WARNING: they still count toward this fleet, so the overflow-gang"
    echo "scenario may schedule instead of staying Pending. Evidence captured"
    echo "from this cluster will not demonstrate gang scheduling."
  else
    echo "Removing them so this fleet matches ${TOPOLOGY}."
    echo "(set KEEP_STALE_NODES=1 to keep them)"
    echo "$stale" | xargs -r kubectl delete node
  fi
fi

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

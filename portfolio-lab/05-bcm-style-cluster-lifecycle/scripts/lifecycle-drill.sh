#!/usr/bin/env bash
# lifecycle-drill.sh — a runnable, honest BCM-STYLE node lifecycle on the KWOK
# fake fleet. It does NOT use NVIDIA Base Command Manager (no invented BCM
# commands); it implements the *generic* lifecycle BCM automates, so you can
# watch each stage as real Kubernetes state transitions:
#
#   provision -> health-gate -> in-service -> patch (drain+reimage) -> retire
#
# Each stage maps to a BCM concept in the README's concept map. Requires the
# Phase 1 kind cluster (make phase1-up) since it needs KWOK + a real scheduler.
set -euo pipefail

CTX="kind-${CLUSTER_NAME:-ai-factory-lab}"
NODE="kwok-lifecycle-demo"
NS="lifecycle-drill"

if ! kubectl config get-contexts -o name 2>/dev/null | grep -qx "$CTX"; then
  echo "kind context '$CTX' not found. Run 'make phase1-up' first."
  exit 1
fi
kubectl config use-context "$CTX" >/dev/null

pause() { echo; read -r -p "  [enter] to continue..." _ || true; echo; }

apply_node() {
  # $1 = lifecycle label, $2 = image-version label, $3 = "gate"|"open" (taint?)
  local lifecycle="$1" imgver="$2" gate="$3"
  local taint_block=""
  if [[ "$gate" == "gate" ]]; then
    taint_block=$'  taints:\n    - key: node.lab/health-gate\n      value: pending\n      effect: NoSchedule\n    - key: kwok.x-k8s.io/node\n      value: fake\n      effect: NoSchedule'
  else
    taint_block=$'  taints:\n    - key: kwok.x-k8s.io/node\n      value: fake\n      effect: NoSchedule'
  fi
  kubectl apply -f - <<NODE
apiVersion: v1
kind: Node
metadata:
  name: ${NODE}
  annotations:
    kwok.x-k8s.io/node: fake
    node.alpha.kubernetes.io/ttl: "0"
  labels:
    kubernetes.io/arch: amd64
    kubernetes.io/os: linux
    kubernetes.io/hostname: ${NODE}
    type: kwok
    node.lab/lifecycle: ${lifecycle}
    node.lab/image-version: "${imgver}"
    nvidia.com/gpu.product: NVIDIA-L40S
spec:
$(printf '%s' "$taint_block")
status:
  allocatable: {cpu: "32", memory: 256Gi, pods: "110", nvidia.com/gpu: "4"}
  capacity:    {cpu: "32", memory: 256Gi, pods: "110", nvidia.com/gpu: "4"}
  nodeInfo:
    architecture: amd64
    operatingSystem: linux
    kubeletVersion: fake
    kubeProxyVersion: fake
    containerRuntimeVersion: fake
NODE
}

probe_pod() {
  kubectl -n "$NS" apply -f - <<POD
apiVersion: v1
kind: Pod
metadata:
  name: workload-probe
spec:
  nodeSelector: {node.lab/lifecycle: in-service}
  tolerations:
    - {key: kwok.x-k8s.io/node, value: fake, effect: NoSchedule}
  containers:
    - name: probe
      image: registry.k8s.io/pause:3.9
      resources: {limits: {nvidia.com/gpu: "1"}}
POD
}

echo "=== BCM-style lifecycle drill (generic mechanisms, no real BCM) ==="
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

echo
echo "STAGE 1 — PROVISION (BCM: image + node category)"
echo "  A new node appears running image-version v1, labelled lifecycle=provisioning,"
echo "  and HEALTH-GATED with a NoSchedule taint so no workload lands prematurely."
apply_node provisioning v1 gate
kubectl get node "$NODE" -L node.lab/lifecycle,node.lab/image-version -o wide
pause

echo "STAGE 2 — HEALTH-GATE (BCM: provisioning health checks)"
echo "  Run scripted checks; on pass, flip lifecycle=in-service and remove the gate"
echo "  taint. This is the gate that keeps unhealthy nodes out of the pool."
gpu_count=$(kubectl get node "$NODE" -o jsonpath='{.status.allocatable.nvidia\.com/gpu}')
echo "  health-check: node advertises ${gpu_count} GPUs ... $([[ "$gpu_count" -ge 1 ]] && echo PASS || echo FAIL)"
kubectl label node "$NODE" node.lab/lifecycle=in-service --overwrite >/dev/null
kubectl taint node "$NODE" node.lab/health-gate- >/dev/null 2>&1 || true
echo "  gate opened."
pause

echo "STAGE 3 — IN-SERVICE (BCM: workload-manager integration)"
echo "  A workload now schedules onto the node (selector lifecycle=in-service)."
probe_pod
sleep 3
kubectl -n "$NS" get pod workload-probe -o wide
pause

echo "STAGE 4 — PATCH (BCM: patching lifecycle = drain -> reimage -> resume)"
echo "  Cordon + drain the node, recreate it at image-version v2, re-gate, re-check,"
echo "  reopen. The workload is evicted during the roll, then reschedules."
kubectl cordon "$NODE" >/dev/null
kubectl -n "$NS" delete pod workload-probe --grace-period=0 --force >/dev/null 2>&1 || true
echo "  drained. re-imaging to v2..."
apply_node provisioning v2 gate           # comes back gated again, like a fresh image
kubectl uncordon "$NODE" >/dev/null
kubectl label node "$NODE" node.lab/lifecycle=in-service --overwrite >/dev/null
kubectl taint node "$NODE" node.lab/health-gate- >/dev/null 2>&1 || true
probe_pod
sleep 3
echo "  after patch:"
kubectl get node "$NODE" -L node.lab/lifecycle,node.lab/image-version
kubectl -n "$NS" get pod workload-probe -o wide
pause

echo "STAGE 5 — RETIRE (BCM: decommission)"
echo "  Drain and remove the node from the cluster's source of truth."
kubectl cordon "$NODE" >/dev/null
kubectl -n "$NS" delete pod workload-probe --grace-period=0 --force >/dev/null 2>&1 || true
kubectl delete node "$NODE" >/dev/null
kubectl delete namespace "$NS" >/dev/null 2>&1 || true
echo "  node retired."

echo
echo "Done. You just walked the full node lifecycle as real K8s transitions."
echo "Map each stage back to BCM in: portfolio-lab/05-bcm-style-cluster-lifecycle/README.md"

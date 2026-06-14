#!/usr/bin/env bash
# lib.sh - shared helpers for the KAI Scheduler demos. Sourced by the demo scripts.
set -euo pipefail

NS="${KAI_DEMO_NS:-kai-demo}"

# gpu_workload <name> <queue> <replicas> [min-member]
# Emit + apply a Deployment of single-GPU pods scheduled by KAI into <queue>.
# Pods are pause containers: no CUDA, control-plane scheduling only. They tolerate
# the KWOK fake-node taint so they land on the simulated GPU fleet. If [min-member]
# is given, the pods carry the gang annotation so KAI binds all-or-none.
gpu_workload() {
  local name="$1" queue="$2" replicas="$3" min_member="${4:-}"
  local gang_anno=""
  if [[ -n "$min_member" ]]; then
    gang_anno="        kai.scheduler/batch-min-member: \"${min_member}\""
  fi
  kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${name}
  namespace: ${NS}
spec:
  replicas: ${replicas}
  selector:
    matchLabels:
      app: ${name}
  template:
    metadata:
      labels:
        app: ${name}
        kai.scheduler/queue: ${queue}
      annotations:
${gang_anno}
    spec:
      schedulerName: kai-scheduler
      terminationGracePeriodSeconds: 0
      # Land on any GPU node in the shared Lesson 1 fleet (a100/h100/l40s). The kwok
      # toleration is what confines these to the fake nodes.
      tolerations:
        - key: kwok.x-k8s.io/node
          operator: Equal
          value: fake
          effect: NoSchedule
      containers:
        - name: app
          image: registry.k8s.io/pause:3.9
          resources:
            limits:
              nvidia.com/gpu: 1
YAML
}

# counts <label-app> - print "<running> running, <pending> pending" for a workload.
counts() {
  local app="$1" running pending
  running=$(kubectl get pods -n "$NS" -l "app=${app}" --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')
  pending=$(kubectl get pods -n "$NS" -l "app=${app}" --field-selector=status.phase=Pending -o name 2>/dev/null | wc -l | tr -d ' ')
  echo "${running} running, ${pending} pending"
}

# wait_settle [seconds] - give the scheduler time to act.
wait_settle() { sleep "${1:-8}"; }

ensure_ns() {
  kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
}

# free_gpus - free GPUs on the shared Lesson 1 fleet (the KWOK GPU nodes):
# sum(allocatable on type=kwok nodes) - sum(running gpu pods on kwok-gpu-* nodes).
free_gpus() {
  local total used
  total=$(kubectl get nodes -l type=kwok -o json \
    | jq '[.items[].status.allocatable["nvidia.com/gpu"] // "0" | tonumber] | add // 0')
  used=$(kubectl get pods -A --field-selector=status.phase=Running -o json \
    | jq '[.items[] | select(.spec.nodeName | test("kwok-gpu-")) | .spec.containers[].resources.limits["nvidia.com/gpu"] // "0" | tonumber] | add // 0')
  echo $((total - used))
}

# clean_demo - remove all demo workloads in the namespace (keeps queues + cluster).
clean_demo() {
  kubectl delete deploy -n "$NS" --all --ignore-not-found >/dev/null 2>&1 || true
}

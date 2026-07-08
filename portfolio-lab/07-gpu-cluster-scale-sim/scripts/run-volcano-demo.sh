#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-gpu-scale}"
FIT_REPLICAS="${FIT_REPLICAS:-16}"
OVERFLOW_REPLICAS="${OVERFLOW_REPLICAS:-120}"
B200_REPLICAS="${B200_REPLICAS:-4}"

kubectl get ns volcano-system >/dev/null 2>&1 || {
  echo "Volcano is not installed. Run: make volcano-up" >&2
  exit 1
}

kubectl create ns "$NS" --dry-run=client -o yaml | kubectl apply -f -

echo "Creating Volcano queues..."
kubectl apply -f - <<YAML
apiVersion: scheduling.volcano.sh/v1beta1
kind: Queue
metadata:
  name: team-a
spec:
  weight: 1
  reclaimable: true
---
apiVersion: scheduling.volcano.sh/v1beta1
kind: Queue
metadata:
  name: team-b
spec:
  weight: 1
  reclaimable: true
YAML

create_podgroup() {
  local name="$1" replicas="$2" queue="$3"
  kubectl -n "$NS" apply -f - <<YAML
apiVersion: scheduling.volcano.sh/v1beta1
kind: PodGroup
metadata:
  name: ${name}
spec:
  minMember: ${replicas}
  queue: ${queue}
YAML
}

create_gpu_pods() {
  local name="$1" replicas="$2" queue="$3" selector_key="${4:-}" selector_value="${5:-}"

  create_podgroup "$name" "$replicas" "$queue"

  tmp="$(mktemp)"
  for i in $(seq 0 $((replicas - 1))); do
    cat >> "$tmp" <<YAML
---
apiVersion: v1
kind: Pod
metadata:
  name: ${name}-${i}
  namespace: ${NS}
  labels:
    app: ${name}
  annotations:
    scheduling.volcano.sh/group-name: ${name}
spec:
  schedulerName: volcano
  restartPolicy: Never
  tolerations:
    - key: kwok.x-k8s.io/node
      operator: Equal
      value: fake
      effect: NoSchedule
  nodeSelector:
    type: kwok
YAML
    if [[ -n "$selector_key" ]]; then
      cat >> "$tmp" <<YAML
    ${selector_key}: ${selector_value}
YAML
    fi
    cat >> "$tmp" <<YAML
  containers:
    - name: main
      image: registry.k8s.io/pause:3.9
      resources:
        limits:
          nvidia.com/gpu: "1"
        requests:
          nvidia.com/gpu: "1"
YAML
  done

  kubectl apply -f "$tmp"
  rm -f "$tmp"
}

echo
echo "Scenario 1: fit-gang (${FIT_REPLICAS} pods x 1 GPU)"
create_gpu_pods fit-gang "$FIT_REPLICAS" team-a

echo
echo "Scenario 2: overflow-gang (${OVERFLOW_REPLICAS} pods x 1 GPU)"
create_gpu_pods overflow-gang "$OVERFLOW_REPLICAS" team-b

echo
echo "Scenario 3: needs-b200 (${B200_REPLICAS} pods x 1 GPU, missing pool)"
create_gpu_pods needs-b200 "$B200_REPLICAS" team-a gpu-pool b200

echo
echo "Waiting briefly for scheduling events..."
sleep 15

echo
echo "Queues:"
kubectl get queue

echo
echo "PodGroups:"
kubectl get podgroups -n "$NS"

echo
echo "Pods:"
kubectl get pods -n "$NS" -o wide | head -80

echo
echo "Recent events:"
kubectl get events -n "$NS" --sort-by=.lastTimestamp | tail -40

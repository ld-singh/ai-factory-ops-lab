#!/usr/bin/env bash
# run-scheduling-demo.sh — deploy the four demo scenarios and show their state.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKLOADS="${SCRIPT_DIR}/../workloads"

kubectl apply -f "${WORKLOADS}/namespace.yaml"
kubectl apply -f "${WORKLOADS}/gpu-pod-schedulable.yaml"
kubectl apply -f "${WORKLOADS}/gpu-pod-pending-capacity.yaml"
kubectl apply -f "${WORKLOADS}/gpu-pod-pending-selector.yaml"
kubectl apply -f "${WORKLOADS}/gpu-deployment-queue-pressure.yaml"

echo
echo "Waiting briefly for the scheduler to act..."
sleep 8

echo
echo "=== Pods (note which are Running vs Pending, and why) ==="
kubectl get pods -n gpu-demo -o wide

echo
echo "=== Recent scheduling events ==="
kubectl get events -n gpu-demo --sort-by=.lastTimestamp | tail -20

echo
echo "Triage the Pending pods yourself:"
echo "  kubectl describe pod -n gpu-demo cuda-train-16gpu     # Insufficient nvidia.com/gpu"
echo "  kubectl describe pod -n gpu-demo cuda-needs-b200      # no node matches selector"
echo "Then capture evidence: make phase1-evidence (from repo root)"

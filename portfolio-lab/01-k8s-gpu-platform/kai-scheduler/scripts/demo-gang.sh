#!/usr/bin/env bash
# Exercise D - gang scheduling. Fill the fleet to ~8 free, submit a 10-pod gang, then
# free capacity. Applies manifests/exercise-d-filler.yaml then exercise-d-gang.yaml.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

kubectl apply -f manifests/namespace.yaml >/dev/null
kubectl get queue gang-demo >/dev/null 2>&1 || { echo "Queues not found. Run 'make queues' first."; exit 1; }
kubectl delete deploy -n kai-demo --all --ignore-not-found >/dev/null 2>&1
sleep 5

running() { kubectl get pods -n kai-demo -l app=gang-job --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' '; }

echo "Filling the fleet to ~8 free (manifests/exercise-d-filler.yaml: 24 of 32 GPUs) ..."
kubectl apply -f manifests/exercise-d-filler.yaml
sleep 10
echo "Submitting the 10-pod gang (manifests/exercise-d-gang.yaml, batch-min-member=10) ..."
kubectl apply -f manifests/exercise-d-gang.yaml
sleep 12

echo "gang-job Running into ~8 free: $(running) of 10"
echo "Concept: 0 running (all-or-none) until 10 GPUs are free."
echo "Observed: a plain Deployment is scheduled as independent per-pod groups, so ~8 run."
echo
echo "Freeing capacity (deleting the filler)..."
kubectl delete -f manifests/exercise-d-filler.yaml >/dev/null 2>&1 || true
sleep 15
echo "gang-job Running after freeing capacity: $(running) of 10"

#!/usr/bin/env bash
# Exercise A - quota enforcement. Applies manifests/exercise-a-quota.yaml (8 pods to
# team-research, 8 to team-prod) and shows each team fills its quota.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

kubectl apply -f manifests/namespace.yaml >/dev/null
kubectl get queue team-research >/dev/null 2>&1 || { echo "Queues not found. Run 'make queues' first."; exit 1; }
kubectl delete deploy -n kai-demo --all --ignore-not-found >/dev/null 2>&1   # clear any prior exercise

echo "Applying manifests/exercise-a-quota.yaml (team-research: 8, team-prod: 8) ..."
kubectl apply -f manifests/exercise-a-quota.yaml
echo "Waiting for KAI to place the pods..."
sleep 12

kubectl get pods -n kai-demo -L kai.scheduler/queue -o wide
echo
echo "Expect: team-research and team-prod each 8 Running, 0 Pending (quota enforced)."

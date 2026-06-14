#!/usr/bin/env bash
# Exercise C - reclaim. Run RIGHT AFTER make demo-borrow (do not clean in between).
# Applies manifests/exercise-c-reclaim.yaml on top of the still-running borrow workload.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! kubectl get deploy -n kai-demo prod-borrow >/dev/null 2>&1; then
  echo "prod-borrow not found. Run 'make demo-borrow' first - this exercise builds on it."
  exit 1
fi

running() { kubectl get pods -n kai-demo -l "app=$1" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' '; }

echo "Before: team-prod Running = $(running prod-borrow)"
echo "Applying manifests/exercise-c-reclaim.yaml (team-research returns, asks for 8) ..."
kubectl apply -f manifests/exercise-c-reclaim.yaml
sleep 15

echo "After:  team-prod Running = $(running prod-borrow), team-research Running = $(running research-reclaim)"
echo
echo "Concept: KAI evicts borrowed team-prod pods so team-research reaches its 8."
echo "Observed: since borrowing did not occur in Exercise B, there is nothing to"
echo "reclaim; team-research simply takes free GPUs. Eviction events (if any):"
echo "  kubectl get events -n kai-demo --sort-by=.lastTimestamp | tail -20"

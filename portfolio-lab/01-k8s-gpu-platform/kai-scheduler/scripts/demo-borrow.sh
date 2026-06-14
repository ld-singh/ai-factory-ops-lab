#!/usr/bin/env bash
# Exercise B - borrowing. team-research idle; team-prod asks for 16 (double its quota).
# Applies manifests/exercise-b-borrow.yaml. Run make demo-reclaim right after this.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

kubectl apply -f manifests/namespace.yaml >/dev/null
kubectl get queue team-prod >/dev/null 2>&1 || { echo "Queues not found. Run 'make queues' first."; exit 1; }
kubectl delete deploy -n kai-demo --all --ignore-not-found >/dev/null 2>&1

echo "Applying manifests/exercise-b-borrow.yaml (team-prod: 16, team-research idle) ..."
kubectl apply -f manifests/exercise-b-borrow.yaml
echo "Waiting..."
sleep 12

running=$(kubectl get pods -n kai-demo -l app=prod-borrow --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
echo "team-prod Running: ${running} of 16"
echo
echo "Concept: team-prod should borrow team-research's idle 8 GPUs and approach 16."
echo "Observed on this fake fleet: it stays around 8 - KAI did not lend a sibling's"
echo "idle-but-guaranteed capacity even with limit > quota. Now run: make demo-reclaim"
echo "(right after this, with nothing in between)."

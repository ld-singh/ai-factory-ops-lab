#!/usr/bin/env bash
set -euo pipefail

REMOVE_VOLCANO="${REMOVE_VOLCANO:-0}"

echo "Deleting Lesson 7 workload namespace..."
kubectl delete ns gpu-scale --ignore-not-found=true

echo "Deleting Lesson 7 Volcano queues..."
kubectl delete queue team-a team-b --ignore-not-found=true

echo "Deleting Lesson 7 fake scale nodes..."
kubectl delete node -l ai-factory-ops-lab/scale-sim=true --ignore-not-found=true

if [[ "$REMOVE_VOLCANO" == "1" ]]; then
  echo "Removing Volcano..."
  kubectl delete ns volcano-system --ignore-not-found=true
  kubectl delete crd queues.scheduling.volcano.sh podgroups.scheduling.volcano.sh jobs.batch.volcano.sh commands.bus.volcano.sh --ignore-not-found=true
fi

echo "Done. The kind cluster and fake-gpu-operator release are left in place."

#!/usr/bin/env bash
# Exercise D - gang scheduling (anti-deadlock). A 10-GPU job must get all 10 or none.
# We fill the fleet down to 8 free, submit the gang, watch it stay entirely Pending
# (it does NOT grab 8 and block), then free capacity and watch all 10 bind together.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

ensure_ns
clean_demo
wait_settle 5

free=$(free_gpus)
echo "Free GPUs now: ${free}"
filler=$(( free - 8 ))
if (( filler > 0 )); then
  echo "Filling the fleet down to 8 free with a ${filler}-GPU filler..."
  gpu_workload gang-filler gang-demo "$filler"
  wait_settle 10
fi
echo "Free GPUs before gang: $(free_gpus)  (target: 8)"

echo
echo "Submitting a 10-pod gang (kai.scheduler/batch-min-member=10) into ~8 free GPUs..."
gpu_workload gang-job gang-demo 10 10
wait_settle 12
echo "gang-job: $(counts gang-job)"
echo
echo "CONCEPT: a gang of 10 must bind all-or-none, so into 8 free GPUs it should stay"
echo "ENTIRELY pending (0 running) rather than grab 8 and deadlock."
echo
echo "OBSERVED ON THIS FAKE FLEET: a plain Deployment is scheduled as independent"
echo "per-pod groups (no gang), so ~8 run. KAI gangs by top-owner (Jobs, training"
echo "CRDs), but KWOK simulates Job pods to Completed instantly, so the held-pending"
echo "state can't be observed cleanly here. Gang is best validated on a real cluster."

echo
echo "Freeing capacity (deleting the filler)..."
kubectl delete deploy -n "$NS" gang-filler --ignore-not-found >/dev/null 2>&1 || true
wait_settle 15
echo "gang-job: $(counts gang-job)"

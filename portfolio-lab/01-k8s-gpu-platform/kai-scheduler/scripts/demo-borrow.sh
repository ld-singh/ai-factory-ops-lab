#!/usr/bin/env bash
# Exercise B - borrowing. team-research is idle, so team-prod borrows its idle GPUs
# and runs beyond its own 8-GPU quota, up to the parent pool (16).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

ensure_ns
clean_demo
echo "Leaving team-research idle; submitting 16 single-GPU pods to team-prod..."
gpu_workload prod-borrow team-prod 16
wait_settle 12

echo
echo "team-prod: $(counts prod-borrow)"
echo
echo "CONCEPT: borrowing should let team-prod exceed its 8-GPU quota by using"
echo "team-research's idle GPUs (up to its limit), so idle GPUs are not wasted."
echo
echo "OBSERVED ON THIS FAKE FLEET: team-prod stays at ~8 (its deserved share). In"
echo "this KWOK + fake-gpu-operator setup KAI did not lend a sibling's idle-but-"
echo "guaranteed capacity to an over-quota queue, even with limit > quota. Borrowing"
echo "of idle reserved capacity needs a real multi-tenant cluster or KAI-version"
echo "tuning to demonstrate. See the README's status note."

#!/usr/bin/env bash
# Exercise A - quota enforcement. Two teams each fill their 8-GPU quota.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

ensure_ns
clean_demo
echo "Submitting 8 single-GPU pods to team-research and 8 to team-prod..."
gpu_workload research-quota team-research 8
gpu_workload prod-quota   team-prod     8
wait_settle 10

echo
echo "team-research: $(counts research-quota)"
echo "team-prod:     $(counts prod-quota)"
echo
echo "Expected: each runs 8 (its quota). Neither exceeds it while the other is using"
echo "its own share. Inspect: kubectl get pods -n ${NS} -o wide"

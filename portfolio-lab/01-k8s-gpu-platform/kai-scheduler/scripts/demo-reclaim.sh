#!/usr/bin/env bash
# Exercise C - reclaim. With team-prod borrowing (from demo-borrow), team-research
# returns and asks for its guaranteed 8. KAI evicts borrowed team-prod pods so the
# owner gets its share back. Run demo-borrow first.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./lib.sh

ensure_ns
if ! kubectl get deploy -n "$NS" prod-borrow >/dev/null 2>&1; then
  echo "prod-borrow not found. Run 'make demo-borrow' first."
  exit 1
fi

echo "Before: team-prod (borrowing): $(counts prod-borrow)"
echo "team-research returns and claims its 8 GPUs..."
gpu_workload research-reclaim team-research 8
wait_settle 15

echo
echo "After:"
echo "team-prod:     $(counts prod-borrow)"
echo "team-research: $(counts research-reclaim)"
echo
echo "CONCEPT: reclaim evicts a queue's borrowed (over-quota) pods when the owner"
echo "returns, so borrowing is safe. team-research should reach its guaranteed 8."
echo
echo "OBSERVED ON THIS FAKE FLEET: because borrowing did not occur (see demo-borrow),"
echo "there is nothing over-quota to reclaim; team-research simply takes free GPUs."
echo "Proper reclaim needs the borrow step to work first. See the README note."

#!/usr/bin/env bash
# pin-node.sh - label exactly ONE pool node demo-node=target (and clear it from any
# others), so the binpack / exhaustion / cores exercises land on a single known node
# and their per-device capacity arithmetic is deterministic. Prints the chosen node.
#
# Usage: pin-node.sh            # pick the first pool node, pin it, print its name
#        pin-node.sh --clear    # remove the demo-node label from all nodes
set -euo pipefail
POOL="run.ai/simulated-gpu-node-pool=default"

if [[ "${1:-}" == "--clear" ]]; then
  kubectl label nodes -l demo-node=target demo-node- >/dev/null 2>&1 || true
  echo "Cleared demo-node label."
  exit 0
fi

target="$(kubectl get nodes -l "$POOL" -o jsonpath='{.items[0].metadata.name}')"
[[ -z "$target" ]] && { echo "No pool nodes found (label $POOL). Run 'make up' first."; exit 1; }

# Ensure only the target carries the label.
kubectl label nodes -l demo-node=target demo-node- >/dev/null 2>&1 || true
kubectl label node "$target" demo-node=target --overwrite >/dev/null
echo "$target"

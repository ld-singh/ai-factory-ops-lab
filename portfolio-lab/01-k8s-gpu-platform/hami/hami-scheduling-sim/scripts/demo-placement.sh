#!/usr/bin/env bash
# Scenario 3 - HAMi's per-pod PLACEMENT decision. Submit three small fractional pods and
# show the hami-scheduler "FilteringSucceed" events: the node + fractional score HAMi chose
# for each. That scheduling DECISION is what this scenario proves on the fake fleet.
# Control-plane only; pause containers.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

kubectl delete -f manifests/03-placement-spread.yaml --ignore-not-found >/dev/null 2>&1 || true
kubectl apply -f manifests/03-placement-spread.yaml
sleep 12

echo
echo "HAMi placement decisions (node chosen + fractional score per pod):"
kubectl get events --field-selector reason=FilteringSucceed 2>/dev/null \
  | grep -i "find fit node" | tail -3 || echo "  (re-run; events may still be arriving)"
echo
kubectl get pods -l app=hami-placement -o wide
echo
echo "The deliverable is the FilteringSucceed decision per pod. (Pods actually reaching"
echo "Running and SHARING a device is the real-GPU lesson - see ../hami-isolation-realgpu/.)"
echo "Verify:  kubectl get events --field-selector reason=FilteringSucceed | grep 'find fit node'"

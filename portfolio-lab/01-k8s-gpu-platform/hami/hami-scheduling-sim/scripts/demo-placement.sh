#!/usr/bin/env bash
# Scenario 3 - HAMi's per-pod PLACEMENT decision. Submit three small fractional pods and
# show the hami-scheduler "FilteringSucceed" events: the node + fractional score HAMi
# chose for each. That scheduling DECISION is the point and is genuine on the fake fleet;
# pods that land alone on a node also reach Running. Control-plane only; pause containers.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
here="$(dirname "${BASH_SOURCE[0]}")"

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
echo "Expected (run to confirm): a FilteringSucceed decision per pod (the node + fractional"
echo "score HAMi chose). That decision is the deliverable here. Pods that share a node will"
echo "show UnexpectedAdmissionError on the fake fleet (multi-pod-per-device sharing needs the"
echo "real GPU - see ../hami-isolation-realgpu/)."
echo "Verify:  kubectl get events --field-selector reason=FilteringSucceed | grep 'find fit node'"

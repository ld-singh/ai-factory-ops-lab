#!/usr/bin/env bash
# Exercise 4 - binpack / device sharing. Pin one 8-GPU node, submit 12 fractional
# pods, and show all 12 reach Running on that single node - i.e. HAMi places several
# pods on the same physical GPU. Stock Kubernetes would cap the node at 8 (one per
# GPU). Control-plane decision only; the pods are pause containers.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

"$(dirname "${BASH_SOURCE[0]}")/register-hami.sh" refresh
node="$("$(dirname "${BASH_SOURCE[0]}")/pin-node.sh")"
echo "Target node: $node (8 fake GPUs)"

kubectl delete -f manifests/04-binpack.yaml --ignore-not-found >/dev/null 2>&1 || true
kubectl apply -f manifests/04-binpack.yaml
sleep 15

running="$(kubectl get pods -l app=hami-binpack --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')"
echo
echo "hami-binpack Running on $node: $running of 12"
kubectl get pods -l app=hami-binpack -o wide
echo
echo "Expected (run to confirm): all 12 Running on the one 8-GPU node => at least four"
echo "GPUs host two pods each. That co-residency is HAMi sharing one device between"
echo "pods - a placement stock Kubernetes cannot make. Capture with 'make evidence'."

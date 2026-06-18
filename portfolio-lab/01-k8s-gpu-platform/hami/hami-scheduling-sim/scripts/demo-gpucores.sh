#!/usr/bin/env bash
# Exercise 6 - compute (gpucores) accounting. Pin one 8-GPU node, submit 9 pods that
# each want 60% of a GPU's compute (and only 1000 MiB). By cores a GPU fits one (60)
# but not two (120 > 100), so 8 fit and the 9th stays Pending - this time bound by
# COMPUTE, not memory. Shows HAMi tracks the two fractional dimensions independently.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

"$(dirname "${BASH_SOURCE[0]}")/register-hami.sh" refresh
node="$("$(dirname "${BASH_SOURCE[0]}")/pin-node.sh")"
echo "Target node: $node (8 fake GPUs, 100% cores each)"

kubectl delete -f manifests/06-gpucores.yaml --ignore-not-found >/dev/null 2>&1 || true
kubectl apply -f manifests/06-gpucores.yaml
sleep 16

running="$(kubectl get pods -l app=hami-gpucores --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')"
pending="$(kubectl get pods -l app=hami-gpucores --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l | tr -d ' ')"
echo
echo "hami-gpucores: $running Running / $pending Pending (of 9)"
echo "Pending pod scheduling reason (the cores-insufficient message - record its exact text):"
pod="$(kubectl get pods -l app=hami-gpucores --field-selector=status.phase=Pending -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
[[ -n "$pod" ]] && kubectl describe pod "$pod" | sed -n '/Events:/,$p' | head -8
echo
echo "Expected (run to confirm): 8 Running, 1 Pending on a compute/cores-insufficient"
echo "reason - memory is plentiful, cores are exhausted. TODO: capture the exact reason"
echo "string (it varies by HAMi version) into your evidence. 'make evidence' to capture."

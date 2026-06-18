#!/usr/bin/env bash
# Exercise 7 - percentage memory form. Submit one pod that asks for 50% of a GPU's
# memory via nvidia.com/gpumem-percentage (instead of absolute MiB) and show it binds.
# Proves the alternate request form is accepted and resolved against each GPU's
# registered devmem. Control-plane only; pause container.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

"$(dirname "${BASH_SOURCE[0]}")/register-hami.sh" refresh
kubectl delete -f manifests/07-gpumem-percentage.yaml --ignore-not-found >/dev/null 2>&1 || true
kubectl apply -f manifests/07-gpumem-percentage.yaml
sleep 12

kubectl get pod hami-gpumem-percentage -o wide
phase="$(kubectl get pod hami-gpumem-percentage -o jsonpath='{.status.phase}' 2>/dev/null || true)"
echo
if [[ "$phase" != "Running" ]]; then
  echo "Not Running yet (phase=$phase) - scheduling reason:"
  kubectl describe pod hami-gpumem-percentage | sed -n '/Events:/,$p' | head -8
fi
echo "Expected (run to confirm): Running. The percentage form (50% => ~40960 MiB of an"
echo "81920 MiB GPU) is accepted; it is mutually exclusive with nvidia.com/gpumem."
echo "TODO: confirm the key name for your HAMi version. 'make evidence' to capture."

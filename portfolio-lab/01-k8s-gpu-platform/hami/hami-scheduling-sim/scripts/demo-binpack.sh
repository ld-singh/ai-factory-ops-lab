#!/usr/bin/env bash
# Scenario 4 (sharing at scale, run-to-confirm) - six fractional pods each take one GPU
# and a 30% memory slice, and all reach Running across the fleet. More concurrent
# fractional tenants than the default scheduler could place (it gives each a whole
# device). Control-plane test; pause containers.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
here="$(dirname "${BASH_SOURCE[0]}")"

kubectl delete -f manifests/04-binpack.yaml --ignore-not-found >/dev/null 2>&1 || true
kubectl apply -f manifests/04-binpack.yaml
sleep 18

running="$(kubectl get pods -l app=hami-binpack --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')"
echo
echo "hami-binpack Running: ${running} of 6"
kubectl get pods -l app=hami-binpack -o wide
echo
echo "Expected (run to confirm): 6/6 Running - six fractional pods coexisting on the"
echo "fleet's GPUs. Each node admits up to its 8 nvidia.com/gpu slots, so they spread"
echo "across workers. Verify:  kubectl get pods -l app=hami-binpack -o wide"

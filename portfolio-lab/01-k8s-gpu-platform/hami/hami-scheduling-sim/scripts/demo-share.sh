#!/usr/bin/env bash
# THE HEADLINE (validated) - two pods SHARE one GPU and both reach Running. The default
# scheduler can't: nvidia.com/gpu is a whole integer to it, and it has no memory-slice
# concept. HAMi, with the mock device plugin answering the kubelet's Allocate, places both
# pods with a 20% memory slice each and both run. Control-plane test; pause containers.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
here="$(dirname "${BASH_SOURCE[0]}")"

kubectl delete -f manifests/00-share.yaml --ignore-not-found >/dev/null 2>&1 || true
kubectl apply -f manifests/00-share.yaml
sleep 15

running="$(kubectl get pods -l app=hami-share --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')"
echo
echo "hami-share Running: ${running} of 2"
kubectl get pods -l app=hami-share -o wide
echo
echo "Expected: 2/2 Running - two pods sharing GPU memory (20% each), which stock"
echo "Kubernetes cannot do. If a pod is OutOfnvidia.com/gpumem, you're on absolute gpumem"
echo "somewhere - use the percentage form (see manifests/00-share.yaml)."
echo "Verify:  kubectl get pods -l app=hami-share -o wide"

#!/usr/bin/env bash
set -euo pipefail

VOLCANO_VERSION="${VOLCANO_VERSION:-v1.10.0}"
MANIFEST_URL="${VOLCANO_MANIFEST_URL:-https://raw.githubusercontent.com/volcano-sh/volcano/${VOLCANO_VERSION}/installer/volcano-development.yaml}"

echo "Installing Volcano from:"
echo "  $MANIFEST_URL"
kubectl apply -f "$MANIFEST_URL"

echo
echo "Waiting for Volcano components..."
kubectl -n volcano-system wait --for=condition=complete job/volcano-admission-init --timeout=180s
kubectl -n volcano-system rollout status deploy/volcano-admission --timeout=180s
kubectl -n volcano-system rollout status deploy/volcano-controllers --timeout=180s
kubectl -n volcano-system rollout status deploy/volcano-scheduler --timeout=180s
kubectl -n volcano-system wait --for=condition=Ready pod -l app=volcano-admission --timeout=180s

echo "Waiting for Volcano admission webhook endpoint..."
for _ in $(seq 1 30); do
  endpoint_count="$(kubectl -n volcano-system get endpoints volcano-admission-service -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w | awk '{print $1}')"
  if [[ "$endpoint_count" -gt 0 ]]; then
    break
  fi
  sleep 2
done
# The admission binary registers webhook paths after the pod becomes Ready.
sleep 8

echo
kubectl get pods -n volcano-system

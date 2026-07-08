#!/usr/bin/env bash
set -euo pipefail

VOLCANO_VERSION="${VOLCANO_VERSION:-v1.10.0}"
MANIFEST_URL="${VOLCANO_MANIFEST_URL:-https://raw.githubusercontent.com/volcano-sh/volcano/${VOLCANO_VERSION}/installer/volcano-development.yaml}"

echo "Installing Volcano from:"
echo "  $MANIFEST_URL"
kubectl apply -f "$MANIFEST_URL"

echo
echo "Waiting for Volcano components..."
kubectl -n volcano-system rollout status deploy/volcano-admission --timeout=180s
kubectl -n volcano-system rollout status deploy/volcano-controllers --timeout=180s
kubectl -n volcano-system rollout status deploy/volcano-scheduler --timeout=180s

echo
kubectl get pods -n volcano-system

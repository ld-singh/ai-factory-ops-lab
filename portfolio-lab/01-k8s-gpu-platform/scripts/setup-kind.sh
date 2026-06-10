#!/usr/bin/env bash
# setup-kind.sh — create the lab kind cluster (idempotent).
set -euo pipefail

CLUSTER_NAME="${1:-ai-factory-lab}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "kind cluster '${CLUSTER_NAME}' already exists — skipping creation."
else
  kind create cluster --config "${SCRIPT_DIR}/../kind/kind-config.yaml" --name "${CLUSTER_NAME}"
fi

kubectl cluster-info --context "kind-${CLUSTER_NAME}"
kubectl get nodes -o wide

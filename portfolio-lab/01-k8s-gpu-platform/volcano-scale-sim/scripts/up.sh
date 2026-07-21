#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-ai-factory-lab}"
TOPOLOGY="${TOPOLOGY:-topology/small.json}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LESSON_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${LESSON_DIR}/../../.." && pwd)"
LAB1="${REPO_ROOT}/portfolio-lab/01-k8s-gpu-platform"

if [[ "$TOPOLOGY" != /* ]]; then
  if [[ -f "$TOPOLOGY" ]]; then
    TOPOLOGY="$(realpath "$TOPOLOGY")"
  elif [[ -f "${LESSON_DIR}/${TOPOLOGY}" ]]; then
    TOPOLOGY="$(realpath "${LESSON_DIR}/${TOPOLOGY}")"
  else
    echo "Topology file not found: $TOPOLOGY" >&2
    echo "Tried current directory and lesson directory: ${LESSON_DIR}" >&2
    exit 1
  fi
elif [[ ! -f "$TOPOLOGY" ]]; then
  echo "Topology file not found: $TOPOLOGY" >&2
  exit 1
fi

cd "$LESSON_DIR"

echo "Using topology: $TOPOLOGY"

"${LAB1}/scripts/setup-kind.sh" "$CLUSTER_NAME"
"${LAB1}/scripts/install-kwok.sh"

TOPOLOGY="$TOPOLOGY" OUT="generated/fake-gpu-operator-values.yaml" ./scripts/render-fgo-values.sh

FGO_VERSION="${FGO_VERSION:-0.0.59}"
FGO_NS="${FGO_NS:-gpu-operator}"
FGO_REPO="${FGO_REPO:-https://runai.jfrog.io/artifactory/api/helm/fake-gpu-operator-charts-prod}"

echo "Installing fake-gpu-operator ${FGO_VERSION} with rendered scale topology..."
helm repo add fake-gpu-operator "$FGO_REPO" --force-update >/dev/null
helm repo update fake-gpu-operator >/dev/null

helm upgrade -i gpu-operator fake-gpu-operator/fake-gpu-operator \
  -n "$FGO_NS" --create-namespace --version "$FGO_VERSION" \
  -f generated/fake-gpu-operator-values.yaml \
  --wait --timeout 5m

kubectl -n "$FGO_NS" rollout status deploy/status-updater --timeout=120s

TOPOLOGY="$TOPOLOGY" ./scripts/create-fake-gpu-nodes.sh

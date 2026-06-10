#!/usr/bin/env bash
# cleanup.sh — remove lab clusters and generated artifacts.
# Asks for confirmation before deleting anything.

set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-ai-factory-lab}"

echo "This will delete:"
echo "  - kind cluster: ${CLUSTER_NAME} (if it exists)"
echo "  - nothing else (evidence directories are kept intentionally)"
read -r -p "Proceed? [y/N] " answer
if [[ "${answer:-n}" != "y" && "${answer:-n}" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

if command -v kind >/dev/null 2>&1 && kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  kind delete cluster --name "${CLUSTER_NAME}"
  echo "Deleted kind cluster ${CLUSTER_NAME}."
else
  echo "No kind cluster named ${CLUSTER_NAME} found."
fi

echo "Evidence directories under portfolio-lab/06-validation-reports/evidence/ were NOT"
echo "deleted — they are the portfolio artifact. Remove manually if desired."

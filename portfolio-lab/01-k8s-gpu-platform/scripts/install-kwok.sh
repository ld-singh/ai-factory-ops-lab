#!/usr/bin/env bash
# install-kwok.sh — install KWOK in-cluster from official release manifests (idempotent).
# Docs: https://kwok.sigs.k8s.io/docs/user/kwok-in-cluster/
set -euo pipefail

KWOK_REPO="kubernetes-sigs/kwok"

# Pin via env var for reproducibility, otherwise resolve latest release.
KWOK_RELEASE="${KWOK_RELEASE:-$(curl -s "https://api.github.com/repos/${KWOK_REPO}/releases/latest" | jq -r '.tag_name')}"
if [[ -z "${KWOK_RELEASE}" || "${KWOK_RELEASE}" == "null" ]]; then
  echo "ERROR: could not resolve KWOK release tag. Set KWOK_RELEASE=vX.Y.Z and retry." >&2
  exit 1
fi

echo "Installing KWOK ${KWOK_RELEASE} ..."
kubectl apply -f "https://github.com/${KWOK_REPO}/releases/download/${KWOK_RELEASE}/kwok.yaml"
# stage-fast makes pods on fake nodes reach Running quickly — ideal for demos.
kubectl apply -f "https://github.com/${KWOK_REPO}/releases/download/${KWOK_RELEASE}/stage-fast.yaml"

kubectl -n kube-system rollout status deployment/kwok-controller --timeout=120s
echo "KWOK controller is ready."

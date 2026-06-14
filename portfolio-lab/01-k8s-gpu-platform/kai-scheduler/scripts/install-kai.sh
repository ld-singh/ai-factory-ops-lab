#!/usr/bin/env bash
# install-kai.sh - install KAI Scheduler from the official OCI Helm chart at a pinned
# version, then wait for its pods. Verified install path from the KAI repo.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

KAI_VERSION="${KAI_VERSION:-v0.15.2}"
KAI_NS="${KAI_NS:-kai-scheduler}"
KAI_CHART="${KAI_CHART:-oci://ghcr.io/kai-scheduler/kai-scheduler/kai-scheduler}"

echo "Installing KAI Scheduler ${KAI_VERSION} into namespace ${KAI_NS} ..."
helm upgrade -i kai-scheduler "$KAI_CHART" \
  -n "$KAI_NS" --create-namespace \
  --version "$KAI_VERSION" \
  --wait --timeout 5m

# KAI injects runtimeClassName: nvidia into GPU pods; the object must exist or the
# API rejects them. The shared Lesson 1 fake-gpu-operator (installed by ensure-cluster)
# already creates the nvidia RuntimeClass, so we do not create it here.

# The kai-operator manages some controllers as separate Deployments. On a re-install
# over a previous KAI, those operator-managed pods can linger with stale, now-invalid
# serviceaccount tokens and fail with "Unauthorized" (podgroups never get a status,
# so nothing schedules). Restart all KAI deployments so every controller has a fresh
# token. Harmless on a first install.
kubectl -n "$KAI_NS" rollout restart deploy >/dev/null 2>&1 || true
kubectl -n "$KAI_NS" rollout status deploy/podgroup-controller --timeout=120s >/dev/null 2>&1 || true
kubectl -n "$KAI_NS" rollout status deploy/kai-scheduler-default --timeout=120s >/dev/null 2>&1 || true

echo "KAI pods:"
kubectl -n "$KAI_NS" get pods

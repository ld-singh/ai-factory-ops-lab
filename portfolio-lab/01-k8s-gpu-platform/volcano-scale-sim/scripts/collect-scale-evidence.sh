#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LESSON_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${LESSON_DIR}/../../.." && pwd)"

ts="$(date +%Y%m%d-%H%M%S)"
out="${REPO_ROOT}/portfolio-lab/06-validation-reports/evidence/gpu-scale-${ts}"
mkdir -p "$out"

kubectl get nodes -l ai-factory-ops-lab/scale-sim=true -o wide > "${out}/nodes-wide.txt" || true
kubectl get nodes -l ai-factory-ops-lab/scale-sim=true -o yaml > "${out}/nodes.yaml" || true
kubectl get queue -o yaml > "${out}/volcano-queues.yaml" || true
kubectl get podgroups -n gpu-scale -o yaml > "${out}/podgroups.yaml" || true
kubectl get pods -n gpu-scale -o wide > "${out}/pods-wide.txt" || true
kubectl get pods -n gpu-scale -o yaml > "${out}/pods.yaml" || true
kubectl get events -n gpu-scale --sort-by=.lastTimestamp > "${out}/events.txt" || true
kubectl get pods -n volcano-system -o wide > "${out}/volcano-pods.txt" || true
kubectl -n gpu-operator get pods -o wide > "${out}/fake-gpu-operator-pods.txt" || true

cat > "${out}/README.txt" <<EOF
GPU scale simulation evidence

Captured: ${ts}

This evidence proves Kubernetes/Volcano control-plane behaviour only.
It does not prove CUDA, driver, NCCL, MIG, HAMi isolation, or GPU performance.
EOF

echo "Evidence written to: $out"

#!/usr/bin/env bash
set -euo pipefail

echo "Scale fake GPU nodes:"
kubectl get nodes -l ai-factory-ops-lab/scale-sim=true \
  -o custom-columns='NAME:.metadata.name,POOL:.metadata.labels.gpu-pool,PRODUCT:.metadata.labels.nvidia\.com/gpu\.product,GPUS:.status.allocatable.nvidia\.com/gpu' | head -80 || true

echo
echo "Node count:"
kubectl get nodes -l ai-factory-ops-lab/scale-sim=true --no-headers 2>/dev/null | wc -l | awk '{print $1}'

echo
echo "Volcano pods:"
kubectl get pods -n volcano-system 2>/dev/null || echo "Volcano is not installed."

echo
echo "GPU scale workloads:"
kubectl get podgroups -n gpu-scale 2>/dev/null || true
kubectl get pods -n gpu-scale -o wide 2>/dev/null | head -80 || true

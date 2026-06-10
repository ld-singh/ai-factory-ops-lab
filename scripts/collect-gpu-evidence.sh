#!/usr/bin/env bash
# collect-gpu-evidence.sh — capture REAL GPU validation evidence.
# REQUIRES: a machine with an NVIDIA GPU, NVIDIA driver, and (optionally) a
# Kubernetes cluster with the NVIDIA GPU Operator installed.
# Read-only. Output goes to portfolio-lab/06-validation-reports/evidence/.

set -euo pipefail

OUT_DIR="portfolio-lab/06-validation-reports/evidence/gpu-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT_DIR"

echo "Collecting REAL GPU evidence into $OUT_DIR"
echo "NOTE: this script is only meaningful on a machine with an NVIDIA GPU."
echo

run() {
  local file="$1"; shift
  {
    echo "\$ $*"
    echo
    "$@" 2>&1
  } > "$OUT_DIR/$file" || echo "  [WARN] command failed (captured anyway): $*"
  echo "  wrote $file"
}

# --- Driver / hardware level ------------------------------------------------
if command -v nvidia-smi >/dev/null 2>&1; then
  run nvidia-smi.txt        nvidia-smi
  run nvidia-smi-L.txt      nvidia-smi -L
  run nvidia-smi-topo.txt   nvidia-smi topo -m
else
  echo "  [SKIP] nvidia-smi not found — driver evidence unavailable on this machine."
fi

# --- Container runtime level --------------------------------------------------
# Image tag may need updating to match your installed driver/CUDA version.
if command -v docker >/dev/null 2>&1 && command -v nvidia-smi >/dev/null 2>&1; then
  run docker-cuda-smi.txt docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
fi

# --- Kubernetes level ---------------------------------------------------------
if command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
  run k8s-nodes.txt           kubectl get nodes -o wide
  run k8s-gpu-allocatable.txt kubectl get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'
  run k8s-gpu-operator.txt    kubectl get pods -n gpu-operator -o wide
  run k8s-nodes-describe.txt  kubectl describe nodes
else
  echo "  [SKIP] kubectl not available or no cluster — Kubernetes GPU evidence unavailable."
fi

echo
echo "Done. Reference this directory from:"
echo "  portfolio-lab/06-validation-reports/real-gpu-validation-report.md"

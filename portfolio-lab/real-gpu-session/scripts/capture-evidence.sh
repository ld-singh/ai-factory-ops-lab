#!/usr/bin/env bash
# capture-evidence.sh - capture Lesson 6 Phase A (real GPU runtime path) evidence on the
# VM, into a local folder + tarball you scp back to your laptop. Self-contained: needs only
# this file (not the whole repo) and a working KUBECONFIG. Read-only except a short-lived
# CUDA pod it creates and deletes.
#
# Run on the VM after install-gpu-operator.sh:
#   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml   # (if not already set)
#   ./capture-evidence.sh
# Then from your laptop:
#   scp -i <key> <user>@<vm-ip>:~/gpu-evidence-*.tgz \
#     ./portfolio-lab/06-validation-reports/evidence/
set -euo pipefail

OUT="gpu-evidence-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
echo "Collecting Phase A evidence into $OUT/ ..."

cap() { local f="$1"; shift; { echo "\$ $*"; echo; "$@" 2>&1 || true; } > "$OUT/$f"; echo "  wrote $f"; }

# --- driver / hardware ------------------------------------------------------
if command -v nvidia-smi >/dev/null 2>&1; then
  cap nvidia-smi.txt       nvidia-smi
  cap nvidia-smi-L.txt     nvidia-smi -L
  cap nvidia-smi-topo.txt  nvidia-smi topo -m
else
  echo "  [SKIP] nvidia-smi not found on host"
fi

# --- cluster / GPU stack ----------------------------------------------------
cap nodes.txt              kubectl get nodes -o wide
cap node-describe.txt      kubectl describe node
cap gpu-allocatable.txt    bash -c "kubectl get nodes -o jsonpath='{.items[0].status.allocatable.nvidia\\.com/gpu}'; echo"
cap gpu-operator-pods.txt  kubectl get pods -n gpu-operator -o wide
cap helm.txt               bash -c "helm list -A 2>/dev/null || echo '(helm not on PATH)'"
cap runtimeclass.txt       kubectl get runtimeclass

# --- the headline: nvidia-smi from INSIDE a scheduled pod -------------------
echo "  running a CUDA pod for the in-pod nvidia-smi ..."
cat <<'YAML' | kubectl apply -f - >/dev/null 2>&1 || true
apiVersion: v1
kind: Pod
metadata:
  name: cuda-evidence
spec:
  restartPolicy: Never
  runtimeClassName: nvidia
  containers:
    - name: cuda
      image: nvidia/cuda:12.4.1-base-ubuntu22.04
      command: ["nvidia-smi"]
      resources:
        limits:
          nvidia.com/gpu: 1
YAML
kubectl wait --for=condition=Ready pod/cuda-evidence --timeout=180s >/dev/null 2>&1 || true
sleep 3
cap cuda-pod-nvidia-smi.txt kubectl logs cuda-evidence
kubectl delete pod cuda-evidence --ignore-not-found >/dev/null 2>&1 || true

# --- optional: real DCGM telemetry (the GPU Operator deploys dcgm-exporter) --
# Scrape via port-forward + host curl: the dcgm-exporter container usually has no
# curl/bash, so `kubectl exec ... curl` doesn't work - but the metrics port does.
dcgm="$(kubectl get pods -n gpu-operator -o name 2>/dev/null | grep -i dcgm | head -1 || true)"
if [ -n "$dcgm" ] && command -v curl >/dev/null 2>&1; then
  echo "  scraping DCGM metrics from $dcgm (port-forward) ..."
  kubectl -n gpu-operator port-forward "${dcgm#pod/}" 9400:9400 >/dev/null 2>&1 &
  pf=$!; sleep 3
  { echo "\$ curl -s localhost:9400/metrics | grep DCGM_FI_DEV_*"; echo
    curl -s localhost:9400/metrics 2>&1 \
      | grep -E 'DCGM_FI_DEV_(GPU_TEMP|FB_USED|FB_FREE|GPU_UTIL|POWER_USAGE|SM_CLOCK)' || echo "(no metrics scraped)"
  } > "$OUT/dcgm-metrics.txt"; echo "  wrote dcgm-metrics.txt"
  kill "$pf" 2>/dev/null || true
fi

tar czf "$OUT.tgz" "$OUT"
echo
echo "=== wrote $OUT.tgz ==="
echo "scp it to your laptop, e.g.:"
echo "  scp -i <key> <user>@<vm-ip>:$PWD/$OUT.tgz ./portfolio-lab/06-validation-reports/evidence/"
echo "then untar it under portfolio-lab/06-validation-reports/evidence/ and fill in"
echo "real-gpu-validation-report.md."

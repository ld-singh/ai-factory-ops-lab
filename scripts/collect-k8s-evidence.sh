#!/usr/bin/env bash
# collect-k8s-evidence.sh — capture Kubernetes scheduling evidence for validation reports.
# Read-only against the cluster. Output goes to portfolio-lab/06-validation-reports/evidence/.

set -euo pipefail

OUT_DIR="portfolio-lab/06-validation-reports/evidence/k8s-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT_DIR"

echo "Collecting Kubernetes evidence into $OUT_DIR"

run() {
  # run <output-file> <command...> : capture both the command and its output,
  # so the evidence file is self-describing.
  local file="$1"; shift
  {
    echo "\$ $*"
    echo
    "$@" 2>&1
  } > "$OUT_DIR/$file" || echo "  [WARN] command failed (captured anyway): $*"
  echo "  wrote $file"
}

run nodes.txt                kubectl get nodes -o wide --show-labels
run nodes-describe.txt       kubectl describe nodes
run pods-all.txt             kubectl get pods -A -o wide
run pods-gpu-demo.txt        kubectl get pods -n gpu-demo -o wide
run pending-pods.txt         kubectl get pods -A --field-selector=status.phase=Pending -o wide
run events.txt               kubectl get events -A --sort-by=.lastTimestamp
run gpu-allocatable.txt      kubectl get nodes -o custom-columns='NAME:.metadata.name,GPU_ALLOC:.status.allocatable.nvidia\.com/gpu,GPU_CAP:.status.capacity.nvidia\.com/gpu'

# Describe any Pending pods in the demo namespace — this is the triage evidence.
if kubectl get ns gpu-demo >/dev/null 2>&1; then
  for pod in $(kubectl get pods -n gpu-demo --field-selector=status.phase=Pending -o name 2>/dev/null); do
    safe_name=$(echo "$pod" | tr '/' '-')
    run "describe-${safe_name}.txt" kubectl describe -n gpu-demo "$pod"
  done
fi

echo
echo "Done. Reference this directory from the validation report:"
echo "  portfolio-lab/06-validation-reports/local-simulation-report.md"

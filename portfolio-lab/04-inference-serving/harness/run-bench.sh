#!/usr/bin/env bash
# run-bench.sh — drive the load harness against an OpenAI-compatible endpoint.
# Defaults to the local CPU server from serve-cpu.sh ($0 harness-validation tier).
# For a REAL benchmark, point --url at vLLM on the Lesson 2 GPU machine.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
URL="${ENDPOINT:-http://localhost:8000}"
MODEL="${MODEL:-local}"
CONC="${CONCURRENCY:-1,2,4,8}"
REQS="${REQUESTS_PER_LEVEL:-12}"

echo "Benchmarking ${URL} (model=${MODEL})"
echo "Reminder: CPU-served numbers validate the HARNESS only, not the hardware."
echo
exec python3 "${SCRIPT_DIR}/loadgen.py" \
  --url "$URL" --model "$MODEL" \
  --concurrency "$CONC" --requests-per-level "$REQS" \
  --json-out "portfolio-lab/06-validation-reports/evidence/inference-$(date +%Y%m%d-%H%M%S).json"

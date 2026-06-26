#!/usr/bin/env bash
# drills.sh - the $0 learning drills for Lesson 4. Each one makes a serving
# behaviour OBSERVABLE on the CPU harness; the numbers aren't a benchmark, the
# shape of the result is the lesson. Point ENDPOINT/MODEL at a GPU server to see
# the same drills with numbers that mean something.
#
#   drills.sh batching   # continuous batching: short requests behind long ones
#   drills.sh prefill    # input-length sweep  -> TTFT (prefill cost)
#   drills.sh decode     # output-length sweep -> e2e/TPOT (decode cost)
#   drills.sh overload   # push past the knee  -> goodput collapses, errors climb
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LG="${SCRIPT_DIR}/loadgen.py"
URL="${ENDPOINT:-http://localhost:8000}"
MODEL="${MODEL:-qwen2:0.5b}"   # matches serve-cpu.sh's default; override for a GPU server
REQS="${REQUESTS_PER_LEVEL:-12}"

drill="${1:-}"
echo "Drill '${drill}' against ${URL} (model=${MODEL})"
echo

case "$drill" in
  batching)
    # Short interactive requests alone, then again behind enough long requests to
    # saturate the server's in-flight slots - that's what inflates short-request TTFT.
    exec python3 "$LG" --url "$URL" --model "$MODEL" --mode mixed \
      --concurrency-mixed 1 --short-tokens 16 --long-tokens 512 --long-count 8 \
      --requests-per-level "$REQS"
    ;;
  prefill)
    # Hold concurrency + output fixed; grow the PROMPT. Watch ttft climb.
    exec python3 "$LG" --url "$URL" --model "$MODEL" --mode sweep --sweep input \
      --concurrency 1 --max-tokens 64 --input-tokens "16,128,512,1024" \
      --requests-per-level "$REQS"
    ;;
  decode)
    # Hold concurrency fixed; grow the OUTPUT cap (a counting prompt keeps the model
    # generating so the cap bites). Watch 'gen' rise, e2e rise with it, tpot stay flat.
    exec python3 "$LG" --url "$URL" --model "$MODEL" --mode sweep --sweep output \
      --concurrency 1 --max-tokens "32,64,128,256" \
      --requests-per-level "$REQS"
    ;;
  overload)
    # Climb concurrency past what the server sustains. Watch goodput% fall off a cliff.
    # Defaults saturate a CPU/tiny-model server. A fast GPU needs more - crank it via env:
    #   CONCURRENCY=32,64,128,256,512 MAX_TOKENS=512 REQUESTS_PER_LEVEL=64 make phase5-overload
    exec python3 "$LG" --url "$URL" --model "$MODEL" --mode sweep --sweep concurrency \
      --concurrency "${CONCURRENCY:-1,2,4,8,16,32}" --max-tokens "${MAX_TOKENS:-128}" \
      --ttft-slo "${TTFT_SLO:-1.0}" --requests-per-level "$REQS"
    ;;
  *)
    echo "usage: drills.sh {batching|prefill|decode|overload}" >&2
    exit 2
    ;;
esac

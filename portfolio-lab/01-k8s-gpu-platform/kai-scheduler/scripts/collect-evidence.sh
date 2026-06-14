#!/usr/bin/env bash
# collect-evidence.sh - snapshot KAI control-plane evidence into evidence/<timestamp>/.
# Read-only. Backs claims about queue/quota/borrow/reclaim/gang scheduling decisions;
# says nothing about GPU runtime (the pods are pause containers on fake nodes).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
NS="${KAI_DEMO_NS:-kai-demo}"

TS="$(date +%Y%m%d-%H%M%S)"
OUT="evidence/$TS"
mkdir -p "$OUT"
echo "Collecting KAI evidence into $OUT"

run() { local f="$1"; shift; { echo "\$ $*"; echo; "$@" 2>&1 || true; } > "$OUT/$f"; echo "  wrote $f"; }

run queues.txt        kubectl get queues.scheduling.run.ai -o wide
run queues-yaml.txt   kubectl get queues.scheduling.run.ai -o yaml
run pods.txt          kubectl get pods -n "$NS" -o wide
run pods-by-queue.txt kubectl get pods -n "$NS" -L kai.scheduler/queue
run events.txt        kubectl get events -n "$NS" --sort-by=.lastTimestamp
run kai-pods.txt      kubectl -n kai-scheduler get pods
run nodes-gpu.txt     kubectl get nodes -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\\.com/gpu

echo "Done. Control-plane evidence only (scheduling decisions), not GPU runtime."

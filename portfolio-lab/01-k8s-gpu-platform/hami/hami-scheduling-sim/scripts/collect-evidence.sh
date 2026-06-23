#!/usr/bin/env bash
# collect-evidence.sh - snapshot control-plane evidence into evidence/<timestamp>/.
# Read-only. Backs one claim: HAMi's scheduler made the right fractional placement
# DECISIONS on a fake fleet (placement + per-device rejection). It says nothing about GPU
# sharing or runtime isolation - those are the paired real-GPU lesson.
set -euo pipefail

TS="$(date +%Y%m%d-%H%M%S)"
OUT="evidence/$TS"
mkdir -p "$OUT"
echo "Collecting control-plane evidence into $OUT"

run() {
  local f="$1"; shift
  { echo "\$ $*"; echo; "$@" 2>&1 || true; } > "$OUT/$f"
  echo "  wrote $f"
}

run nodes.txt            kubectl get nodes -o wide -L gpu
run node-resources.txt   bash scripts/verify-resources.sh
run hami-pods.txt        kubectl -n kube-system get pods
run pods-all.txt         kubectl get pods -A -o wide
run fractional.txt       kubectl describe pod hami-fractional
run overrequest.txt      kubectl describe pod hami-overrequest
run placement.txt        kubectl get pods -l app=hami-placement -o wide

# The placement DECISIONS and the Pending rejection reason are the evidence this fake
# fleet backs; capture the scheduler events too.
run scheduler-events.txt bash -c 'kubectl get events --field-selector reason=FilteringSucceed 2>/dev/null | grep -i "find fit node" | tail -20 || echo "(none)"'
run pending-reasons.txt  bash -c 'kubectl get events 2>/dev/null | grep -iE "Insufficient|Card" | tail -20 || echo "(none)"'

echo
echo "Done. Control-plane SCHEDULING DECISIONS only - not GPU sharing or isolation."

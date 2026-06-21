#!/usr/bin/env bash
# collect-evidence.sh - snapshot control-plane evidence into evidence/<timestamp>/.
# Read-only. Backs the claim that HAMi's control plane scheduled and SHARED GPUs correctly
# on a fake fleet (placement, sharing, rejection). It says nothing about runtime isolation
# (the slice enforced inside the container), which is the paired real-GPU lesson.
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

run nodes.txt              kubectl get nodes -o wide -L gpu
run node-resources.txt     bash scripts/verify-resources.sh
run mock-plugin.txt        bash -c 'kubectl -n kube-system get pods | grep -iE "hami|mock"'
run pods-all.txt           kubectl get pods -A -o wide
run share.txt              kubectl get pods -l app=hami-share -o wide
run binpack.txt            kubectl get pods -l app=hami-binpack -o wide
run fractional.txt         kubectl describe pod hami-fractional
run overrequest.txt        kubectl describe pod hami-overrequest
run placement.txt          kubectl get pods -l app=hami-placement -o wide

# The placement DECISIONS and Pending rejection reasons are scheduler-side evidence;
# capture the events too.
run scheduler-events.txt   bash -c 'kubectl get events --field-selector reason=FilteringSucceed 2>/dev/null | grep -i "find fit node" | tail -20 || echo "(none)"'
run pending-reasons.txt    bash -c 'kubectl get events 2>/dev/null | grep -iE "Insufficient|Card" | tail -20 || echo "(none)"'

echo
echo "Done. CONTROL-PLANE evidence (scheduling + sharing decisions), not runtime isolation."

#!/usr/bin/env bash
# collect-evidence.sh - snapshot control-plane evidence into evidence/<timestamp>/.
# Read-only. This evidence backs exactly one claim: the HAMi control plane scheduled
# fractional requests correctly. It says nothing about runtime isolation, which is
# the paired real-GPU lesson.
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

run nodes.txt              kubectl get nodes -o wide -L gpu,demo-node
run node-resources.txt     bash scripts/verify-resources.sh
run hami-pods.txt          kubectl -n kube-system get pods
run pods-all.txt           kubectl get pods -A -o wide
run fractional.txt         kubectl describe pod hami-fractional
run overrequest.txt        kubectl describe pod hami-overrequest
run placement.txt          kubectl get pods -l app=hami-placement -o wide

# Exercises 4-7 (sharing / per-device accounting). Each is captured if its workload
# is present; absent ones just record empty output rather than failing the run.
run binpack.txt            kubectl get pods -l app=hami-binpack -o wide
run mem-exhaustion.txt     kubectl get pods -l app=hami-mem-exhaustion -o wide
run gpucores.txt           kubectl get pods -l app=hami-gpucores -o wide
run gpumem-percentage.txt  kubectl describe pod hami-gpumem-percentage

# The Pending reasons are the proof for exercises 5 and 6; capture the events too.
run pending-reasons.txt    bash -c 'kubectl get events --field-selector reason=FailedScheduling --sort-by=.lastTimestamp 2>/dev/null | grep -iE "Insufficient|Card" | tail -20 || echo "(no FailedScheduling events captured)"'

echo
echo "Done. This is CONTROL-PLANE evidence only (scheduling), not isolation."

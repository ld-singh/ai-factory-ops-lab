#!/usr/bin/env bash
# capture-evidence.sh - run the HAMi isolation exercises end to end and snapshot the
# evidence into a local folder + tarball you scp back. Run AFTER install-hami.sh, with a
# working KUBECONFIG, from anywhere (paths resolve relative to this script).
#
# It captures the five Part B artifacts:
#   1 co-residency      - two pods Running on one physical GPU
#   2 virtualized smi   - each pod sees its slice, not the full card
#   3 memory-cap        - a CUDA alloc past the slice is refused by HAMi-core
#   4 per-device budget - a third pod stays Pending (CardInsufficientMemory)
#   5 the mechanism     - the HAMi-core env/library the runtime injects
#
# Size the oversubscribe pod for YOUR card first (see manifests/oversubscribe-pending.yaml;
# the committed value suits a 48 GB A6000). Read-only except the lab's own pods.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(dirname "$SCRIPT_DIR")"
OUT="hami-evidence-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

log() { printf '\n=== %s ===\n' "$*"; }
cap() { local f="$1"; shift; { echo "\$ $*"; echo; "$@" 2>&1 || true; } > "$OUT/$f"; echo "  wrote $f"; }

command -v kubectl >/dev/null || { echo "ERROR: kubectl not found" >&2; exit 1; }
kubectl get nodes >/dev/null  || { echo "ERROR: kubectl can't reach the cluster (set KUBECONFIG)" >&2; exit 1; }

log "Exercise 1: co-residency - two pods on one GPU"
kubectl apply -f "$LAB_DIR/manifests/share-two-pods.yaml" >/dev/null
kubectl wait --for=condition=Ready pod/hami-share-a pod/hami-share-b --timeout=300s || true
cap 1-co-residency.txt        kubectl get pods -o wide
cap node-allocatable.txt      bash -c "kubectl get nodes -o json | grep -oE '\"nvidia.com/(gpu|gpumem|gpucores)\": *\"[0-9]+\"' | sort -u"

log "Exercise 2+3: virtualized nvidia-smi + memory-cap probe (both pods)"
cap 2-3-probe-memory-a.txt    bash "$SCRIPT_DIR/probe-memory.sh" hami-share-a
cap 2-3-probe-memory-b.txt    bash "$SCRIPT_DIR/probe-memory.sh" hami-share-b

log "Exercise 4: per-device budget - a third pod stays Pending"
kubectl apply -f "$LAB_DIR/manifests/oversubscribe-pending.yaml" >/dev/null
sleep 15
cap 4-oversubscribe-status.txt   kubectl get pod hami-oversubscribe -o wide
cap 4-oversubscribe-events.txt   bash -c "kubectl describe pod hami-oversubscribe | sed -n '/Events:/,\$p' | head -12"

log "Exercise 5: the mechanism - HAMi-core injection + device view"
cap 5-probe-mechanism-a.txt   bash "$SCRIPT_DIR/probe-mechanism.sh" hami-share-a

log "HAMi pods (context)"
cap hami-pods.txt             bash -c "kubectl -n kube-system get pods | grep -i hami"

tar czf "$OUT.tgz" "$OUT"
cat <<EOF

=== wrote $OUT.tgz ===
scp it to your laptop and record it as the Part B isolation evidence, e.g.:
  scp -i <key> <user>@<vm-ip>:$PWD/$OUT.tgz \\
    ./portfolio-lab/06-validation-reports/evidence/
Then clean up:  kubectl delete -f $LAB_DIR/manifests/ ; and tear the VM down.
EOF

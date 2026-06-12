#!/usr/bin/env bash
# collect-slurm-evidence.sh — capture Slurm scheduling evidence (Phase 3).
# Read-only. Works two ways:
#   - if `sinfo` is on PATH (real-GPU Slurm box), run directly on the host;
#   - otherwise, run inside the Slurm-in-Docker `login` container.
# Output goes to portfolio-lab/06-validation-reports/evidence/.

set -euo pipefail

COMPOSE="portfolio-lab/02-slurm-gpu-platform/docker/docker-compose.yml"

# Decide how to run slurm client commands.
if command -v sinfo >/dev/null 2>&1; then
  slurm() { "$@"; }
  MODE="host"
elif docker compose -f "$COMPOSE" ps --status running 2>/dev/null | grep -q login; then
  slurm() { docker compose -f "$COMPOSE" exec -T login "$@"; }
  MODE="docker (login container)"
else
  echo "No Slurm CLI on host and the Slurm-in-Docker cluster is not running."
  echo "Start it with: make phase3-up"
  exit 1
fi

OUT_DIR="portfolio-lab/06-validation-reports/evidence/slurm-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT_DIR"
echo "Collecting Slurm evidence into $OUT_DIR (mode: $MODE)"

run() {
  local file="$1"; shift
  { echo "\$ $*"; echo; slurm "$@" 2>&1; } > "$OUT_DIR/$file" || echo "  [WARN] failed (captured): $*"
  echo "  wrote $file"
}

run sinfo.txt        sinfo -N -l
run squeue.txt       squeue -l
run pending.txt      squeue --states=PENDING -o '%.10i %.12j %.8T %.6D %.20R'
run partitions.txt   scontrol show partition
run nodes.txt        scontrol show node
run qos.txt          sacctmgr show qos format=Name,MaxTRESPU%20,Priority
run assoc.txt        sacctmgr show assoc format=Account,User,QOS%30
run fairshare.txt    sshare -l
run sacct.txt        sacct -X --starttime today --format=JobID,JobName,Partition,QOS,AllocTRES%30,State,Elapsed

echo
echo "Done. Reference this directory from:"
echo "  portfolio-lab/06-validation-reports/slurm-gres-validation.md"

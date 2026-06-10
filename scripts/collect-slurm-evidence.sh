#!/usr/bin/env bash
# collect-slurm-evidence.sh — capture Slurm evidence (Phase 3).
# STATUS: stub until Phase 3 lands. Kept here so the evidence workflow is
# consistent across phases. Read-only.

set -euo pipefail

if ! command -v sinfo >/dev/null 2>&1; then
  echo "Slurm CLI not found. Phase 3 (portfolio-lab/02-slurm-gpu-platform) sets up"
  echo "a Slurm-in-Docker cluster; run this script inside that environment."
  exit 1
fi

OUT_DIR="portfolio-lab/06-validation-reports/evidence/slurm-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT_DIR"

run() {
  local file="$1"; shift
  { echo "\$ $*"; echo; "$@" 2>&1; } > "$OUT_DIR/$file" || true
  echo "  wrote $file"
}

run sinfo.txt        sinfo -N -l
run squeue.txt       squeue -l
run partitions.txt   scontrol show partition
run nodes.txt        scontrol show node
run sacct.txt        sacct --starttime today --format=JobID,JobName,Partition,AllocTRES%40,State,Elapsed

echo "Done. Reference from portfolio-lab/06-validation-reports/slurm-gres-validation.md"

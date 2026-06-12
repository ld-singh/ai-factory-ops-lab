#!/usr/bin/env bash
# drain-drill.sh — the Slurm analogue of cordon/drain in Kubernetes. Drain a node,
# watch work route around it, then resume. Feeds the slurm-node-drained runbook.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE="${SCRIPT_DIR}/../docker/docker-compose.yml"
in_login() { docker compose -f "$COMPOSE" exec -T login "$@"; }

NODE="${1:-c2}"

echo "==> Before: node states"
in_login sinfo -N -l

echo
echo "==> Draining ${NODE} (running jobs keep going; no NEW work lands there)..."
in_login scontrol update nodename="${NODE}" state=drain reason="lab drain drill"
in_login sinfo -N -l

echo
echo "==> Submitting a burst while ${NODE} is drained — watch it pack onto the"
echo "    remaining node only:"
in_login sbatch /jobs/04-queue-pressure.sbatch
sleep 5
in_login squeue -o '%.10i %.12j %.8T %.8B %.20R' || true

echo
echo "==> Resuming ${NODE}..."
in_login scontrol update nodename="${NODE}" state=resume
in_login sinfo -N -l

echo
echo "Drill complete. The runbook this exercises:"
echo "  runbooks/slurm-node-drained.md"

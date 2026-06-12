#!/usr/bin/env bash
# demo.sh - submit the four GPU scheduling scenarios and show the queue with
# pending reasons, the Slurm analogue of Lesson 1's run-scheduling-demo.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE="${SCRIPT_DIR}/../docker/docker-compose.yml"
in_login() { docker compose -f "$COMPOSE" exec -T login "$@"; }

# Scenario 3 needs the capped QoS in place first.
"${SCRIPT_DIR}/setup-qos.sh"

echo
echo "==> Scenario 1 (schedulable): should RUN"
in_login sbatch /jobs/01-schedulable.sbatch

echo
echo "==> Scenario 2 (impossible request, gpu:16 on 8-GPU nodes):"
echo "    Slurm REJECTS this AT SUBMIT - a key difference from Kubernetes, which"
echo "    would accept it and leave the pod Pending forever. The rejection IS the"
echo "    lesson; the error below is expected:"
in_login sbatch /jobs/02-capacity-mismatch.sbatch || true

echo
echo "==> Scenario 3 (QoS cap): should PEND with a QOSMax...PerUser reason"
in_login sbatch --qos=capped /jobs/03-qos-blocked.sbatch

echo
echo "==> Scenario 4 (queue pressure): ~16 RUN, rest PEND (Resources/Priority)"
in_login sbatch /jobs/04-queue-pressure.sbatch

echo
echo "==> Giving the scheduler a few seconds..."
sleep 6

echo
echo "=== Queue (note ST=R running vs PD pending, and the NODELIST(REASON) col) ==="
in_login squeue -l || true
echo
echo "=== Pending reasons only ==="
in_login squeue --states=PENDING -o '%.10i %.12j %.8T %.6D %.20R' || true

echo
echo "Triage like a real cluster:"
echo "  squeue -l                          # who's R vs PD and why"
echo "  scontrol show job <jobid>          # the full request for a stuck job"
echo "  sinfo -N -l                        # the supply side (nodes, gres, state)"
echo "  sacct -X --format=JobID,JobName,State,AllocTRES%30,Elapsed   # history"
echo
echo "Expected outcomes:"
echo "  01-schedulable        -> Running"
echo "  02-capacity-mismatch  -> REJECTED at submit (impossible: no node has 16 GPUs)"
echo "  03-qos-blocked        -> Pending, QOSMax...PerUser (capped at 4 GPUs/user)"
echo "  04-queue-pressure     -> ~16 Running, rest Pending Resources/Priority"
echo
echo "Capture evidence:  make phase3-evidence"

#!/bin/bash
# SCENARIO 2 — impossible request. Asks for 16 GPUs on one node; each node has 8.
# Expected: REJECTED AT SUBMIT — "Requested node configuration is not available".
# This is a key Slurm-vs-Kubernetes difference: Kubernetes accepts an impossible
# request and leaves the pod Pending forever (Lesson 1's cuda-train-16gpu), whereas
# Slurm refuses it up front because no node could EVER satisfy it. Same root cause
# (asked for more than exists), opposite scheduler behaviour — that contrast is the
# lesson. For a *Pending* (possible-but-not-now) case, see scenarios 3 and 4.
#SBATCH --job-name=gpu-toobig
#SBATCH --partition=gpu
#SBATCH --nodes=1
#SBATCH --gres=gpu:16
#SBATCH --cpus-per-task=1
#SBATCH --mem=200M
#SBATCH --time=00:05:00
#SBATCH --output=/tmp/%x-%j.out

echo "If you ever see this run, a node grew more GPUs. It should stay Pending."
sleep 30

#!/bin/bash
# SCENARIO 3 — QoS limit. Asks for 6 GPUs while running under the 'capped' QoS,
# which setup-qos.sh limits to MaxTRESPerUser=gres/gpu=4. Expected: PENDING with
# a Reason in the QOSMax...PerUser family. Slurm analogue of Lesson 1B's quota
# enforcement — the limit is an accounting decision, fully valid on fake GRES.
#
# Requires: scripts/setup-qos.sh has been run (creates the 'capped' QoS + grants
# it to the lab account). Submit with:  sbatch --qos=capped 03-qos-blocked.sbatch
#SBATCH --job-name=gpu-qoscap
#SBATCH --partition=gpu
#SBATCH --qos=capped
#SBATCH --gres=gpu:6
#SBATCH --cpus-per-task=1
#SBATCH --mem=200M
#SBATCH --time=00:05:00
#SBATCH --output=/tmp/%x-%j.out

echo "Should stay Pending: 6 GPUs requested, QoS caps the user at 4."
sleep 30

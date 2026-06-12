#!/bin/bash
# SCENARIO 4 - queue pressure (job array). 24 array tasks, each holding 1 GPU for
# a while, against a 16-GPU fleet (2 nodes x 8). Expected: ~16 RUNNING, the rest
# PENDING with Reason=Resources/Priority - the backfill scheduler draining the
# queue over time. Slurm analogue of Lesson 1's 40-replica queue-pressure deploy.
#
# Submit with:  sbatch 04-queue-pressure.sbatch
#SBATCH --job-name=qp
#SBATCH --partition=gpu
#SBATCH --array=1-24
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=1
#SBATCH --mem=100M
#SBATCH --time=00:02:00
#SBATCH --output=/tmp/%x-%A_%a.out

echo "array task ${SLURM_ARRAY_TASK_ID} on $(hostname), holding 1 GPU"
sleep 25

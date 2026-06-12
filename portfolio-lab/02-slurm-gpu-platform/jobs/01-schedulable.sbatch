#!/bin/bash
# SCENARIO 1 — schedulable. Asks for 1 GPU; a node has 8 free. Expected: RUNS.
# Slurm analogue of Lesson 1's cuda-batch-small.
#SBATCH --job-name=gpu-small
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=1
#SBATCH --mem=200M
#SBATCH --time=00:02:00
#SBATCH --output=/tmp/%x-%j.out

echo "host:            $(hostname)"
echo "SLURM_JOB_GPUS:  ${SLURM_JOB_GPUS:-<unset>}"
# THE FAKE/REAL TELL: on a real node Slurm sets CUDA_VISIBLE_DEVICES to the
# allocated device index(es). Here the GRES is count-only, so the allocation is
# real but there is no device behind the number.
echo "CUDA_VISIBLE_DEVICES: ${CUDA_VISIBLE_DEVICES:-<unset — fake GRES has no device>}"
echo "Pretending to train for a few seconds..."
sleep 20
echo "done."

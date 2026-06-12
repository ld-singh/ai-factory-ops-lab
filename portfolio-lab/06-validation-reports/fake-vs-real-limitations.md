# Fake vs Real: The Limitations Ledger

> Part of [★ Your Lab Notebook](./README.md) · Course home:
> [AI Factory Operations Lab](../../README.md). Every lesson's "🔬 What you proved /
> did NOT prove" box traces back to this table - it is the course's source of truth
> for honest claims.

The credibility of this project rests on this file. It states exactly which
claims each lab mode can support.

## Claims the FAKE (simulation) mode supports

| Claim | Why it holds |
|---|---|
| Kubernetes GPU scheduling and placement behaviour | Scheduler compares integers; fake `nvidia.com/gpu` exercises the identical code path |
| Pending-pod triage workflow | Events and describe output are produced by the real control plane |
| Heterogeneous fleet modelling (pools, labels, taints) | Pure API-level design |
| Queue pressure and contention dynamics | Real scheduler, real contention, fake capacity |
| Queue/quota policy behaviour (with KAI Scheduler) | Scheduling policy is control-plane logic |
| Fractional-GPU *scheduling arithmetic* (HAMi/KAI concepts, Lesson 1C Parts 1–2) | Deciding whether a memory/core slice fits a device is bookkeeping over integers |
| Slurm GRES *scheduling* logic (Phase 3, fake GRES) | slurmctld scheduling does not require the device to exist |

## Claims ONLY the REAL mode supports

| Claim | Requires |
|---|---|
| CUDA containers execute on GPU | Driver + Container Toolkit + real GPU |
| Device plugin advertises real GPUs | GPU Operator on real hardware |
| Real GPU telemetry | DCGM Exporter on real hardware |
| Multi-pod sharing of one GPU with enforced memory slices (HAMi, Lesson 1C Part 3) | HAMi device plugin + HAMi-core intercepting real CUDA calls |
| Real GRES enforcement in Slurm | Slurm on a GPU machine |
| Inference SLO numbers (TTFT, tokens/sec, p95/p99) | Real GPU serving real model |

## Claims NEITHER mode in this lab supports

State these unprompted when presenting the project:

- CUDA kernel / compute performance characteristics
- NCCL collective performance, multi-node training behaviour
- NVLink / NVSwitch topology effects
- GPUDirect RDMA or any GPU networking data path
- MIG partitioning and isolation behaviour
- GPU-sharing performance interference under sustained load (HAMi compute-throttling
  accuracy, noisy-neighbour effects)
- Real GPU memory pressure, fragmentation, OOM dynamics at scale
- Production-scale fleet operations (hundreds+ GPUs, multi-tenant SLAs)

## Vocabulary discipline

Use: "control-plane simulation", "runtime validation", "architecture notes",
"operational drill". Avoid: any phrasing that lets a reader infer production
GPU fleet experience from this repo.

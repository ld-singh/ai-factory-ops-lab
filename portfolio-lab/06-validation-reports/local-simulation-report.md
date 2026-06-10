# Local Simulation Validation Report — Lesson 1 (Kubernetes GPU Scheduling)

> Your [lab notebook](./README.md) entry for [Lesson 1](../01-k8s-gpu-platform/README.md).
> Fill this in after running `make phase1-up`, `make phase1-demo`, `make phase1-evidence`.
> A report without an evidence directory reference is not complete.

## Environment

| Item | Value |
|---|---|
| Date | _TODO_ |
| Host OS | _TODO (macOS / Linux / WSL2)_ |
| kind version | _TODO_ |
| Kubernetes version | _TODO (`kubectl version`)_ |
| KWOK release | _TODO_ |
| Evidence directory | `evidence/k8s-YYYYMMDD-HHMMSS/` _TODO_ |

## Simulated fleet

5 fake nodes / 32 fake GPUs: 2x a100 (8 GPU), 1x h100 (8 GPU), 2x l40s (4 GPU).
Confirm with `gpu-allocatable.txt` in the evidence directory.

## Scenario results

| # | Scenario | Expected | Observed | Evidence file |
|---|---|---|---|---|
| 1 | `cuda-batch-small` (1 GPU, a100 pool) | Running on a100 node | _TODO_ | `pods-gpu-demo.txt` |
| 2 | `cuda-train-16gpu` (16 GPU) | Pending: Insufficient nvidia.com/gpu | _TODO_ | `describe-pod-cuda-train-16gpu.txt` |
| 3 | `cuda-needs-b200` (selector mismatch) | Pending: no matching node | _TODO_ | `describe-pod-cuda-needs-b200.txt` |
| 4 | `queue-pressure` (40 replicas vs 32 GPUs) | ~32 Running, ~8 Pending | _TODO_ | `pods-gpu-demo.txt`, `pending-pods.txt` |

## What this run proves

Control-plane GPU scheduling behaviour: placement across heterogeneous pools,
capacity-mismatch and selector-mismatch Pending diagnosis, contention behaviour
under queue pressure with the default scheduler.

## What this run does NOT prove

No CUDA execution, no driver/runtime path, no NCCL/NVLink/MIG/GPUDirect RDMA,
no real GPU memory behaviour, no real DCGM telemetry. See
`fake-vs-real-limitations.md`.

## Notes / surprises

_TODO — anything unexpected is the most interesting part of the report._

# Local Simulation Validation Report - Lesson 1 (Kubernetes GPU Scheduling)

> Your [lab notebook](./README.md) entry for [Lesson 1](../01-k8s-gpu-platform/README.md).
> Captured after `make phase1-up`, `make phase1-demo`, `make phase1-evidence`.

## Environment

| Item | Value |
|---|---|
| Date | 2026-06-14 |
| Host OS | Linux (WSL2) |
| kind version | v0.32.0 |
| Kubernetes version | v1.36.1 |
| KWOK release | kwok-v0.7.0 |
| GPU layer | run.ai fake-gpu-operator (advertises `nvidia.com/gpu`, emits synthetic DCGM) |
| Evidence directory | `evidence/k8s-20260614-153951/` |

## Simulated fleet

5 fake (KWOK) nodes, 32 fake GPUs advertised by the fake-gpu-operator, confirmed in
`gpu-allocatable.txt`:

| Node | Pool | GPUs |
|---|---|---|
| kwok-gpu-a100-0 | a100 | 8 |
| kwok-gpu-a100-1 | a100 | 8 |
| kwok-gpu-h100-0 | h100 | 8 |
| kwok-gpu-l40s-0 | l40s | 4 |
| kwok-gpu-l40s-1 | l40s | 4 |

Total: 32 GPUs. The two real kind nodes (control-plane, worker) advertise no GPUs.

## Scenario results

| # | Scenario | Expected | Observed | Evidence file |
|---|---|---|---|---|
| 1 | `cuda-batch-small` (1 GPU, a100 pool) | Running on a100 node | **Running on `kwok-gpu-a100-1`** | `pods-gpu-demo.txt` |
| 2 | `cuda-train-16gpu` (16 GPU) | Pending: Insufficient nvidia.com/gpu | **Pending** - `0/7 nodes available: ... 6 Insufficient nvidia.com/gpu` (1 node untolerated taint) | `describe-pod-cuda-train-16gpu.txt` |
| 3 | `cuda-needs-b200` (selector mismatch) | Pending: no matching node | **Pending** - `0/7 nodes available: ... 6 node(s) didn't match Pod's node affinity/selector` | `describe-pod-cuda-needs-b200.txt` |
| 4 | `queue-pressure` (40 replicas vs 32 GPUs) | ~32 Running, ~8 Pending | **31 Running, 9 Pending** (the 32nd GPU is held by `cuda-batch-small`) | `pods-gpu-demo.txt`, `pending-pods.txt` |

Namespace totals: **32 Running, 11 Pending** in `gpu-demo` (9 queue-pressure +
`cuda-train-16gpu` + `cuda-needs-b200`). The fleet's 32 GPUs are the binding
constraint, exactly as designed.

The two Pending root causes are distinct and diagnosable from Events alone:
`Insufficient nvidia.com/gpu` (asked for more than any node has) vs
`didn't match Pod's node affinity/selector` (asked for a pool that does not exist).

## What this run proves

Control-plane GPU scheduling with the **default scheduler**: placement across
heterogeneous pools, capacity-mismatch and selector-mismatch Pending diagnosis,
contention behaviour under queue pressure, operator-shaped GPU advertisement (a device
plugin, not a hand-written integer), and a synthetic DCGM metrics stream (the Lesson 4
bridge).

## What this run does NOT prove

No CUDA execution, no driver/runtime path, no NCCL/NVLink/MIG/GPUDirect RDMA, no real
GPU memory behaviour. The DCGM metrics are fabricated by the operator (dashboard/alert
*design*, not real telemetry), and pods on KWOK nodes are simulated (no real container).
See `fake-vs-real-limitations.md`.

## Notes / surprises

- Right after `phase1-up`, the `VERSION` column for the KWOK nodes fills in one node at
  a time (some blank, then `kwok-v0.7.0`); the kwok-controller stamps `kubeletVersion`
  asynchronously. It converges within seconds and does not affect scheduling.
- `cuda-batch-small` landed on `kwok-gpu-a100-1` (either a100 node is valid; placement
  is up to the scheduler's scoring).

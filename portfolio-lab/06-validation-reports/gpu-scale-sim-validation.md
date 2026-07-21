# GPU Fleet Scale Simulation Validation Report - Lesson 1D (Volcano)

> Your [lab notebook](./README.md) entry for
> [Lesson 1D](../01-k8s-gpu-platform/volcano-scale-sim/README.md).
> Captured after `make up`, `make volcano-up`, `make demo`, `make evidence`
> (from the lesson directory), on the `small.json` topology.

## Environment

| Item | Value |
|---|---|
| Date | 2026-07-21 |
| Host OS | Linux |
| kind version | v0.32.0 |
| Kubernetes version | v1.36.1 |
| KWOK release | v0.8.0 |
| Volcano | v1.10.0 (`volcanosh/vc-scheduler:v1.10.0`, upstream installer manifest) |
| GPU layer | run.ai fake-gpu-operator 0.0.59 (values rendered from `topology/small.json`) |
| Evidence directory | `evidence/gpu-scale-20260721-093643/` |

## Simulated fleet

5 fake (KWOK) nodes, 32 fake GPUs, generated from `topology/small.json` and
advertised by the fake-gpu-operator, confirmed in `nodes.yaml`:

| Node | Pool | Product | GPUs |
|---|---|---|---|
| kwok-scale-a100-0 | a100 | NVIDIA-A100-SXM4-80GB | 8 |
| kwok-scale-a100-1 | a100 | NVIDIA-A100-SXM4-80GB | 8 |
| kwok-scale-h100-0 | h100 | NVIDIA-H100-80GB-HBM3 | 8 |
| kwok-scale-l40s-0 | l40s | NVIDIA-L40S | 4 |
| kwok-scale-l40s-1 | l40s | NVIDIA-L40S | 4 |

Total: 32 GPUs. Demo pods carry `schedulerName: volcano` and a
`ai-factory-ops-lab/scale-sim: "true"` nodeSelector, so this run is isolated from
any Lesson 1 (`kwok-gpu-*`) nodes that may share the cluster.

## Scenario results

| # | Scenario | Gang size | Expected | Observed | Evidence file |
|---|---|---|---|---|---|
| 1 | `fit-gang` (queue `team-a`) | 16 × 1 GPU | Whole gang Running | **16/16 Running** across all three pools; PodGroup phase `Running` | `pods-wide.txt`, `podgroups.yaml` |
| 2 | `overflow-gang` (queue `team-b`) | 33 × 1 GPU vs 32 GPUs | Whole gang Pending (all-or-nothing) | **33/33 Pending**, PodGroup phase `Inqueue` - even though 16 pods were individually schedulable | `pods-wide.txt`, `events.txt` |
| 3 | `needs-b200` (queue `team-a`) | 4 × 1 GPU, `gpu-pool: b200` selector | Pending: no matching pool | **4/4 Pending**, PodGroup phase `Inqueue`, selector mismatch in Events | `events.txt` |

Namespace totals in `gpu-scale`: **16 Running, 37 Pending** (33 overflow-gang +
4 needs-b200). PodGroup phases from `podgroups.yaml`: `Running` / `Inqueue` / `Inqueue`.

## The gang-scheduling signature

The single most important line in the run is the overflow-gang Event. From
`events.txt` (verbatim):

```text
Warning   FailedScheduling   pod/overflow-gang-30   pod group is not ready, 33 Pending, 33 minAvailable; Pending: 16 Schedulable, 17 Unschedulable. Origin reason is overflow-gang-16: 0/7 nodes are unavailable: 7 Insufficient nvidia.com/gpu.
Normal    Scheduled          podgroup/fit-gang      pod group is ready
```

`16 Schedulable, 17 Unschedulable` - Volcano *could* have started 16 of the 33
pods, and started **none** of them, because `minMember: 33` was not satisfiable.
Contrast with Lesson 1's default-scheduler `queue-pressure` run, which happily
started 31 of 40 pods and left the rest Pending. That difference (partial
placement vs all-or-nothing) is gang scheduling, captured in one Event.

The selector-mismatch scenario stays diagnosable from Events alone, same as
Lesson 1:

```text
Warning   FailedScheduling   pod/needs-b200-0   0/7 nodes are unavailable: 2 Insufficient nvidia.com/gpu, 5 node(s) didn't match Pod's node affinity/selector.
```

## What this run proves

Volcano control-plane behaviour on a topology-generated fake fleet: scheduler
handoff via `schedulerName: volcano`, `Queue` objects accepting work
(`team-a`/`team-b`, state `Open`), `PodGroup` gang semantics (all-or-nothing
admission with `minMember`), the `Inqueue` vs `Running` PodGroup lifecycle, and
Pending root-cause diagnosis (capacity vs selector) under queue pressure.

## What this run does NOT prove

No CUDA execution, no driver/runtime path, no NCCL/NVLink/MIG/GPUDirect RDMA,
no real GPU memory behaviour, and no scheduler *performance* claims (this ran on
the 5-node `small.json` topology; larger topologies stress the API server, not
real hardware). Pods on KWOK nodes are simulated - no real container runs. See
[`fake-vs-real-limitations.md`](./fake-vs-real-limitations.md).

## Notes / surprises

- Right after pod creation, Volcano briefly reports the gang as
  `2 Pending, 33 minAvailable` - it evaluates the PodGroup while the pods are
  still being created, then converges to the full `33 Pending` verdict within a
  couple of scheduling cycles. Harmless, but surprising in `events.txt`.
- The Volcano admission webhook rejects Queue objects for a few seconds after
  the deployment reports Ready (the webhook paths register late); the demo
  script retries queue creation for exactly this reason.
- `fit-gang` spread across all three pools (a100/h100/l40s) - with no pool
  selector, Volcano's scoring distributes the gang; placement is not
  pool-affine by default.

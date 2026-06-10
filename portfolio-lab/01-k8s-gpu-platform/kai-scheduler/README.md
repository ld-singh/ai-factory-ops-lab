# kai-scheduler/

Queue-based GPU scheduling concepts, anchored to the queue-pressure scenario in
`../workloads/gpu-deployment-queue-pressure.yaml`.

## The problem this module addresses

The default kube-scheduler has no concept of queues, quotas-with-borrowing,
fair-share between teams, or gang scheduling. Run the queue-pressure demo and
you get 32 Running pods and 8 Pending pods in arrival order — no policy at all.
Real AI platforms need answers to:

- Which **team/project** gets GPUs when demand exceeds supply?
- Can a team **borrow** idle GPUs beyond its quota, and be **reclaimed** from later?
- Do distributed jobs get **gang scheduled** (all pods or none), avoiding
  deadlocked partial allocations that waste GPUs?
- How is **starvation** of low-priority queues detected and handled?

## KAI Scheduler

[KAI Scheduler](https://github.com/NVIDIA/KAI-Scheduler) is NVIDIA's
open-source Kubernetes scheduler (Apache-2.0, derived from Run:ai's scheduling
engine) built for exactly these problems: hierarchical queues, quota with
over-quota borrowing and reclaim, gang scheduling, and GPU sharing concepts.

### Status in this lab

> **HONESTY MARKER:** install steps and CRD schemas below are intentionally NOT
> hardcoded. KAI Scheduler is an actively evolving project; copy exact Helm
> commands and Queue CRD fields from the official repo README and docs at the
> time you run this, not from this file:
> https://github.com/NVIDIA/KAI-Scheduler
>
> When this module is exercised, the actual manifests used and outputs captured
> go into `../../06-validation-reports/` like every other module.

### Planned exercise (works on the fake fleet)

KAI Scheduler makes scheduling decisions at the control-plane level, so the
KWOK fake GPU fleet is a valid environment for studying its queueing behaviour:

1. Install KAI Scheduler per official docs into the simulation cluster.
2. Create two queues (e.g. `team-research`, `team-prod`) with different quotas.
3. Re-run the queue-pressure scenario split across both queues with
   `schedulerName` pointing at KAI and the queue label applied.
4. Observe: quota enforcement, over-quota borrowing when one queue is idle,
   reclaim when the owning queue returns, and Pending behaviour vs the default
   scheduler baseline.
5. Capture `kubectl get pods`, queue status objects, and events as evidence.

### What this proves / does not prove

- **Proves:** queue and quota policy behaviour, scheduling decisions, starvation
  and reclaim dynamics — all control-plane.
- **Does not prove:** GPU sharing/fractioning at runtime (that requires real
  GPUs and runtime components), nor anything about CUDA-level behaviour.

## Why this matters operationally

- Default kube-scheduler vs queue-based AI schedulers: what is missing and why
  it matters financially (idle GPU = burning money; partial gang allocation =
  deadlock that burns even more).
- Quota-with-borrowing vs hard quota: utilization vs predictability trade-off.
- Gang scheduling: why distributed training without it deadlocks clusters.

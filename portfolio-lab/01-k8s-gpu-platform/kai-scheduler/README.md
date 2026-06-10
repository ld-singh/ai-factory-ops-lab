# Lesson 1 · Extension — Queue-based GPU scheduling (KAI Scheduler)

> Part of [Lesson 1 — Kubernetes GPU Scheduling](../README.md). This is the natural
> follow-on to **Step 3, scenario 4** (queue pressure). Do that first.

🎯 **Learning objectives** — after this extension you can:

1. Explain what the default kube-scheduler *cannot* do for multi-team GPU clusters:
   no queues, no quota-with-borrowing, no fair-share, no gang scheduling.
2. Describe how a queue-based scheduler (KAI) solves the queue-pressure mess you
   produced in Step 3 with actual policy.
3. Articulate the financial stakes — idle GPUs and deadlocked gang allocations both
   burn money.

🧭 **Mode:** 🟦 Simulation (no GPU). Queueing is control-plane logic, so the fake
fleet is a valid place to study it.

## The problem this addresses

The default kube-scheduler has no concept of queues, quotas-with-borrowing,
fair-share between teams, or gang scheduling. Run the queue-pressure demo and you get
32 Running pods and 8 Pending pods in arrival order — **no policy at all.** That's
the wall you hit at the end of Step 3. Real AI platforms need answers to:

- Which **team/project** gets GPUs when demand exceeds supply?
- Can a team **borrow** idle GPUs beyond its quota, and be **reclaimed** from later?
- Do distributed jobs get **gang scheduled** (all pods or none), avoiding deadlocked
  partial allocations that waste GPUs?
- How is **starvation** of low-priority queues detected and handled?

## KAI Scheduler

[KAI Scheduler](https://github.com/NVIDIA/KAI-Scheduler) is NVIDIA's open-source
Kubernetes scheduler (Apache-2.0, derived from Run:ai's scheduling engine) built for
exactly these problems: hierarchical queues, quota with over-quota borrowing and
reclaim, gang scheduling, and GPU sharing concepts.

### Status in this lab

> **HONESTY MARKER:** install steps and CRD schemas below are intentionally NOT
> hardcoded. KAI Scheduler is an actively evolving project; copy exact Helm commands
> and Queue CRD fields from the official repo README and docs at the time you run
> this, not from this file: https://github.com/NVIDIA/KAI-Scheduler
>
> When this extension is exercised, the actual manifests used and outputs captured go
> into [`../../06-validation-reports/`](../../06-validation-reports/) like every other
> lesson.

### 🔧 Guided exercise (works on the fake fleet)

KAI Scheduler makes scheduling decisions at the control-plane level, so the KWOK fake
GPU fleet is a valid environment for studying its queueing behaviour:

1. Install KAI Scheduler per official docs into the simulation cluster.
2. Create two queues (e.g. `team-research`, `team-prod`) with different quotas.
3. Re-run the queue-pressure scenario split across both queues with `schedulerName`
   pointing at KAI and the queue label applied.
4. **Observe:** quota enforcement, over-quota borrowing when one queue is idle,
   reclaim when the owning queue returns, and Pending behaviour vs the default
   scheduler baseline you saw in Step 3.
5. Capture `kubectl get pods`, queue status objects, and events as evidence.

✅ **Checkpoint:** you can demonstrate one queue borrowing a GPU beyond its quota
while the other queue is idle, then losing it back (reclaim) when the owning queue
submits work. Capture both states.

### 🔬 What this proves / does not prove

- **Proves:** queue and quota policy behaviour, scheduling decisions, starvation and
  reclaim dynamics — all control-plane.
- **Does not prove:** GPU sharing/fractioning at runtime (that requires real GPUs and
  runtime components), nor anything about CUDA-level behaviour.

## Why this matters operationally

- Default kube-scheduler vs queue-based AI schedulers: what is missing and why it
  matters financially (idle GPU = burning money; partial gang allocation = deadlock
  that burns even more).
- Quota-with-borrowing vs hard quota: utilization vs predictability trade-off.
- Gang scheduling: why distributed training without it deadlocks clusters.

📎 **Related runbook:** [kai-scheduler-queue-starvation.md](../../../runbooks/kai-scheduler-queue-starvation.md).

➡️ **Back to:** [Lesson 1](../README.md) · **Next lesson:**
[Lesson 2 — Real GPU validation](../gpu-operator-real/README.md).

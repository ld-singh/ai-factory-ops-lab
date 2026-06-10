# Lesson 1B — Queue-Based GPU Scheduling with KAI Scheduler

> Course home: [AI Factory Operations Lab](../../../README.md) · Previous:
> [Lesson 1 — Kubernetes GPU Scheduling](../README.md) · Next:
> [Lesson 2 — Real GPU validation](../gpu-operator-real/README.md)
>
> Do [Lesson 1, Step 3 scenario 4 (queue pressure)](../README.md#step-3--triage-like-its-a-real-cluster)
> first — this lesson picks up exactly where that wall is.

## Why this lesson is the best argument for fake GPUs

Here's the thing worth internalising: **the hardest, most valuable GPU-platform
skills to learn are queue policy and gang scheduling — and they cost nothing to learn,
because they are pure control-plane decisions.**

A queue scheduler never touches a GPU. It decides *which pod binds to which node, in
what order, and whether a group of pods may bind at all*. Those are API operations
over integers and labels. A KWOK fake node with `nvidia.com/gpu: 8` exercises the
**identical** decision path as a real DGX. So on a laptop, with zero GPU spend, you
can faithfully reproduce:

- quota enforcement across teams,
- over-quota **borrowing** of idle capacity,
- **reclaim** (preempting borrowed capacity when the owner returns),
- **fair-share** ordering between queues,
- **gang scheduling** — the all-or-nothing placement that stops distributed training
  from deadlocking a cluster,
- priority and **starvation** dynamics.

Every one of those is something companies normally only learn by burning real GPU
hours. You can learn the *decision logic* here for free. What you **cannot** learn
here is anything that needs the GPU to actually exist — runtime GPU sharing/memory
isolation, MIG, CUDA. We mark that line explicitly in every exercise.

🎯 **Learning objectives** — after this lesson you can:

1. Explain, concretely, what the default kube-scheduler cannot do for a multi-team
   GPU cluster, and why each gap costs money.
2. Install KAI Scheduler into the simulation cluster and point workloads at it.
3. Design a **hierarchical queue + quota** model and demonstrate enforcement.
4. Reproduce **borrowing** and **reclaim** between two queues, and capture both
   states as evidence.
5. Demonstrate **gang scheduling** preventing a partial-allocation deadlock.
6. Trigger and diagnose **queue starvation**, then resolve it with priority/fair-share.
7. State precisely which of these you proved on fake GPUs vs which require real
   hardware.

🧭 **Mode:** 🟦 Simulation (no GPU). Queueing, quota, and gang decisions are
control-plane logic, so the fake fleet is a *valid* environment for all of it.

📋 **Prerequisites:** [Lesson 1](../README.md) complete and the fake fleet up
(`make phase1-up`).

---

## Part 1 — The gap you're filling

Re-run the baseline so the problem is fresh:

```bash
kubectl get pods -n gpu-demo -l app=queue-pressure -o wide
kubectl get pods -n gpu-demo -l app=queue-pressure --field-selector status.phase=Pending | wc -l
```

With the **default kube-scheduler** you get 32 Running and 8 Pending pods in arrival
order — and that's *all* it can do. The default scheduler has no concept of:

| Missing capability | The question it can't answer | What it costs you |
|---|---|---|
| **Queues / quota** | Which *team* owns these GPUs when demand exceeds supply? | First-come monopolises the fleet; other teams blocked |
| **Borrowing** | Can team B use team A's idle GPUs right now? | Idle GPUs sit dark while jobs wait — burning money |
| **Reclaim** | When team A comes back, can it take its GPUs back? | Either A is starved, or B never yields — pick your pain |
| **Fair-share** | Who's been under-served lately and should go next? | Loud/frequent submitters crowd out everyone else |
| **Gang scheduling** | Can this 8-pod job get *all 8* GPUs or *none*? | Partial allocation: 5 pods hold GPUs waiting for 3 that never come — **deadlock that wastes GPUs** |
| **Priority** | Is this a production job that should jump the queue? | Batch experiments delay revenue-serving work |

💡 **The financial framing matters in interviews and in practice:** an idle GPU is
money on fire, and a *partially* gang-allocated distributed job is worse — it holds
GPUs hostage while making no progress. Queue schedulers exist to turn the Pending
pile above into *policy*.

---

## Part 2 — KAI Scheduler, and what runs where

[KAI Scheduler](https://github.com/NVIDIA/KAI-Scheduler) is NVIDIA's open-source
Kubernetes scheduler (Apache-2.0, derived from Run:ai's scheduling engine) built for
exactly these problems: hierarchical queues, quota with over-quota borrowing and
reclaim, gang scheduling, bin-packing/spread strategies, priorities, and GPU sharing
concepts.

**How it coexists with the fake fleet:**

```
KAI components (real pods)            Workload pods (target fake nodes)
─────────────────────────            ─────────────────────────────────
scheduler / podgrouper / etc.        cuda-* pods with schedulerName: kai
run on the REAL kind worker  ──────▶ bound by KAI onto kwok-gpu-* fake nodes
(they're just controllers)           (KWOK simulates them reaching Running)
```

💡 **Why this is sound:** KAI's own pods are ordinary controllers — they run on the
real worker node and make decisions. The *workloads* they schedule carry
`schedulerName: <kai>` and a queue label, and get bound onto the fake GPU nodes. The
binding, the gang check, the quota math, the reclaim/eviction — all happen at the API
level, which is exactly what KWOK serves. The containers never execute, but the
**scheduling decisions are real**.

> **HONESTY MARKER — read before you copy anything below.** KAI Scheduler is actively
> evolving. The exact Helm chart name/values, the `Queue` CRD `apiVersion`/fields, and
> the queue/priority **label keys** change between releases. Every manifest in this
> lesson is marked **ILLUSTRATIVE** and shows the *shape* of the concept, not a
> guaranteed copy-paste. **Confirm exact names against the official repo and docs at
> the time you run this:** https://github.com/NVIDIA/KAI-Scheduler
> When you run it for real, the manifests you actually used and the output you
> captured go into [`../../06-validation-reports/`](../../06-validation-reports/).

### Install (pattern)

```bash
# ILLUSTRATIVE — get the current chart name, repo URL, and version from the official
# KAI Scheduler install docs. Do not assume these values are current.
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia   # verify exact repo/chart in docs
helm repo update
helm install kai-scheduler <official-chart> -n kai-scheduler --create-namespace
```

✅ **Checkpoint:** KAI's controller pods are `Running` in their namespace:
`kubectl get pods -n kai-scheduler`. You haven't scheduled any workload with it yet —
that's the next parts.

---

## Part 3 — Exercise A: two queues with quota (enforcement)

**Goal:** prove that quota is enforced — a queue cannot exceed its deserved share
while another queue wants its own.

1. Create two queues with quotas that sum to the fleet (32 fake GPUs). For example
   `team-research` = 16, `team-prod` = 16.

   ```yaml
   # ILLUSTRATIVE Queue shape — confirm apiVersion/kind/field names in KAI docs.
   # The idea: a queue with a "deserved"/guaranteed GPU quota. Real field names vary.
   apiVersion: <kai-queue-apiVersion>
   kind: Queue
   metadata:
     name: team-research
   spec:
     resources:
       gpu:
         quota: 16          # deserved/guaranteed share (confirm field name)
         overQuotaWeight: 1 # used when borrowing idle capacity (confirm field name)
   ```

2. Submit ~16 single-GPU pods to each queue. Point each at KAI and tag the queue:

   ```yaml
   # ILLUSTRATIVE pod spec fragment — confirm the queue label KEY in KAI docs.
   spec:
     schedulerName: <kai-scheduler-name>
     # KAI associates a pod to a queue via a label; the exact key changes by release.
     # e.g. metadata.labels["<kai-queue-label-key>"]: team-research
   ```

   You can adapt [`../workloads/gpu-deployment-queue-pressure.yaml`](../workloads/gpu-deployment-queue-pressure.yaml)
   by duplicating it per team, setting `replicas: 16`, adding `schedulerName` and the
   queue label, and keeping the existing KWOK toleration.

✅ **Checkpoint:** both queues run ~16 pods; neither exceeds its quota while the other
is full. Capture `kubectl get pods -n gpu-demo -o wide` and the queue status objects.

🔬 **Proved on fake GPUs:** quota enforcement is a control-plane decision — fully
valid here. **Not proved:** that 16 real GPUs would physically serve the work.

---

## Part 4 — Exercise B: borrowing (utilisation)

**Goal:** show idle capacity being lent out, instead of sitting dark.

1. Leave `team-research` **idle** (submit nothing).
2. Submit ~32 single-GPU pods to `team-prod` (double its 16 quota).

✅ **Checkpoint:** `team-prod` runs **more than its 16-GPU quota** — it borrows
`team-research`'s idle 16 and approaches 32 Running. Capture the pod list showing
`team-prod` over quota.

💡 **Why this is the money-saver:** without borrowing, half the fleet would idle while
`team-prod` jobs waited. Borrowing is how queue schedulers keep expensive GPUs busy
*and* preserve ownership.

🔬 **Proved on fake GPUs:** the borrowing decision and the resulting placement. The
scheduler genuinely allocates beyond quota into idle capacity.

---

## Part 5 — Exercise C: reclaim (the hard part)

**Goal:** the owner returns and takes its GPUs back — this is where naive systems
fail.

1. With `team-prod` still over quota (borrowing), now submit ~16 pods to
   `team-research`.

✅ **Checkpoint:** KAI **reclaims** the borrowed GPUs — some `team-prod` pods are
**evicted back to Pending** so `team-research` can reach its guaranteed 16. Capture
the before (prod over quota) and after (prod reclaimed down to ~16, research at ~16)
states, plus the eviction events:
`kubectl get events -n gpu-demo --sort-by=.lastTimestamp`.

💡 **Why reclaim is the whole point:** borrowing without reclaim is just over-commit
— the owner gets starved. Reclaim is what makes "borrow idle GPUs" safe: you can lend
freely *because* you can take it back. This is the single most important dynamic in
multi-team GPU scheduling, and you just reproduced it with zero GPUs.

🔬 **Proved on fake GPUs:** the reclaim/preemption decision and eviction. **Not
proved:** graceful checkpoint/restart of a *real* training job mid-eviction (that's a
workload-runtime concern, not a scheduler one).

---

## Part 6 — Exercise D: gang scheduling (anti-deadlock)

**Goal:** prove all-or-nothing placement, the feature that keeps distributed training
from deadlocking a cluster.

**Setup the trap first (default scheduler):** submit a single "job" of 10 pods × 1
GPU into a fleet that only has, say, 8 free GPUs, using the *default* scheduler. You
get **8 pods Running holding GPUs, 2 Pending forever** — the job makes zero progress
yet occupies 8 GPUs. That's the deadlock.

**Now with KAI gang scheduling:** submit the same 10-pod job as a single *gang* (KAI
groups the pods of a workload and requires a minimum-member count to bind together).

```yaml
# ILLUSTRATIVE — KAI groups pods into a "pod group" with a minimum member count.
# The mechanism (a PodGroup-like object, or annotations the pod-grouper reads) and
# its exact fields change by release. Confirm against KAI docs.
# Concept: minMember: 10  → bind all 10 or none.
```

✅ **Checkpoint:** the 10-pod gang stays **entirely Pending** while only 8 GPUs are
free — it does **not** grab the 8 and block. Free up capacity (delete other pods) and
the whole gang schedules **together**. Capture both states.

💡 **Why this is gold to learn for free:** gang scheduling bugs in the real world cost
enormous GPU hours — a 64-GPU job half-allocated wastes 32 GPUs indefinitely. Here you
see the all-or-nothing logic directly, on fake nodes, in seconds.

🔬 **Proved on fake GPUs:** the gang admission decision (bind-all-or-none) and the
anti-deadlock behaviour — fully control-plane. **Not proved:** the actual NCCL
all-reduce the gang would run once placed (that needs real GPUs + NVLink/network —
[Lesson 2](../gpu-operator-real/README.md) territory, and even there, single-node).

---

## Part 7 — Exercise E: priority & starvation

**Goal:** reproduce a low-priority queue being starved, then fix it.

1. Flood the fleet with high-priority `team-prod` work so `team-research` (lower
   priority, no guaranteed quota in this variant) gets nothing for a while.
2. Observe `team-research` pods Pending indefinitely — **starvation**.
3. Resolve it: give `team-research` a guaranteed quota (so reclaim protects it) or
   adjust fair-share/priority so it eventually gets a turn.

✅ **Checkpoint:** you can *cause* starvation on demand and then *eliminate* it with a
quota/priority change, capturing both. That's the exact muscle the
[queue-starvation runbook](../../../runbooks/kai-scheduler-queue-starvation.md)
exercises.

🔬 **Proved on fake GPUs:** starvation detection and the fair-share/priority response —
all scheduler logic.

---

## What you can and cannot learn here — the precise line

| Capability | Learnable on the fake fleet? | Why |
|---|---|---|
| Hierarchical queues & quota enforcement | ✅ Yes | Pure control-plane bookkeeping |
| Over-quota borrowing | ✅ Yes | Placement decision over integers |
| Reclaim / preemption | ✅ Yes | Eviction is an API operation |
| Fair-share ordering | ✅ Yes | Scheduler-internal accounting |
| Gang scheduling (all-or-none) | ✅ Yes | Admission decision before binding |
| Priority & starvation dynamics | ✅ Yes | Ordering logic |
| Bin-pack vs spread placement | ✅ Yes | Node-selection strategy |
| **GPU sharing / fractional GPUs (scheduling view)** | ⚠️ Partly | KAI's *bookkeeping* of fractions is visible; **runtime memory isolation is NOT** |
| **MIG partitioning** | ❌ No | Requires real GPU + driver |
| **Actual CUDA / NCCL the gang would run** | ❌ No | Requires real GPUs (and, for scale, real network) |

💡 The pattern is consistent with the whole course: **decisions** are learnable on
fakes; **execution and isolation** need real hardware. KAI happens to be almost
entirely about decisions — which is why it's such a high-value, low-cost thing to
study here.

---

## Evidence to capture (lab notebook)

For each exercise, snapshot into your [lab notebook](../../06-validation-reports/README.md):

- `kubectl get pods -n gpu-demo -o wide` (before/after states)
- the `Queue` status objects (`kubectl get queue -o yaml` or the equivalent KAI lists)
- `kubectl get events -n gpu-demo --sort-by=.lastTimestamp` (borrow/reclaim/gang/evict)
- the exact manifests you applied (since the illustrative ones above are not
  authoritative)

A claim like "I demonstrated quota borrowing and reclaim between two queues" is only
backed once those captures exist. See
[`fake-vs-real-limitations.md`](../../06-validation-reports/fake-vs-real-limitations.md).

---

## Operational takeaways

- **Default kube-scheduler vs queue-based AI schedulers:** the six gaps in Part 1 are
  the reason platforms like KAI exist; each maps to real money.
- **Quota-with-borrowing vs hard quota:** the utilisation-vs-predictability trade-off.
  Borrowing maximises utilisation; reclaim is the safety valve that makes it
  acceptable.
- **Gang scheduling:** non-negotiable for distributed training — without it, large
  jobs deadlock clusters.

📎 **Related runbook:** [kai-scheduler-queue-starvation.md](../../../runbooks/kai-scheduler-queue-starvation.md).

➡️ **Back to:** [Lesson 1](../README.md) · **Next lesson:**
[Lesson 2 — Real GPU validation](../gpu-operator-real/README.md), where you finally
run something below the kubelet on real hardware.

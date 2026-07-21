# Lesson 1B - Queue-Based GPU Scheduling with KAI Scheduler

> Course home: [AI Factory Operations Lab](../../../README.md) · Previous:
> [Lesson 1 - Kubernetes GPU Scheduling](../README.md) · Next:
> [Lesson 1C - GPU sharing with HAMi](../hami/README.md)
>
> Do [Lesson 1, Step 3 scenario 4 (queue pressure)](../README.md#step-3---triage-like-its-a-real-cluster)
> first - this lesson picks up exactly where that wall is.

## What this lesson teaches

Queue policy is the most valuable, most expensive-to-learn GPU-platform skill: which
team's pod binds, in what order, and whether a group binds at all. KAI Scheduler is
NVIDIA's open-source scheduler for exactly that (hierarchical queues, quota, over-quota
borrowing, reclaim, gang scheduling, fair-share).

You can run KAI with **no real GPU**, but there is an important catch you must know up
front.

> ### The cluster requirement (read before you run)
>
> KAI does **not** schedule against raw `nvidia.com/gpu` in a node's allocatable; its
> GPU accounting comes from a GPU-operator topology. That is exactly why **Lesson 1's
> fleet is KWOK + the fake-gpu-operator** (the operator advertises GPUs and provides
> the topology). KAI simply **reuses that shared Lesson 1 fleet** - `make up` here
> builds the same fleet as `make phase1-up` and then installs KAI on top. No separate
> fleet, no duplicated setup.
>
> Two things that would otherwise waste your time (both handled by the Lesson 1
> scripts this reuses):
> - **Chart source.** The fleet uses the run.ai JFrog chart
>   (`https://runai.jfrog.io/artifactory/api/helm/fake-gpu-operator-charts-prod`). The
>   `ghcr.io/run-ai/...` OCI build is DRA-oriented and never populates `nvidia.com/gpu`.
> - **`scheduler.kubeScheduler.imageTag`** is not used by KAI's chart; KAI versions
>   itself. (That knob is HAMi's, [Lesson 1C](../hami/README.md).)

🎯 **Learning objectives** - after this lesson you can:

1. Explain what the default kube-scheduler cannot do for a multi-team GPU cluster.
2. Install KAI Scheduler on the shared Lesson 1 fleet and point workloads at a queue.
3. Design a **hierarchical queue + quota** model and **demonstrate enforcement**
   (the validated, runnable exercise here).
4. Explain over-quota **borrowing**, **reclaim**, and **gang scheduling**, and read the
   precise limits of demonstrating them on a fake-GPU simulation.

🧭 **Mode:** 🟦 Simulation (no GPU), via the fake-gpu-operator. Real runtime behavior
(CUDA, memory isolation, MIG) is out of scope; see [Lesson 6](../gpu-operator-real/README.md).

> **KAI can also slice GPUs - this lesson just doesn't.** Every exercise here asks for
> *whole* GPUs (`nvidia.com/gpu: 1`) to keep the focus on **queue policy** - quota,
> borrowing, reclaim, gang. KAI does fractions too, so read "whole-GPU" as a scoping
> choice, not a KAI limit. The hands-on sharing lab is [Lesson 1C (HAMi)](../hami/README.md).
>
> **What KAI can do as of June 2026.** A pod can ask for a slice two ways - a fixed amount
> of GPU memory, or a `gpu-fraction` (e.g. `0.5`) that KAI converts to a memory limit once
> it picks the node. KAI owns the *scheduling*: which pods share which GPU. For the cap
> *inside* the container it sets a `CUDA_DEVICE_MEMORY_LIMIT` and leaves enforcement to
> **HAMi-core**, run on each GPU node
> ([NVIDIA/KAI-Scheduler #60](https://github.com/NVIDIA/KAI-Scheduler/pull/60), merged
> 2026-06-09).
>
> **So KAI and HAMi aren't rivals here** - they're two layers of one stack. KAI brings the
> queue and the scheduling; HAMi-core brings the hard memory isolation, which is exactly
> what [Lesson 1C](../hami/README.md) teaches.

📋 **Prerequisites:** docker, kind, kubectl, helm, jq. The lesson's `make up` builds
the shared Lesson 1 fleet (kind + KWOK + fake-gpu-operator, 32 GPUs) if it is not
already up, then installs KAI.

---

## Set up once

```bash
cd portfolio-lab/01-k8s-gpu-platform/kai-scheduler
make up        # shared Lesson 1 fleet (kind+KWOK+fake-gpu-operator, 32 GPUs) + install KAI
make queues    # create the namespace + the queue hierarchy (see manifests/queues.yaml)
```

`make queues` is a separate step on purpose: open
[`manifests/queues.yaml`](manifests/queues.yaml) and read it first. It defines the
hierarchy the exercises use - a parent queue (`ai-factory`) with two leaf queues
(`team-research`, `team-prod`, quota 8 each) plus a separate `gang-demo` queue. The
queue is the core KAI primitive, so it is worth seeing the YAML before running anything.

✅ **Checkpoint:** KAI's pods are Running and the queues exist:

```bash
kubectl -n kai-scheduler get pods
kubectl get queues.scheduling.run.ai
```

Run `make up` and `make queues` **once**. Each exercise below applies its own manifest
and re-prepares its workloads (it clears the `kai-demo` namespace first), so you can run
them back to back. Capture evidence and uninstall **at the very end**, not between
exercises.

### The whole loop

Each `make` step prints its own result and ends with a `Verify:` line - the `kubectl`
command to re-check that state by hand. (The exercise sections below explain each result.)

```bash
cd portfolio-lab/01-k8s-gpu-platform/kai-scheduler

make up            # shared Lesson 1 fleet (kind+KWOK+fake-gpu-operator) + KAI
make queues        # create the namespace + the queue hierarchy

make demo-quota    # A: two teams each fill their 8-GPU quota
make demo-borrow   # B: prod submits 16 (double its quota)
make demo-reclaim  # C: research returns (run right after demo-borrow)
make demo-gang     # D: a 10-GPU gang binds all-or-none

make evidence      # snapshot queues/pods/events into evidence/<timestamp>/
make uninstall     # delete the whole kind cluster (KAI + fleet + workloads)
```

## The exercises (run in order)

### Exercise A - quota enforcement (validated)

```bash
make demo-quota
```

Applies [`manifests/exercise-a-quota.yaml`](manifests/exercise-a-quota.yaml): 8
single-GPU pods to `team-research` and 8 to `team-prod` (quota 8 each). Open the file
to see how a pod joins a queue (`schedulerName: kai-scheduler` + the
`kai.scheduler/queue` label).

**Expect:** both queues reach **8 Running, 0 Pending** - neither exceeds its quota
while the other is using its share. Confirm:

```bash
kubectl get pods -n kai-demo -L kai.scheduler/queue -o wide
```

This is the validated result end to end: the operator advertises GPUs, KAI's webhook
routes the pods, and quota is enforced per queue.

### Exercise B - borrowing idle capacity

```bash
make demo-borrow
```

Applies [`manifests/exercise-b-borrow.yaml`](manifests/exercise-b-borrow.yaml): leaves
`team-research` idle and submits 16 pods to `team-prod` (double its quota).

- **Concept:** `team-prod` should borrow the idle GPUs and run beyond its quota.
- **Observed on this fake fleet:** it stays at ~8. KAI did not lend a sibling's
  idle-but-guaranteed capacity even with `limit > quota`. The script prints this.
  Treat it as a concept demo; the over-quota behavior needs a real multi-tenant
  cluster (or deeper KAI tuning) to reproduce.

### Exercise C - reclaim (run immediately after B)

```bash
make demo-reclaim
```

Applies [`manifests/exercise-c-reclaim.yaml`](manifests/exercise-c-reclaim.yaml).
**Run this right after `make demo-borrow`**, with nothing in between - it adds
`team-research`'s pods on top of the still-running borrow workload (and errors if
`prod-borrow` is not present).

- **Concept:** when the owner returns, KAI evicts borrowed pods so `team-research`
  gets its guaranteed share.
- **Observed:** because borrowing did not occur in B, there is nothing to reclaim;
  `team-research` simply takes free GPUs. Inspect with
  `kubectl get events -n kai-demo --sort-by=.lastTimestamp`.

### Exercise D - gang scheduling (anti-deadlock)

```bash
make demo-gang
```

Applies [`manifests/exercise-d-filler.yaml`](manifests/exercise-d-filler.yaml) to fill
the fleet down to ~8 free, then [`manifests/exercise-d-gang.yaml`](manifests/exercise-d-gang.yaml)
(note the `kai.scheduler/batch-min-member: "10"` annotation - the all-or-none knob).

- **Concept:** all-or-none - the gang should stay entirely Pending until 10 GPUs are
  free, rather than grabbing 8 and deadlocking.
- **Observed:** a plain Deployment schedules as independent per-pod groups (so ~8
  run), and a batch Job is gang-grouped but KWOK marks its pods `Completed` instantly,
  so the held state isn't observable here. The script explains this as it runs. Gang
  is best validated on a real cluster.

> Exercise E (priority & starvation) has no `make` target; follow
> [Part 7](#part-7---exercise-e-priority--starvation) manually if you want to explore it.

## Capture evidence, then tear down (at the end)

```bash
make evidence    # snapshot queues, pods, and events into evidence/<timestamp>/
make uninstall   # delete the whole kind cluster (KAI + the shared fleet + all workloads)
```

`make evidence` captures whatever is deployed at that moment, so run it right after the
exercise you want to document (for a clean record, capture **Exercise A**, the
validated one).

> **Run `make uninstall` last** - after you have worked through all the exercises **and
> read the Parts below**. It deletes the entire kind cluster (KAI and the shared Lesson 1
> fleet), so anything not captured with `make evidence` is gone. There is no need to
> tear down between exercises.

The Parts below explain the concepts and the manual manifests behind each exercise.

---

## Part 1 - The gap you're filling

Re-run the baseline so the problem is fresh:

```bash
kubectl get pods -n gpu-demo -l app=queue-pressure -o wide
kubectl get pods -n gpu-demo -l app=queue-pressure --field-selector status.phase=Pending | wc -l
```

With the **default kube-scheduler** you get roughly 31 Running and 9 Pending pods
(the fleet has 32 GPUs, and scenario 1's `cuda-batch-small` already holds one) - in
arrival order, and that's *all* it can do. The default scheduler has no concept of:

| Missing capability | The question it can't answer | What it costs you |
|---|---|---|
| **Queues / quota** | Which *team* owns these GPUs when demand exceeds supply? | First-come monopolises the fleet; other teams blocked |
| **Borrowing** | Can team B use team A's idle GPUs right now? | Idle GPUs sit dark while jobs wait - burning money |
| **Reclaim** | When team A comes back, can it take its GPUs back? | Either A is starved, or B never yields - pick your pain |
| **Fair-share** | Who's been under-served lately and should go next? | Loud/frequent submitters crowd out everyone else |
| **Gang scheduling** | Can this 8-pod job get *all 8* GPUs or *none*? | Partial allocation: 5 pods hold GPUs waiting for 3 that never come - **deadlock that wastes GPUs** |
| **Priority** | Is this a production job that should jump the queue? | Batch experiments delay revenue-serving work |

💡 **The financial framing is what matters in practice:** an idle GPU is
money on fire, and a *partially* gang-allocated distributed job is worse - it holds
GPUs hostage while making no progress. Queue schedulers exist to turn the Pending
pile above into *policy*.

---

## Part 2 - KAI Scheduler, and what runs where

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

💡 **Why this is sound:** KAI's own pods are ordinary controllers - they run on the
real worker node and make decisions. The *workloads* they schedule carry
`schedulerName: <kai>` and a queue label, and get bound onto the fake GPU nodes. The
binding, the gang check, the quota math, the reclaim/eviction - all happen at the API
level, which is exactly what KWOK serves. The containers never execute, but the
**scheduling decisions are real**.

> **⚠️ Don't copy the manifests below blindly.** KAI Scheduler is actively
> evolving. The exact Helm chart name/values, the `Queue` CRD `apiVersion`/fields, and
> the queue/priority **label keys** change between releases. Every manifest in this
> lesson is marked **ILLUSTRATIVE** and shows the *shape* of the concept, not a
> guaranteed copy-paste. **Confirm exact names against the official repo and docs at
> the time you run this:** https://github.com/NVIDIA/KAI-Scheduler
> When you run it for real, the manifests you actually used and the output you
> captured go into [`../../06-validation-reports/`](../../06-validation-reports/).

### Install (pattern)

```bash
# ILLUSTRATIVE - get the current chart name, repo URL, and version from the official
# KAI Scheduler install docs. Do not assume these values are current.
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia   # verify exact repo/chart in docs
helm repo update
helm install kai-scheduler <official-chart> -n kai-scheduler --create-namespace
```

✅ **Checkpoint:** KAI's controller pods are `Running` in their namespace:
`kubectl get pods -n kai-scheduler`. You haven't scheduled any workload with it yet -
that's the next parts.

---

## Part 3 - Exercise A: two queues with quota (enforcement)

**Goal:** prove that quota is enforced - a queue cannot exceed its deserved share
while another queue wants its own.

1. Create two queues with quotas that sum to the fleet (32 fake GPUs). For example
   `team-research` = 16, `team-prod` = 16.

   ```yaml
   # ILLUSTRATIVE Queue shape - confirm apiVersion/kind/field names in KAI docs.
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
   # ILLUSTRATIVE pod spec fragment - confirm the queue label KEY in KAI docs.
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

🔬 **Proved on fake GPUs:** quota enforcement is a control-plane decision - fully
valid here. **Not proved:** that 16 real GPUs would physically serve the work.

---

## Part 4 - Exercise B: borrowing (utilisation)

**Goal:** show idle capacity being lent out, instead of sitting dark.

1. Leave `team-research` **idle** (submit nothing).
2. Submit ~32 single-GPU pods to `team-prod` (double its 16 quota).

✅ **Checkpoint:** `team-prod` runs **more than its 16-GPU quota** - it borrows
`team-research`'s idle 16 and approaches 32 Running. Capture the pod list showing
`team-prod` over quota.

💡 **Why this is the money-saver:** without borrowing, half the fleet would idle while
`team-prod` jobs waited. Borrowing is how queue schedulers keep expensive GPUs busy
*and* preserve ownership.

🔬 **Proved on fake GPUs:** the borrowing decision and the resulting placement. The
scheduler genuinely allocates beyond quota into idle capacity.

---

## Part 5 - Exercise C: reclaim (the hard part)

**Goal:** the owner returns and takes its GPUs back - this is where naive systems
fail.

1. With `team-prod` still over quota (borrowing), now submit ~16 pods to
   `team-research`.

✅ **Checkpoint:** KAI **reclaims** the borrowed GPUs - some `team-prod` pods are
**evicted back to Pending** so `team-research` can reach its guaranteed 16. Capture
the before (prod over quota) and after (prod reclaimed down to ~16, research at ~16)
states, plus the eviction events:
`kubectl get events -n gpu-demo --sort-by=.lastTimestamp`.

💡 **Why reclaim is the whole point:** borrowing without reclaim is just over-commit
- the owner gets starved. Reclaim is what makes "borrow idle GPUs" safe: you can lend
freely *because* you can take it back. This is the single most important dynamic in
multi-team GPU scheduling, and you just reproduced it with zero GPUs.

🔬 **Proved on fake GPUs:** the reclaim/preemption decision and eviction. **Not
proved:** graceful checkpoint/restart of a *real* training job mid-eviction (that's a
workload-runtime concern, not a scheduler one).

---

## Part 6 - Exercise D: gang scheduling (anti-deadlock)

**Goal:** prove all-or-nothing placement, the feature that keeps distributed training
from deadlocking a cluster.

**Setup the trap first (default scheduler):** submit a single "job" of 10 pods × 1
GPU into a fleet that only has, say, 8 free GPUs, using the *default* scheduler. You
get **8 pods Running holding GPUs, 2 Pending forever** - the job makes zero progress
yet occupies 8 GPUs. That's the deadlock.

**Now with KAI gang scheduling:** submit the same 10-pod job as a single *gang* (KAI
groups the pods of a workload and requires a minimum-member count to bind together).

```yaml
# ILLUSTRATIVE - KAI groups pods into a "pod group" with a minimum member count.
# The mechanism (a PodGroup-like object, or annotations the pod-grouper reads) and
# its exact fields change by release. Confirm against KAI docs.
# Concept: minMember: 10  → bind all 10 or none.
```

✅ **Checkpoint:** the 10-pod gang stays **entirely Pending** while only 8 GPUs are
free - it does **not** grab the 8 and block. Free up capacity (delete other pods) and
the whole gang schedules **together**. Capture both states.

💡 **Why this is gold to learn for free:** gang scheduling bugs in the real world cost
enormous GPU hours - a 64-GPU job half-allocated wastes 32 GPUs indefinitely. Here you
see the all-or-nothing logic directly, on fake nodes, in seconds.

🔬 **Proved on fake GPUs:** the gang admission decision (bind-all-or-none) and the
anti-deadlock behaviour - fully control-plane. **Not proved:** the actual NCCL
all-reduce the gang would run once placed (that needs real GPUs + NVLink/network -
[Lesson 6](../gpu-operator-real/README.md) territory, and even there, single-node).

---

## Part 7 - Exercise E: priority & starvation

**Goal:** reproduce a low-priority queue being starved, then fix it.

1. Flood the fleet with high-priority `team-prod` work so `team-research` (lower
   priority, no guaranteed quota in this variant) gets nothing for a while.
2. Observe `team-research` pods Pending indefinitely - **starvation**.
3. Resolve it: give `team-research` a guaranteed quota (so reclaim protects it) or
   adjust fair-share/priority so it eventually gets a turn.

✅ **Checkpoint:** you can *cause* starvation on demand and then *eliminate* it with a
quota/priority change, capturing both. That's the exact muscle the
[queue-starvation runbook](../../../runbooks/kai-scheduler-queue-starvation.md)
exercises.

🔬 **Proved on fake GPUs:** starvation detection and the fair-share/priority response -
all scheduler logic.

---

## What you can and cannot learn here - the precise line

| Capability | Learnable on the fake fleet? | Why |
|---|---|---|
| Hierarchical queues & quota enforcement | ✅ Yes | Pure control-plane bookkeeping |
| Over-quota borrowing | ✅ Yes | Placement decision over integers |
| Reclaim / preemption | ✅ Yes | Eviction is an API operation |
| Fair-share ordering | ✅ Yes | Scheduler-internal accounting |
| Gang scheduling (all-or-none) | ✅ Yes | Admission decision before binding |
| Priority & starvation dynamics | ✅ Yes | Ordering logic |
| Bin-pack vs spread placement | ✅ Yes | Node-selection strategy |
| **GPU sharing / fractional GPUs (scheduling view)** | ⚠️ Partly | KAI's *bookkeeping* of fractions is visible; **runtime memory isolation is NOT** - [Lesson 1C (HAMi)](../hami/README.md) is where you prove enforcement on real hardware |
| **MIG partitioning** | ❌ No | Requires real GPU + driver |
| **Actual CUDA / NCCL the gang would run** | ❌ No | Requires real GPUs (and, for scale, real network) |

💡 The pattern is consistent with the whole course: **decisions** are learnable on
fakes; **execution and isolation** need real hardware. KAI happens to be almost
entirely about decisions - which is why it's such a high-value, low-cost thing to
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
- **Gang scheduling:** non-negotiable for distributed training - without it, large
  jobs deadlock clusters.

- **KAI vs Volcano:** KAI's focus is queue quota, borrowing, and reclaim on a
  single fake fleet. [Lesson 1D](../volcano-scale-sim/README.md) complements it
  with Volcano's `Queue`/`PodGroup` gang scheduling at fleet scale - read the two
  back to back if you care about admission control for distributed jobs.

📎 **Related runbook:** [kai-scheduler-queue-starvation.md](../../../runbooks/kai-scheduler-queue-starvation.md).

➡️ **Back to:** [Lesson 1](../README.md) · **Next:**
[Lesson 1C - GPU sharing & fractional GPUs with HAMi](../hami/README.md) (the
sharing concepts are free; its hands-on isolation half runs in the Lesson 6 rental),
then [Lesson 1D - GPU fleet scale simulation with Volcano](../volcano-scale-sim/README.md)
for gang scheduling, and eventually [Lesson 6 - Real GPU](../../real-gpu-session/README.md),
where you finally run something below the kubelet on real hardware.

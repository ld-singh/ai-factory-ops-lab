# Lesson 1 — Kubernetes GPU Scheduling

> Course home: [AI Factory Operations Lab](../../README.md) · Previous:
> [Lesson 0 — Orientation](../../README.md#lesson-0--orientation--setup) ·
> Next: [Lesson 2 — Real GPU validation](./gpu-operator-real/README.md)

In this lesson you build a **heterogeneous GPU fleet that has no GPUs in it**, run
real workloads against it, and learn to diagnose why GPU pods get stuck Pending —
using the exact same `kubectl` workflow you'd use on a production cluster.

🎯 **Learning objectives** — after this lesson you can:

1. Explain why `nvidia.com/gpu` is just an integer to the Kubernetes scheduler, and
   why that makes fake GPU nodes a *legitimate* way to study scheduling.
2. Model a heterogeneous fleet (A100/H100/L40S pools) with node labels, taints, and
   GFD-style product labels.
3. Deploy a schedulable GPU workload and watch it land on the right pool.
4. Diagnose two different Pending causes — capacity mismatch vs fleet mismatch —
   from `kubectl describe` and Events alone.
5. Reproduce queue pressure (more demand than GPUs) and explain why the default
   scheduler can't solve it — motivating [KAI Scheduler](./kai-scheduler/README.md).

🧭 **Mode:** 🟦 Simulation (no GPU). The real-hardware half of this module is
[Lesson 2](./gpu-operator-real/README.md).

📋 **Prerequisites:** [Lesson 0](../../README.md#lesson-0--orientation--setup)
complete (`make check` passes).

This module has two halves, and the line between them is the whole point:

| Half | Mode | GPU required | Lesson |
|---|---|---|---|
| `kind/`, `kwok/`, `workloads/`, `kai-scheduler/`, `fake-gpu-operator/` | 🟦 Control-plane simulation | No | This lesson |
| `gpu-operator-real/` | 🟥 Real GPU runtime validation | Yes (one NVIDIA GPU) | [Lesson 2](./gpu-operator-real/README.md) |

---

## The big idea (read before you run anything)

💡 The Kubernetes scheduler **never talks to a GPU.** It compares integer resource
requests against integer node `allocatable` values. A node advertising
`nvidia.com/gpu: 8` exercises the *identical* scheduling code path whether those 8
GPUs are real silicon or a number we wrote into a fake node object. That's why this
entire lesson works on a laptop — and exactly why it can't tell you anything about
CUDA, NVLink, or GPU memory. Hold onto that distinction; it comes back in every
"what you proved" box.

Deep-dive page: [kwok/README.md — why fake nodes are legitimate](./kwok/README.md).

---

## Step 1 — Stand up the simulated fleet

```bash
# From the repo root
make phase1-up
```

This runs three scripts in order: create the kind cluster, install KWOK, then stamp
out the fake GPU node pools.

💡 **Why:** [`setup-kind.sh`](./scripts/setup-kind.sh) gives you a *real*
Kubernetes control plane (so the scheduler logic is real); [`install-kwok.sh`](./scripts/install-kwok.sh)
adds KWOK, which lets fake nodes join and have their pod lifecycle simulated; and
[`create-fake-gpu-nodes.sh`](./scripts/create-fake-gpu-nodes.sh) creates the fleet
below. See [kind/README.md](./kind/README.md) and [kwok/README.md](./kwok/README.md)
for the details of each.

The simulated fleet you just built:

| Pool | Nodes | GPUs/node | Product label (GFD-style) |
|---|---|---|---|
| `a100` | 2 | 8 | `NVIDIA-A100-SXM4-80GB` |
| `h100` | 1 | 8 | `NVIDIA-H100-80GB-HBM3` |
| `l40s` | 2 | 4 | `NVIDIA-L40S` |

**Total simulated fleet: 5 nodes, 32 "GPUs".**

✅ **Checkpoint:** you can see the fleet, with product labels and GPU counts:

```bash
kubectl get nodes -L nvidia.com/gpu.product -L gpu-pool
```

You should see five `kwok-gpu-*` nodes across the three pools, each reporting its
product label. If they're missing, re-run `make phase1-up` (it's idempotent).

---

## Step 2 — Deploy the four scenarios

```bash
make phase1-demo
```

This applies four deliberately-chosen workloads into the `gpu-demo` namespace.
Three are designed to teach you something specific:

| Scenario | Workload | Designed outcome |
|---|---|---|
| 1 — Schedulable | [`cuda-batch-small`](./workloads/gpu-pod-schedulable.yaml) | **Running** on an A100 node (1 GPU fits) |
| 2 — Capacity mismatch | [`cuda-train-16gpu`](./workloads/gpu-pod-pending-capacity.yaml) | **Pending** — asks for 16 GPUs; no node has more than 8 |
| 3 — Fleet mismatch | [`cuda-needs-b200`](./workloads/gpu-pod-pending-selector.yaml) | **Pending** — nodeSelector targets a `b200` pool that doesn't exist |
| 4 — Queue pressure | [`queue-pressure`](./workloads/gpu-deployment-queue-pressure.yaml) | 40 replicas × 1 GPU vs 32 GPUs → ~32 Running, rest Pending |

💡 **Why these four:** scenario 1 proves placement works; scenarios 2 and 3 are the
two most common real-world Pending causes (asked for more than exists vs asked for a
pool that doesn't exist), and they produce *different* events; scenario 4 is the raw
material for the queueing discussion in [Lesson 1's KAI section](./kai-scheduler/README.md).

✅ **Checkpoint:** one pod Running, the two single Pending pods Pending, and the
deployment partially scheduled:

```bash
kubectl get pods -n gpu-demo -o wide
```

---

## Step 3 — Triage like it's a real cluster

This is the skill the lesson exists for. Inspect the fleet and the stuck pods with
the same commands you'd use on production:

```bash
kubectl get nodes -L nvidia.com/gpu.product -L gpu-pool   # fleet at a glance
kubectl describe node kwok-gpu-a100-0                      # one node in detail
kubectl get pods -n gpu-demo -o wide                       # who's Running vs Pending
kubectl get events -n gpu-demo --sort-by=.lastTimestamp    # the scheduler's reasoning
```

Now diagnose each Pending pod yourself:

```bash
kubectl describe pod -n gpu-demo cuda-train-16gpu   # scenario 2
kubectl describe pod -n gpu-demo cuda-needs-b200    # scenario 3
```

💡 **Why the events differ:** read the `Events:` section at the bottom of each
`describe`. Scenario 2 fails on **`Insufficient nvidia.com/gpu`** — the scheduler
found candidate nodes but none had enough GPUs. Scenario 3 fails on
**`node(s) didn't match Pod's node affinity/selector`** — the scheduler rejected
every node *before* even checking GPU counts, because the `gpu-pool: b200` selector
matched nothing. Same symptom (Pending), completely different root cause and fix.

✅ **Checkpoint — predict, then verify.** Before reading each `describe`, write down
which of the two failure reasons you expect. You understand the lesson when your
prediction matches the event every time. Specifically you should observe:

1. `cuda-batch-small` → **Running** on `kwok-gpu-a100-0` or `-1`.
2. `cuda-train-16gpu` → **Pending**, `Insufficient nvidia.com/gpu` (deliberate
   capacity mismatch — no single node exposes 16 GPUs).
3. `cuda-needs-b200` → **Pending**, selector/affinity mismatch (deliberate fleet
   mismatch — the `b200` pool was never created).
4. `queue-pressure` → some replicas Running, the rest Pending. Count them:
   `kubectl get pods -n gpu-demo -l app=queue-pressure | grep -c Running` should be
   about 32 (the fleet's total GPU count), the rest Pending.

---

## Step 4 — Capture evidence

```bash
make phase1-evidence
```

💡 **Why:** [`collect-k8s-evidence.sh`](../../scripts/collect-k8s-evidence.sh)
snapshots node, pod, and event state into a timestamped directory under
[`../06-validation-reports/evidence/`](../06-validation-reports/). In ops work, "I
saw it happen" doesn't count — the captured artifact does. This is also how the
course enforces honesty: a lesson is only "Complete" once its report holds real
output.

✅ **Checkpoint:** fill in
[`../06-validation-reports/local-simulation-report.md`](../06-validation-reports/local-simulation-report.md)
with your environment details and a reference to the evidence directory you just
produced.

---

## Step 5 — Tear down

```bash
make phase1-down
```

✅ **Checkpoint:** `kind get clusters` no longer lists `ai-factory-lab`.

---

## 🔬 What this lesson proved — and did NOT

**Proved (simulation):**
- GPU-aware scheduling and placement across heterogeneous pools
- The two canonical Pending root causes and how to tell them apart
- Capacity contention / queue-pressure behaviour (more requests than GPUs)
- Fleet modelling: labels, taints, pool design for A100/H100/L40S-class nodes
- The Pending-pod triage workflow — identical to the one used on real clusters

**Did NOT prove:** no CUDA execution, no NCCL, no NVLink/NVSwitch, no MIG, no
GPUDirect RDMA, no real GPU memory behaviour, no DCGM telemetry. The containers
never actually run. Those belong to [Lesson 2](./gpu-operator-real/README.md) and
only count once captured in
[`../06-validation-reports/real-gpu-validation-report.md`](../06-validation-reports/real-gpu-validation-report.md).
The full ledger: [`fake-vs-real-limitations.md`](../06-validation-reports/fake-vs-real-limitations.md).

---

## Go deeper (optional sub-pages)

These expand on parts of the lesson. Read them when the corresponding step makes you
curious:

- [kind/](./kind/README.md) — the local cluster, and kind vs k3d.
- [kwok/](./kwok/README.md) — how fake GPU nodes are built and why it's legitimate.
- [kai-scheduler/](./kai-scheduler/README.md) — **the natural follow-on to Step 3's
  scenario 4:** queues, quotas-with-borrowing, gang scheduling. Solve the
  queue-pressure mess with policy.
- [fake-gpu-operator/](./fake-gpu-operator/README.md) — a richer simulation that runs
  real containers with fake GPUs and emits DCGM-shaped metrics (sets up Lesson 4).
- [gpu-operator-real/](./gpu-operator-real/README.md) — **Lesson 2:** prove the real
  GPU path on actual hardware.

## Directory guide

- `kind/` — kind cluster config (control plane + one real worker for system pods)
- `kwok/` — KWOK installation notes and fake GPU node manifests/templates
- `fake-gpu-operator/` — notes on run.ai's fake-gpu-operator as a richer alternative
- `kai-scheduler/` — queue/quota scheduling concepts and KAI Scheduler notes
- `workloads/` — the four demo workloads (schedulable, two Pending, queue pressure)
- `gpu-operator-real/` — Lesson 2: real GPU validation guide
- `scripts/` — setup and demo automation

➡️ **Next:** [Lesson 2 — Real GPU validation](./gpu-operator-real/README.md), where
the same manifests run on actual hardware and you prove everything this lesson
deliberately couldn't.

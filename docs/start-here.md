---
hide:
  - toc
---

# Start Here

New to the course? This page is your orientation. Five minutes here and you will know exactly
what to run first.

## Who this is for

You are comfortable in a terminal and have **basic Kubernetes literacy** (you know what a Pod
and a node are). You want to learn how AI infrastructure platforms are actually scheduled,
observed, shared, and operated.

**No prior NVIDIA GPU stack experience is assumed. No GPU is required to start.**

By the end you can reason about, and *demonstrate* with evidence, GPU scheduling, queueing, the
driver-to-pod path, GPU sharing, inference capacity, and the operational workflows around them.

## The one idea: learn without a GPU

Most of what a GPU platform engineer does is **control-plane** work: scheduling, queueing,
sharing decisions, observability design, capacity planning. None of that needs a physical GPU
to learn, because the behaviour is the same shape whether the GPU is real or simulated.

So the course teaches the majority on your laptop, for free, and gathers the few
**hardware-specific** things (a CUDA pod actually executing, an enforced memory cap, real
telemetry, real benchmarks) into one optional capstone on a single cheap rented GPU.

| Mode | What it is | What it proves | What it does **not** prove |
|---|---|---|---|
| 🟦 **Simulation** | kind + KWOK fake nodes, fake-gpu-operator, fake GRES, synthetic DCGM / vLLM metrics | Control-plane behaviour: scheduling, queueing, sharing *decisions*, dashboard/alert *design* | Anything below the kubelet: CUDA execution, memory enforcement, MIG, NCCL/NVLink, real throughput |
| 🟥 **Real GPU** | One entry-level NVIDIA card, real driver + toolkit + runtime | The runtime path, enforced sharing, real telemetry and inference numbers, single node | Multi-node scale, topology (NVLink/InfiniBand), distributed training |

Keeping that line clear is itself a skill this course teaches. You will always know whether you
proved a *decision* or proved *hardware behaviour*.

## How evidence works (course completion)

A lesson is not "done" when a command runs. It is done when you have **captured evidence** of
what you built, what you broke, how you diagnosed it, and what you proved. The course ships a
[lab notebook](portfolio-lab/06-validation-reports/README.md) of validation reports, and the
capstone produces evidence you can keep in a portfolio. This is the difference between "I ran a
tutorial" and "I can operate this."

## What you need

- **Docker, kind, kubectl, helm, jq** on a laptop (Linux, macOS, or WSL2). `make check` verifies
  them.
- That is all for the free tier. The capstone additionally needs one rented GPU VM, and is
  clearly marked.

## Expected effort

- **Free tier (Lessons 1 to 5):** a focused evening or two. Individual lessons run roughly 20 to
  45 minutes each (estimates; you can stop and resume between lessons).
- **Capstone (Lesson 6):** one focused session, roughly 1 to 2 hours, on a GPU that costs about
  $5 to $10 for the session.

## The recommended sequence

Work these in order. Lessons 1 to 1D are the scheduling spine; everything after builds on that
mental model.

1. **[Lesson 1 - Kubernetes GPU scheduling](portfolio-lab/01-k8s-gpu-platform/README.md)** -
   the fake fleet and the driver-to-pod path.
2. **[1B - Queue scheduling (KAI)](portfolio-lab/01-k8s-gpu-platform/kai-scheduler/README.md)**,
   **[1C - GPU sharing (HAMi)](portfolio-lab/01-k8s-gpu-platform/hami/README.md)**,
   **[1D - Fleet scale (Volcano)](portfolio-lab/01-k8s-gpu-platform/volcano-scale-sim/README.md)**
   - the scheduling family.
3. **[Lesson 2 - Slurm](portfolio-lab/02-slurm-gpu-platform/README.md)** - GPU jobs on an HPC
   scheduler.
4. **[Lesson 3 - GPU observability](portfolio-lab/03-observability/README.md)** and
   **[3B - Inference observability](portfolio-lab/03-observability/inference-observability/README.md)**
   - metrics, dashboards, SLO alerts.
5. **[Lesson 4A - Inference benchmarks](portfolio-lab/04-inference-serving/README.md)** and
   **[4B - The KV cache](portfolio-lab/04-inference-serving/kv-cache/README.md)** - serving
   capacity and its memory limit.
6. **[Lesson 5 - Cluster lifecycle](portfolio-lab/05-bcm-style-cluster-lifecycle/README.md)** -
   the node lifecycle drill.
7. **[Lesson 6 - The AI Factory Operator Capstone](portfolio-lab/real-gpu-session/README.md)**
   (optional) - prove the hardware-specific half on one real GPU.

## What to run first

```bash
git clone https://github.com/ld-singh/ai-factory-ops-lab
cd ai-factory-ops-lab
make check          # verify docker, kind, kubectl, helm, jq
make phase1-up      # kind cluster + KWOK + fake GPU node pools
make phase1-demo    # schedulable + intentionally-Pending GPU workloads
```

Then open [Lesson 1](portfolio-lab/01-k8s-gpu-platform/README.md) and follow the Build, Break,
Diagnose, Prove loop. When you are done, `make phase1-down` tears it all back down.

➡️ **Begin:** [Lesson 1 - Kubernetes GPU scheduling](portfolio-lab/01-k8s-gpu-platform/README.md).

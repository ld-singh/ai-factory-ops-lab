# AI Factory Operations Lab - A Hands-On Course

📖 **Read it as a website: https://ld-singh.github.io/ai-factory-ops-lab/**
(built with MkDocs Material; the lesson markdown below is the source).

A guided, learn-by-doing course in **AI/HPC infrastructure operations**: NVIDIA GPU
infrastructure concepts, Kubernetes GPU scheduling, Slurm GPU workload management,
GPU observability, inference serving, and BCM-style cluster lifecycle patterns.

You don't read this repo - you *run* it. Each lesson has you stand something up,
break it on purpose, diagnose it the way you would on a real cluster, and capture
the evidence. Most of the course needs **no GPU at all**; one lesson uses a single
rented GPU VM and is clearly marked.

> **Read this first - what the course claims, and what it doesn't**
>
> This course teaches production cloud/Kubernetes/DevOps operational discipline
> applied to the NVIDIA GPU stack. It does **not** pretend a laptop is a GPU
> datacenter.
>
> Every lesson declares one of two **modes** (simulation vs real GPU) and states
> exactly what it proves and what it does not. The boundary between "I simulated
> the control plane" and "I validated real GPU hardware" is kept explicit in every
> lesson and documented in
> [`portfolio-lab/06-validation-reports/fake-vs-real-limitations.md`](./portfolio-lab/06-validation-reports/fake-vs-real-limitations.md).
> Knowing exactly where that line sits is itself one of the skills this course teaches.

---

## Who this course is for

You're comfortable in a terminal and have basic Kubernetes literacy (you know what
a Pod and a node are), and you want to learn how AI infrastructure platforms are
actually scheduled, observed, and operated. By the end you'll be able to reason
about - and demonstrate - GPU scheduling, queueing, the full driver-to-pod GPU
path, and the operational workflows around them.

No prior NVIDIA GPU stack experience is assumed. No GPU is required to start.

---

## How the course works

Each lesson follows the same rhythm so you always know where you are:

| Section in every lesson | What it gives you |
|---|---|
| 🎯 **Learning objectives** | What you'll be able to do after the lesson |
| 🧭 **Mode & prerequisites** | Simulation or real GPU, and what you need installed |
| 🔧 **Steps** | Copy-paste commands, each with the **expected output** |
| 💡 **Why it works** | The concept behind the command - the part that transfers |
| ✅ **Checkpoint** | A concrete check to confirm the step worked before moving on |
| 🔬 **What you proved / did NOT prove** | What that lesson's mode does and doesn't establish |
| ➡️ **Next** | Where to go next |

The two **modes** you'll see throughout:

- **🟦 Simulation mode (no GPU).** kind + KWOK fake nodes with the fake-gpu-operator
  GPU layer (advertises GPUs + synthetic DCGM metrics), Slurm
  with fake GRES. Proves *control-plane behaviour*: scheduling, queueing, placement,
  triage, operational workflow. Nothing below the kubelet.
- **🟥 Real GPU mode (one NVIDIA GPU).** Real driver, container toolkit, GPU
  Operator, CUDA pod, DCGM telemetry. Proves the *real runtime path*, single-node.

Lessons 1–5 are entirely simulation mode. Every real-GPU piece is gathered into the
single optional **Lesson 6**, which runs on one rented GPU - so the sim lessons stay
free and the hardware work is one clearly-marked session at the end.

---

## The Learning Path

Work through these in order. Lessons 1–1C are the spine; everything after builds on
the GPU-scheduling mental model you form there. **Lessons 1–5 are all no-GPU
simulation**; every piece that needs real hardware is gathered into the single,
optional **Lesson 6** at the end.

| # | Lesson | Mode | GPU? | You'll be able to… |
|---|---|---|---|---|
| **0** | [Orientation & setup](#lesson-0---orientation--setup) | - | No | Install the toolchain and verify your machine is ready |
| **1** | [Kubernetes GPU scheduling](./portfolio-lab/01-k8s-gpu-platform/README.md) | 🟦 Sim | No | Build a fake GPU fleet and diagnose why GPU pods stay Pending |
| **1B** | [Queue-based scheduling - KAI Scheduler](./portfolio-lab/01-k8s-gpu-platform/kai-scheduler/README.md) | 🟦 Sim | No | Install KAI on a fake GPU fleet (fake-gpu-operator) and **enforce queue quota**; understand borrowing/reclaim/gang and the limits of demoing them on fakes |
| **1C** | [GPU sharing & fractional GPUs - HAMi](./portfolio-lab/01-k8s-gpu-platform/hami/README.md) | 🟦 Sim | No | Compare time-slicing/MPS/MIG/HAMi and prove fractional **scheduling** on fakes (binpack, per-device accounting); the real isolation half runs in Lesson 6 |
| **2** | [Slurm GPU workload management](./portfolio-lab/02-slurm-gpu-platform/README.md) | 🟦 Sim | No | Run a Slurm-in-Docker cluster with fake GRES; schedule GPU jobs, QoS caps, queue pressure, drain/resume |
| **3** | [GPU observability](./portfolio-lab/03-observability/README.md) | 🟦 Sim | No | Stand up Prometheus/Grafana over synthetic DCGM; build dashboards + SLO alerts; **trip them on purpose** |
| **4** | [Inference serving](./portfolio-lab/04-inference-serving/README.md) | 🟦 Sim/harness | No | Run the $0 CPU load harness for TTFT/p95-p99/tokens-per-sec; real benchmark numbers come in Lesson 6 |
| **5** | [BCM-style cluster lifecycle](./portfolio-lab/05-bcm-style-cluster-lifecycle/README.md) | 🟨 Concept+drill | No | Run a provision→health-gate→patch→retire node-lifecycle drill; map it to BCM |
| **6** | [Real GPU (one-rental capstone)](./portfolio-lab/real-gpu-session/README.md) | 🟥 Real | Opt (1) | The **only** real-GPU lesson: in one rental, prove the GPU runtime path + real DCGM, HAMi sharing, Slurm GRES, and the inference benchmark - then tear down |
| **★** | [Your lab notebook](./portfolio-lab/06-validation-reports/) | - | - | Capture evidence; a lesson is only "done" when its report holds real output |

> **Lessons 1–5 run entirely on a laptop with no GPU.** The only real hardware is the
> optional Lesson 6, which consolidates every GPU step into a single cheap rental.
> Lessons 2, 3 and 5 stand up real clusters/stacks against *fake* GPUs; Lesson 4 ships
> a $0 CPU harness tier. The status table is at the bottom of this file.

---

## What this course costs

Designed to be as close to free as is practical. The cost ladder:

| Tier | Lessons | What you pay | What you get |
|---|---|---|---|
| **$0 - simulation** | 0, 1, 1B, 1C, 2, 3, 4, 5 | Nothing - a laptop runs it | All scheduling, queueing, sharing-*decision*, triage, observability-design, and lifecycle skills. This is the whole numbered course. |
| **~$5 - one GPU session** | 6 (the capstone) | A few hours on one rented entry-level NVIDIA GPU VM | The real runtime path, enforced GPU sharing, real DCGM telemetry, real Slurm GRES, and real inference benchmarks |

Three habits keep the paid tier at a few dollars:

1. **It's already one rental session.** Lesson 6 is the only real-GPU lesson by design:
   it runs the GPU runtime path, HAMi sharing, Slurm GRES, and the inference benchmark
   back-to-back on a single machine. Set up the host once, run all phases, capture
   evidence as you go, tear down. See [Lesson 6](./portfolio-lab/real-gpu-session/README.md).
2. **Cheapest GPU that works.** Everything real-mode here needs only one
   entry-level datacenter or consumer NVIDIA GPU (T4/L4/A10G-class). You never need
   an A100/H100 in this course.
3. **Tear down immediately.** The evidence captures (`scripts/collect-*-evidence.sh`)
   are the deliverable - once they're on your machine, the VM has no further value.
   A forgotten GPU VM is the only way this course gets expensive.

---

## Lesson 0 - Orientation & setup

🎯 **Objectives:** get the simulation toolchain installed and confirm your machine
can run Lesson 1.

🧭 **Mode:** setup (no GPU).

### Step 1 - Install the prerequisites

Simulation mode (Lessons 1–5) needs these. Real GPU mode (Lesson 6) adds an
NVIDIA GPU machine, covered there.

| Tool | macOS | Linux | Windows (WSL2) |
|---|---|---|---|
| Docker | Docker Desktop | docker-ce | Docker Desktop + WSL2 backend |
| kind | `brew install kind` | release binary | release binary inside WSL2 |
| kubectl | `brew install kubectl` | apt/release binary | inside WSL2 |
| helm | `brew install helm` | release binary | inside WSL2 |
| kwokctl/kwok | `brew install kwok` | release binary | inside WSL2 |
| jq | `brew install jq` | apt | apt inside WSL2 |

Official install docs:
- kind: https://kind.sigs.k8s.io/docs/user/quick-start/
- KWOK: https://kwok.sigs.k8s.io/docs/user/installation/
- helm: https://helm.sh/docs/intro/install/
- NVIDIA GPU Operator (for Lesson 6): https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/

### Step 2 - Verify your machine

```bash
make check
```

💡 **Why:** this runs [`scripts/check-prereqs.sh`](./scripts/check-prereqs.sh),
which confirms docker, kind, kubectl, helm, kwok, and jq are present *before* you
start a lesson - so a missing tool fails here, loudly, instead of halfway through
building a cluster.

✅ **Checkpoint:** `make check` reports every tool as found. Fix anything it flags
before continuing.

### Step 3 - See the whole course map as commands

```bash
make help
```

💡 **Why:** the [Makefile](./Makefile) is the course's command index. Every `make`
target maps to a lesson phase, and unimplemented phases print a "not yet"
message rather than pretending to work.

➡️ **Next:** [Lesson 1 - Kubernetes GPU scheduling](./portfolio-lab/01-k8s-gpu-platform/README.md).

---

## Quick reference - the loops

`make help` is the full command index. The per-lesson loops:

> **Note:** the `make phaseN-*` target numbers are historical *module* numbers and no
> longer line up with lesson numbers (the renumber kept the targets stable). Each
> comment below states the lesson it belongs to.

```bash
# Lesson 1 - Kubernetes fake-GPU scheduling (kind + KWOK + fake-gpu-operator)
make phase1-up && make phase1-demo && make phase1-evidence && make phase1-down

# Lesson 1B - queueing with KAI (own Makefile; reuses the Lesson 1 fleet + installs KAI)
( cd portfolio-lab/01-k8s-gpu-platform/kai-scheduler && make up && make demo-quota )

# Lesson 1C - GPU sharing with HAMi (scheduling sim, no GPU; own Makefile)
( cd portfolio-lab/01-k8s-gpu-platform/hami/hami-scheduling-sim && make up && make demo-fractional )

# Lesson 2 - Slurm-in-Docker with fake GRES  (targets: phase3-*)
make phase3-up && make phase3-demo && make phase3-drain && make phase3-evidence && make phase3-down

# Lesson 3 - observability (needs the Lesson 1 cluster up)  (targets: phase4-*)
make phase4-up && make phase4-break && make phase4-evidence && make phase4-down

# Lesson 4 - inference load harness ($0 CPU tier)  (targets: phase5-*)
make phase5-serve-cpu && make phase5-bench && make phase5-down

# Lesson 5 - BCM-style lifecycle drill (needs the Lesson 1 cluster up)  (targets: phase6-*)
make phase6-drill

# Lesson 6 - Real GPU (one rental): guided, no make loop - see portfolio-lab/real-gpu-session/README.md
```

Each lesson walks its loop with expected output and checkpoints.

---

## Repository map

```
portfolio-lab/
  01-k8s-gpu-platform/        Lessons 1, 1B, 1C - K8s GPU scheduling, queueing (KAI),
                              sharing (HAMi) [sim]. gpu-operator-real/ = Lesson 6's GPU runtime path
  02-slurm-gpu-platform/      Lesson 2 - Slurm-in-Docker, fake GRES [sim]. slurm-realgpu/ = Lesson 6's real GRES
  03-observability/           Lesson 3 - fake-dcgm-exporter/ manifests/ dashboards/ scripts/ [sim]
  04-inference-serving/       Lesson 4 - harness/ (loadgen) + scripts/ (CPU serve) [sim]; real bench in Lesson 6
  05-bcm-style-cluster-lifecycle/  Lesson 5 - scripts/ lifecycle drill + conceptual BCM mapping
  real-gpu-session/           Lesson 6 - the one-rental real-GPU capstone (runtime path, HAMi, Slurm GRES, inference)
  06-validation-reports/      Your lab notebook - what you ran, observed, and proved
control-plane/                Small FastAPI app unifying K8s + Slurm inventory views
runbooks/                     Operational runbooks for GPU/Slurm/K8s failure modes
diagrams/                     Architecture and lifecycle diagrams (Mermaid)
scripts/                      Prereq checks, evidence collection, cleanup

```

Supporting material you'll be pointed to from inside lessons:
- **[runbooks/](./runbooks/)** - the operational playbooks each observability alert links to.
- **[diagrams/](./diagrams/)** - Mermaid diagrams (e.g. [the GPU path to a pod](./diagrams/gpu-path-to-pod.md)) used to anchor the concepts.

---

## What this course proves (and does not)

**Proves:** designing/operating a Kubernetes GPU scheduling environment;
diagnosing Pending GPU pods; queue policy (quota, borrowing, reclaim, gang
scheduling) with KAI Scheduler; GPU sharing and fractional-GPU placement with HAMi
(with enforcement proven on real hardware); Slurm GPU scheduling (GRES/TRES, QoS,
accounting); GPU-aware observability and the runbooks behind alerts; the full
driver→pod GPU path on real hardware; standing up and benchmarking inference
serving; and documenting infrastructure work to a production standard.

**Does NOT prove (in simulation mode):** CUDA kernel performance, NCCL collective
performance, NVLink/NVSwitch topology, GPUDirect RDMA, MIG isolation, real GPU
memory pressure/OOM, multi-node distributed training at scale, or production-scale
fleet operations. Real GPU validation here is single-node by design - it proves the
runtime path and telemetry, not scale. The full ledger:
[`fake-vs-real-limitations.md`](./portfolio-lab/06-validation-reports/fake-vs-real-limitations.md).

---

## Course status

A lesson is only marked **Complete** when its validation report in
[`portfolio-lab/06-validation-reports/`](./portfolio-lab/06-validation-reports/)
contains real captured output.

| Lesson | Topic | Status |
|---|---|---|
| 0 | Repo foundation / Orientation | Complete |
| 1 | Kubernetes fake-GPU scheduling (simulation) | Complete |
| 1B | Queue-based scheduling with KAI Scheduler | Runnable; quota enforcement validated. Needs the fake-gpu-operator (not bare KWOK); borrow/reclaim/gang documented with sim limits |
| 1C | GPU sharing & fractional GPUs with HAMi | Sim validates HAMi's scheduling *decisions* (fractional placement, Pending rejection, `FilteringSucceed`). GPU *sharing* + memory-cap *isolation* are real-GPU only → done in Lesson 6 |
| 2 | Slurm GPU workload management | Complete (runnable; validated with captured output) |
| 3 | Observability | Complete (runnable; metrics/alerts/dashboards validated) |
| 4 | Inference serving | Harness runnable + validated; real benchmark in Lesson 6 |
| 5 | BCM-style cluster lifecycle (conceptual + drill) | Drill runnable + validated; BCM specifics conceptual |
| 6 | Real GPU (capstone: runtime path, real DCGM, HAMi isolation, Slurm GRES, inference) | **Parts A & B validated on an RTX A6000.** Part A - runtime path + real `DCGM_FI_*` telemetry ([real-gpu-validation-report.md](./portfolio-lab/06-validation-reports/real-gpu-validation-report.md), 2026-06-22). Part B - HAMi GPU sharing: two pods on one card, slice enforced by HAMi-core (CUDA `malloc` refused at 8 GB while 40 GB free), `CardInsufficientMemory` oversubscribe ([hami-isolation-validation.md](./portfolio-lab/06-validation-reports/hami-isolation-validation.md), 2026-06-23). **Parts C (inference benchmark) and D (Slurm real GRES, optional) are planned additions coming in future updates.** |

## Documentation site

The lessons are published as a website at
**https://ld-singh.github.io/ai-factory-ops-lab/** (MkDocs Material). The lesson
markdown in this repo is the single source of truth; `scripts/sync-docs.sh` mirrors it
into `docs/` for the build, and a GitHub Actions workflow
([`.github/workflows/docs.yml`](.github/workflows/docs.yml)) publishes to GitHub Pages
on every push to `main`.

Preview locally:

```bash
pip install -r requirements-docs.txt   # use a venv if your Python is externally managed
make docs-serve                        # http://localhost:8000
```

One-time setup to publish: in the GitHub repo, **Settings -> Pages -> Build and
deployment -> Source: GitHub Actions**.

## License and attribution

All third-party tools (kind, KWOK, run.ai fake-gpu-operator, NVIDIA GPU Operator, KAI
Scheduler, HAMi, Slurm, Triton, vLLM, Prometheus, Grafana) belong to their respective
projects; this repo
only contains configuration, automation and documentation written for this course.

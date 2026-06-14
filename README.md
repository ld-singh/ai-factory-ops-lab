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

A few lessons are marked **🟦+🟥 Split**: their concepts and scheduling halves are
free simulation, and a clearly-marked final part runs on the same rented GPU as
Lesson 2.

---

## The Learning Path

Work through these in order. Lessons 0–2 are the spine; everything after builds on
the mental model you form there.

| # | Lesson | Mode | GPU? | You'll be able to… |
|---|---|---|---|---|
| **0** | [Orientation & setup](#lesson-0---orientation--setup) | - | No | Install the toolchain and verify your machine is ready |
| **1** | [Kubernetes GPU scheduling](./portfolio-lab/01-k8s-gpu-platform/README.md) | 🟦 Sim | No | Build a fake GPU fleet and diagnose why GPU pods stay Pending |
| **1B** | [Queue-based scheduling - KAI Scheduler](./portfolio-lab/01-k8s-gpu-platform/kai-scheduler/README.md) | 🟦 Sim | No | Install KAI on a fake GPU fleet (fake-gpu-operator) and **enforce queue quota**; understand borrowing/reclaim/gang and the limits of demoing them on fakes |
| **1C** | [GPU sharing & fractional GPUs - HAMi](./portfolio-lab/01-k8s-gpu-platform/hami/README.md) | 🟦+🟥 Split | Optional (1) | Compare time-slicing/MPS/MIG/HAMi, then **split one real GPU between pods** with enforced memory slices |
| **2** | [Real GPU validation](./portfolio-lab/01-k8s-gpu-platform/gpu-operator-real/README.md) | 🟥 Real | Yes (1) | Prove the full driver → toolkit → device plugin → pod path on real hardware |
| **3** | [Slurm GPU workload management](./portfolio-lab/02-slurm-gpu-platform/README.md) | 🟦 Sim | No | Run a Slurm-in-Docker cluster with fake GRES; schedule GPU jobs, QoS caps, queue pressure, drain/resume |
| **4** | [GPU observability](./portfolio-lab/03-observability/README.md) | 🟦 Sim | No | Stand up Prometheus/Grafana over synthetic DCGM; build dashboards + SLO alerts; **trip them on purpose** |
| **5** | [Inference serving](./portfolio-lab/04-inference-serving/README.md) | 🟡 Split | Opt (1) | Run the load harness ($0 CPU) for TTFT/p95-p99/tokens-per-sec; real benchmark numbers on the Lesson 2 GPU |
| **6** | [BCM-style cluster lifecycle](./portfolio-lab/05-bcm-style-cluster-lifecycle/README.md) | 🟨 Concept+drill | No | Run a provision→health-gate→patch→retire node-lifecycle drill; map it to BCM |
| **★** | [Your lab notebook](./portfolio-lab/06-validation-reports/) | - | - | Capture evidence; a lesson is only "done" when its report holds real output |

> All lessons are now runnable on a laptop with no GPU, except where a real GPU is
> explicitly called for (Lesson 2; the real-benchmark tier of Lesson 5). Lessons 3,
> 4 and 6 stand up real clusters/stacks against fake GPUs; Lesson 5 ships a load
> harness with a $0 CPU validation tier. The status table is at the bottom of this
> file.

---

## What this course costs

Designed to be as close to free as is practical. The cost ladder:

| Tier | Lessons | What you pay | What you get |
|---|---|---|---|
| **$0 - simulation** | 0, 1, 1B, 1C (parts 1–2), 3, 4 | Nothing - a laptop runs it | All scheduling, queueing, sharing-*decision*, triage, and observability-design skills. This is most of the course. |
| **~$5 - one GPU session** | 2, 1C (part 3), 5 | A few hours on one rented entry-level NVIDIA GPU VM | The real runtime path, enforced GPU sharing, real DCGM telemetry, and real inference benchmarks |

Three habits keep the paid tier at a few dollars:

1. **Batch the GPU lessons into one rental session.** Lesson 2 (runtime path),
   Lesson 1C Part 3 (sharing), and Lesson 5 (inference) all run on the same
   single-GPU machine. Do them back-to-back, capture evidence as you go.
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

Simulation mode (Lessons 1, 3, 4) needs these. Real GPU mode (Lessons 2, 5) adds an
NVIDIA GPU machine, covered in those lessons.

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
- NVIDIA GPU Operator (for Lesson 2): https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/

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

```bash
# Lesson 1 - Kubernetes fake-GPU scheduling (kind + KWOK + fake-gpu-operator)
make phase1-up && make phase1-demo && make phase1-evidence && make phase1-down

# Lesson 1B - queueing with KAI (own Makefile; reuses the Lesson 1 fleet + installs KAI)
( cd portfolio-lab/01-k8s-gpu-platform/kai-scheduler && make up && make demo-quota )

# Lesson 1C - GPU sharing with HAMi (sim + real-GPU; own Makefile)
( cd portfolio-lab/01-k8s-gpu-platform/hami/hami-scheduling-sim && make up && make verify )

# Lesson 3 - Slurm-in-Docker with fake GRES
make phase3-up && make phase3-demo && make phase3-drain && make phase3-evidence && make phase3-down

# Lesson 4 - observability (needs the Lesson 1 cluster up)
make phase4-up && make phase4-break && make phase4-evidence && make phase4-down

# Lesson 5 - inference load harness ($0 CPU tier)
make phase5-serve-cpu && make phase5-bench && make phase5-down

# Lesson 6 - BCM-style lifecycle drill (needs the Lesson 1 cluster up)
make phase6-drill
```

Each lesson walks its loop with expected output and checkpoints.

---

## Repository map

```
portfolio-lab/
  01-k8s-gpu-platform/        Lessons 1, 1B, 1C & 2 - K8s GPU scheduling, queueing (KAI),
                              sharing (HAMi): simulation + real GPU path
  02-slurm-gpu-platform/      Lesson 3 - Slurm-in-Docker (docker/ config/ jobs/ scripts/), fake GRES
  03-observability/           Lesson 4 - fake-dcgm-exporter/ manifests/ dashboards/ scripts/
  04-inference-serving/       Lesson 5 - harness/ (loadgen) + scripts/ (CPU serve); real bench on GPU
  05-bcm-style-cluster-lifecycle/  Lesson 6 - scripts/ lifecycle drill + conceptual BCM mapping
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

| Phase | Lesson | Status |
|---|---|---|
| 0 | Repo foundation / Orientation | Complete |
| 1 | Kubernetes fake-GPU scheduling (simulation) | Complete |
| 1B | Queue-based scheduling with KAI Scheduler | Runnable; quota enforcement validated. Needs the fake-gpu-operator (not bare KWOK); borrow/reclaim/gang documented with sim limits |
| 1C | GPU sharing & fractional GPUs with HAMi | Guide complete, isolation evidence pending hardware run |
| 2 | Real Kubernetes GPU validation | Guide complete, evidence pending hardware run |
| 3 | Slurm GPU workload management | Complete (runnable; validated with captured output) |
| 4 | Observability | Complete (runnable; metrics/alerts/dashboards validated) |
| 5 | Inference serving | Harness runnable + validated; real benchmark pending GPU run |
| 6 | BCM-style cluster lifecycle (conceptual + drill) | Drill runnable + validated; BCM specifics conceptual |

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

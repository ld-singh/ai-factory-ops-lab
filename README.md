# AI Factory Operations Lab — A Hands-On Course

A guided, learn-by-doing course in **AI/HPC infrastructure operations**: NVIDIA GPU
infrastructure concepts, Kubernetes GPU scheduling, Slurm GPU workload management,
GPU observability, inference serving, and BCM-style cluster lifecycle patterns.

You don't read this repo — you *run* it. Each lesson has you stand something up,
break it on purpose, diagnose it the way you would on a real cluster, and capture
the evidence. Most of the course needs **no GPU at all**; one lesson uses a single
rented GPU VM and is clearly marked.

> **Read this before anything else — the honesty contract**
>
> This course teaches production cloud/Kubernetes/DevOps operational discipline
> applied to the NVIDIA GPU stack. It does **not** pretend a laptop is a GPU
> datacenter.
>
> Every lesson declares one of two **modes** (simulation vs real GPU) and states
> exactly what it proves and what it does not. The boundary between "I simulated
> the control plane" and "I validated real GPU hardware" is kept explicit in every
> lesson and is fully documented in
> [`portfolio-lab/06-validation-reports/fake-vs-real-limitations.md`](./portfolio-lab/06-validation-reports/fake-vs-real-limitations.md).
> Keeping that line honest is itself one of the skills this course teaches.

---

## Who this course is for

You're comfortable in a terminal and have basic Kubernetes literacy (you know what
a Pod and a node are), and you want to learn how AI infrastructure platforms are
actually scheduled, observed, and operated. By the end you'll be able to reason
about — and demonstrate — GPU scheduling, queueing, the full driver-to-pod GPU
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
| 💡 **Why it works** | The concept behind the command — the part that transfers |
| ✅ **Checkpoint** | A concrete check to confirm the step worked before moving on |
| 🔬 **What you proved / did NOT prove** | The honesty boundary for that lesson |
| ➡️ **Next** | Where to go next |

The two **modes** you'll see throughout:

- **🟦 Simulation mode (no GPU).** kind + KWOK fake nodes, a fake GPU fleet, Slurm
  with fake GRES. Proves *control-plane behaviour*: scheduling, queueing, placement,
  triage, operational workflow. Nothing below the kubelet.
- **🟥 Real GPU mode (one NVIDIA GPU).** Real driver, container toolkit, GPU
  Operator, CUDA pod, DCGM telemetry. Proves the *real runtime path*, single-node.

---

## The Learning Path

Work through these in order. Lessons 0–2 are the spine; everything after builds on
the mental model you form there.

| # | Lesson | Mode | GPU? | You'll be able to… |
|---|---|---|---|---|
| **0** | [Orientation & setup](#lesson-0--orientation--setup) | — | No | Install the toolchain and verify your machine is ready |
| **1** | [Kubernetes GPU scheduling](./portfolio-lab/01-k8s-gpu-platform/README.md) | 🟦 Sim | No | Build a fake GPU fleet and diagnose why GPU pods stay Pending |
| **2** | [Real GPU validation](./portfolio-lab/01-k8s-gpu-platform/gpu-operator-real/README.md) | 🟥 Real | Yes (1) | Prove the full driver → toolkit → device plugin → pod path on real hardware |
| **3** | [Slurm GPU workload management](./portfolio-lab/02-slurm-gpu-platform/README.md) | 🟦 Sim | No | *(Phase 3)* Schedule GPU jobs with GRES, QoS, fair-share, accounting |
| **4** | [GPU observability](./portfolio-lab/03-observability/README.md) | 🟦 Sim | No | *(Phase 4)* Build DCGM dashboards, SLO alerts, and the runbooks behind them |
| **5** | [Inference serving](./portfolio-lab/04-inference-serving/README.md) | 🟥 Real | Yes (1) | *(Phase 5)* Serve and benchmark a model (TTFT, p95/p99, tokens/sec) |
| **6** | [BCM-style cluster lifecycle](./portfolio-lab/05-bcm-style-cluster-lifecycle/README.md) | 🟨 Concept | No | *(Phase 6)* Map head/compute node, imaging, and lifecycle concepts |
| **★** | [Your lab notebook](./portfolio-lab/06-validation-reports/) | — | — | Capture evidence; a lesson is only "done" when its report holds real output |

> Lessons 3–6 are **not yet implemented** (their phases are planned). Their pages
> teach the concepts and learning objectives now, and will gain runnable steps as
> each phase lands. The honest status table is at the bottom of this file.

---

## Lesson 0 — Orientation & setup

🎯 **Objectives:** get the simulation toolchain installed and confirm your machine
can run Lesson 1.

🧭 **Mode:** setup (no GPU).

### Step 1 — Install the prerequisites

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

### Step 2 — Verify your machine

```bash
make check
```

💡 **Why:** this runs [`scripts/check-prereqs.sh`](./scripts/check-prereqs.sh),
which confirms docker, kind, kubectl, helm, kwok, and jq are present *before* you
start a lesson — so a missing tool fails here, loudly, instead of halfway through
building a cluster.

✅ **Checkpoint:** `make check` reports every tool as found. Fix anything it flags
before continuing.

### Step 3 — See the whole course map as commands

```bash
make help
```

💡 **Why:** the [Makefile](./Makefile) is the course's command index. Every `make`
target maps to a lesson phase, and unimplemented phases print an honest "not yet"
message rather than pretending to work.

➡️ **Next:** [Lesson 1 — Kubernetes GPU scheduling](./portfolio-lab/01-k8s-gpu-platform/README.md).

---

## Quick reference — the Lesson 1 loop

Once you've done Lesson 0, the core simulation loop is:

```bash
make phase1-up        # kind cluster + KWOK + fake GPU node pools
make phase1-demo      # deploy schedulable + intentionally-Pending GPU workloads
make phase1-evidence  # capture kubectl evidence into 06-validation-reports/
make phase1-down      # tear it all down
```

Lesson 1 walks each of these with expected output and checkpoints.

---

## Repository map

```
portfolio-lab/
  01-k8s-gpu-platform/        Lesson 1 & 2 — K8s GPU scheduling: simulation + real GPU path
  02-slurm-gpu-platform/      Lesson 3 — Slurm GRES/TRES, jobs, QoS, accounting
  03-observability/           Lesson 4 — Prometheus, Grafana, DCGM, queue metrics, alerts
  04-inference-serving/       Lesson 5 — Triton/vLLM, gateway, load tests, benchmark reports
  05-bcm-style-cluster-lifecycle/  Lesson 6 — Conceptual BCM-style lifecycle module
  06-validation-reports/      Your lab notebook — what you ran, observed, and proved
control-plane/                Small FastAPI app unifying K8s + Slurm inventory views
runbooks/                     Operational runbooks for GPU/Slurm/K8s failure modes
diagrams/                     Architecture and lifecycle diagrams (Mermaid)
scripts/                      Prereq checks, evidence collection, cleanup
private/                      (gitignored) personal notes — not part of the public repo
```

Supporting material you'll be pointed to from inside lessons:
- **[runbooks/](./runbooks/)** — the operational playbooks each observability alert links to.
- **[diagrams/](./diagrams/)** — Mermaid diagrams (e.g. [the GPU path to a pod](./diagrams/gpu-path-to-pod.md)) used to anchor the concepts.

---

## What this course proves (and does not)

**Proves:** designing/operating a Kubernetes GPU scheduling environment;
diagnosing Pending GPU pods; Slurm GPU scheduling (GRES/TRES, QoS, accounting);
GPU-aware observability and the runbooks behind alerts; the full driver→pod GPU
path on real hardware; standing up and benchmarking inference serving; and
documenting infrastructure work to a production standard.

**Does NOT prove (in simulation mode):** CUDA kernel performance, NCCL collective
performance, NVLink/NVSwitch topology, GPUDirect RDMA, MIG isolation, real GPU
memory pressure/OOM, multi-node distributed training at scale, or production-scale
fleet operations. Real GPU validation here is single-node by design — it proves the
runtime path and telemetry, not scale. The full ledger:
[`fake-vs-real-limitations.md`](./portfolio-lab/06-validation-reports/fake-vs-real-limitations.md).

---

## Course status (honest)

A lesson is only marked **Complete** when its validation report in
[`portfolio-lab/06-validation-reports/`](./portfolio-lab/06-validation-reports/)
contains real captured output.

| Phase | Lesson | Status |
|---|---|---|
| 0 | Repo foundation / Orientation | Complete |
| 1 | Kubernetes fake-GPU scheduling (simulation) | Complete |
| 2 | Real Kubernetes GPU validation | Guide complete, evidence pending hardware run |
| 3 | Slurm GPU workload management | Planned |
| 4 | Observability | Planned |
| 5 | Inference serving | Planned |
| 6 | BCM-style cluster lifecycle (conceptual) | Planned |

## License and attribution

All third-party tools (kind, KWOK, NVIDIA GPU Operator, KAI Scheduler, Slurm,
Triton, vLLM, Prometheus, Grafana) belong to their respective projects; this repo
only contains configuration, automation and documentation written for this course.

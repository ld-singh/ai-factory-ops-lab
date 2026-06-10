# AI Factory Operations Lab

A production-style AI/HPC infrastructure operations lab covering NVIDIA GPU infrastructure
concepts, Kubernetes GPU scheduling, Slurm GPU workload management, GPU observability,
inference serving, and BCM-style cluster lifecycle patterns.

> **Scope and honesty statement (read this first)**
>
> This lab applies production cloud, Kubernetes and DevOps operational discipline to
> NVIDIA GPU infrastructure: Kubernetes GPU scheduling, Slurm GPU workload management,
> GPU observability, inference serving, and cluster lifecycle patterns.
>
> It does **not** claim production GPU fleet experience. It claims something verifiable
> instead: every scheduling behaviour, failure mode, and operational workflow here can
> be reproduced from this repo, and the line between simulation and real GPU validation
> is documented explicitly in
> [`portfolio-lab/06-validation-reports/fake-vs-real-limitations.md`](./portfolio-lab/06-validation-reports/fake-vs-real-limitations.md).

---

## Why this project exists

AI infrastructure roles need two things that rarely come together:

1. Production-grade platform operations discipline (incident handling, capacity planning,
   observability, lifecycle management, runbooks).
2. Working fluency with the NVIDIA GPU stack and AI workload schedulers (GPU Operator,
   Container Toolkit, device plugin, DCGM, Slurm GRES, queue-based scheduling, inference
   serving).

This lab combines both: production-style operational discipline applied to the GPU
stack, with the simulation/real boundary kept explicit throughout.

---

## The two lab modes

Every module in this repo declares which mode it runs in. This distinction is the
integrity backbone of the project.

### Mode 1 — Local simulation (no GPU required)

| What it uses | What it proves |
|---|---|
| kind/k3d local Kubernetes | Kubernetes control-plane behaviour |
| KWOK fake nodes with `nvidia.com/gpu` allocatable | Scheduling, bin-packing, Pending diagnosis |
| Fake A100/H100/L40S node labels and pools | Heterogeneous fleet placement strategy |
| run.ai fake-gpu-operator (optional) | GPU-Operator-shaped components without GPUs |
| Slurm in Docker with fake GRES | GRES/TRES scheduling, QoS, fair-share, accounting |
| Queue-pressure workloads | Contention, starvation, priority behaviour |

**Simulation proves control-plane scheduling, queueing, placement and operational
workflows. Nothing more.**

### Mode 2 — Real GPU validation (one GPU VM or local NVIDIA GPU)

| What it uses | What it proves |
|---|---|
| NVIDIA driver + `nvidia-smi` | Real driver/runtime installation |
| NVIDIA Container Toolkit | CUDA containers actually execute on GPU |
| Kubernetes + NVIDIA GPU Operator | Real device plugin advertising real GPUs |
| CUDA test pod | End-to-end GPU path: driver → runtime → kubelet → pod |
| DCGM Exporter | Real GPU telemetry into Prometheus |
| Optional: Slurm `--gres=gpu` | Real GRES enforcement |
| Optional: Triton/vLLM | Real inference serving and benchmarking |

---

## What this project proves

- Designing and operating a Kubernetes GPU scheduling environment: heterogeneous
  GPU node pools, resource requests, taints/tolerations, and diagnosing why GPU
  pods stay Pending.
- Configuring and operating Slurm for GPU workloads: GRES/TRES, partitions, QoS,
  job arrays, accounting, drain/resume, and pending-reason triage.
- Building GPU-aware observability: DCGM metrics, queue-pressure metrics, fleet
  dashboards, SLO-oriented alerts, and the runbooks behind each alert.
- The full GPU path to a pod: driver → container toolkit → device plugin →
  kubelet → scheduler → container, with each link validated on real hardware.
- Standing up and benchmarking an inference serving stack (Triton/vLLM) with
  meaningful SLOs (TTFT, p95/p99 latency, tokens/sec, error rate).
- Documenting, runbooking, and presenting infrastructure work to a production
  standard.

## What this project does NOT prove

The fake-GPU simulation does **not** validate:

- CUDA kernel performance or any real GPU compute behaviour
- NCCL collective communication performance
- NVLink / NVSwitch topology behaviour
- GPUDirect RDMA or any GPU networking data path
- MIG partitioning or isolation behaviour
- Real GPU memory pressure, fragmentation, or OOM behaviour
- Multi-node distributed training at scale
- Production-scale GPU fleet operations (hundreds/thousands of GPUs)

Real GPU validation in this lab is single-node by design: it proves the runtime path and
telemetry, not scale.

---

## Repository map

```
portfolio-lab/
  01-k8s-gpu-platform/        Kubernetes GPU scheduling: simulation + real GPU path
  02-slurm-gpu-platform/      Slurm GRES/TRES, jobs, QoS, accounting
  03-observability/           Prometheus, Grafana, DCGM, queue metrics, alerts
  04-inference-serving/       Triton/vLLM, gateway, load tests, benchmark reports
  05-bcm-style-cluster-lifecycle/  Conceptual BCM-style lifecycle module (documented as such)
  06-validation-reports/      Evidence: what was run, what was observed, what it proves
control-plane/                Small FastAPI app unifying K8s + Slurm inventory views
runbooks/                     Operational runbooks for GPU/Slurm/K8s failure modes
diagrams/                     Architecture and lifecycle diagrams (Mermaid)
scripts/                      Prereq checks, evidence collection, cleanup
private/                      (gitignored) personal notes — not part of the public repo
```

## Quick start

```bash
# 0. Check prerequisites (docker, kind, kubectl, helm, kwok)
make check

# 1. Phase 1: local Kubernetes GPU scheduling simulation
make phase1-up        # kind cluster + KWOK + fake GPU node pools
make phase1-demo      # deploy schedulable + intentionally-pending GPU workloads
make phase1-evidence  # capture kubectl evidence into 06-validation-reports/

# Tear down
make phase1-down
```

See the [Makefile](./Makefile) for all targets. Each phase directory has its own README
with the full walkthrough.

## Prerequisites

| Tool | macOS | Linux | Windows (WSL2) |
|---|---|---|---|
| Docker | Docker Desktop | docker-ce | Docker Desktop + WSL2 backend |
| kind | `brew install kind` | release binary | release binary inside WSL2 |
| kubectl | `brew install kubectl` | apt/release binary | inside WSL2 |
| helm | `brew install helm` | release binary | inside WSL2 |
| kwokctl/kwok | `brew install kwok` | release binary | inside WSL2 |
| jq | `brew install jq` | apt | apt inside WSL2 |

Run `./scripts/check-prereqs.sh` to verify. Official install docs:
- kind: https://kind.sigs.k8s.io/docs/user/quick-start/
- KWOK: https://kwok.sigs.k8s.io/docs/user/installation/
- helm: https://helm.sh/docs/intro/install/
- NVIDIA GPU Operator: https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/

Real GPU validation mode additionally requires one machine with an NVIDIA GPU
(rented cloud GPU VM or local). See `portfolio-lab/01-k8s-gpu-platform/gpu-operator-real/`.

## Project phases and status

| Phase | Module | Status |
|---|---|---|
| 0 | Repo foundation | Complete |
| 1 | Kubernetes fake-GPU control-plane simulation | Complete |
| 2 | Real Kubernetes GPU validation guide | Guide complete, evidence pending hardware run |
| 3 | Slurm GPU workload management | Planned |
| 4 | Observability | Planned |
| 5 | Inference serving | Planned |
| 6 | BCM-style cluster lifecycle (conceptual) | Planned |
| 7 | Portfolio assets | Planned |

Statuses are updated as evidence is captured. A module is only marked Complete when its
validation report in `portfolio-lab/06-validation-reports/` contains real captured output.

## License and attribution

All third-party tools (kind, KWOK, NVIDIA GPU Operator, KAI Scheduler, Slurm, Triton,
vLLM, Prometheus, Grafana) belong to their respective projects; this repo only contains
configuration, automation and documentation written for this lab.

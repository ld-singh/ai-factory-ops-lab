# Module 01 — Kubernetes GPU Platform

This module has two halves, and the line between them is deliberate:

| Half | Mode | GPU required |
|---|---|---|
| `kind/`, `kwok/`, `workloads/`, `kai-scheduler/`, `fake-gpu-operator/` | **Control-plane simulation** | No |
| `gpu-operator-real/` | **Real GPU runtime validation** | Yes (one NVIDIA GPU machine) |

## What this module teaches

- How `nvidia.com/gpu` is just an extended resource to the Kubernetes scheduler:
  the scheduler counts integers; it has no idea what a GPU is. This is exactly why
  fake GPU nodes are a legitimate way to study scheduling behaviour.
- How heterogeneous GPU fleets are modelled: node pools, GPU product labels,
  taints/tolerations, nodeSelectors and affinity.
- How to diagnose Pending GPU pods quickly (`kubectl describe pod`, Events,
  `Insufficient nvidia.com/gpu`, unmatched selectors).
- Where the simulation boundary sits: everything below the kubelet (driver,
  container toolkit, CUDA, DCGM) is only proven in `gpu-operator-real/`.

## What the simulation proves

- GPU-aware scheduling and placement decisions across heterogeneous node pools
- Capacity contention and queue-pressure behaviour (more requests than GPUs)
- Pending-pod triage workflow, the same one used on real clusters
- Fleet modelling: labels, taints, pool design for A100/H100/L40S-class nodes

## What the simulation does NOT prove

No CUDA execution, no NCCL, no NVLink/NVSwitch, no MIG, no GPUDirect RDMA, no real
GPU memory behaviour, no DCGM telemetry. Those live in `gpu-operator-real/` and only
count as proven once captured in `06-validation-reports/real-gpu-validation-report.md`.

## Walkthrough (simulation mode)

```bash
# From repo root
make check
make phase1-up      # kind cluster + KWOK + fake GPU node pools
make phase1-demo    # schedulable, pending-capacity, pending-selector, queue-pressure workloads
```

Then inspect like you would a real cluster:

```bash
kubectl get nodes -L nvidia.com/gpu.product -L gpu-pool
kubectl describe node kwok-gpu-a100-0
kubectl get pods -n gpu-demo -o wide
kubectl describe pod -n gpu-demo <pending-pod>
kubectl get events -n gpu-demo --sort-by=.lastTimestamp
```

Expected observations to capture:

1. `cuda-batch-small` schedules onto an A100-pool node (1 GPU fits).
2. `cuda-train-16gpu` stays **Pending** with `Insufficient nvidia.com/gpu`
   (no single node exposes 16 GPUs — a deliberate capacity-mismatch scenario).
3. `cuda-needs-b200` stays **Pending** because its nodeSelector matches no node
   (deliberate fleet-mismatch scenario).
4. `queue-pressure` deployment: some replicas run, the rest stay Pending —
   this is the raw material for queueing/quota discussions in `kai-scheduler/`.

Capture evidence:

```bash
make phase1-evidence
```

Then fill in `../06-validation-reports/local-simulation-report.md`.

## Directory guide

- `kind/` — kind cluster config (control plane + one real worker for system pods)
- `kwok/` — KWOK installation notes and fake GPU node manifests/templates
- `fake-gpu-operator/` — notes on run.ai's fake-gpu-operator as a richer alternative
- `kai-scheduler/` — queue/quota scheduling concepts and KAI Scheduler notes
- `workloads/` — demo workloads (schedulable, pending, queue pressure)
- `gpu-operator-real/` — Phase 2: real GPU validation guide
- `scripts/` — setup and demo automation

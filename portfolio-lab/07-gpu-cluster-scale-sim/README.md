# Lesson 7 - GPU Fleet Scale Simulation with Volcano

> Course home: [AI Factory Operations Lab](../../README.md) · Previous:
> [Lesson 6 - Real GPU](../real-gpu-session/README.md)

In this lesson you turn the small fake GPU fleet from Lesson 1 into a **scale
simulation harness**. You model hundreds or thousands of fake GPU nodes, create
queue pressure, and validate queue/gang-scheduling behaviour with **Volcano**
without renting a single GPU.

The key distinction stays the same as Lesson 1:

```text
KWOK + fake-gpu-operator + Volcano
  = real Kubernetes scheduling control plane

No kubelet, no driver, no CUDA, no NCCL, no real GPU memory
  = not a runtime or performance benchmark
```

## 🎯 Learning objectives

After this lesson you can:

1. Generate a large heterogeneous fake GPU fleet from a topology file.
2. Explain which GPU platform behaviours are safe to validate with fake nodes.
3. Install Volcano and schedule GPU-like Pods through `schedulerName: volcano`.
4. Use Volcano `Queue` and `PodGroup` objects to model queue pressure and gang scheduling.
5. Capture scheduling evidence for a fleet-scale experiment.
6. Decide when to stay in simulation and when to move to a real GPU validation run.

## 🧭 Mode & prerequisites

| Item | Value |
|---|---|
| Mode | 🟦 Simulation |
| GPU required | No |
| Runtime path | Not validated |
| Scheduler path | Validated through Kubernetes + Volcano |
| Base stack | kind + KWOK + fake-gpu-operator |
| Extra scheduler | Volcano |

Prerequisites are the same as Lesson 1, plus `jq` and `helm`:

```bash
make check
```

## Why Volcano here?

Lesson 1B already covers KAI Scheduler for queue-based scheduling. Lesson 7 uses
Volcano because it is a good fit for a **large-scale batch/HPC-style GPU cluster
simulation**:

- `Queue` models team/project capacity boundaries.
- `PodGroup` models gang scheduling: either a whole distributed job can start, or it waits.
- `schedulerName: volcano` makes it explicit which scheduler is handling the workload.
- It is useful for MCP/AI-factory control-plane experiments where the question is
  "where would this job land?" rather than "how fast would CUDA run?"

This lesson deliberately does **not** replace KAI. Use:

```text
KAI lesson      -> queue quota / borrowing / reclaim mental model
Volcano lesson  -> large fake fleet + PodGroup/gang scheduling drills
```

## The topology file

The default topology is small enough for a laptop:

```bash
cat topology/small.json
```

It models the same shape as Lesson 1:

```json
{
  "name": "small",
  "description": "Laptop-safe 5-node baseline: 32 fake GPUs",
  "pools": {
    "a100": { "nodes": 2, "gpusPerNode": 8, "gpuMemoryMiB": 81920, "product": "NVIDIA-A100-SXM4-80GB" },
    "h100": { "nodes": 1, "gpusPerNode": 8, "gpuMemoryMiB": 81920, "product": "NVIDIA-H100-80GB-HBM3" },
    "l40s": { "nodes": 2, "gpusPerNode": 4, "gpuMemoryMiB": 46068, "product": "NVIDIA-L40S" }
  }
}
```

The medium topology is still a simulation, but it is large enough to exercise
scheduler pressure:

```bash
make up TOPOLOGY=topology/medium.json
```

A larger 1k-node profile is provided as a template. Use it only when your local
API server has enough CPU and memory:

```bash
make up TOPOLOGY=topology/large-1k.json
```

## Step 1 - Stand up the scale fleet

```bash
# From this lesson directory
cd portfolio-lab/07-gpu-cluster-scale-sim
make up
```

This creates or reuses the kind cluster, installs KWOK, renders a
fake-gpu-operator topology values file, installs the fake GPU layer, and creates
KWOK fake GPU nodes.

Verify the fleet:

```bash
make status
```

Expected signal:

```text
- KWOK nodes exist
- nodes have gpu-pool and nvidia.com/gpu.product labels
- fake-gpu-operator eventually publishes nvidia.com/gpu allocatable values
```

## Step 2 - Install Volcano

```bash
make volcano-up
```

By default this installs Volcano from the upstream installer manifest:

```bash
VOLCANO_VERSION=v1.10.0
```

Override it when you want to test another release:

```bash
VOLCANO_VERSION=v1.11.0 make volcano-up
```

## Step 3 - Run the scale demo

```bash
make demo
```

The demo creates three scenarios in the `gpu-scale` namespace:

| Scenario | Purpose | Expected result on `small.json` |
|---|---|---|
| `fit-gang` | A gang job that fits the fake fleet | Scheduled by Volcano |
| `overflow-gang` | A gang job larger than available GPUs | Pending |
| `needs-b200` | A job targeting a missing pool | Pending due to selector/fleet mismatch |

Inspect the result:

```bash
kubectl get podgroups -n gpu-scale
kubectl get pods -n gpu-scale -o wide
kubectl get events -n gpu-scale --sort-by=.lastTimestamp | tail -40
```

## Step 4 - Capture evidence

```bash
make evidence
```

This writes a timestamped evidence directory under:

```text
portfolio-lab/06-validation-reports/evidence/
```

The evidence includes nodes, queues, PodGroups, Pods, and recent events.

## Step 5 - Tear down

```bash
make down
```

This removes the `gpu-scale` namespace, the KWOK fake nodes created by this
lesson, and optionally uninstalls Volcano if you pass:

```bash
REMOVE_VOLCANO=1 make down
```

The kind cluster itself is left running so you can inspect state or continue other
lessons. Delete it manually if you want a full cleanup:

```bash
kind delete cluster --name ai-factory-lab
```

## 🔬 What this lesson proved - and did NOT

**Proved in simulation:**

- Heterogeneous GPU fleet modelling at hundreds/thousands of fake nodes
- GPU-like queue pressure
- Volcano scheduler handoff through `schedulerName: volcano`
- Volcano `Queue` and `PodGroup` control-plane behaviour
- Gang scheduling success/failure paths
- Evidence capture workflow for scheduler experiments

**Did NOT prove:**

- CUDA execution
- GPU memory allocation or OOM behaviour
- NVIDIA driver/container-toolkit path
- DCGM accuracy
- MIG, MPS, HAMi, or vGPU isolation
- NCCL, NVLink, NVSwitch, GPUDirect RDMA
- inference throughput, TTFT, TPOT, p95/p99 latency

## Design notes

This lesson intentionally uses JSON topology files instead of YAML so it can rely
only on `jq`, which is already a prerequisite for the course. The generated files
under `generated/` are disposable.

The scale simulator should remain a control-plane lab. Use Lesson 6 for runtime
validation and real GPU evidence.

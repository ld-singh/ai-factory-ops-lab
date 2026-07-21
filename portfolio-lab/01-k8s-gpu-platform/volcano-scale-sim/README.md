# Lesson 1D - GPU Fleet Scale Simulation with Volcano

> Course home: [AI Factory Operations Lab](../../../README.md) · Previous:
> [Lesson 1C - GPU sharing with HAMi](../hami/README.md) · Next:
> [Lesson 2 - Slurm workload management](../../02-slurm-gpu-platform/README.md)
>
> See also: [Lesson 1B - Queue-based scheduling with KAI Scheduler](../kai-scheduler/README.md)
> for the complementary queue-quota/borrowing/reclaim model this lesson does not cover.

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

Lesson 1B already covers KAI Scheduler for queue-based scheduling. Lesson 1D uses
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
cd portfolio-lab/01-k8s-gpu-platform/volcano-scale-sim
make up
```

This creates or reuses the kind cluster, installs KWOK, renders a
fake-gpu-operator topology values file, installs the fake GPU layer, and creates
KWOK fake GPU nodes.

> ⚠️ **Shared with Lesson 1:** this upgrades the same `gpu-operator` Helm release
> that Lesson 1 installs, replacing its topology values with the rendered ones
> from this lesson. The pool names match (`a100`/`h100`/`l40s` on `small.json`),
> so Lesson 1 nodes keep advertising GPUs - but if you customised Lesson 1's
> topology, re-run its install script afterwards to restore it.

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

**Checkpoint** - the script waits for the admission webhook, then prints the
`volcano-system` pods. Expected output:

```text
NAME                                   READY   STATUS      RESTARTS   AGE
volcano-admission-69947d8b7d-5b8sw     1/1     Running     0          60s
volcano-admission-init-xlbsf           0/1     Completed   0          60s
volcano-controllers-58c76fbdd7-txrzw   1/1     Running     0          60s
volcano-scheduler-58b5974944-rp46l     1/1     Running     0          60s
```

`volcano-admission-init` is a one-shot Job; `Completed` is its healthy state.

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

The demo pods carry a `ai-factory-ops-lab/scale-sim: "true"` nodeSelector, so
they only target this lesson's fleet - Lesson 1 fake nodes on the same cluster
cannot absorb the overflow and skew the scenarios.

Inspect the result:

```bash
kubectl get podgroups -n gpu-scale
kubectl get pods -n gpu-scale -o wide
kubectl get events -n gpu-scale --sort-by=.lastTimestamp | tail -40
```

**Checkpoint** - on `small.json` the PodGroups settle like this:

```text
NAME            STATUS    MINMEMBER   RUNNINGS   AGE
fit-gang        Running   16          16         25s
needs-b200      Inqueue   4                      24s
overflow-gang   Inqueue   33                     25s
```

The line worth reading twice is in the overflow-gang Events:

```text
pod group is not ready, 33 Pending, 33 minAvailable; Pending: 16 Schedulable, 17 Unschedulable
```

16 pods *could* start, and **none did** - that all-or-nothing refusal is gang
scheduling. The default scheduler (Lesson 1's queue-pressure demo) would have
started the 16 and stranded the rest.

## Step 4 - Capture evidence

```bash
make evidence
```

This writes a timestamped evidence directory under:

```text
portfolio-lab/06-validation-reports/evidence/
```

**Checkpoint** - expected output, and what lands in the directory:

```text
Evidence written to: .../portfolio-lab/06-validation-reports/evidence/gpu-scale-20260721-171717
```

```text
events.txt  fake-gpu-operator-pods.txt  nodes-wide.txt  nodes.yaml
podgroups.yaml  pods-wide.txt  pods.yaml  README.txt
versions.txt  volcano-pods.txt  volcano-queues.yaml
```

`versions.txt` records the Kubernetes, Volcano, fake-gpu-operator, and KWOK
versions of the run, so the bundle can be graded without trusting your notes.

The captured run for this lesson is written up in the validation report:
[`gpu-scale-sim-validation.md`](../../06-validation-reports/gpu-scale-sim-validation.md).

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

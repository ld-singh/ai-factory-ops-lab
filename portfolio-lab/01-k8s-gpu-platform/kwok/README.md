# Lesson 1 · Deep dive - How a fake GPU fleet works

> Part of [Lesson 1 - Kubernetes GPU Scheduling](../README.md). Read this when
> Step 1 makes you ask "wait, how is this legitimate?"

🎯 **Objective:** understand exactly what [KWOK](https://kwok.sigs.k8s.io/)
(Kubernetes WithOut Kubelet) fakes, what it does *not* fake, and how the fake GPU
nodes are constructed - so you can defend the simulation's validity and name its
limits precisely.

KWOK lets us register **fake nodes** that the scheduler treats as real: pure API
objects with no kubelet. KWOK provides the *nodes*; the **fake-gpu-operator** then
advertises `nvidia.com/gpu` onto them (see
[fake-gpu-operator/README.md](../fake-gpu-operator/README.md)). We also give the
nodes the same `gpu-pool` / product labels GPU Feature Discovery would apply on a
real cluster, and the control plane behaves exactly as it would against a real GPU
fleet. KWOK and the operator are complementary: KWOK = nodes, operator = the GPU
layer on those nodes.

## Why this is legitimate (and where it stops)

💡 The default Kubernetes scheduler never talks to a GPU. It compares integer resource
requests against integer node allocatable values. A fake node with
`nvidia.com/gpu: 8` exercises the identical scheduling code path as a DGX with 8
real GPUs. What it does NOT exercise: kubelet device allocation, the NVIDIA
container runtime, CUDA, NVLink topology, MIG, or DCGM. Those are
[Lesson 6](../gpu-operator-real/README.md).

## Install

The setup script ([`../scripts/install-kwok.sh`](../scripts/install-kwok.sh)) applies
the official release manifests, per https://kwok.sigs.k8s.io/docs/user/kwok-in-cluster/ :

```bash
KWOK_REPO=kubernetes-sigs/kwok
KWOK_LATEST_RELEASE=$(curl -s "https://api.github.com/repos/${KWOK_REPO}/releases/latest" | jq -r '.tag_name')
kubectl apply -f "https://github.com/${KWOK_REPO}/releases/download/${KWOK_LATEST_RELEASE}/kwok.yaml"
kubectl apply -f "https://github.com/${KWOK_REPO}/releases/download/${KWOK_LATEST_RELEASE}/stage-fast.yaml"
```

`stage-fast.yaml` makes pods on fake nodes transition to Running quickly, so
scheduling demos are immediate.

## Fake GPU node pools

[`../scripts/create-fake-gpu-nodes.sh`](../scripts/create-fake-gpu-nodes.sh)
generates three pools from the template in this directory:

| Pool | Nodes | GPUs/node | Product label (GFD-style) |
|---|---|---|---|
| `a100` | 2 | 8 | `NVIDIA-A100-SXM4-80GB` |
| `h100` | 1 | 8 | `NVIDIA-H100-80GB-HBM3` |
| `l40s` | 2 | 4 | `NVIDIA-L40S` |

Total simulated fleet: 5 nodes, 32 "GPUs".

Each fake node carries:

- `kwok.x-k8s.io/node: fake` annotation (managed by KWOK)
- Taint `kwok.x-k8s.io/node=fake:NoSchedule` - workloads must tolerate it, which
  doubles as a safety net so nothing accidental lands on fake nodes
- `run.ai/simulated-gpu-node-pool: <pool>` - the label the fake-gpu-operator keys
  off to advertise that pool's GPUs onto the node
- `gpu-pool` and `nvidia.com/gpu.product` labels for pool targeting/display, matching
  what GPU Feature Discovery sets on real clusters

Note the node script no longer hand-writes `nvidia.com/gpu` into `status.allocatable`
- the operator does that, so the advertisement is operator-shaped (a device plugin,
like production). See [`fake-gpu-node-template.yaml`](./fake-gpu-node-template.yaml)
for the annotated node template.

## Where the GPU count comes from

The `nvidia.com/gpu` integer is advertised by the fake-gpu-operator from its per-pool
topology, not hand-written and not discovered from a driver (there is none). The
`nvidia.com/gpu.product` label is a display/targeting convenience whose *name* matches
real GFD output, so workload manifests written here work unchanged on real clusters.

✅ **Checkpoint:** name the single field the scheduler uses for GPU placement (an
integer under `status.allocatable`, now advertised by the operator) and say which
component puts it there. If you can, you understand why this simulation is both
legitimate *and* limited.

➡️ **Back to:** [Lesson 1, Step 1](../README.md#step-1---stand-up-the-simulated-fleet).

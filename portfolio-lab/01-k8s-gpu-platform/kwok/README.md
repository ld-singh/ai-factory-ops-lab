# Lesson 1 · Deep dive - How a fake GPU fleet works

> Part of [Lesson 1 - Kubernetes GPU Scheduling](../README.md). Read this when
> Step 1 makes you ask "wait, how is this legitimate?"

🎯 **Objective:** understand exactly what [KWOK](https://kwok.sigs.k8s.io/)
(Kubernetes WithOut Kubelet) fakes, what it does *not* fake, and how the fake GPU
nodes are constructed - so you can defend the simulation's validity and name its
limits precisely.

KWOK lets us register **fake nodes** that the scheduler treats as real. We give
those nodes `nvidia.com/gpu` in `status.allocatable`, plus the same labels NVIDIA's
GPU Feature Discovery would apply on a real cluster, and the control plane behaves
exactly as it would against a real GPU fleet.

## Why this is legitimate (and where it stops)

💡 The Kubernetes scheduler never talks to a GPU. It compares integer resource
requests against integer node allocatable values. A fake node with
`nvidia.com/gpu: 8` exercises the identical scheduling code path as a DGX with 8
real GPUs. What it does NOT exercise: kubelet device allocation, the NVIDIA
container runtime, CUDA, NVLink topology, MIG, or DCGM. Those are
[Lesson 2](../gpu-operator-real/README.md).

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
- Labels mirroring what GPU Feature Discovery sets on real clusters:
  `nvidia.com/gpu.product`, `nvidia.com/gpu.count`, plus a lab-specific
  `gpu-pool` label for pool-level targeting

See [`fake-gpu-node-template.yaml`](./fake-gpu-node-template.yaml) for the annotated
template - read it top to bottom; every field is commented with why it's there.

## Where these labels come from

The `nvidia.com/gpu.product` values here are written by our script, not discovered by
GFD. On a real cluster, GFD discovers them from the driver. The label *names* are
kept identical to real GFD output so that workload manifests written against this
simulation work unchanged on real clusters.

✅ **Checkpoint:** open the template and find the single field the scheduler actually
uses to make GPU placement decisions (hint: it's an integer under
`status.allocatable`). If you can point to it, you understand why this simulation is
both legitimate *and* limited.

➡️ **Back to:** [Lesson 1, Step 1](../README.md#step-1--stand-up-the-simulated-fleet).

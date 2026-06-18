# Lesson 1 · Deep dive - the GPU layer (fake-gpu-operator)

> Part of [Lesson 1 - Kubernetes GPU Scheduling](../README.md). Read this to
> understand how the fake fleet advertises GPUs and emits DCGM metrics with no
> hardware. Installed for you by `make phase1-up`.

🎯 **Objective:** understand the second half of the fake fleet. KWOK gives us the
*nodes*; [run.ai's fake-gpu-operator](https://github.com/run-ai/fake-gpu-operator)
gives us the *GPU layer* on those nodes - GPU advertisement, an operator-shaped
device plugin, and a per-node DCGM exporter. They are complementary, not
alternatives.

## Why an operator at all (vs hand-writing the integer)

You *could* hand-write `nvidia.com/gpu: 8` into a KWOK node's `status.allocatable`
(earlier versions of this lesson did). The operator is better because it makes the
fake fleet behave like a real one in two ways that matter later:

- **Operator-shaped advertisement.** A device plugin advertises the GPUs, exactly as
  the real NVIDIA GPU Operator does in production - not a hand-edited status field.
- **A DCGM metrics stream.** It stands up a DCGM exporter per node emitting real
  `DCGM_FI_*` metric names/labels (with per-pod attribution), so
  [Lesson 3](../../03-observability/README.md) can build dashboards and alerts against
  the same fleet. The *values* are synthetic; the *shape* is real.

It is also the mechanism [Lesson 1B (KAI)](../kai-scheduler/README.md) and
[Lesson 1C (HAMi)](../hami/README.md) require, so the whole course uses one fake-GPU
layer instead of several.

## How it works on KWOK nodes

fake-gpu-operator is designed to sit on top of KWOK. KWOK provides kubelet-less nodes
at any scale; the operator's components advertise GPUs on the nodes carrying the
`run.ai/simulated-gpu-node-pool=<pool>` label:

- **status-updater / topology-server** - hold the per-pool topology (count, product,
  memory) and patch node status.
- **kwok-gpu-device-plugin** - the KWOK-aware device plugin that advertises
  `nvidia.com/gpu` (a normal DaemonSet device plugin can't run on a kubelet-less
  node, so the operator ships a KWOK-specific one).
- **nvidia-dcgm-exporter (per node)** - emits `DCGM_FI_*` metrics for each simulated
  GPU, with `pod=`/`namespace=` attribution for scheduled workloads.

`make phase1-up` installs it with three pools matching the node labels:

| Pool | label `run.ai/simulated-gpu-node-pool` | GPUs/node | Product |
|---|---|---|---|
| a100 | `a100` | 8 | `NVIDIA-A100-SXM4-80GB` |
| h100 | `h100` | 8 | `NVIDIA-H100-80GB-HBM3` |
| l40s | `l40s` | 4 | `NVIDIA-L40S` |

Install detail is in [`../scripts/install-fake-gpu-operator.sh`](../scripts/install-fake-gpu-operator.sh)
(JFrog `prod` chart; the ghcr.io OCI build is DRA-oriented and does not populate
`nvidia.com/gpu`).

## See the metrics

```bash
kubectl -n gpu-operator port-forward svc/nvidia-dcgm-exporter 9400:9400 &
curl -s localhost:9400/metrics | grep -E '^DCGM_FI_' | head
```

> **SCOPE NOTE:** everything here is synthetic. The advertised GPUs, the device
> plugin, and the DCGM metrics are fabricated, and pods on KWOK nodes are simulated
> (no real container, so no real `nvidia-smi` or CUDA). Dashboards built on these
> metrics prove dashboard/alert *design*, not real telemetry. Real DCGM evidence
> belongs to [Lesson 6](../gpu-operator-real/README.md).

✅ **Checkpoint:** state which component advertises `nvidia.com/gpu` on a KWOK node,
and the one thing this layer still cannot give you (real GPU telemetry / a real
`nvidia-smi`).

➡️ **Back to:** [Lesson 1](../README.md) · **Leads to:**
[Lesson 3 - Observability](../../03-observability/README.md).

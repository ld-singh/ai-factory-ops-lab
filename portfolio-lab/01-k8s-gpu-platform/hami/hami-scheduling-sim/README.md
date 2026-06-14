# HAMi scheduling simulation (control plane, no GPU)

## The boundary (read first)

This lesson validates HAMi's **control plane only**: the scheduling decision over
fractional GPU requests, on a fake GPU fleet with no hardware. Validated here:

- the mutating webhook routing GPU pods to the HAMi scheduler (`schedulerName:
  hami-scheduler` is injected),
- the scheduler's filter/score over `nvidia.com/gpu`, `nvidia.com/gpumem`, and
  `nvidia.com/gpucores` (fractional placement, not just whole GPUs),
- capacity accounting: a `gpumem` request larger than any GPU stays Pending with
  `CardInsufficientMemory`.

It does **not** validate runtime isolation: the in-container memory cap, OOM
behavior, time-sliced cores, or a virtualized `nvidia-smi`. Those need a real GPU and
a real CUDA workload, and are the paired lesson
[`../hami-isolation-realgpu/`](../hami-isolation-realgpu/README.md). A green run here
proves HAMi made the right placement decision, not that a container is held to its
slice.

## Relationship to the official HAMi tutorial

This lesson is based on the official
[HAMi local-fake-gpu tutorial](https://project-hami.io/tutorials/labs/local-fake-gpu),
with one important difference. The official tutorial uses run.ai's fake-gpu-operator
and notes that only `nvidia.com/gpu` works, while `gpumem`/`gpucores` "require a real
NVIDIA GPU environment." That statement is about runtime **isolation**. The
**scheduling** of `gpumem`/`gpucores` does work on fakes once HAMi's scheduler has the
per-GPU memory and core figures, which this lesson supplies through the
`hami.io/node-nvidia-register` annotation (see below). With that annotation, fractional
pods schedule on fakes; this was verified on the live cluster (a `gpu:1, gpumem:3000,
gpucores:30` pod reaches Running, and an over-large `gpumem` request stays Pending).

## How the fake fleet works (the validated recipe)

Three pieces, in this order (the Makefile does them):

1. **fake-gpu-operator** (run.ai, JFrog `prod` chart) makes each labelled node
   advertise `nvidia.com/gpu` by patching node status directly through the API. No
   kubelet or driver. Use the JFrog `prod` chart; the `ghcr.io` OCI build is
   DRA-oriented and does not populate `nvidia.com/gpu`.
2. **HAMi**, installed with `devicePlugin.enabled=false`. HAMi's own device plugin
   uses NVML to find GPUs and **crashes on GPU-free nodes**, so it must be off (the
   official tutorial does the same). `mockDevicePlugin.enabled=false` too: the bundled
   mock plugin (image 1.0.1) fails to parse HAMi 2.9.0's generated device config
   (`cannot unmarshal map into []ascend.VNPUConfig`), so we do not use it.
   `scheduler.kubeScheduler.imageTag` is pinned to `K8S_VERSION`.
3. **Node registration.** With both device plugins off, nothing writes the annotation
   HAMi's scheduler reads, so [`scripts/register-hami.sh`](scripts/register-hami.sh)
   writes it: `hami.io/node-nvidia-register` (the per-GPU list including `devmem` and
   `devcore`, which is what enables fractional placement) plus `hami.io/node-handshake`
   (a liveness timestamp). HAMi drops a node whose handshake is stale beyond ~60s; on a
   real node the device plugin refreshes it every ~30s, so here `make demo-*` refreshes
   it before scheduling.

## Why not reuse the KWOK fleet from Lesson 1

Two reasons. First, HAMi's scheduler reads GPU inventory from the
`hami.io/node-nvidia-register` annotation, not from `allocatable`, so a KWOK node with
`nvidia.com/gpu: 8` is invisible to it until something writes that annotation. Second,
the pod still needs `nvidia.com/gpu` in node `allocatable` for the resource fit, which
on a real worker comes from fake-gpu-operator. This lesson uses real kind workers (no
GPU) so fake-gpu-operator can advertise the resource and pods run as ordinary
containers. The annotation supplies HAMi's scheduler view.

## One `K8S_VERSION` feeds both the node image and HAMi's scheduler image

A mismatch between the cluster Kubernetes version and
`scheduler.kubeScheduler.imageTag` is a common HAMi failure. The Makefile defines a
single `K8S_VERSION` and passes it to both `kindest/node:vX.Y.Z` and
`--set scheduler.kubeScheduler.imageTag=vX.Y.Z`, so they cannot drift.

## Resource semantics

| Resource | Meaning | Unit |
|---|---|---|
| `nvidia.com/gpu` | number of physical GPUs | count |
| `nvidia.com/gpumem` | per-pod GPU memory | MiB (1 unit = 1 MiB). HAMi docs sometimes write "MB"; treated as MiB here |
| `nvidia.com/gpucores` | share of GPU compute | percent (1 unit = 1%) |

`nvidia.com/gpumem-percentage` expresses memory as a fraction instead of an absolute;
a pod sets that or `gpumem`, not both. The examples use absolute `gpumem`.

## Prerequisites

- docker, kind, kubectl, helm, jq (the repo's `make check` covers these)
- no GPU

## The loop (copy-paste)

```bash
cd portfolio-lab/01-k8s-gpu-platform/hami/hami-scheduling-sim

make up               # kind cluster + fake-gpu-operator + HAMi + node registration
make verify           # nvidia.com/gpu per node + the HAMi registration annotation
make demo-fractional  # scenario 1: a fractional pod (gpu:1, gpumem:3000, gpucores:30) binds
make demo-pending     # scenario 2: a gpumem request bigger than any GPU stays Pending
make demo-placement   # scenario 3: HAMi's per-pod placement decisions
make evidence         # capture control-plane evidence into evidence/
make down             # delete the cluster
```

## Scenarios and what was observed

| # | Manifest | Shows | Observed |
|---|---|---|---|
| 1 | [`manifests/01-fractional-pod.yaml`](manifests/01-fractional-pod.yaml) | `gpu:1, gpumem:3000, gpucores:30` | **Running** on a worker (fractional scheduling works) |
| 2 | [`manifests/02-overrequest-pending.yaml`](manifests/02-overrequest-pending.yaml) | `gpumem` beyond any GPU | **Pending**, `CardInsufficientMemory` (fractional accounting works) |
| 3 | [`manifests/03-placement-spread.yaml`](manifests/03-placement-spread.yaml) | small slices | HAMi prints a `FilteringSucceed` decision (node + fractional score) per pod |

Scenario 3 note: HAMi's binder serializes binds and briefly locks a node per bind, so
several concurrent fractional pods reach Running slowly on simulated nodes. That is a
binding-throughput quirk of fake nodes, not a scheduling error; the placement
**decision** (the `FilteringSucceed` events) is what this scenario demonstrates.

TODO: confirm the exact Helm value that selects binpack vs spread for `HAMI_VERSION`;
the scheduler-policy value name has changed across releases, so it is not set here.

## What "done" looks like

`make evidence` captures the node registration, the three scenarios' pod and event
output, and the scheduler decisions. That evidence backs one claim: HAMi's control
plane scheduled fractional requests correctly on a fake fleet. For the isolation
claim, go to [`../hami-isolation-realgpu/`](../hami-isolation-realgpu/README.md).

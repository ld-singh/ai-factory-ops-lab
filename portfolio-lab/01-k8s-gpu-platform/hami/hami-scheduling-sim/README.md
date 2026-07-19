# HAMi scheduling simulation (control plane, no GPU)

> Part of [Lesson 1C - GPU sharing with HAMi](../README.md) · Course home:
> [AI Factory Operations Lab](../../../../README.md). The paired data-plane lesson is
> [`../hami-isolation-realgpu/`](../hami-isolation-realgpu/README.md).

## What this proves (read first)

On a fake GPU fleet with **no hardware**, this lab validates HAMi's **scheduling
decisions** - the control-plane half:

- the mutating webhook routing GPU pods to the HAMi scheduler,
- the scheduler's filter/score over `nvidia.com/gpu` + `nvidia.com/gpumem` /
  `nvidia.com/gpucores` (it **places** a fractional request),
- per-device **rejection**: a request that can't fit stays Pending with a clear reason
  (`CardInsufficientMemory`).

It does **not** do **GPU sharing** (multiple pods co-resident on one device, all Running)
or **runtime isolation** (the slice enforced inside the container). Those need a real GPU
and are the paired lesson [`../hami-isolation-realgpu/`](../hami-isolation-realgpu/README.md).

> ### Why sharing isn't here (we tried)
> We explored running real multi-pod GPU sharing on the fake fleet using HAMi's **mock
> device plugin**. It can answer the kubelet's `Allocate`, but HAMi's per-node **bind lock**
> (`hami.io/mutex.lock`) is only released by a *real* device plugin after each allocation -
> the mock plugin doesn't release it, so binding more than a pod or two onto a node either
> stalls (lock stuck, 5-minute timeout) or, if you clear the lock to force it, races and
> fails (`UnexpectedAdmissionError`). That's forcing, and it isn't reliable. So the fake
> fleet stays scoped to **scheduling decisions**, and all sharing/isolation lives in the
> [real-GPU lesson](../hami-isolation-realgpu/README.md). The decision is genuine; the
> sharing belongs on hardware.

## Relationship to the official HAMi tutorial

This lesson is based on the official
[HAMi local-fake-gpu tutorial](https://project-hami.io/tutorials/labs/local-fake-gpu),
which uses run.ai's fake-gpu-operator and disables HAMi's real device plugin. That
tutorial notes only `nvidia.com/gpu` works on fakes, while `gpumem`/`gpucores` "require a
real NVIDIA GPU environment" - that statement is about runtime **isolation**. The
**scheduling** of `gpumem`/`gpucores` does work on fakes once HAMi's scheduler has the
per-GPU memory/core figures, which this lesson supplies via the
`hami.io/node-nvidia-register` annotation (below).

## How the fake fleet works (the recipe)

Three pieces, in order (the Makefile does them):

1. **fake-gpu-operator** (run.ai, JFrog `prod` chart) makes each labelled node advertise
   `nvidia.com/gpu` by patching node status through the API - no kubelet or driver. Use
   the JFrog `prod` chart; the `ghcr.io` OCI build is DRA-oriented and won't populate it.
2. **HAMi** with `devicePlugin.enabled=false` (the real plugin needs NVML and crashes
   GPU-free) and `mockDevicePlugin.enabled=false`. `scheduler.kubeScheduler.image.tag` is
   pinned to `K8S_VERSION`.
3. **Node registration** - [`scripts/register-hami.sh`](scripts/register-hami.sh) writes
   `hami.io/node-nvidia-register` (the per-GPU `devmem`/`devcore` list the scheduler scores
   against) + a liveness handshake. With both device plugins off, nothing else writes it,
   so the scheduler would otherwise report "node unregistered". `make up` does this once.

## Why not reuse the KWOK fleet from Lesson 1

HAMi's scheduler scores GPUs from the `hami.io/node-nvidia-register` annotation, and a pod
still needs `nvidia.com/gpu` in node `allocatable` (from fake-gpu-operator) for the
resource fit. This lab uses real kind workers so fake-gpu-operator can advertise the
resource and the HAMi scheduler/webhook run normally; KWOK fake nodes don't provide that.

## One `K8S_VERSION` feeds the node image and HAMi's scheduler image

A mismatch between the cluster Kubernetes version and `scheduler.kubeScheduler.image.tag` is
a common HAMi failure. The Makefile defines a single `K8S_VERSION` and passes it to both
`kindest/node:vX.Y.Z` and `--set scheduler.kubeScheduler.image.tag=vX.Y.Z`.

## Resource semantics

| Resource | Meaning | Unit |
|---|---|---|
| `nvidia.com/gpu` | number of GPUs | count |
| `nvidia.com/gpumem` | per-pod GPU memory | MiB (1 unit = 1 MiB) |
| `nvidia.com/gpucores` | share of GPU compute | percent (1 unit = 1%) |

## Prerequisites

- docker, kind, kubectl, helm, jq (the repo's `make check` covers these)
- no GPU

## The loop (copy-paste)

Each `make` step prints its result and ends with a `Verify:` line.

```bash
cd portfolio-lab/01-k8s-gpu-platform/hami/hami-scheduling-sim

make up               # kind + fake-gpu-operator + HAMi + node registration
make verify           # nvidia.com/gpu per node + the HAMi registration annotation

make demo-fractional  # 1: a fractional request is placed
make demo-pending     # 2: an over-large request stays Pending (CardInsufficientMemory)
make demo-placement   # 3: HAMi's per-pod placement DECISION (FilteringSucceed)

make evidence         # capture control-plane evidence into evidence/<timestamp>/
make clean            # delete the demo workloads
make down             # delete the kind cluster
```

---

## The exercises

Each is one control-plane scheduling **decision** - what the fake fleet genuinely proves.

| # | `make` target | Decision it proves |
|---|---|---|
| 1 | `demo-fractional` | HAMi places a fractional request (`gpu:1, gpumem:3000, gpucores:30`) |
| 2 | `demo-pending` | a request bigger than any GPU stays **Pending** (`CardInsufficientMemory`) |
| 3 | `demo-placement` | per-pod node+device **selection** (`FilteringSucceed`) |

### Exercise 1 - a fractional request is placed

```bash
make demo-fractional
```

[`manifests/01-fractional-pod.yaml`](manifests/01-fractional-pod.yaml): `gpu:1`,
`gpumem:3000`, `gpucores:30`. The HAMi webhook routes it to the HAMi scheduler, which
scores it against each node's registered `devmem`/`devcore` and **places** it - the
fractional arithmetic Lessons 1/1B couldn't express.

✅ **Checkpoint:** a `FilteringSucceed` event and a `hami.io/vgpu-devices-allocated`
annotation on the pod (HAMi's allocation decision). 🔬 **Not proved:** the slice enforced
at runtime (real-GPU lesson).

### Exercise 2 - an over-request stays Pending

```bash
make demo-pending
```

[`manifests/02-overrequest-pending.yaml`](manifests/02-overrequest-pending.yaml): a single
`gpumem: 999999` (~976 GiB) that exceeds any one GPU. ✅ **Pending** with
`CardInsufficientMemory`. A pure scheduler decision (it never reaches the kubelet), so it's
the cleanest, most deterministic evidence here.

### Exercise 3 - the placement decision

```bash
make demo-placement
```

[`manifests/03-placement-spread.yaml`](manifests/03-placement-spread.yaml): three small
slices. The demo prints the hami-scheduler `FilteringSucceed` events - the node chosen and
fractional score, per pod. ✅ a `FilteringSucceed` per pod.

---

## What you can and cannot learn here - the precise line

| Capability | Learnable on the fake fleet? | Why |
|---|---|---|
| Fractional placement decision | ✅ Yes | Scheduler arithmetic over registered devmem/devcore |
| Capacity **rejection** (Pending + reason) | ✅ Yes | Pure scheduler decision, never reaches the kubelet |
| `FilteringSucceed` node+device selection | ✅ Yes | Scheduler-internal decision, surfaced as events |
| **GPU sharing** (multiple pods co-resident on one device, Running) | ❌ No | Needs a real device plugin to complete + release each bind - real GPU |
| **The slice enforced inside the container** (cap, OOM, virtualized `nvidia-smi`) | ❌ No | HAMi-core must intercept real CUDA calls |
| Compute-throttling accuracy / MIG | ❌ No | Real hardware / a MIG-capable card (A100, H100, …) |

💡 The course's pattern: scheduling **decisions** are learnable on fakes; **sharing and
enforcement** need real hardware. This lesson is the decisions half;
[`hami-isolation-realgpu/`](../hami-isolation-realgpu/README.md) is where pods actually
share one card and the slice is enforced.

## What "done" looks like

`make evidence` captures the registration, the placed fractional pod, the Pending
rejection and its reason, and the `FilteringSucceed` decisions. That backs one claim:
**HAMi's scheduler made the right fractional placement decisions on a fake fleet.** For
sharing and isolation, go to [`../hami-isolation-realgpu/`](../hami-isolation-realgpu/README.md).

📎 **Related runbooks:**
[device-plugin-not-advertising-gpus.md](../../../../runbooks/device-plugin-not-advertising-gpus.md),
[gpu-memory-pressure.md](../../../../runbooks/gpu-memory-pressure.md),
[cuda-visible-devices-debugging.md](../../../../runbooks/cuda-visible-devices-debugging.md).

➡️ **Next:** [Lesson 2 - Slurm GPU Workload Management](../../../02-slurm-gpu-platform/README.md).
(The real-GPU isolation half of HAMi runs later, in [Lesson 6](../../../real-gpu-session/README.md).)

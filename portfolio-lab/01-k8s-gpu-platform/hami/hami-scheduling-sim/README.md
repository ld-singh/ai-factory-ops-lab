# HAMi scheduling simulation (control plane, no GPU)

> Part of [Lesson 1C - GPU sharing with HAMi](../README.md) · Course home:
> [AI Factory Operations Lab](../../../../README.md). The paired data-plane lesson is
> [`../hami-isolation-realgpu/`](../hami-isolation-realgpu/README.md).

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

> **The course's central line, drawn through one YAML block.** Everything below is a
> *decision* HAMi's scheduler makes over integers (does a slice fit? which device?).
> What happens *after* placement - a CUDA `malloc` past the cap actually failing
> inside the container - is *enforcement*, and only the real-GPU lesson proves it.
> Decisions are free; enforcement needs hardware.

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
a pod sets that or `gpumem`, not both. Exercises 1-6 use absolute `gpumem`; Exercise 7
shows the percentage form.

## Prerequisites

- docker, kind, kubectl, helm, jq (the repo's `make check` covers these)
- no GPU

## The loop (copy-paste)

```bash
cd portfolio-lab/01-k8s-gpu-platform/hami/hami-scheduling-sim

make up                     # kind cluster + fake-gpu-operator + HAMi + node registration
make verify                 # nvidia.com/gpu per node + the HAMi registration annotation

# The exercises (run in any order; each cleans up the previous workload it touches)
make demo-fractional        # 1: a fractional pod (gpu:1, gpumem:3000, gpucores:30) binds
make demo-pending           # 2: a gpumem request bigger than any GPU stays Pending
make demo-placement         # 3: HAMi's per-pod placement decisions (FilteringSucceed)
make demo-binpack           # 4: 12 pods share one 8-GPU node (several pods per device)
make demo-mem-exhaustion    # 5: per-device gpumem budget exhausts; last pod Pending
make demo-gpucores          # 6: gpucores (compute %) exhausts independently of memory
make demo-gpumem-percentage # 7: the percentage memory form (gpumem-percentage) binds

make evidence               # capture control-plane evidence into evidence/<timestamp>/
make clean                  # delete the demo workloads (keep the cluster)
make down                   # delete the kind cluster
```

Run `make up` and `make verify` **once**, then the exercises. Exercises 4-6 pin their
pods to one node (via a `demo-node=target` label that [`scripts/pin-node.sh`](scripts/pin-node.sh)
sets) so their per-device capacity arithmetic is deterministic. Capture evidence at the
end of whichever exercise you want to document; `make clean` removes the workloads and
the pin label.

---

## The exercises

Each exercise is one scheduling *decision*. The first three are validated on the live
cluster (real captured output). Exercises 4-7 are **runnable and expected** - their
outcomes follow from per-device capacity arithmetic - but ship marked *Expected*: run
them and capture the real output into your evidence before you claim them as validated,
exactly as the project's [validation rule](../../../06-validation-reports/README.md)
requires.

| # | `make` target | Decision it proves | Status |
|---|---|---|---|
| 1 | `demo-fractional` | a fractional request (`gpu:1, gpumem:3000, gpucores:30`) places | ✅ Validated |
| 2 | `demo-pending` | a `gpumem` larger than any GPU stays Pending (`CardInsufficientMemory`) | ✅ Validated |
| 3 | `demo-placement` | per-pod node+device selection (`FilteringSucceed`) | ✅ Validated (decision) |
| 4 | `demo-binpack` | multiple pods share ONE physical GPU (the sharing decision) | 🟡 Expected - run to confirm |
| 5 | `demo-mem-exhaustion` | per-device `gpumem` budget exhausts while whole GPUs remain free | 🟡 Expected - run to confirm |
| 6 | `demo-gpucores` | compute (`gpucores`) exhausts independently of memory | 🟡 Expected - run to confirm |
| 7 | `demo-gpumem-percentage` | the percentage memory form places | 🟡 Expected - run to confirm |

### Exercise 1 - a fractional pod places (validated)

```bash
make demo-fractional
```

Applies [`manifests/01-fractional-pod.yaml`](manifests/01-fractional-pod.yaml):
`gpu:1, gpumem:3000, gpucores:30`. `schedulerName` is intentionally **not** set - the
HAMi mutating webhook routes any pod that requests these resources to the HAMi
scheduler automatically.

✅ **Checkpoint:** the pod reaches **Running** on a worker. That is HAMi placing a
*slice*, not a whole device - the thing Lessons 1/1B could not express.

🔬 **Proved:** fractional scheduling arithmetic. **Not proved:** that a container is
held to 3000 MiB at runtime (real-GPU lesson).

### Exercise 2 - over-request stays Pending (validated)

```bash
make demo-pending
```

Applies [`manifests/02-overrequest-pending.yaml`](manifests/02-overrequest-pending.yaml):
a single `gpumem: 999999` (≈976 GiB) that exceeds any one GPU.

✅ **Checkpoint:** **Pending** with `CardInsufficientMemory` in the events. The
scheduler refused a slice that cannot fit on any device - capacity accounting at the
control-plane level.

> Exercise 2 over-requests against a **single** device. Exercise 5 is the subtler
> cousin: every request fits a GPU, but the *aggregate* exhausts one.

### Exercise 3 - the placement decision (validated)

```bash
make demo-placement
```

Applies [`manifests/03-placement-spread.yaml`](manifests/03-placement-spread.yaml):
three small slices. The demo prints the hami-scheduler `FilteringSucceed` events -
node chosen and fractional score, per pod.

> **Binding-throughput quirk on fakes:** HAMi's binder serializes binds and briefly
> locks a node per bind, so several concurrent fractional pods reach Running slowly on
> simulated nodes. That is a fake-node quirk, not a scheduling error; the placement
> **decision** (the `FilteringSucceed` events) is what this scenario demonstrates.
>
> TODO: confirm the exact Helm value that selects binpack vs spread for `HAMI_VERSION`;
> the scheduler-policy value name has changed across releases, so it is not set here.

✅ **Checkpoint:** a `FilteringSucceed` ("find fit node") event per placed pod.

### Exercise 4 - binpack: multiple pods on one device (expected)

```bash
make demo-binpack
```

Pins one 8-GPU node and applies [`manifests/04-binpack.yaml`](manifests/04-binpack.yaml):
**12** pods, each a tiny slice (`gpumem:2000, gpucores:5`), all confined to that node.

💡 **Why it's deterministic:** 12 pods each need `nvidia.com/gpu: 1`, but the node has
only 8 physical GPUs - by pigeonhole at least four GPUs must host two pods. The slices
are tiny, so neither memory nor cores binds; the physical GPU count does, and HAMi
*shares* devices to fit all 12. Stock Kubernetes caps this node at 8 (one pod per GPU).

🟡 **Expected (run to confirm):** all **12 Running on the one node**. That co-residency
- more pods than physical GPUs - is the core thing HAMi adds. Capture
`kubectl get pods -l app=hami-binpack -o wide` showing 12 on one 8-GPU node.

### Exercise 5 - per-device memory exhaustion (expected)

```bash
make demo-mem-exhaustion
```

Pins one 8-GPU node and applies [`manifests/05-mem-exhaustion.yaml`](manifests/05-mem-exhaustion.yaml):
**17** pods, each `gpumem: 30000`.

💡 **The arithmetic:** each GPU has 81920 MiB, so it fits two 30000-MiB pods (60000)
but not three (90000). The node holds at most 8 × 2 = **16**; the 17th cannot be placed
on any device. This is a capacity bound, not a policy choice, so it holds on any HAMi
scheduler policy.

🟡 **Expected (run to confirm):** **16 Running, 1 Pending** with `CardInsufficientMemory`
- even though whole GPUs by *count* are still free. This is the sharpest proof that
HAMi accounts memory **per device**, not just GPU count the way Lessons 1/1B do.

### Exercise 6 - compute (gpucores) accounting (expected)

```bash
make demo-gpucores
```

Pins one 8-GPU node and applies [`manifests/06-gpucores.yaml`](manifests/06-gpucores.yaml):
**9** pods, each `gpucores: 60` and only `gpumem: 1000`.

💡 **The arithmetic:** by cores a GPU fits one pod (60) but not two (120 > 100); by
memory it could fit dozens. So **cores** bind at one pod per GPU: 8 fit, the 9th does
not. Same fleet as Exercise 5, *different* binding dimension.

🟡 **Expected (run to confirm):** **8 Running, 1 Pending** on a compute/cores-insufficient
reason. HAMi tracks memory and compute **independently**: a device can have memory to
spare and still be full on cores.

> **TODO - confirm the reason string.** The cores-insufficient Pending message varies
> by HAMi version (it may read `CardInsufficientCore` / `CardComputeUnitsInsufficient`
> or similar). The demo prints it; record the exact text from your run into evidence,
> and confirm against the hami-scheduler logs and
> [the HAMi repo](https://github.com/Project-HAMi/HAMi).

### Exercise 7 - the percentage memory form (expected)

```bash
make demo-gpumem-percentage
```

Applies [`manifests/07-gpumem-percentage.yaml`](manifests/07-gpumem-percentage.yaml):
one pod asking `nvidia.com/gpumem-percentage: 50` instead of an absolute MiB figure.

💡 **Why:** HAMi accepts either the absolute (`gpumem`) or relative
(`gpumem-percentage`) memory form - a pod sets one, not both. 50% resolves against each
GPU's registered `devmem` (81920 MiB → ~40960 MiB).

🟡 **Expected (run to confirm):** **Running**. Two such pods would fill one device's
memory; a third 50% request would not fit - the same per-device accounting as
Exercise 5, expressed as a percentage.

> **TODO:** confirm `nvidia.com/gpumem-percentage` is the exact key, and that it is
> mutually exclusive with `nvidia.com/gpumem`, for your `HAMI_VERSION`.

---

## What you can and cannot learn here - the precise line

| Capability | Learnable on the fake fleet? | Why |
|---|---|---|
| Fractional request placement (gpumem/gpucores) | ✅ Yes | Control-plane arithmetic over registered devmem/devcore |
| Multi-pod sharing of one device (binpack) | ✅ Yes | A placement decision; co-residency is visible in `get pods` |
| Per-device memory / compute accounting & exhaustion | ✅ Yes | Capacity bookkeeping over integers |
| `FilteringSucceed` node+device selection | ✅ Yes | Scheduler-internal decision, surfaced as events |
| **In-container memory cap enforcement** | ❌ No | HAMi-core must intercept real CUDA calls - [real-GPU lesson](../hami-isolation-realgpu/README.md) |
| **Virtualized `nvidia-smi`, OOM at the slice limit** | ❌ No | Runtime behavior on a real device |
| Compute-throttling accuracy / interference under load | ❌ No | Needs sustained real workloads + measurement |
| MIG hardware partitioning | ❌ No | Needs an Ampere+ datacenter GPU |

💡 The pattern matches the whole course: **decisions** are learnable on fakes;
**execution and isolation** need real hardware. HAMi splits cleanly along that line -
this lesson is the decisions half, [`hami-isolation-realgpu/`](../hami-isolation-realgpu/README.md)
is the enforcement half.

## What "done" looks like

`make evidence` captures the node registration, each deployed exercise's pod/event
output, and the Pending reasons that prove exercises 5-6. That evidence backs one
claim: **HAMi's control plane scheduled fractional requests correctly on a fake fleet**
- placement, device sharing, and per-device memory/compute accounting. For the
isolation claim, go to [`../hami-isolation-realgpu/`](../hami-isolation-realgpu/README.md).

📎 **Related runbooks:**
[device-plugin-not-advertising-gpus.md](../../../../runbooks/device-plugin-not-advertising-gpus.md),
[gpu-memory-pressure.md](../../../../runbooks/gpu-memory-pressure.md),
[cuda-visible-devices-debugging.md](../../../../runbooks/cuda-visible-devices-debugging.md).

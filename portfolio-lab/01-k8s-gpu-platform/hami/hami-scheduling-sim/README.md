# HAMi GPU sharing simulation (control plane, no GPU)

> Part of [Lesson 1C - GPU sharing with HAMi](../README.md) · Course home:
> [AI Factory Operations Lab](../../../../README.md). The paired data-plane lesson is
> [`../hami-isolation-realgpu/`](../hami-isolation-realgpu/README.md).

## What this proves (read first)

On a fake GPU fleet with **no hardware**, this lab demonstrates HAMi's control plane,
**including multiple pods sharing one GPU and reaching Running** - the thing the default
scheduler cannot do. It proves:

- the mutating webhook routing GPU pods to the HAMi scheduler,
- fractional placement over `nvidia.com/gpu` + a memory/compute slice (a pod **places and
  runs**),
- capacity **rejection**: a request that can't fit stays Pending with a clear reason,
- **GPU sharing**: two (or more) fractional pods co-scheduled and **both Running**, each
  holding a memory slice - validated on the fake fleet.

The trick is HAMi's own **mock device plugin**, which answers the kubelet's `Allocate`
with no hardware (so shared pods are admitted, not rejected). What still needs a **real
GPU** - the paired [`../hami-isolation-realgpu/`](../hami-isolation-realgpu/README.md)
lesson - is the **data plane**: the slice actually *enforced* inside the container (a
CUDA `malloc` past the cap failing), a virtualized `nvidia-smi`, OOM behaviour, and MIG.

> ### ⚠️ Two hard rules of the fake fleet
>
> 1. **Request GPU memory as a PERCENTAGE** (`nvidia.com/gpumem-percentage`), not absolute
>    MiB. The mock plugin registers one device per MiB; an 80 GiB GPU = 81920 devices and a
>    full node blows past the kubelet's ~120 GiB device limit, so **absolute `gpumem` comes
>    back capacity `0`** (`OutOfnvidia.com/gpumem`). Percentage registers a small count
>    (8×100) and allocates fine. So sim demos slice memory by **percent**; absolute-MiB
>    slices are a real-GPU thing.
> 2. **Pin HAMi to 2.8.x.** HAMi 2.9.0's Ascend user-space partitioning reshaped the
>    `hami-scheduler-device` ConfigMap to a map, which the mock plugin (image 1.0.1)
>    rejects (`cannot unmarshal map into []ascend.VNPUConfig`). 2.8.x emits the list format
>    it expects. The Makefile pins `HAMI_VERSION ?= 2.8.0` for this reason.
>
> *Validated 2026-06-21:* two pods (`gpu:1` + `gpumem-percentage:20` each) both reached
> Running on one node under HAMi 2.8.0 + mock plugin 1.0.1.

## What this lab does that the official docs do NOT

⭐ **No single official HAMi doc shows multi-pod GPU sharing running with zero hardware.**
This lab does - by combining three pieces none of the docs combine, plus three gotchas we
had to discover by hand. That's the original engineering here; it's worth being explicit
about where the official material stops and this lab goes further.

| Source | What it does | Where it stops |
|---|---|---|
| Official [local-fake-gpu tutorial](https://project-hami.io/tutorials/labs/local-fake-gpu) | fake-gpu-operator advertises `nvidia.com/gpu`; HAMi's real device plugin **off** | a **single** pod schedules; says **sharing needs a real GPU** |
| Official [mock-device-plugin](https://github.com/Project-HAMi/mock-device-plugin) | registers `gpumem`/`gpucores` into node `allocatable` and answers the kubelet `Allocate` | registers resources only - **no `hami.io/node-nvidia-register` annotation**, no fake-sharing recipe, and **breaks on current HAMi** |
| **This lab** | **all three stitched together** → **multiple pods share one GPU and reach Running, no hardware** | runtime *isolation* (the slice enforced inside the container) - that's the real-GPU lab |

**The three pieces we combine (no official doc combines them):**

1. **fake-gpu-operator** - advertises `nvidia.com/gpu` (from the local-fake-gpu tutorial).
2. **HAMi's mock device plugin** - answers the kubelet `Allocate` so *shared* pods are
   admitted, not just scheduled (the tutorial's missing data-plane half).
3. **A hand-written `hami.io/node-nvidia-register` annotation** ([`register-hami.sh`](scripts/register-hami.sh))
   - **this is our shim, not an official step.** The scheduler needs that annotation to see
   a node's GPUs; in a real cluster HAMi's *real* device plugin writes it, but we've
   disabled that (it needs NVML), and **neither the mock plugin nor fake-gpu-operator writes
   it** (confirmed in the mock plugin's README). So we write it ourselves. A real GPU
   cluster would not need this.

**The three gotchas we discovered (undocumented):**

1. **Pin HAMi to 2.8.x.** 2.9.0's Ascend user-space partitioning reshaped the
   `hami-scheduler-device` ConfigMap to a map; the mock plugin (1.0.1) rejects it
   (`cannot unmarshal map into []ascend.VNPUConfig`). 2.8.x emits the list it expects.
2. **Slice memory by PERCENTAGE, never absolute MiB.** The mock plugin registers one device
   per MiB, so an 80 GiB GPU = 81920 devices and a node exceeds the kubelet's ~120 GiB
   device limit - absolute `gpumem` comes back capacity `0`. `gpumem-percentage` is a small
   count and works.
3. **Register ONCE, never per-demo.** Re-writing the node annotation mid-flight tangles
   HAMi's per-node bind lock and leaves the second pod Pending
   (`node ... has been locked within 5m0s`).

> None of this is in the docs as a recipe; we proved it on a live cluster (2 pods sharing
> one GPU, both Running - HAMi 2.8.0 + mock 1.0.1, 2026-06-21). **Treat it as a working
> extension of the official material, not as official guidance.**

## How the fake fleet works (the recipe)

Four pieces, in order (the Makefile does them):

1. **fake-gpu-operator** (run.ai, JFrog `prod` chart) makes each labelled node advertise
   `nvidia.com/gpu` by patching node status through the API - no kubelet or driver. Use
   the JFrog `prod` chart; the `ghcr.io` OCI build is DRA-oriented and won't populate it.
2. **HAMi 2.8.x** with `devicePlugin.enabled=false` (the real plugin needs NVML and
   crashes GPU-free) **and `mockDevicePlugin.enabled=true`** (image `1.0.1`). The mock
   plugin registers `gpumem` / `gpumem-percentage` / `gpucores` and **answers `Allocate`**
   - the part that lets shared pods be admitted. `scheduler.kubeScheduler.imageTag` is
   pinned to `K8S_VERSION`.
3. **Node registration** - [`scripts/register-hami.sh`](scripts/register-hami.sh) writes
   the `hami.io/node-nvidia-register` annotation (per-GPU `devmem`/`devcore` list) + a
   liveness handshake. The mock plugin registers devices with the *kubelet* but **not** the
   annotation HAMi's *scheduler* reads - without it the scheduler reports "node
   unregistered" and pods stay Pending. `make up` does this **once**.
4. **Workloads** request `nvidia.com/gpu` + `gpumem-percentage` (+ optional `gpucores`).

> **Why register runs ONCE, not before every demo (a bug worth knowing).** An earlier
> version ran `register` as a prerequisite of *every* demo. Re-writing the node annotation
> mid-flight tangles HAMi's per-node bind lock, leaving the second pod Pending with
> `node ... has been locked within 5m0s`. Registering once at `make up` and leaving it
> alone fixed sharing. If nodes go stale after long inactivity (~60s), `make register`
> refreshes the handshake.

## Why not reuse the KWOK fleet from Lesson 1

A pod needs `nvidia.com/gpu` in node `allocatable` for the resource fit (from
fake-gpu-operator), the mock device plugin to register `gpumem-percentage`/`gpucores` and
answer the kubelet's `Allocate`, and HAMi's scheduler to read the per-GPU figures. KWOK
fake nodes give none of that wiring (no real kubelet for the device plugin), so this lab
uses real kind workers.

## Resource semantics

| Resource | Meaning | Unit / note |
|---|---|---|
| `nvidia.com/gpu` | number of (virtual) GPUs | count |
| `nvidia.com/gpumem-percentage` | per-pod GPU memory as a fraction | percent (1 = 1%). **Use this on fakes.** |
| `nvidia.com/gpucores` | share of GPU compute | percent (1 = 1%) |
| `nvidia.com/gpumem` | per-pod GPU memory, absolute | MiB. **Does not register on the fake fleet** (device-count limit); real-GPU only. |

## Prerequisites

- docker, kind, kubectl, helm, jq (the repo's `make check` covers these)
- no GPU

## The loop (copy-paste)

Each `make` step prints its result and ends with a `Verify:` line.

```bash
cd portfolio-lab/01-k8s-gpu-platform/hami/hami-scheduling-sim

make up               # kind + fake-gpu-operator + HAMi 2.8 with the mock device plugin ON
make verify           # what each node advertises (nvidia.com/gpu, gpumem-percentage, gpucores)

make demo-share       # ★ THE HEADLINE: two pods SHARE one GPU - both Running
make demo-fractional  # 1: a single fractional pod places (Running)
make demo-pending     # 2: an over-percentage request stays Pending (CardInsufficientMemory)
make demo-placement   # 3: HAMi's per-pod placement DECISION (FilteringSucceed)
make demo-binpack     # 4: six fractional pods coexist across the fleet (sharing at scale)

make evidence         # capture control-plane evidence into evidence/<timestamp>/
make clean            # delete the demo workloads
make down             # delete the kind cluster
```

---

## The exercises

| # | `make` target | What it proves | Status |
|---|---|---|---|
| ★ | `demo-share` | **two pods share one GPU, both Running** (default scheduler can't) | ✅ Validated |
| 1 | `demo-fractional` | a fractional request (`gpu:1` + memory/compute %) places and runs | 🟡 Run to confirm |
| 2 | `demo-pending` | a request bigger than a GPU stays **Pending** (`CardInsufficientMemory`) | 🟡 Run to confirm |
| 3 | `demo-placement` | HAMi's per-pod node+device **selection** (`FilteringSucceed`) | 🟡 Run to confirm |
| 4 | `demo-binpack` | several fractional pods coexist (sharing at scale) | 🟡 Run to confirm |

### ★ The headline - two pods share one GPU (validated)

```bash
make demo-share
```

Applies [`manifests/00-share.yaml`](manifests/00-share.yaml): **two** pods, each `gpu:1` +
`gpumem-percentage:20`. Both reach **Running** on one node - two pods sharing GPU memory,
which the default scheduler can never do (it treats `nvidia.com/gpu` as a whole integer
and has no memory-slice concept). The mock device plugin answers the kubelet `Allocate`,
so the shared pods are admitted instead of erroring.

✅ **Checkpoint:** `kubectl get pods -l app=hami-share -o wide` → **2/2 Running**.

🔬 **Proved:** the sharing *decision* + admission on fakes. **Not proved:** that each
container is actually held to its slice at runtime - that's the
[real-GPU lesson](../hami-isolation-realgpu/README.md).

### Exercise 1 - a single fractional pod places

```bash
make demo-fractional
```

[`manifests/01-fractional-pod.yaml`](manifests/01-fractional-pod.yaml): `gpu:1` +
`gpumem-percentage:30` + `gpucores:30`. ✅ Reaches **Running** - HAMi placing a *slice*,
not a whole device.

### Exercise 2 - an over-request stays Pending

```bash
make demo-pending
```

[`manifests/02-overrequest-pending.yaml`](manifests/02-overrequest-pending.yaml): one pod
asking `gpumem-percentage:150` - impossible (no GPU has 150% of itself). ✅ Stays
**Pending** with a `CardInsufficientMemory`-style reason. A pure scheduler decision (never
reaches the kubelet), so it's clean evidence.

### Exercise 3 - the placement decision

```bash
make demo-placement
```

[`manifests/03-placement-spread.yaml`](manifests/03-placement-spread.yaml): three small
slices. The demo prints the hami-scheduler `FilteringSucceed` events - the node chosen and
fractional score per pod. ✅ A `FilteringSucceed` ("find fit node") per pod, and the pods
reach Running.

> TODO: confirm the exact Helm value that selects binpack vs spread for `HAMI_VERSION`;
> the scheduler-policy value name has changed across releases, so it is not set here.

### Exercise 4 - sharing at scale

```bash
make demo-binpack
```

[`manifests/04-binpack.yaml`](manifests/04-binpack.yaml): **six** pods, each `gpu:1` +
`gpumem-percentage:30`, all reaching **Running** across the fleet - many more concurrent
fractional tenants than the default scheduler could place. (Each node admits up to its 8
`nvidia.com/gpu` slots, so the six spread across workers.)

---

## What you can and cannot learn here - the precise line

| Capability | Learnable on the fake fleet? | Why |
|---|---|---|
| Fractional placement + a pod running | ✅ Yes | Scheduler arithmetic + mock plugin admission |
| **Multiple pods sharing one GPU (both Running)** | ✅ Yes | Mock device plugin answers `Allocate` with no hardware |
| Capacity **rejection** (Pending + reason) | ✅ Yes | Pure scheduler decision |
| `FilteringSucceed` node+device selection | ✅ Yes | Scheduler-internal decision, surfaced as events |
| **The slice ENFORCED inside the container** (cap, OOM, virtualized `nvidia-smi`) | ❌ No | HAMi-core must intercept real CUDA calls - [real-GPU lesson](../hami-isolation-realgpu/README.md) |
| Absolute-MiB memory slices (`gpumem`) | ❌ No | Per-MiB device count exceeds the kubelet limit on fakes |
| Compute-throttling accuracy / MIG | ❌ No | Real hardware / a MIG-capable card (A100, H100, …) |

💡 The pattern matches the whole course: **scheduling and sharing *decisions*** are
learnable on fakes; **runtime *enforcement*** needs real hardware. This lesson is the
decisions half (now including sharing); [`hami-isolation-realgpu/`](../hami-isolation-realgpu/README.md)
proves the slice is actually held inside the container.

## What "done" looks like

`make evidence` captures what each node advertises, the shared pods Running, the fractional
pod, the Pending rejection, and the `FilteringSucceed` decisions. That backs the claim:
**HAMi's control plane schedules and *shares* GPUs correctly on a fake fleet.** For the slice being
*enforced*, go to [`../hami-isolation-realgpu/`](../hami-isolation-realgpu/README.md).

📎 **Related runbooks:**
[device-plugin-not-advertising-gpus.md](../../../../runbooks/device-plugin-not-advertising-gpus.md),
[gpu-memory-pressure.md](../../../../runbooks/gpu-memory-pressure.md),
[cuda-visible-devices-debugging.md](../../../../runbooks/cuda-visible-devices-debugging.md).

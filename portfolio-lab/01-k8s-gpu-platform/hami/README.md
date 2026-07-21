# Lesson 1C - GPU Sharing & Fractional GPUs with HAMi

> Course home: [AI Factory Operations Lab](../../../README.md) · Previous:
> [Lesson 1B - KAI Scheduler](../kai-scheduler/README.md) · Next:
> [Scheduling simulation lab](./hami-scheduling-sim/README.md) (the hands-on part of this lesson)

> 🧪 **Want to run it? Jump straight to the hands-on labs:**
> **[▶ Scheduling simulation](./hami-scheduling-sim/README.md)** (free, no GPU) ·
> **[▶ Isolation on a real GPU](./hami-isolation-realgpu/README.md)** (validated on an RTX A6000).
> The rest of this page is the concepts behind them.

So far you've requested a GPU as an indivisible integer: a pod asks for
`nvidia.com/gpu: 1` and gets a whole device. Lesson 1's default scheduler can do nothing
else, and Lesson 1B's KAI exercises kept to whole GPUs on purpose - to focus on *queue*
policy (KAI can itself slice GPUs, via a `gpu-fraction` request; see the contrast below).
In real fleets, whole-GPU allocation is often wasteful - an inference pod using 3 GB of
an 80 GB A100 strands the other 77 GB. **GPU sharing** is how platforms fix that, and
[HAMi](https://github.com/Project-HAMi/HAMi) (Heterogeneous AI Computing Virtualization
Middleware, a CNCF sandbox project) is an open-source way to do it: it lets one physical
GPU be requested as *fractions* - "2 GB of GPU memory and 30% of compute" - with the
scheduler packing multiple pods onto one device and a runtime layer enforcing the limits
inside each container.

This lesson matters doubly for this course's mission of learning cheaply:

1. **The sharing *decision* is control-plane logic** - like queueing in Lesson 1B,
   the bin-packing of fractional requests onto devices is studyable without hardware.
2. **On real hardware, sharing is a cost multiplier.** When you rent one GPU for
   Lesson 6, HAMi turns it into *several* - you can run multi-tenant sharing,
   oversubscription, and isolation experiments on a single cheap VM that would
   otherwise need a fleet.

🎯 **Learning objectives** - after this lesson you can:

1. Explain the four mainstream GPU-sharing mechanisms - time-slicing, MPS, MIG, and
   software virtualization (HAMi) - and the isolation guarantee each does and
   doesn't give.
2. Explain how HAMi's pieces fit: mutating webhook → scheduler (extender) → device
   plugin → in-container enforcement (HAMi-core intercepting CUDA calls).
3. Install HAMi on a real-GPU node (the Lesson 6 machine) and run **multiple pods
   sharing one physical GPU**, each seeing only its memory slice in `nvidia-smi`.
4. Demonstrate that fractional *scheduling arithmetic* (does a 0.5-GPU request fit?)
   is a control-plane decision, while memory/compute *isolation* is runtime
   enforcement that only real hardware can prove.
5. Say precisely which sharing claims belong on which side of the fake/real line.

🧭 **Mode:** 🟦 Simulation. The concepts and the runnable scheduling sim are free and no-GPU.
The real isolation half is **executed as part of
[Lesson 6 - Real GPU](../../real-gpu-session/README.md)** in your one rental session -
it is described here, next to the concepts it proves, but run there.

📋 **Prerequisites:** [Lesson 1](../README.md) (mental model). The real isolation half
needs the [Lesson 6](../../real-gpu-session/README.md) host set up (driver, toolkit,
Kubernetes) - all part of that one rental session.

> ### 🧪 Two runnable labs in this lesson
>
> The Parts below are the concepts. The hands-on work ships as two self-contained labs
> on opposite sides of the sim/real line - each with its own Makefile and pinned
> versions:
>
> - **🟦 [Scheduling simulation](./hami-scheduling-sim/README.md) - no GPU, free.** Prove
>   HAMi's *scheduling decisions* on a fake GPU fleet, on your laptop: a fractional request
>   is placed, an over-large request is rejected (Pending + reason), and the per-pod
>   placement decision (`FilteringSucceed`) is visible. **GPU sharing** (multiple pods
>   co-resident on one device) and isolation are *not* here - the fake fleet can't do them
>   without forcing - so they live in the real-GPU half below. Free.
> - **🟥 [Isolation on a real GPU](./hami-isolation-realgpu/README.md) - the real half,
>   run in [Lesson 6](../../real-gpu-session/README.md).** Two pods sharing one physical
>   card, a virtualized `nvidia-smi`, and a CUDA allocation refused at the slice limit -
>   the half a simulation can never prove. It runs on one cheap GPU **as part of the
>   Lesson 6 one-rental session**, but it's documented here next to the concepts it proves.
>
> Do the simulation now, for free; the real isolation lab is waiting for you in Lesson 6.

> **⚠️ ILLUSTRATIVE-manifest rule (same as Lesson 1B):** HAMi is actively developed.
> Chart values, resource names, annotations, and defaults can change between
> releases. Snippets below show the *shape*; confirm exact names against the
> official docs before running: https://project-hami.io/ and
> https://github.com/Project-HAMi/HAMi. The manifests you actually run, and their
> output, go into [`../../06-validation-reports/`](../../06-validation-reports/).

---

## The GPU-sharing landscape

One physical GPU, many workloads. Four mainstream ways to slice it:

| Mechanism | How it works | Memory isolation | Compute isolation | Needs special hardware? |
|---|---|---|---|---|
| **Time-slicing** (NVIDIA device plugin option) | Advertise N "replicas" of each GPU; contexts take turns | ❌ None - any pod can OOM the device for everyone | ❌ None (round-robin, no limit) | No |
| **MPS** (Multi-Process Service) | CUDA contexts share the GPU concurrently via a daemon | ⚠️ Limited (resource limits per client, weaker fault isolation) | ⚠️ Partial (active thread percentage) | No |
| **MIG** (Multi-Instance GPU) | Hardware partitions the GPU into isolated instances | ✅ Hardware-enforced | ✅ Hardware-enforced | Yes - only specific datacenter cards: A100/A30, H100/H200, Blackwell. **Not** Ada Lovelace (L4/L40S) |
| **HAMi** (software virtualization) | Device plugin advertises virtual GPUs; HAMi-core library intercepts CUDA calls in-container to cap memory/compute | ✅ Software-enforced (CUDA-API level) | ⚠️ Software-enforced (core-percentage throttling) | No - works on consumer and datacenter GPUs |

> ### 💡 Why HAMi is the one worth learning here
>
> Each of the other three mechanisms fails this course's test in a different way:
>
> - **MIG** needs an expensive A100/H100-class card, and it partitions in *hardware* -
>   something you enable, not something you operate.
> - **Time-slicing** gives *no* isolation, so there's nothing to prove.
> - **MPS** only partially isolates.
>
> **HAMi gives enforceable memory limits on a GPU you can actually afford to rent** - a
> T4 or RTX-class card - and it is the one mechanism that surfaces **both halves of this
> course's central distinction**, in a single YAML block:
>
> | The two halves | What it is | Where this course proves it |
> |---|---|---|
> | **① Scheduling decision** | which device gets which fraction | **free, on fake GPUs** - [`hami-scheduling-sim/`](./hami-scheduling-sim/README.md) |
> | **② Runtime enforcement** | the cap held *inside* the container | **one cheap real GPU** - [`hami-isolation-realgpu/`](./hami-isolation-realgpu/README.md) |
>
> Master that line - **decision vs enforcement** - and you can evaluate *any*
> GPU-sharing technology, not just HAMi. It is the single most transferable idea in
> this lesson.
>
> **And it isn't a niche bet.** In June 2026 NVIDIA's own KAI Scheduler adopted
> **HAMi-core** as the engine that enforces its fractional-GPU memory limits
> ([PR #60](https://github.com/NVIDIA/KAI-Scheduler/pull/60)). So the runtime layer you
> learn here is the same one a flagship scheduler now leans on - HAMi-core is becoming the
> de-facto isolation layer, not an underdog.

How HAMi's pieces fit together:

```
pod requests nvidia.com/gpu + gpumem/gpucores fractions
        │
        ▼
mutating webhook        routes the pod to HAMi's scheduler
        │
        ▼
hami-scheduler          (kube-scheduler + extender) picks a node AND a specific
        │               device with enough remaining memory/core budget
        ▼
hami-device-plugin      advertises virtual GPUs, mounts HAMi-core into the container
        │
        ▼
HAMi-core (libvgpu.so)  intercepts CUDA driver API calls inside the container,
                        enforcing the memory cap and throttling compute
```

✅ **Checkpoint (concept):** without looking at the table, name the sharing mechanism
you'd pick for (a) hard multi-tenant isolation on H100s, (b) squeezing three small
inference services onto one rented T4, (c) quick-and-dirty test parallelism where
isolation doesn't matter. (MIG / HAMi / time-slicing.)

---

## The fractional resource model

With HAMi installed, a pod can ask for a *slice* instead of a whole device:

```yaml
# ILLUSTRATIVE pod fragment - confirm resource names/units in the HAMi docs.
resources:
  limits:
    nvidia.com/gpu: 1          # number of (virtual) GPUs
    nvidia.com/gpumem: 2000    # GPU memory for this slice, in MiB
    nvidia.com/gpucores: 30    # % of the device's compute for this slice
```

💡 **Read that the way the scheduler does.** These are still just numbers - the
scheduler's job is arithmetic: "device 0 has 16 384 MiB total, 6 000 MiB already
promised, so a 2 000 MiB request fits." That bookkeeping is exactly the kind of
control-plane decision Lessons 1 and 1B taught. What is **new** here, and *not*
arithmetic, is what happens after placement: HAMi-core making a CUDA `malloc` beyond
2 000 MiB actually fail inside the container. Decision vs enforcement - the course's
fake/real line, drawn through a single YAML block.

Contrast with [KAI Scheduler](../kai-scheduler/README.md), which **also** does GPU
fractions (a `gpu-fraction: 0.5` request, plus time-slicing/MPS sharing). The difference
is emphasis, not capability: KAI's strength is queue policy (quota/borrow/reclaim/gang);
HAMi's strength is per-device memory slicing with in-container enforcement. Real platforms
combine a queue layer with a sharing layer.

---

## Sharing on a real GPU (the enforcement half)

Everything above is the *decision* side, and you study it for free. The other half - HAMi
actually holding the cap inside a running container - is the one thing only a real GPU can
prove.

On one cheap card, HAMi runs two pods on a single physical GPU, each capped at its own memory
slice. Inside a capped pod, `nvidia-smi` reports only the slice (not the card's full memory),
and a CUDA `malloc` past the cap **fails even with plenty of memory free elsewhere on the
device**. That allocation failure is the single artifact that separates *enforced isolation*
from *bookkeeping*.

🔬 **Proved on real hardware:** concurrent multi-pod sharing of one device, and software-enforced
memory isolation at the CUDA API level. **Not proved:** hardware-grade isolation (that's MIG),
performance interference under sustained load, or fleet-scale behaviour.

▶ **This is a full, runnable lab** - the install steps, manifests, pinned versions, and captured
evidence live in **[Isolation on a real GPU](./hami-isolation-realgpu/README.md)**. Run it during
your one Lesson 6 rental (validated on an RTX A6000).

---

## Two paired runnable lessons

The concepts above are split into two self-contained sub-lessons that sit on opposite
sides of the scope boundary. Each has its own Makefile and pinned versions.

- [`hami-scheduling-sim/`](./hami-scheduling-sim/README.md) - control plane, **no GPU**.
  Based on the official [HAMi local-fake-gpu tutorial](https://project-hami.io/tutorials/labs/local-fake-gpu):
  a kind cluster with real workers, the run.ai fake-gpu-operator advertising
  `nvidia.com/gpu`, HAMi with its device plugins off, and a node-registration annotation.
  Validates HAMi's **scheduling decisions**: a fractional request is placed, an over-large
  request stays Pending (`CardInsufficientMemory`), and the per-pod placement decision
  (`FilteringSucceed`) is visible. It does **not** do GPU *sharing* (multiple pods on one
  device) or *isolation* - the fake fleet can't without forcing - so those are the real-GPU
  lab below.
- [`hami-isolation-realgpu/`](./hami-isolation-realgpu/README.md) - data plane, **one
  cheap real GPU**. Two pods share a single consumer 24 GB card; you observe the
  virtualized `nvidia-smi` and a CUDA allocation refused at the slice limit. Validates
  runtime isolation, which the simulation cannot.

The official tutorial notes `gpumem`/`gpucores` "require a real GPU"; that is about
runtime **isolation**. Fractional **scheduling** works on fakes once HAMi's scheduler
has the per-GPU memory/core figures, which the sim lesson supplies via the
`hami.io/node-nvidia-register` annotation. The split keeps the boundary clear: the sim
proves the placement decision, the real-GPU lesson proves enforcement.

**Getting to production:** most real clusters install the GPU stack with the NVIDIA GPU
Operator, and running HAMi alongside it has one sharp edge (both ship a device plugin
advertising `nvidia.com/gpu`).
[`hami-gpu-operator-coexistence/`](./hami-gpu-operator-coexistence/README.md) walks the
clean single-node setup: the Operator manages the base stack (in production typically the
driver and toolkit too; on the course VM those come from the image, so it runs with
`driver.enabled=false` and `toolkit.enabled=false`), HAMi owns the device plugin, and it
covers the reboot race that trips people up. Validated on an NVIDIA L40.

---

## What you can and cannot learn here - the precise line

| Capability | Where it's learnable | Why |
|---|---|---|
| Sharing-mechanism trade-offs (time-slicing/MPS/MIG/HAMi) | ✅ Free (concepts) | Concepts |
| Fractional resource model & scheduling arithmetic | ✅ Free (the sim lab; 1B for quota math) | Control-plane bookkeeping |
| Multi-pod co-residency on one device | 🟥 Real GPU (isolation lab) | Needs a real device plugin path |
| **Memory-cap enforcement inside the container** | 🟥 Real GPU (isolation lab) | HAMi-core intercepts real CUDA calls |
| Compute throttling accuracy / interference under load | ❌ Out of scope | Needs sustained real workloads + measurement |
| MIG hardware partitioning | ❌ Out of scope | Needs a MIG-capable card (A100/A30, H100/H200, Blackwell) - not Ada Lovelace |

---

## Operational takeaways

- **Sharing is two problems, not one:** placement (scheduler) and enforcement
  (runtime). Evaluate any sharing solution by asking what enforces the limit and
  what happens when a tenant exceeds it.
- **No isolation = no multi-tenancy.** Time-slicing is fine for your own test pods,
  unacceptable across teams: one OOM kills everyone's work on the device.
- **Fractionalization is the single biggest cost lever for inference fleets** -
  small models on dedicated big GPUs are the most common money fire in AI infra.

📎 **Related runbooks:** [cuda-visible-devices-debugging.md](../../../runbooks/cuda-visible-devices-debugging.md),
[device-plugin-not-advertising-gpus.md](../../../runbooks/device-plugin-not-advertising-gpus.md),
[gpu-memory-pressure.md](../../../runbooks/gpu-memory-pressure.md).

➡️ **Next:** run the hands-on lab - [HAMi scheduling simulation](./hami-scheduling-sim/README.md)
(free, no GPU). Then continue to
[Lesson 1D - GPU fleet scale simulation with Volcano](../volcano-scale-sim/README.md)
for gang scheduling at fleet scale, or on to
[Lesson 2 - Slurm GPU Workload Management](../../02-slurm-gpu-platform/README.md).
The real isolation half of this lesson is run later, in
[Lesson 6 - Real GPU](../../real-gpu-session/README.md), alongside the other
real-hardware work - one rental, everything at once.

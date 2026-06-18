# Lesson 1C - GPU Sharing & Fractional GPUs with HAMi

> Course home: [AI Factory Operations Lab](../../../README.md) · Previous:
> [Lesson 1B - KAI Scheduler](../kai-scheduler/README.md) · Next:
> [Lesson 2 - Slurm GPU Workload Management](../../02-slurm-gpu-platform/README.md)

Lessons 1 and 1B treated a GPU as an indivisible integer: a pod asks for
`nvidia.com/gpu: 1` and gets a whole device. In real fleets that's often wasteful -
an inference pod using 3 GB of an 80 GB A100 strands the other 77 GB. **GPU sharing**
is how platforms fix that, and [HAMi](https://github.com/Project-HAMi/HAMi)
(Heterogeneous AI Computing Virtualization Middleware, a CNCF sandbox project) is an
open-source way to do it: it lets one physical GPU be requested as *fractions* -
"2 GB of GPU memory and 30% of compute" - with the scheduler packing multiple pods
onto one device and a runtime layer enforcing the limits inside each container.

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

🧭 **Mode:** 🟦 Simulation. Parts 1–2 are concepts (free) and the runnable scheduling
sim is no-GPU. The real isolation half (Part 3) is **executed as part of
[Lesson 6 - Real GPU](../../real-gpu-session/README.md)** in your one rental session -
it is described here, next to the concepts it proves, but run there. Part 4 is an
optional simulation-side experiment.

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
>   HAMi's *placement* decisions (fractional scheduling, device sharing, per-device
>   memory/compute accounting) on a fake GPU fleet, on your laptop. This is most of the
>   lesson and costs nothing.
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

## Part 1 - The GPU-sharing landscape (free)

One physical GPU, many workloads. Four mainstream ways to slice it:

| Mechanism | How it works | Memory isolation | Compute isolation | Needs special hardware? |
|---|---|---|---|---|
| **Time-slicing** (NVIDIA device plugin option) | Advertise N "replicas" of each GPU; contexts take turns | ❌ None - any pod can OOM the device for everyone | ❌ None (round-robin, no limit) | No |
| **MPS** (Multi-Process Service) | CUDA contexts share the GPU concurrently via a daemon | ⚠️ Limited (resource limits per client, weaker fault isolation) | ⚠️ Partial (active thread percentage) | No |
| **MIG** (Multi-Instance GPU) | Hardware partitions the GPU into isolated instances | ✅ Hardware-enforced | ✅ Hardware-enforced | Yes - Ampere+ datacenter GPUs (A100/H100…) |
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

## Part 2 - The fractional resource model (free)

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

Contrast with [KAI Scheduler](../kai-scheduler/README.md), which also has a
fractional-GPU concept: KAI's strength is queue policy (quota/borrow/reclaim/gang);
HAMi's strength is per-device slicing with in-container enforcement. Real platforms
combine a queue layer with a sharing layer.

---

## Part 3 - 🟥 Share one real GPU between pods (do this during your Lesson 6 rental)

**Goal:** two or more pods Running on one physical GPU at the same time, each seeing
only its own memory slice.

### Step 1 - Install HAMi

On the Lesson 6 machine (driver + container toolkit + Kubernetes already validated):

```bash
# ILLUSTRATIVE - confirm the current repo URL, chart name, and values in the
# HAMi install docs before running.
helm repo add hami-charts https://project-hami.github.io/HAMi/
helm repo update
helm install hami hami-charts/hami -n kube-system
# HAMi's device plugin targets nodes labelled for GPU management (the default
# selector is documented in the chart) - label your GPU node accordingly, e.g.:
kubectl label node <your-gpu-node> gpu=on
```

> HAMi replaces/wraps the device-plugin role. If you installed the GPU Operator in
> Lesson 6, check the HAMi docs for how to coexist with or disable the operator's
> own device plugin first - running two device plugins for the same resource name
> is a classic self-inflicted outage (and a good thing to understand *why*).

✅ **Checkpoint:** HAMi's scheduler and device-plugin pods are Running
(`kubectl get pods -n kube-system | grep -i hami`), and the node now advertises the
fractional resources (`kubectl describe node <node>` shows `nvidia.com/gpumem` etc.).

### Step 2 - Run two pods on one GPU

Apply two pods, each requesting `nvidia.com/gpu: 1` with a small `gpumem` slice
(e.g. 2000 MiB each on a 16 GiB T4), each running `nvidia-smi` and then sleeping.

✅ **Checkpoint:** both pods are **Running simultaneously** on the single-GPU node -
something stock Kubernetes can never do, since the whole device would be allocated
to the first pod.

### Step 3 - Prove the memory cap is real

```bash
kubectl exec <pod-a> -- nvidia-smi
```

**Pass criteria:** `nvidia-smi` *inside the pod* reports the slice (≈2000 MiB
total), not the physical device's full memory. For the strongest evidence, run a
small CUDA program that tries to allocate beyond the cap and capture the allocation
failure - that failure is the single artifact that distinguishes *enforced
isolation* from *bookkeeping*.

🔬 **Proved on real hardware:** concurrent multi-pod sharing of one device, and
software-enforced memory isolation at the CUDA API level. **Not proved:**
hardware-grade isolation (that's MIG), performance interference characteristics
under sustained load, or behaviour at fleet scale.

### Step 4 - Capture evidence

Record in your [lab notebook](../../06-validation-reports/README.md): the chart
version, the node's advertised resources, `kubectl get pods -o wide` showing
co-residency, and the in-pod `nvidia-smi` / allocation-failure output.

---

## Two paired runnable lessons

The concepts above are split into two self-contained sub-lessons that sit on opposite
sides of the scope boundary. Each has its own Makefile and pinned versions.

- [`hami-scheduling-sim/`](./hami-scheduling-sim/README.md) - control plane, **no GPU**.
  Based on the official [HAMi local-fake-gpu tutorial](https://project-hami.io/tutorials/labs/local-fake-gpu):
  a kind cluster with real workers, the run.ai fake-gpu-operator advertising
  `nvidia.com/gpu`, HAMi with its device plugin disabled, and a node-registration
  annotation that lets the scheduler place fractional requests. Validated: a fractional
  pod (`gpu:1, gpumem:3000, gpucores:30`) schedules, and an over-large `gpumem` request
  stays Pending (`CardInsufficientMemory`). It then extends to four further
  scheduling-decision exercises (run-to-confirm): **binpacking** several pods onto one
  physical GPU, **per-device memory exhaustion** (Pending while whole GPUs remain),
  **compute (`gpucores`) accounting** as a dimension independent of memory, and the
  **percentage memory form**. Scheduling only, not isolation.
- [`hami-isolation-realgpu/`](./hami-isolation-realgpu/README.md) - data plane, **one
  cheap real GPU**. Two pods share a single consumer 24 GB card; you observe the
  virtualized `nvidia-smi` and a CUDA allocation refused at the slice limit. Validates
  runtime isolation, which the simulation cannot.

The official tutorial notes `gpumem`/`gpucores` "require a real GPU"; that is about
runtime **isolation**. Fractional **scheduling** works on fakes once HAMi's scheduler
has the per-GPU memory/core figures, which the sim lesson supplies via the
`hami.io/node-nvidia-register` annotation. The split keeps the boundary clear: the sim
proves the placement decision, the real-GPU lesson proves enforcement.

---

## What you can and cannot learn here - the precise line

| Capability | Where it's learnable | Why |
|---|---|---|
| Sharing-mechanism trade-offs (time-slicing/MPS/MIG/HAMi) | ✅ Free (Part 1) | Concepts |
| Fractional resource model & scheduling arithmetic | ✅ Free (Part 2; 1B for quota math) | Control-plane bookkeeping |
| Multi-pod co-residency on one device | 🟥 Real GPU (Part 3) | Needs a real device plugin path |
| **Memory-cap enforcement inside the container** | 🟥 Real GPU (Part 3) | HAMi-core intercepts real CUDA calls |
| Compute throttling accuracy / interference under load | ❌ Out of scope | Needs sustained real workloads + measurement |
| MIG hardware partitioning | ❌ Out of scope | Needs Ampere+ datacenter GPU |

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

➡️ **Next:** [Lesson 2 - Slurm GPU Workload Management](../../02-slurm-gpu-platform/README.md).
The real isolation half of this lesson is run later, in
[Lesson 6 - Real GPU](../../real-gpu-session/README.md), alongside the other
real-hardware work - one rental, everything at once.

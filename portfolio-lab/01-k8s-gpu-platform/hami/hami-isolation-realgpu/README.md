# HAMi isolation on a real GPU (data plane)

## The boundary (read first)

This lesson validates HAMi's **data plane**: the part the
[scheduling simulation](../hami-scheduling-sim/README.md) cannot. On one physical
GPU, with two pods each allocated a memory slice, you observe:

- a virtualized `nvidia-smi` inside each pod that reports the slice, not the full
  card,
- a CUDA allocation that fails when it crosses the slice's memory limit.

That is runtime isolation: HAMi-core, a user-space library, intercepts CUDA driver
calls inside the container and holds the process to its allocation.

What this lesson does **not** claim:

- It is **software isolation**, user-space CUDA interception, not the hardware fault
  isolation of MIG. A misbehaving kernel is constrained by interception, not by a
  hardware partition. Treat the isolation as a scheduling-and-accounting guarantee
  with runtime enforcement, not as a security boundary equivalent to MIG.
- The simulation's green run still proves nothing here. Scheduling correctness and
  isolation are separate systems; this lesson is the only place isolation is shown.

## Why a single non-MIG card

HAMi's primary use case is fractioning GPUs that **cannot** be partitioned by MIG.
Datacenter cards like A100 and H100 support MIG, which gives hardware-level partitions.
Cards like the **RTX A6000** (Ampere, 48 GB), **L4 / L40 / L40S** (Ada Lovelace), and the
consumer RTX 4090/3090 (24 GB) have **no MIG**, so software sharing is the only way to put
more than one tenant on the card. That makes any of them a faithful, cheap target for
demonstrating what HAMi adds - this lab was validated on a 48 GB RTX A6000, which holds two
8 GB slices with plenty of headroom.

> ⚠️ **GPUs are scarce - stay flexible.** The exact card you want is often out of stock,
> back minutes later, or only on another provider. **Any non-MIG card works the same** here;
> take whichever is available rather than waiting. Only the slice sizes depend on the card
> (they scale with VRAM) - a one-line change in the manifests.

## Cost

A working session for this lesson is well under an hour of GPU time. Entry non-MIG cards
commonly run well under ~1 USD/hour on-demand and less on interruptible/spot; rates move
constantly, so **check current pricing before you start**. Capture evidence, then tear the
instance down.

## Provider and runtime requirements

You need a host where you control the container runtime, not a locked-down marketplace
container:

- root on the host,
- the ability to install the NVIDIA Container Toolkit and **set nvidia as the default
  containerd runtime** (HAMi-core is injected through the NVIDIA container runtime, so a
  fixed prebuilt app container you cannot reconfigure will not work),
- a single NVIDIA GPU visible to `nvidia-smi` on the host.

A bare VM or a "full machine" rental where you install your own stack works (Hyperstack,
Lambda, hyperscaler). A managed notebook or a fixed inference container (Vast.ai/RunPod
pods) usually does not.

> **Run HAMi without the NVIDIA GPU Operator.** HAMi brings its own device plugin and
> [must not coexist with NVIDIA's](https://project-hami.io/docs/v2.4.1/installation/prerequisites);
> Operator+HAMi integration is [not officially documented](https://github.com/Project-HAMi/HAMi/issues/1708).
> Part A (the GPU-Operator runtime path) and this part are best run as separate clusters/
> sessions. See [`scripts/setup-notes.md`](scripts/setup-notes.md).

Marketplaces also vary in reliability: driver versions, host config, and uptime are uneven.
Expect to occasionally discard an instance and reprovision.

## What you build

A single-node k3s cluster on the rented host with **nvidia as the default containerd
runtime** and **no GPU Operator**, HAMi installed with the scheduler image tag matched to
the k3s Kubernetes version, the node labelled `gpu=on`, then two pods that each ask for one
GPU and a memory slice and therefore both land on the one card.

## How to run it (scripts)

> 🆕 **Start a fresh GPU VM for this lab.** Because HAMi can't coexist with the GPU
> Operator, Part B does **not** share Part A's cluster - rent a **new** GPU VM (any non-MIG
> card) and run the sequence below on it. Each part captures its own evidence, so running
> Part B on a separate VM loses nothing.

Run the whole lab **on the VM** (SSH in). That keeps helm/kubectl talking to k3s over
localhost - no flaky remote link - and `install-hami.sh` auto-installs `helm` and picks up the
k3s kubeconfig itself.

**Step A - clone the lab onto the new VM:**

```bash
git clone https://github.com/ld-singh/ai-factory-ops-lab.git
cd ai-factory-ops-lab
```

**Step B - bring up the cluster (run from the repo root, as root):**

```bash
sudo PUBLIC_IP=<vm-ip> bash portfolio-lab/real-gpu-session/scripts/host-setup.sh   # toolkit + k3s + nvidia RuntimeClass + gpu=on
sudo bash portfolio-lab/01-k8s-gpu-platform/hami/hami-isolation-realgpu/scripts/set-default-runtime.sh   # nvidia = DEFAULT runtime
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
#  ↳ do NOT run install-gpu-operator.sh - HAMi brings its own device plugin
```

**Step C - install HAMi.** Move into this lab directory so the script's relative paths
(`scripts/`, `manifests/`) resolve, then run it:

```bash
cd portfolio-lab/01-k8s-gpu-platform/hami/hami-isolation-realgpu
./scripts/install-hami.sh
```

When it prints `OK: nvidia.com/gpu = ...` plus the `node-nvidia-register` annotation, setup
is done. (HAMi advertises only `nvidia.com/gpu` in allocatable; the shareable memory lives
in that annotation, not in `nvidia.com/gpumem`.) Now work [the exercises](#the-exercises)
**one at a time**.

> ⚠️ **Install interrupted?** If helm leaves a half-written release, clear it and re-run -
> both are safe to repeat:
> ```bash
> helm -n kube-system uninstall hami 2>/dev/null || true
> ./scripts/install-hami.sh        # auto-clears a stuck release, then reinstalls
> ```

> Read each script before running it - the host-level steps are version-sensitive.
> [`scripts/setup-notes.md`](scripts/setup-notes.md) is the same setup by hand, with the
> reasoning.

## Files

| File | Purpose |
|---|---|
| [`scripts/set-default-runtime.sh`](scripts/set-default-runtime.sh) | **(VM, root)** make `nvidia` the default containerd runtime on k3s - HAMi's prerequisite |
| [`scripts/install-hami.sh`](scripts/install-hami.sh) | **(laptop/VM)** install HAMi, refuse coexistence with a GPU Operator, match the scheduler image tag to the k8s version, verify `nvidia.com/gpumem` |
| [`scripts/capture-evidence.sh`](scripts/capture-evidence.sh) | run all five exercises and snapshot the evidence to a tarball |
| [`manifests/share-two-pods.yaml`](manifests/share-two-pods.yaml) | two pods, each `nvidia.com/gpu: 1` and a `nvidia.com/gpumem` slice, both on the one GPU |
| [`manifests/oversubscribe-pending.yaml`](manifests/oversubscribe-pending.yaml) | a third pod that fits an empty card but not beside the two slices → Pending on real HW |
| [`scripts/probe-memory.sh`](scripts/probe-memory.sh) | in-container checks: virtualized `nvidia-smi`, and a CUDA allocation that should fail at the slice limit |
| [`scripts/probe-mechanism.sh`](scripts/probe-mechanism.sh) | surfaces HOW the cap is enforced: HAMi-core env/library injection + device view |
| [`scripts/setup-notes.md`](scripts/setup-notes.md) | the same setup by hand, with the reasoning |

## The exercises

Run these **one at a time** from the lab directory. Do a step, read the output, **capture
it**, then move to the next - don't rush them into a single run. Save each into your
[lab notebook](../../../06-validation-reports/README.md) as the isolation evidence. Each
step builds on the pods the previous one left Running.

### Exercise 1 - Co-residency

Two pods, each asking for one GPU and an 8 GB slice, both land on the **one** physical card
- something stock Kubernetes cannot do.

```bash
kubectl apply -f manifests/share-two-pods.yaml
kubectl wait --for=condition=Ready pod/hami-share-a pod/hami-share-b --timeout=300s
kubectl get pods -o wide
```

**Expect:** both `hami-share-a` and `hami-share-b` `Running` on the same node.
📸 **Capture:** the `get pods -o wide` output.

### Exercise 2 & 3 - Virtualized view, then the memory cap

One probe shows both halves of the isolation:

```bash
./scripts/probe-memory.sh hami-share-a
```

**Expect — and here's the key idea:**

1. **The container sees a *fake* small GPU.** `nvidia-smi` inside the pod reports `~8000MiB`
   total, **not** the A6000's real `~49140MiB`. HAMi-core rewrites the card size it shows.
2. **The cap actually holds.** The allocator climbs `256 … 7680 MiB`, then:
   `cudaMalloc refused after 7680 MiB ... [HAMI-core ERROR] ... OOM`.

**Why that's the proof:** the pod hit "out of memory" at ~8 GB **while the physical card
still had ~40 GB free** - and the refusal came from `HAMI-core`, not the hardware. That
contradiction is only possible with a software cap intercepting CUDA calls. Stock Kubernetes
hands a pod the whole card; it cannot do this. *This* is what real hardware proves and the
simulation cannot.

📸 **Capture:** the in-pod `nvidia-smi` (showing the slice) and the `HAMI-core ... OOM`
refusal line. State it as "refused at the slice", not an exact byte boundary.

Repeat for the second pod when ready:

```bash
./scripts/probe-memory.sh hami-share-b
```

### Exercise 4 - Per-device budget (a third pod stays Pending)

A third pod whose slice would fit an **empty** card but **not** beside the two slices already
held. On real hardware the HAMi scheduler leaves it `Pending` with `CardInsufficientMemory` -
proving the card's memory is one shared, finite budget, accounted end to end.

> ⚠️ **Two things must be right or this "fails" by *scheduling* instead of staying Pending:**
>
> 1. **Size the request to your card.** It must be **larger than the free space beside the
>    slices** but **smaller than the whole card**. With two 8 GB slices on a 48 GB A6000,
>    free ≈ `49140 − 16000 ≈ 33 GB`, so the committed value is `45000` (> 33 GB, < 48 GB).
>    On a different card, recompute and edit
>    [`oversubscribe-pending.yaml`](manifests/oversubscribe-pending.yaml).
> 2. **The two share pods must still be Running.** They hold the slices; if they've exited,
>    the memory is free and this pod schedules. (The manifests use `sleep infinity` so they
>    don't quietly Complete mid-lab - confirm with `kubectl get pods` first.)

```bash
kubectl apply -f manifests/oversubscribe-pending.yaml
sleep 15
kubectl get pod hami-oversubscribe -o wide
kubectl describe pod hami-oversubscribe | sed -n '/Events:/,$p' | head -12
```

**Expect:** `hami-oversubscribe` `Pending`, with a `FilteringFailed` / `CardInsufficientMemory`
event (contrast Exercise 1, where the same scheduler logged `FilteringSucceed`).
📸 **Capture:** the pod status and the event line.

### Exercise 5 - The mechanism

Surface *how* the cap is enforced: the HAMi-core env/library the runtime injects to
intercept CUDA calls (software isolation, not MIG).

```bash
./scripts/probe-mechanism.sh hami-share-a
```

**Expect:** HAMi-injected env vars (e.g. `CUDA_DEVICE_MEMORY_LIMIT*`, `LD_PRELOAD`) and the
HAMi-core library inside the container.
📸 **Capture:** the env + library output.

---

Exercise 4 is the real-hardware counterpart of the simulation's per-device exhaustion test:
the sim proves the *scheduler* does the arithmetic; here the *device plugin + real card*
prove the same budget is finite and shared end to end. Exercise 5 ties to the
[CUDA_VISIBLE_DEVICES runbook](../../../../runbooks/cuda-visible-devices-debugging.md).

> 🏃 **Shortcut (only if you've done it once and want a clean re-run):**
> [`./scripts/capture-evidence.sh`](scripts/capture-evidence.sh) runs all five exercises
> back-to-back and writes a `hami-evidence-*.tgz`. The step-by-step path above is the way to
> *learn* it; this is for re-capturing quickly.

> **Out of scope (state this when presenting):** this lab does **not** measure
> compute-throttling accuracy or noisy-neighbour interference under sustained load -
> the [limitations ledger](../../../06-validation-reports/fake-vs-real-limitations.md)
> places GPU-sharing performance there. The isolation claim is the memory cap and the
> virtualized device view, not throughput fairness.

## Resource semantics

Same as the simulation lesson: `nvidia.com/gpu` is physical GPU count,
`nvidia.com/gpumem` is per-pod memory in MiB (TODO: docs phrase this as "MB"; confirm
against the installed chart), `nvidia.com/gpucores` is percent of compute. The two
share pods each request a memory slice (around 8000 MiB) so that two of them fit on the
48 GB A6000 with room to spare (use ~4000 MiB on a 24 GB card).

## What to observe, and how to state it

1. **Virtualized reporting.** `nvidia-smi` run inside a pod reports the pod's memory
   limit as the device memory, not the card's full 48 GB. That is HAMi-core rewriting
   the view the container sees.
2. **Memory cap enforcement.** A CUDA allocation that grows past the slice limit
   fails. Demonstrate the behavior; do not assert an exact byte boundary. The cap is
   enforced through CUDA interception, and the precise point at which an allocation is
   refused depends on allocator and driver behavior. The precise claim is "allocations
   beyond the slice are refused," not "it fails at exactly N bytes."

Record both observations into the repo's validation reports as evidence for the
isolation claim. Keep it separate from the simulation evidence; they back different
claims.

## Relationship to the simulation lesson

[`../hami-scheduling-sim/`](../hami-scheduling-sim/README.md) proved the scheduler
places fractional requests correctly, for free, with no GPU. This lesson proves the
runtime holds a placed pod to its slice, on one cheap real GPU. Together they cover
both halves of HAMi. Neither one covers the other's half, which is the entire point of
keeping them apart.

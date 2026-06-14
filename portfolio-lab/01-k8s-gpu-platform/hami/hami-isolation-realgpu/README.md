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

## Why a single consumer 24 GB card

HAMi's primary use case is fractioning GPUs that **cannot** be partitioned by MIG.
Datacenter cards like A100 and H100 support MIG, which gives hardware-level partitions.
Consumer cards like the RTX 4090 and RTX 3090 (both 24 GB) have no MIG, so software
sharing is the only way to put more than one tenant on the card. That makes a single
consumer 24 GB GPU the most faithful and cheapest target for demonstrating what HAMi
adds. 24 GB also comfortably holds two multi-GB slices with headroom.

## Cost

Approximate, single consumer GPU, on-demand or interruptible, as of this writing.
Rates move; check current rates before you start.

- RTX 4090: roughly 0.30 to 0.50 USD per hour on common marketplaces, with a wider
  observed range across providers and billing models.
- RTX 3090: roughly 0.15 to 0.25 USD per hour, lower on interruptible or spot.

A working session for this lesson is well under an hour of GPU time. Capture evidence,
then tear the instance down. See the verified-facts list in the change description for
the sources behind these figures.

## Provider and runtime requirements

You need a host where you control the container runtime, not a locked-down marketplace
container:

- root on the host,
- the ability to install the NVIDIA Container Toolkit and set the containerd runtime
  (HAMi-core is injected through the NVIDIA container runtime, so a fixed prebuilt
  app container you cannot reconfigure will not work),
- a single NVIDIA GPU visible to `nvidia-smi` on the host.

A bare VM or a "full machine" rental where you install your own stack works. A managed
notebook or a fixed inference container usually does not.

Consumer-card marketplaces vary in reliability: driver versions, host configuration,
and uptime are uneven. Expect to occasionally discard an instance and reprovision.

## What you build

A single-node k3s cluster on the rented host, HAMi installed with the scheduler image
tag matched to the k3s Kubernetes version, the node labelled `gpu=on`, then two pods
that each ask for one GPU and a memory slice and therefore both land on the one card.

The ordered host setup, from a fresh instance through deploying the two pods, is in
[`scripts/setup-notes.md`](scripts/setup-notes.md). It is written as notes rather than
a one-command script because the host-level steps (toolkit install, containerd
runtime, k3s install) depend on the provider image and are not safe to run blindly.

## Files

| File | Purpose |
|---|---|
| [`manifests/share-two-pods.yaml`](manifests/share-two-pods.yaml) | two pods, each `nvidia.com/gpu: 1` and a `nvidia.com/gpumem` slice, both on the one GPU |
| [`scripts/probe-memory.sh`](scripts/probe-memory.sh) | in-container checks: virtualized `nvidia-smi`, and a CUDA allocation that should fail at the slice limit |
| [`scripts/setup-notes.md`](scripts/setup-notes.md) | ordered host setup steps |

## Resource semantics

Same as the simulation lesson: `nvidia.com/gpu` is physical GPU count,
`nvidia.com/gpumem` is per-pod memory in MiB (TODO: docs phrase this as "MB"; confirm
against the installed chart), `nvidia.com/gpucores` is percent of compute. The two
share pods each request a memory slice (around 4000 MiB) so that two of them fit on a
24 GB card with room to spare.

## What to observe, and how to state it

1. **Virtualized reporting.** `nvidia-smi` run inside a pod reports the pod's memory
   limit as the device memory, not the card's full 24 GB. That is HAMi-core rewriting
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

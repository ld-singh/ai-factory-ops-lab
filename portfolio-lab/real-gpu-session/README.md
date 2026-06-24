# Lesson 6 - Real GPU (the one-rental capstone)

> Course home: [AI Factory Operations Lab](../../README.md) · Previous:
> [Lesson 5 - BCM-Style Cluster Lifecycle](../05-bcm-style-cluster-lifecycle/README.md) ·
> Next: [★ Your lab notebook](../06-validation-reports/)

## Overview

Lessons 1–5 are **all simulation** - they run on your laptop, no GPU, and prove
control-plane behaviour (scheduling, queueing, sharing *decisions*, observability design,
lifecycle). This is the **one lesson that needs real hardware**. It gathers every real-GPU
piece into a single rental so you **rent once, prove what a simulation cannot, capture
evidence, and tear down**.

You run these on one cheap card, in order. **Parts A & B are live; C & D are planned
additions coming in future updates:**

| Part | What it proves | Counterpart sim lesson | Status |
|---|---|---|---|
| **A - Runtime path + telemetry** | a CUDA pod actually executes on the GPU; real `DCGM_FI_*` metrics | Lessons 1 / 3 | ✅ validated |
| **B - HAMi sharing** | two pods share one card with an **enforced** memory cap | Lesson 1C sim | ✅ validated |
| **C - Inference** | real tokens/sec and latency under load | Lesson 4 CPU tier | 🚧 planned |
| **D - Slurm GRES** | `--gres=gpu` actually confines a job to its device | Lesson 2 fake GRES | 🚧 planned (optional) |

> ✅ **Part A is already validated** - captured on a **Hyperstack RTX A6000** (2026-06-22):
> [`real-gpu-validation-report.md`](../06-validation-reports/real-gpu-validation-report.md).
> The steps below re-stand it on a fresh VM, then carry on to Part B. Parts C & D are
> planned additions coming in future updates.

🎯 **After this lesson you can** (items 1–3 are live today; 4–5 land with Parts C & D):

1. Stand up the full GPU runtime path on one node and run a CUDA pod (driver → toolkit →
   device plugin → kubelet → scheduler → container). ✅
2. Pull *real* DCGM telemetry - the hardware counterpart of Lesson 3's synthetic stream. ✅
3. Share one physical GPU between pods with HAMi and prove the memory cap is enforced. ✅
4. Produce real inference benchmark numbers (the real tier of Lesson 4). 🚧 *planned (Part C)*
5. Enforce real `--gres=gpu` in Slurm - the hardware counterpart of Lesson 2's fake GRES.
   🚧 *planned (Part D, optional)*
6. State precisely what one real GPU proves, and what still needs scale/topology.

🧭 **Mode:** 🟥 Real GPU (one entry-level card). **Optional** - the course is complete and
defensible without it; this is where "I simulated it" becomes "I ran it on hardware."

> **This page sequences; the per-topic lessons stay the source of truth.** Each part links
> into the lesson that authored it. What this page adds is the *order*, the *rent-once*
> boundary, and the *evidence checklist*. Read the linked concepts (all free) before you
> boot the VM.

---

## What it costs, and the one iron rule

| | |
|---|---|
| **Hardware** | One entry-level NVIDIA card. **Validated on a Hyperstack RTX A6000 (48 GB)**; an L4 (24 GB) or L40/L40S works just as well. None of these support MIG - which is exactly HAMi's use case. Never an A100/H100. |
| **Time** | A focused session - roughly 1–2 hours including setup. |
| **Money** | A few dollars. Tear down the moment you're done. |

> ⚠️ **GPUs are scarce - stay flexible.** Entry GPUs sell out constantly: the exact card
> you want is often out of stock in your region, comes back minutes later, or only appears
> on another provider. Don't anchor on one model. For this course **any non-MIG card works
> the same** - RTX A6000, L4, L40/L40S, RTX A-series - so take whichever of them is
> available rather than waiting. If none are, try another region or provider. The slice
> sizes in the HAMi lab are the only thing that depends on the card (they scale with VRAM),
> and that's a one-line change.

> **The iron rule: destroy the VM the moment evidence is captured.** The evidence
> directories are the deliverable; the VM has no residual value. A forgotten GPU VM is the
> only way this course gets expensive - delete the boot/storage volume too if it's billed
> separately.

---

## Pre-flight (free, before you rent)

1. **Read the concepts** of the lessons whose real halves you'll run:
   [GPU runtime path](../01-k8s-gpu-platform/gpu-operator-real/README.md),
   [HAMi sharing](../01-k8s-gpu-platform/hami/README.md),
   [inference](../04-inference-serving/README.md), and
   [Slurm](../02-slurm-gpu-platform/README.md).
2. **Do the free simulation halves first** so you arrive knowing what hardware adds - the
   [HAMi scheduling sim](../01-k8s-gpu-platform/hami/hami-scheduling-sim/README.md) and
   [Lesson 4's $0 CPU harness tier](../04-inference-serving/README.md#the-loop-run-this).
3. **Get the scripts ready.** Everything is in [`scripts/`](./scripts/README.md) - read it
   first. The private-repo path is `scp -r scripts <user>@<vm>:~/lesson6-scripts`.
4. **Pick a "deep learning / GPU" image** with the NVIDIA driver pre-installed - it removes
   the slowest, most error-prone step.

---

## The workflow, in order

### Part 0 - Rent + set up the host (once)

The shared foundation every part builds on; do it a single time.

```bash
# 1. ON YOUR LAPTOP - copy the scripts onto the VM (private repo)
scp -r scripts <user>@<vm-ip>:~/lesson6-scripts
```

```bash
# 2. ON THE GPU VM (SSH in as a sudo user, then: sudo su -)
sudo PUBLIC_IP=<vm-ip> bash host-setup.sh            # NVIDIA toolkit + k3s + API cert
```

```bash
# 3. BACK ON YOUR LAPTOP (open TCP 6443 to the VM first)
./fetch-kubeconfig.sh <ssh-user>@<vm-ip> --key <ssh-key>   # writes ./kubeconfig-gpuvm
export KUBECONFIG=$PWD/kubeconfig-gpuvm
```

Hyperstack/Lambda/hyperscaler bare GPU VMs work; marketplace *containers* (Vast.ai/RunPod
pods) do **not** - they can't install the toolkit + k3s. Details and the by-hand fallback:
[`scripts/README.md`](./scripts/README.md).

✅ **Gate:** `nvidia-smi` works on the host, and `kubectl get nodes` is Ready.

### Part A - GPU runtime path + real telemetry  ✅ *validated*

Install the GPU layer and run a CUDA pod:

```bash
./install-gpu-operator.sh        # GPU Operator (incl. DCGM) + a CUDA smoke pod
# capture (run on the VM): writes a tarball you scp back
./capture-evidence.sh
```

📸 **Capture:** [`scripts/capture-evidence.sh`](./scripts/capture-evidence.sh) into
[`real-gpu-validation-report.md`](../06-validation-reports/real-gpu-validation-report.md).

✅ **Gate:** `nvidia-smi` from *inside* a scheduled pod, and real `DCGM_FI_*` metrics whose
values match `nvidia-smi` - the hardware counterpart of
[Lesson 3](../03-observability/README.md)'s synthetic telemetry.

### Part B - HAMi GPU sharing & isolation

Reuse the node. Install HAMi, share the one card between pods, and prove the slice is
enforced - co-residency → virtualized `nvidia-smi` → memory-cap → real-HW exhaustion → the
HAMi-core mechanism:
[HAMi isolation lab](../01-k8s-gpu-platform/hami/hami-isolation-realgpu/README.md). This is
the runtime-enforcement half the
[HAMi scheduling sim](../01-k8s-gpu-platform/hami/hami-scheduling-sim/README.md) (Lesson 1C)
deliberately cannot prove.

> ⚠️ **Run HAMi without the GPU Operator.** Part A's GPU Operator runs a device plugin that
> owns `nvidia.com/gpu`; HAMi ships its own and
> [the two must not coexist](https://project-hami.io/docs/v2.4.1/installation/prerequisites)
> (Operator+HAMi integration is [undocumented upstream](https://github.com/Project-HAMi/HAMi/issues/1708)).
> So run Part B on its **own cluster** - simplest is a **fresh GPU VM** (or this one after
> `helm uninstall gpu-operator`): `host-setup.sh`, then set nvidia as the default runtime
> and install HAMi (no `install-gpu-operator.sh`). The lab's
> [How to run it](../01-k8s-gpu-platform/hami/hami-isolation-realgpu/README.md#how-to-run-it-scripts)
> covers the fresh-VM steps, file transfer, and which directory to run from.

📸 **Capture:** the in-pod virtualized `nvidia-smi`, the allocation-refusal line, and the
Pending `CardInsufficientMemory` from the oversubscribe exercise - into the lab notebook,
**separate** from Part A (they back different claims).

### Part C - Real inference benchmark · 🚧 planned

> 🚧 **Coming in a future update.** This lab is on the roadmap, not yet built out. The plan
> below is the intended shape.

Serve a small model with vLLM and point the (already-validated) harness at it:
[Lesson 4 → real benchmark tier](../04-inference-serving/README.md#the-loop-run-this).

📸 **Capture:** the concurrency-sweep table (tokens/sec climbing while ttft_p95 / e2e_p99
degrade) into
[`inference-benchmark-report.md`](../06-validation-reports/inference-benchmark-report.md).
Optional high-value tie-in to Part B: two replicas sharing one card via HAMi slices vs one
dedicated replica - measuring what sharing costs in p99.

### Part D - Slurm real GRES (enforcement on hardware) · 🚧 planned (optional)

> 🚧 **Coming in a future update (optional).** The fake-GRES [Slurm lesson](../02-slurm-gpu-platform/README.md)
> (Lesson 2) already validates the *scheduling* half. This real `--gres=gpu` **enforcement**
> half - a job confined to its allocated device via cgroups - is an optional real-hardware
> add-on planned for a later update. The run-ready guide is
> [here](../02-slurm-gpu-platform/slurm-realgpu/README.md) for when it lands.

📸 **Capture:** `nvidia-smi` and `CUDA_VISIBLE_DEVICES` from *inside* the job step (it sees
only its allocated GPU), plus the `gres.conf` / `slurm.conf` you used - into the
[Slurm GRES report](../06-validation-reports/slurm-gres-validation.md) (its real-enforcement
section, kept separate from the fake-GRES scheduling evidence).

### Part E - Tear down

Confirm your evidence tarballs are on your laptop, then **destroy the VM and its storage**.

---

## Evidence checklist (what "done" looks like)

After teardown these reports should hold **real captured output**, flipping their status
from "pending hardware run" to Complete:

- [x] [`real-gpu-validation-report.md`](../06-validation-reports/real-gpu-validation-report.md) - runtime path + DCGM (Part A) — **done, RTX A6000, 2026-06-22**
- [x] [`hami-isolation-validation.md`](../06-validation-reports/hami-isolation-validation.md) - co-residency, virtualized `nvidia-smi`, allocation refusal, real-HW exhaustion, mechanism (Part B) — **done, RTX A6000, 2026-06-23**
- 🚧 [`inference-benchmark-report.md`](../06-validation-reports/inference-benchmark-report.md) - the concurrency sweep (Part C — **planned, coming in a future update**)
- 🚧 [`slurm-gres-validation.md`](../06-validation-reports/slurm-gres-validation.md) - the real `--gres=gpu` enforcement section (Part D — **planned future update, optional**)

🔬 **What this session proves - and does not.** Today (Parts A & B) it proves the real,
single-node runtime path: execution, real telemetry, and enforced GPU sharing. Real
benchmarks (Part C) and enforced Slurm GRES (Part D) are planned additions, not yet
delivered. Even complete, it does **not** prove NCCL/NVLink/MIG/GPUDirect-RDMA, multi-node
scale, or sharing-performance under sustained load. Full ledger:
[`fake-vs-real-limitations.md`](../06-validation-reports/fake-vs-real-limitations.md).

➡️ **Next:** [★ Your lab notebook](../06-validation-reports/) - confirm every lesson you
ran, sim or real, has its captured evidence. That's what makes a lesson "done."

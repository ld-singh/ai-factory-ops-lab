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

> 📖 **This page is an overview, not the labs themselves.** It gives you the *order*, the
> *rent-once boundary*, and the *evidence checklist*. Every part below links to its own lab
> page, and **that page is the source of truth** for the actual commands. Read this to plan
> the session; follow the linked labs to run it.

You run these on one cheap card, in order. Each part is a full lab page of its own:

| Part | The lab | What it proves | Counterpart sim lesson | Status |
|---|---|---|---|---|
| **A** | [Runtime path + telemetry](../01-k8s-gpu-platform/gpu-operator-real/README.md) | a CUDA pod actually executes on the GPU; real `DCGM_FI_*` metrics | Lessons 1 / 3 | ✅ validated |
| **B** | [HAMi sharing + isolation](../01-k8s-gpu-platform/hami/hami-isolation-realgpu/README.md) | two pods share one card with an **enforced** memory cap | Lesson 1C sim | ✅ validated |
| **C** | [HAMi + GPU Operator coexistence](../01-k8s-gpu-platform/hami/hami-gpu-operator-coexistence/README.md) | the Operator and HAMi on one node without fighting over `nvidia.com/gpu` | Lesson 1C concepts | 🟡 run-ready |
| **D** | [Inference benchmark](../04-inference-serving/inference-realgpu/README.md) | real tokens/sec and latency under load | Lesson 4 CPU tier | ✅ validated |
| **E** | [Slurm real GRES](../02-slurm-gpu-platform/slurm-realgpu/README.md) | `--gres=gpu` actually confines a job to its device | Lesson 2 fake GRES | 🚧 planned (optional) |

> **Pick your track.** Parts A and D share one cluster (both want the GPU Operator's device
> plugin). Part B needs HAMi *without* the Operator, and Part C is where the two run
> *together*. Read [Which parts share a cluster](#which-parts-share-a-cluster) below before
> you rent, so you know how many VMs you need.

🎯 **After this lesson you can:**

1. Stand up the full GPU runtime path on one node and run a CUDA pod (driver → toolkit →
   device plugin → kubelet → scheduler → container). ✅
2. Pull *real* DCGM telemetry - the hardware counterpart of Lesson 3's synthetic stream. ✅
3. Share one physical GPU between pods with HAMi and prove the memory cap is enforced. ✅
4. Run HAMi alongside the NVIDIA GPU Operator on one node, the way most real clusters are
   built. 🟡 *run-ready (Part C)*
5. Produce real inference benchmark numbers - serve a model with vLLM and run the Lesson 4
   drills against it. ✅ *validated (Part D)*
6. Enforce real `--gres=gpu` in Slurm - the hardware counterpart of Lesson 2's fake GRES.
   🚧 *planned (Part E, optional)*
7. State precisely what one real GPU proves, and what still needs scale/topology.

🧭 **Mode:** 🟥 Real GPU (one entry-level card). **Optional** - the course is complete and
defensible without it; this is where "I simulated it" becomes "I ran it on hardware."

> **The per-topic lessons stay the source of truth.** Each part links into the lesson that
> authored it, and that lesson holds the real commands. Read the linked concepts (all free)
> before you boot the VM.

---

## What it costs, and the one iron rule

| | |
|---|---|
| **Hardware** | One entry-level NVIDIA card - an **RTX A6000 (48 GB)**, **L4 (24 GB)**, or **L40/L40S** all work. None of these support MIG - which is exactly HAMi's use case. Never an A100/H100. |
| **Time** | A focused session - roughly 1–2 hours including setup. |
| **Money** | About $5-10 for the session. Tear down the moment you're done. |

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
   [Lesson 4's $0 CPU harness tier](../04-inference-serving/README.md#the-learning-path-run-these-in-order).
3. **Get the lab onto the VM.** On the VM:
   `git clone https://github.com/ld-singh/ai-factory-ops-lab.git && cd ai-factory-ops-lab`,
   then run from the repo root. Setup scripts are in [`scripts/`](./scripts/README.md).
4. **Pick a "deep learning / GPU" image** with the NVIDIA driver pre-installed - it removes
   the slowest, most error-prone step.

---

## Which parts share a cluster

Only one device plugin can own `nvidia.com/gpu` on a node, and that single fact decides how
many VMs you rent. Three of the parts want a different answer to "who owns it":

| Parts | Who owns `nvidia.com/gpu` | Cluster |
|---|---|---|
| **A + D** (runtime path, inference) | the GPU Operator's device plugin | one cluster, shared |
| **B** (HAMi isolation) | HAMi's device plugin, no Operator | its own cluster |
| **C** (coexistence) | HAMi's device plugin, Operator's disabled | its own cluster |

In practice: **A and D on one VM** back to back, then **B or C on a second VM** (or the same
VM rebuilt after `helm uninstall gpu-operator`). Doing all of it means either two short
rentals or one rental with a rebuild in the middle. Both are within the $5-10 budget.

## The workflow, in order

### Part 0 - Rent + set up the host (once)

The shared foundation every part builds on; do it a single time.

```bash
# 1. ON THE GPU VM - clone the repo
git clone https://github.com/ld-singh/ai-factory-ops-lab.git
cd ai-factory-ops-lab
```

```bash
# 2. ON THE GPU VM - set up the host (run from the repo root, as a sudo user)
sudo PUBLIC_IP=<vm-ip> bash portfolio-lab/real-gpu-session/scripts/host-setup.sh   # NVIDIA toolkit + k3s + API cert
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

Run the rest of Lesson 6 from this repo root on the VM. (Prefer to drive `kubectl` from your
laptop? Open TCP 6443 and use `portfolio-lab/real-gpu-session/scripts/fetch-kubeconfig.sh
<user>@<vm-ip> --key <key>`, then `export KUBECONFIG=$PWD/kubeconfig-gpuvm` - but running on the
VM avoids a flaky laptop↔API link.)

Hyperstack/Lambda/hyperscaler bare GPU VMs work; marketplace *containers* (Vast.ai/RunPod
pods) do **not** - they can't install the toolkit + k3s. Details and the by-hand fallback:
[`scripts/README.md`](./scripts/README.md).

✅ **Gate:** `nvidia-smi` works on the host, and `kubectl get nodes` is Ready.

### Part A - GPU runtime path + real telemetry  ✅ *validated*

Install the GPU layer and run a CUDA pod:

```bash
# from the repo root on the VM:
portfolio-lab/real-gpu-session/scripts/install-gpu-operator.sh   # GPU Operator (incl. DCGM) + a CUDA smoke pod
portfolio-lab/real-gpu-session/scripts/capture-evidence.sh       # writes a tarball you scp back to your laptop
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

> ⚠️ **Part B runs HAMi without the GPU Operator.** Part A's GPU Operator ships a device
> plugin that owns `nvidia.com/gpu`, and HAMi ships its own. Two device plugins advertising
> the same resource on one node conflict, so Part B does **not** reuse Part A's cluster. Run
> it on a **fresh GPU VM** (or this one after `helm uninstall gpu-operator`): `host-setup.sh`,
> set nvidia as the default runtime, then install HAMi (no `install-gpu-operator.sh`). The
> lab's [How to run it](../01-k8s-gpu-platform/hami/hami-isolation-realgpu/README.md#how-to-run-it-scripts)
> covers the fresh-VM steps and which directory to run from.
>
> Want them on the **same** node? That is exactly what
> [Part C](../01-k8s-gpu-platform/hami/hami-gpu-operator-coexistence/README.md) covers.

📸 **Capture:** the in-pod virtualized `nvidia-smi`, the allocation-refusal line, and the
Pending `CardInsufficientMemory` from the oversubscribe exercise - into the lab notebook,
**separate** from Part A (they back different claims).

### Part C - HAMi + GPU Operator coexistence · 🟡 run-ready

Part B keeps HAMi and the Operator apart. Most production clusters cannot: the Operator is how
the driver, toolkit, and runtime get installed and managed. This part runs both on one node,
with the Operator owning the base stack and HAMi owning the device plugin.

Full lab (the Helm values, the component-by-component behaviour, and the reboot gotcha):
[**Part C - HAMi + GPU Operator coexistence**](../01-k8s-gpu-platform/hami/hami-gpu-operator-coexistence/README.md).

📸 **Capture:** `bash portfolio-lab/01-k8s-gpu-platform/hami/hami-gpu-operator-coexistence/scripts/capture-evidence.sh`
snapshots all six artifacts (the Operator's absent device plugin, HAMi's virtual `nvidia.com/gpu`
count, the default runtime, a fractional pod with the slice enforced, and DCGM still on physical
counters) into a tarball. Record them in
[`hami-gpu-operator-coexistence-validation.md`](../06-validation-reports/hami-gpu-operator-coexistence-validation.md) -
that filled report is what flips this from run-ready to validated.

### Part D - Real inference benchmark · ✅ validated

Serve a model with vLLM on the GPU (as a k3s pod - no Docker needed), then run the same drills
you practised for free in Lesson 4 - now with real numbers. On the VM:

```bash
make phase5-serve-gpu                                          # deploy vLLM as a k3s pod
kubectl -n inference port-forward svc/vllm 8000:8000           # one terminal: expose :8000
MODEL=local ENDPOINT=http://localhost:8000 make phase5-bench   # another terminal: the drills
```

Full lab (URL details, laptop vs VM, model choice, evidence):
[**Part D - Real inference benchmark**](../04-inference-serving/inference-realgpu/README.md).

📸 **Capture:** the concurrency-sweep table (tokens/sec climbing while ttft_p95 / e2e_p99
degrade) into
[`inference-benchmark-report.md`](../06-validation-reports/inference-benchmark-report.md) -
that captured output is what flips this from runnable to **validated**. Optional high-value
tie-in to Part B: two replicas sharing one card via HAMi slices vs one dedicated replica -
measuring what sharing costs in p99.

### Part E - Slurm real GRES (enforcement on hardware) · 🚧 planned (optional)

> 🚧 **Coming in a future update (optional).** The fake-GRES [Slurm lesson](../02-slurm-gpu-platform/README.md)
> (Lesson 2) already validates the *scheduling* half. This real `--gres=gpu` **enforcement**
> half - a job confined to its allocated device via cgroups - is an optional real-hardware
> add-on planned for a later update. The run-ready guide is
> [here](../02-slurm-gpu-platform/slurm-realgpu/README.md) for when it lands.

📸 **Capture:** `nvidia-smi` and `CUDA_VISIBLE_DEVICES` from *inside* the job step (it sees
only its allocated GPU), plus the `gres.conf` / `slurm.conf` you used - into the
[Slurm GRES report](../06-validation-reports/slurm-gres-validation.md) (its real-enforcement
section, kept separate from the fake-GRES scheduling evidence).

### Part F - Tear down

Confirm your evidence tarballs are on your laptop, then **destroy the VM and its storage**.

---

## Evidence checklist (what "done" looks like)

After teardown these reports should hold **real captured output**, flipping their status
from "pending hardware run" to Complete:

- [x] [`real-gpu-validation-report.md`](../06-validation-reports/real-gpu-validation-report.md) - runtime path + DCGM (Part A)
- [x] [`hami-isolation-validation.md`](../06-validation-reports/hami-isolation-validation.md) - co-residency, virtualized `nvidia-smi`, allocation refusal, real-HW exhaustion, mechanism (Part B)
- 🟡 [`hami-gpu-operator-coexistence-validation.md`](../06-validation-reports/hami-gpu-operator-coexistence-validation.md) - the Operator and HAMi side by side on one node, fractional pod still enforced (Part C - **run-ready, awaiting a hardware run**)
- [x] [`inference-benchmark-report.md`](../06-validation-reports/inference-benchmark-report.md) - the concurrency sweep + saturation knee (Part D)
- 🚧 [`slurm-gres-validation.md`](../06-validation-reports/slurm-gres-validation.md) - the real `--gres=gpu` enforcement section (Part E - **planned future update, optional**)

🔬 **What this session covers.** Parts A, B, and D give you the real single-node serving
path: a CUDA pod executing, real DCGM telemetry, enforced GPU sharing, and real inference
benchmarks - all three validated with captured output. Part C (HAMi + GPU Operator
coexistence) is run-ready and awaiting a hardware run. Part E - enforced Slurm GRES - is a
planned optional add-on.
None of this covers NCCL/NVLink/MIG/GPUDirect-RDMA, multi-node scale, or sharing-performance
under sustained load. Full ledger:
[`fake-vs-real-limitations.md`](../06-validation-reports/fake-vs-real-limitations.md).

➡️ **Next:** [★ Your lab notebook](../06-validation-reports/) - confirm every lesson you
ran, sim or real, has its captured evidence. That's what makes a lesson "done."

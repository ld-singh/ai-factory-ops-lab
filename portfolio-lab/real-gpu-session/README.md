# Lesson 6 - Real GPU (the one-rental capstone)

> Course home: [AI Factory Operations Lab](../../README.md) · Previous:
> [Lesson 5 - BCM-Style Cluster Lifecycle](../05-bcm-style-cluster-lifecycle/README.md) ·
> Next: [★ Your lab notebook](../06-validation-reports/)

Lessons 1–5 are **all simulation** - they run on your laptop, no GPU, and prove
control-plane behaviour (scheduling, queueing, sharing *decisions*, observability
design, lifecycle). This final lesson is the **only one that needs real hardware**, and
it gathers *every* real-GPU piece into one rental session so you rent once, prove the
things a simulation cannot, capture evidence, and tear down.

🎯 **Learning objectives** - after this lesson you can:

1. Stand up the full GPU runtime path on one node and run a CUDA pod (driver → toolkit
   → device plugin → kubelet → scheduler → container).
2. Pull *real* DCGM telemetry - the hardware counterpart of Lesson 3's synthetic stream.
3. Share one physical GPU between pods with HAMi and prove the memory cap is enforced.
4. Enforce real `--gres=gpu` in Slurm - the hardware counterpart of Lesson 2's fake GRES.
5. Produce real inference benchmark numbers (the real tier of Lesson 4).
6. State precisely what one real GPU proves and what still needs scale/topology.

🧭 **Mode:** 🟥 Real GPU (one entry-level card). **Optional** - the whole course is
complete and defensible without it; this lesson is where you turn "I simulated it" into
"I ran it on hardware."

> **This lesson sequences; the per-topic lessons stay the source of truth.** Each phase
> links into the lesson that authored it (the GPU runtime path, HAMi, Slurm, inference).
> What this page adds is the *order*, the *set-up-once* boundary, and the *evidence
> checklist* - the things only obvious when you do them together. Read the linked
> lessons' concepts (all free) before you boot the VM.

---

## What it costs, and the one iron rule

| | |
|---|---|
| **Hardware** | One entry-level NVIDIA GPU (T4 / L4 / A10G-class, or an RTX-class marketplace card). Never an A100/H100. |
| **Time** | A focused session - roughly 1–2 hours including setup. |
| **Money** | A few dollars. See [the renting guide](../01-k8s-gpu-platform/gpu-operator-real/README.md#renting-the-gpu-cheaply) for the spot/preemptible tactics. |

> **The iron rule: tear the VM down the moment evidence is captured.** The evidence
> directories are the deliverable; the VM has no residual value. A forgotten GPU VM is
> the only way this course gets expensive - delete the boot/storage volume too if your
> provider bills it separately.

---

## Pre-flight (do this before you rent, for free)

1. **Read the concepts of the lessons whose real halves you'll run here:** the
   [GPU runtime path](../01-k8s-gpu-platform/gpu-operator-real/README.md),
   [HAMi sharing](../01-k8s-gpu-platform/hami/README.md),
   [Slurm](../02-slurm-gpu-platform/README.md), and
   [inference](../04-inference-serving/README.md).
2. **Do the free simulation halves first** so you arrive knowing what hardware adds:
   the [HAMi scheduling sim](../01-k8s-gpu-platform/hami/hami-scheduling-sim/README.md),
   the [Slurm fake-GRES lesson](../02-slurm-gpu-platform/README.md), and
   [Lesson 4's $0 CPU harness tier](../04-inference-serving/README.md#the-loop-run-this).
3. **Have the evidence collectors ready:** [`scripts/collect-gpu-evidence.sh`](../../scripts/collect-gpu-evidence.sh)
   and the inference harness in [`04-inference-serving/`](../04-inference-serving/README.md).
4. **Prefer a "deep learning / GPU" image** with the NVIDIA driver pre-installed - it
   removes the slowest, most error-prone setup step.

---

## The session, in order

### Phase 0 - Rent + set up the host (once)

The shared foundation every phase builds on; do it a single time.

> 🚀 **Scripted path (any bare GPU VM with root - Hyperstack, Lambda, hyperscaler):** the
> [`scripts/`](./scripts/README.md) directory automates this - `host-setup.sh` on the
> VM (toolkit + k3s), then `fetch-kubeconfig.sh` on your laptop so you drive the cluster
> from local. (Not for marketplace *containers* like Vast.ai/RunPod pods.) Read
> [`scripts/README.md`](./scripts/README.md) first.

If you prefer to do it by hand (or aren't on apt):

- Boot the GPU VM and confirm the card: [runtime-path Step 1 (driver)](../01-k8s-gpu-platform/gpu-operator-real/README.md#step-1---driver-validation).
- Install the container toolkit and a single-node Kubernetes: [Steps 2–3](../01-k8s-gpu-platform/gpu-operator-real/README.md#step-2---nvidia-container-toolkit-validation).

✅ **Gate:** `nvidia-smi` works on the host, a `--gpus all` container sees the GPU, and
`kubectl get nodes` is Ready. Don't proceed until all three pass.

### Phase A - GPU runtime path + real telemetry

Install the GPU layer and run a CUDA pod. Scripted:
[`scripts/install-gpu-operator.sh`](./scripts/install-gpu-operator.sh) (GPU Operator
with DCGM, plus a CUDA smoke test); or follow
[Lesson 6 Part A - the runtime path](../01-k8s-gpu-platform/gpu-operator-real/README.md#step-4---nvidia-gpu-operator)
by hand.

📸 **Capture:** run [`scripts/collect-gpu-evidence.sh`](../../scripts/collect-gpu-evidence.sh)
and record versions into
[`real-gpu-validation-report.md`](../06-validation-reports/real-gpu-validation-report.md).

✅ **Gate:** `nvidia-smi` from inside a scheduled pod, and real `DCGM_FI_*` metrics - the
single most important artifacts in the course, and the hardware counterpart of
[Lesson 3](../03-observability/README.md)'s synthetic telemetry.

### Phase B - HAMi GPU sharing & isolation

Reuse the node. Install HAMi, share the one card between pods, prove the slice is
enforced: [HAMi isolation lab](../01-k8s-gpu-platform/hami/hami-isolation-realgpu/README.md)
(co-residency → virtualized `nvidia-smi` → memory-cap → real-HW per-device exhaustion →
the HAMi-core mechanism). This is the runtime-enforcement half that the
[HAMi scheduling sim](../01-k8s-gpu-platform/hami/hami-scheduling-sim/README.md) (Lesson 1C)
deliberately cannot prove.

> ⚠️ **Device-plugin coexistence:** HAMi wraps the device-plugin role. Decide up front
> whether to run it alongside or instead of the GPU Operator's plugin - two plugins
> claiming `nvidia.com/gpu` is a classic self-inflicted outage.

📸 **Capture:** the in-pod `nvidia-smi`, the allocation-failure line, and the Pending
`CardInsufficientMemory` from the oversubscribe exercise - into the lab notebook,
**separate** from the Phase A evidence (they back different claims).

### Phase C - Slurm real GRES (enforcement on hardware)

The fake-GRES [Slurm lesson](../02-slurm-gpu-platform/README.md) (Lesson 2) proved the
*scheduling* decision; this proves real `--gres=gpu` **enforcement** - that a job is
actually confined to its allocated devices via cgroups. Run it on the same GPU host:
[Slurm real-GRES guide](../02-slurm-gpu-platform/slurm-realgpu/README.md).

📸 **Capture:** `nvidia-smi` and `CUDA_VISIBLE_DEVICES` from *inside* the job step
showing it sees only its allocated GPU, plus the `gres.conf`/`slurm.conf` you used -
into the [Slurm GRES report](../06-validation-reports/slurm-gres-validation.md) (its
real-enforcement section, kept separate from the fake-GRES scheduling evidence).

### Phase D - Real inference benchmark

Serve a small model with vLLM and point the (already-validated) harness at it:
[Lesson 4 → real benchmark tier](../04-inference-serving/README.md#the-loop-run-this).

📸 **Capture:** the concurrency-sweep table (tokens/sec climbing while ttft_p95 /
e2e_p99 degrade) into
[`inference-benchmark-report.md`](../06-validation-reports/inference-benchmark-report.md).
Optional high-value tie-in: two replicas sharing one GPU via HAMi slices vs one
dedicated replica - measuring what sharing costs in p99.

### Phase E - Tear down

Destroy the VM and its storage. Confirm your evidence is on your local machine first.

---

## Evidence checklist (what "done" looks like)

After teardown these reports should hold **real captured output**, flipping their
status from "pending hardware run" to Complete:

- [ ] [`real-gpu-validation-report.md`](../06-validation-reports/real-gpu-validation-report.md) - GPU runtime path + DCGM (Phase A)
- [ ] HAMi isolation evidence in the [lab notebook](../06-validation-reports/README.md) - co-residency, virtualized `nvidia-smi`, allocation refusal, real-HW exhaustion (Phase B)
- [ ] [`slurm-gres-validation.md`](../06-validation-reports/slurm-gres-validation.md) - the real `--gres=gpu` enforcement section (Phase C)
- [ ] [`inference-benchmark-report.md`](../06-validation-reports/inference-benchmark-report.md) - the concurrency sweep (Phase D)

🔬 **What this session proves - and does not.** It proves the real, single-node runtime
path: execution, enforced GPU sharing, enforced Slurm GRES, real telemetry, and real
benchmarks. It does **not** prove NCCL/NVLink/MIG/GPUDirect-RDMA, multi-node scale, or
sharing-performance under sustained load. The full ledger is
[`fake-vs-real-limitations.md`](../06-validation-reports/fake-vs-real-limitations.md).

➡️ **Next:** [★ Your lab notebook](../06-validation-reports/) - confirm every lesson you
ran, sim or real, has its captured evidence. That's what makes a lesson "done."

# Real inference benchmark on a real GPU (Lesson 6, Part C)

> Part of [Lesson 6 - Real GPU](../../real-gpu-session/README.md) · The simulation
> counterpart is [Lesson 4 - Inference Serving](../README.md) · Course home:
> [AI Factory Operations Lab](../../../README.md)

> 🟡 **STATUS: RUNNABLE.** You learned the method for free in [Lesson 4](../README.md) -
> serving SLOs, the prefill/decode split, the goodput cliff, capacity planning. Here you run
> the **same drills** against a model served on a real GPU, so the numbers are real. Capture
> them into [`inference-benchmark-report.md`](../../06-validation-reports/inference-benchmark-report.md).

## What this adds over the sim lesson

[Lesson 4](../README.md) teaches you to *read* an inference server - on CPU, where the
**shape** of every curve is the same as on a GPU. What CPU can't give you is throughput
*numbers* for a specific card: how many tokens/sec an L4 or A6000 actually serves, and where
*that* card saturates. That's this part.

| Claim | Where it's shown |
|---|---|
| How to read serving SLOs; prefill vs decode; the goodput cliff; capacity math | ✅ [Lesson 4](../README.md) - on CPU, free |
| Real tokens/sec, real latency, and the saturation knee **for an actual GPU** | 🟥 Here - vLLM on one rented card |

Single GPU by design, like the rest of Lesson 6 - so it does not cover multi-replica routing,
multi-node scale, or NVLink/topology effects.

## Setup (do this first, on the GPU VM)

**Run everything in this lab ON the GPU VM** (over SSH), not from your laptop - vLLM runs on
the VM and the harness talks to it locally, so there's no flaky laptop↔VM link and no ports to
open. First, get the lab onto the VM and `cd` into it - **run every command below from this
repo root**:

```bash
# on the GPU VM:
git clone https://github.com/ld-singh/ai-factory-ops-lab.git
cd ai-factory-ops-lab
```

Part C needs a k3s cluster with the `nvidia.com/gpu` device plugin - which is **exactly the
Part A setup**. So the simplest path is to do Part C on the **same VM as Part A**: the GPU
runtime is already there and the whole card is free, so you can skip straight to Step 1.

Starting on a fresh VM? Run the two Part A setup steps first (from the repo root):

```bash
# 1. base host - installs k3s (containerd) + the NVIDIA Container Toolkit  (NOT Docker)
sudo PUBLIC_IP=<vm-ip> bash portfolio-lab/real-gpu-session/scripts/host-setup.sh

# 2. GPU Operator (Part A) - adds the nvidia.com/gpu device plugin + the nvidia runtime
portfolio-lab/real-gpu-session/scripts/install-gpu-operator.sh
```

That's it - now you have a GPU-ready k3s cluster. For the full walkthrough of these two
steps (what each proves, the gates, troubleshooting), see the real labs they come from:
[setup scripts](../../real-gpu-session/scripts/README.md) for `host-setup.sh`, and
[Part A - GPU runtime path](../../01-k8s-gpu-platform/gpu-operator-real/README.md) for
`install-gpu-operator.sh`.

> **No Docker needed.** host-setup.sh installs k3s, and vLLM runs as a **k3s pod** (not a
> `docker run`). The harness ([`../harness/`](../harness/)) needs only `python3` (stdlib, no
> pip install).

## Step 1 - Deploy vLLM on the cluster

On the VM:

```bash
make phase5-serve-gpu
```

This runs [`../scripts/serve-gpu.sh`](../scripts/serve-gpu.sh), which deploys vLLM as a pod
(image `vllm/vllm-openai:latest`, `runtimeClassName: nvidia`, requesting `nvidia.com/gpu: 1`)
serving `Qwen/Qwen2.5-0.5B-Instruct` by default - swap to a 7B on a 24 GB+ card with
`MODEL=Qwen/Qwen2.5-7B-Instruct make phase5-serve-gpu`. It waits for the pod to pull the image
and load the model (a few minutes the first time), then prints the next two commands.

✅ **Gate:** `kubectl -n inference get pods` shows the `vllm` pod `Running` and `1/1` ready.

## Step 2 - Open a port-forward → that's your URL

vLLM listens on port 8000 inside the cluster. Forward it to the VM's localhost - run this in
**one terminal on the VM** and leave it open:

```bash
kubectl -n inference port-forward svc/vllm 8000:8000
```

Your endpoint is now **`http://localhost:8000`** (the model is served under the name `local`).

## Step 3 - Run the same drills, now with real numbers

In a **second terminal on the VM** (the port-forward keeps running in the first):

```bash
MODEL=local ENDPOINT=http://localhost:8000 make phase5-bench       # concurrency sweep
MODEL=local ENDPOINT=http://localhost:8000 make phase5-overload    # find the knee
```

Any Lesson 4 drill works the same way (`phase5-batching`, `phase5-prefill`, `phase5-decode`).
The harness is identical to the CPU tier - it doesn't care whether a CPU or a GPU is behind the
endpoint - so the only thing that changed is that the numbers now mean something for this card.

✅ **Gate:** the concurrency sweep shows `tok/s` climbing while `ttft_p95` / `e2e_p99` degrade,
and `goodput%` holding until the knee - the same shape you saw on CPU, at real GPU speeds.

## Step 4 - Capture evidence, then tear down

Record the sweep and the saturation point into
[`inference-benchmark-report.md`](../../06-validation-reports/inference-benchmark-report.md) -
that captured output is what flips this from runnable to **validated**. Then remove the server
(and destroy the VM when you're done with Lesson 6):

```bash
kubectl delete namespace inference     # stop and remove vLLM
```

## Optional - the GPU-sharing tie-in

High-value extension to [Part B](../../01-k8s-gpu-platform/hami/hami-isolation-realgpu/README.md):
serve two model replicas sharing one card via HAMi slices, versus one dedicated replica, and
measure what sharing costs in p99. That connects the sharing *mechanism* you proved in Part B
to its serving *cost* - the question a platform team actually has to answer.

➡️ **Next:** [★ Your lab notebook](../../06-validation-reports/) - record the numbers.

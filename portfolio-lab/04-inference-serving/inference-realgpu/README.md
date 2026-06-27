# Real inference benchmark on a real GPU (Lesson 6, Part C)

> Part of [Lesson 6 - Real GPU](../../real-gpu-session/README.md) · The simulation
> counterpart is [Lesson 4 - Inference Serving](../README.md) · Course home:
> [AI Factory Operations Lab](../../../README.md)

> ✅ **STATUS: VALIDATED** on a real RTX A6000 - see
> [`inference-benchmark-report.md`](../../06-validation-reports/inference-benchmark-report.md)
> for the captured run. You learned the method for free in [Lesson 4](../README.md) -
> serving SLOs, the prefill/decode split, the goodput cliff, capacity planning. Here you run
> the **same drills** against a model served on a real GPU, so the numbers are real. Capture
> them into [`inference-benchmark-report.md`](../../06-validation-reports/inference-benchmark-report.md).

## Same drills, real hardware - and why that's the deeper lesson

This is **not a new lesson** - it's the *same* drills from [Lesson 4](../README.md), pointed at
a real GPU. The concepts are identical: the SLOs, the prefill/decode split, batching contention,
the saturation knee, the capacity math. You learned to *read* an inference server for free; here
you read the same things on a real card - and that's where they become true instead of
illustrative.

What a real GPU reveals that CPU can only approximate:

| Concept (the same on both) | The free CPU tier showed you... | The real GPU reveals... |
|---|---|---|
| **Continuous batching** | the *contention* it exists to fix (an interactive request stalls behind long ones) | the fix **working** - TTFT stays flat under heavy load while the running batch absorbs it |
| **The saturation knee** | a crude, early cliff (CPU has little parallelism, so TTFT spikes fast) | the real shape - `tok/s` plateaus and `e2e` climbs while TTFT holds; gate goodput on `e2e` to catch it |
| **Throughput / latency** | shape only (the numbers are meaningless on CPU) | real tokens/sec and latency for *this* card - what you provision and budget against |
| **Right-sizing** | (can't show it) | that a big GPU is **wasted** on a tiny model - the cost lever that actually matters |

So the real-GPU run isn't a different syllabus - it's the same one, where continuous batching,
the throughput ceiling, and model↔GPU fit stop being words and start being numbers. That's the
"greater" part, and it's worth the few dollars.

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
serving **`Qwen/Qwen2.5-7B-Instruct`** by default - a real-sized model that actually exercises
the card. It waits for the pod to pull the image and load the model (a few minutes the first
time), then prints the next two commands.

> 🧪 **Serve any model you like - testing variants is part of the learning.** `MODEL=` takes any
> Hugging Face model id that fits your VRAM. The easy set to compare is the ungated **Qwen2.5**
> family - `Qwen/Qwen2.5-0.5B-Instruct`, `-1.5B-`, `-3B-`, `-7B-`, `-14B-Instruct` - so you can
> watch tok/s, latency, and GPU memory change with model size on the *same* card:
> ```bash
> MODEL=Qwen/Qwen2.5-14B-Instruct make phase5-serve-gpu     # bigger: lower tok/s, more VRAM
> ```
> Other families (Llama, Mistral) work too if you have access to them on Hugging Face (set
> `HF_TOKEN` for gated models). Rule of thumb: a ~7B in fp16 needs ~15 GB; a 14B ~28 GB.

> 🔁 **Switching models?** A model is already deployed - remove it first so the new one loads
> cleanly: `kubectl delete namespace inference` then re-run `make phase5-serve-gpu`.

✅ **Gate:** `kubectl -n inference get pods` shows the `vllm` pod `Running` and `1/1` ready.

## Step 2 - Open a port-forward → that's your URL

vLLM listens on port 8000 inside the cluster. Forward it to the VM's localhost - run this in
**one terminal on the VM** and leave it open:

```bash
kubectl -n inference port-forward svc/vllm 8000:8000
```

Your endpoint is now **`http://localhost:8000`** (the model is served under the name `local`).

## Step 3 - Run the drills (with real example output)

In a **second terminal on the VM** (the port-forward keeps running in the first). Each drill is
one command. The harness is the same one you used on CPU - only the hardware behind the endpoint
changed.

> 📊 **The outputs below are example runs** (one RTX A6000 (48 GB) serving Qwen2.5-7B-Instruct),
> shown so you have a reference for the *shape* and what "right" looks like. **Your numbers will
> be different** - they depend on the card, the model, the vLLM version, and even run-to-run
> variation. Read the *trend* (what rises, what flattens, where it cliffs), not the exact values.

> ⚠️ **`REQUESTS_PER_LEVEL` must be ≥ your highest concurrency.** Each level fires that many
> requests; if it's smaller than the concurrency the pool never fills, so you're secretly testing
> a *lower* concurrency and the rows look flat. Match it to your top concurrency - and skip tiny
> levels, since thousands of requests at conc8 take minutes to drain.

### a) Baseline sweep

```bash
MODEL=local ENDPOINT=http://localhost:8000 make phase5-bench
```
```
 conc  reqs  err  gen  ttft_p50  ttft_p95  tpot_p50  e2e_p95  e2e_p99   tok/s  goodput%
    1    12    0   53     0.047     1.121    0.0219    2.261    2.640    42.3    100.0
    2    12    0   51     0.067     0.068    0.0220    1.378    1.423    84.0    100.0
    4    12    0   51     0.067     0.068    0.0221    1.316    1.335   153.1    100.0
    8    12    0   51     0.171     0.177    0.0223    1.357    1.381   240.4    100.0
```
`tok/s` climbs cleanly (42 → 240) with goodput pinned at 100% - the card has plenty of headroom
at this load. (The conc-1 `ttft_p95` blip is first-request warmup; ignore it.)

### b) Find the knee - push past saturation (the headline)

```bash
MODEL=local ENDPOINT=http://localhost:8000 \
  CONCURRENCY=64,128,256,512 REQUESTS_PER_LEVEL=512 make phase5-bench
```
```
 conc  reqs  err  gen  ttft_p50  ttft_p95  tpot_p50  e2e_p95  e2e_p99    tok/s  goodput%
   64   512    0   51     0.087     0.163    0.0275    1.678    1.792   2127.6    100.0
  128   512    0   52     0.126     0.325    0.0360    2.291    2.421   3138.1    100.0
  256   512    0   52     0.299     0.517    0.0531    3.535    3.784   4039.9    100.0
  512   512    0   52     1.043     3.564    0.0564    5.828    5.946   3896.1     50.0
```
**This is the whole lesson in one table.** `tok/s` climbs to ~4040 at conc256, then *stops* -
conc512 runs 2x the load for **less** throughput (3896) because the batch is saturated. `ttft_p95`
holds low (0.16 → 0.52s) while continuous batching keeps up, then **spikes to 3.56s** at conc512,
so `goodput` cliffs to **50%**. **Capacity ≈ conc256** (~4000 tok/s at 100% goodput); past it you
serve more requests, all of them worse. (`phase5-overload` is the same sweep with a wider default
range - this cranked command is the GPU version of it.)

### c) Batching - the benefit you could only *describe* on CPU

```bash
MODEL=local ENDPOINT=http://localhost:8000 make phase5-batching
```
```
   phase  reqs  err  gen  ttft_p50  ttft_p95  tpot_p50  e2e_p95  e2e_p99   tok/s  goodput%
 A-alone    12    0   17     0.035     0.053    0.0209    0.386    0.392    45.8    100.0
B-loaded    12    0   17     0.036     0.069    0.0209    0.415    0.417    44.7    100.0
=> short-request ttft_p95 went 0.053s -> 0.069s (1.3x) when the server filled with long requests.
```
On CPU this exact drill inflated a short request's TTFT by **~50x** (requests queued behind the
long ones). On the GPU it's **1.3x** - continuous batching admits the short request *into* the
running batch instead of making it wait. That ratio, CPU vs GPU, *is* the value of continuous
batching - measured, not described.

### d) Prefill - input length drives TTFT

```bash
MODEL=local ENDPOINT=http://localhost:8000 make phase5-prefill
```
```
 in_tok  reqs  err  gen  ttft_p50  ttft_p95  tpot_p50  e2e_p95  e2e_p99   tok/s  goodput%
     16    12    0   45     0.047     0.049    0.0218    1.213    1.215    44.6    100.0
    128    12    0   29     0.047     0.055    0.0216    0.710    0.731    44.5    100.0
    512    12    0   34     0.048     0.130    0.0217    1.024    1.056    44.2    100.0
   1024    12    0   41     0.049     0.150    0.0219    1.185    1.207    44.1    100.0
```
`ttft_p95` rises with prompt length (0.049 → 0.150s) - the model must read the whole prompt before
the first token. `tpot` stays flat (~0.022s): **input length is a TTFT cost**, not a per-token one.

### e) Decode - output length drives total time

```bash
MODEL=local ENDPOINT=http://localhost:8000 make phase5-decode
```
```
 out_tok  reqs  err  gen  ttft_p50  ttft_p95  tpot_p50  e2e_p95  e2e_p99   tok/s  goodput%
      32    12    0   33     0.036     0.048    0.0216    0.739    0.743    45.3    100.0
      64    12    0   55     0.047     0.047    0.0219    1.454    1.454    44.8    100.0
     128    12    0   56     0.047     0.049    0.0220    2.557    2.731    44.7    100.0
     256    12    0   57     0.047     0.047    0.0220    2.220    2.290    44.6    100.0
```
Watch `gen` (tokens actually generated) and `e2e` grow together while `tpot` (~0.022s) and `ttft`
stay flat. **Output length is a duration cost**: `e2e ≈ ttft + tpot × gen`. (`gen` caps around 57
here - this model answers in ~57 tokens regardless of the higher caps, which is why 128 and 256
look similar.)

### f) Optional - make goodput itself reflect the knee

The `b)` sweep cliffs goodput only at *hard* saturation (when TTFT finally spikes). To catch the
degradation *earlier* - the moment end-to-end latency crosses your promise - gate goodput on `e2e`:

```bash
MODEL=local ENDPOINT=http://localhost:8000 \
  CONCURRENCY=64,128,256,512 REQUESTS_PER_LEVEL=512 E2E_SLO=1.0 make phase5-bench
```
The header will show `+ e2e-SLO=1.0s`, and `goodput%` drops as soon as `e2e_p95` crosses 1s (from
the `b)` table, that's already by conc64) - giving you an earlier, latency-honest capacity signal.

💡 Watch it happen: `watch -n1 nvidia-smi` in another terminal - GPU-Util climbs as you push.

✅ **Gate:** point at the row where `tok/s` stops scaling and `goodput` drops, name it as this
card's capacity for this model, and explain *why* (the batch saturated). That explanation, in real
numbers, **is** the lesson.

## Study it - things to try (and what each teaches)

> ⚠️ **Don't expect CPU-scale load to do anything here.** A GPU is *vastly* more capable than
> the laptop CPU tier - the concurrency that choked Ollama (conc 4-8) won't even warm an A6000.
> Two levers actually move the needle: **much higher load** (see "Find the knee" above) and the
> **model size** (a 7B is the default; a 14B saturates sooner, a 1.5B much later).

Work through these - each isolates a different idea (set `REQUESTS_PER_LEVEL` ≥ top concurrency):

Set `REQUESTS_PER_LEVEL` ≥ your top concurrency in every one (or high-concurrency rows go flat):

| Try this | What you're studying |
|---|---|
| `watch -n1 nvidia-smi` in another terminal during any sweep | the actual GPU-Util and memory - *is the card even busy?* On a tiny model it sits near idle; on a 7B under load it climbs |
| `CONCURRENCY=64,128,256,512 REQUESTS_PER_LEVEL=512 make phase5-bench` | find where `tok/s` **stops scaling** and `goodput` cliffs - the card's real limit for this model |
| `CONCURRENCY=64,128,256,512 REQUESTS_PER_LEVEL=512 E2E_SLO=1.0 make phase5-bench` | the goodput cliff gated on end-to-end latency - catches the knee *earlier* than TTFT does |
| `make phase5-prefill` then `make phase5-decode` | real prefill vs decode cost - `tpot` is now a true per-token time for this card |
| `make phase5-batching` | continuous batching's benefit: even with long requests in flight, a short request's TTFT barely moves - the opposite of what you saw on CPU |
| Serve a few sizes (`1.5B`, `7B`, `14B`) and run the same sweep on each | **right-sizing**: a small model wastes the card (huge tok/s, idle GPU, lower quality); a bigger one uses it (lower tok/s, more VRAM, better quality). Matching model→GPU is the cost lever |

💡 **The headline you'll be able to defend:** *"On this card, throughput saturates at conc N
(~X tok/s); past that, latency rises with no throughput gain. TTFT stays flat because continuous
batching admits requests into the running batch - so I size capacity on tok/s + e2e, not TTFT
alone, and I right-size the model to the GPU."* That sentence is worth the rental.

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

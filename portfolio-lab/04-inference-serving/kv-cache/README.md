# Lesson 4B - The KV cache (the real capacity limit)

> Part of [Lesson 4A - Inference benchmarks](../README.md) · Course home:
> [AI Factory Operations Lab](../../../README.md) · Next:
> [Lesson 5 - BCM-Style Cluster Lifecycle](../../05-bcm-style-cluster-lifecycle/README.md)
> (Lesson 4C, Prefill/Decode disaggregation, is planned)

> ✅ **STATUS: RUNNABLE.** The calculator and every concept here run on your laptop, free.
> Observing the *live* KV metrics (cache usage, prefix-hit rate under load) on a real vLLM
> server is the real-GPU half of this lesson, and is **not captured yet**.

Lesson 4A said the quiet part once: **"how many requests fit is a memory question, not a speed
one."** This lesson is that memory. Every in-flight request holds a **KV cache**, and its size,
not tokens/sec, is usually what caps how many users you serve at once. If you can size the KV
cache from a model's config, you can predict concurrency before you rent a single GPU.

🎯 **Learning objectives** - you'll be able to:

1. Explain what the KV cache is and why decode cannot go fast without it.
2. Compute KV memory **per token** and **per request** from a model's real architecture, and
   how many requests fit a given GPU.
3. Reason about the levers that move it: **context length**, **GQA**, **dtype/quantization**,
   **PagedAttention**, **prefix caching**, and **offload**.
4. Name the KV metrics you would read on a real vLLM server: cache usage %, prefix-hit rate,
   and the point where a full cache turns into queued and preempted requests.

🧭 **Mode:** 🟦 Free, no GPU, for the calculator and the concepts. 🟥 The live metrics need a
real GPU server (Lesson 6 stands one up); capturing them is the real-GPU half of this lesson,
still to do.

📋 **Prerequisites:** [Lesson 4A](../README.md), especially the prefill/decode split and the
KV cache row in its vocabulary table.

---

## Why the KV cache exists (30 seconds)

Decode generates one token at a time, and each new token attends to **every** previous token.
The keys and values for those earlier tokens do not change, so recomputing them every step
would make decode quadratic. Instead the server computes each token's key and value once and
**caches** them: the KV cache. That is what makes decode a cheap per-token step (the flat TPOT
you measured in Lesson 4A) instead of a re-read of the whole context every time.

The cost: that cache lives in GPU memory, and it grows with **context length** (more tokens
cached) and **concurrency** (more requests, each with its own cache).

## The one formula

KV cache size, per token, for one sequence:

```
2  x  num_layers  x  num_kv_heads  x  head_dim  x  bytes_per_element
^                                                  ^
K and V                                            fp16/bf16 = 2, fp8 = 1
```

Then multiply by **context length** for one request, and by **concurrency** for the server.

**What multiplies by what** (this is the part that trips people up): each request has its
**own** KV cache. A request's "context" is *its* tokens, the prompt plus whatever it has
generated so far, so one request at 8k context holds `KV/token x 8,192` **by itself**. The GPU
holds the **sum of every in-flight request**:

```
total KV on the GPU  =  KV per token  x  context length  x  concurrency
                        \___________/    \_____________/    \__________/
                        model arch        ONE request's      how many requests
                                          own tokens         are in flight now
```

So `8k` is **one request's** size, never a shared pool across users. Concurrency is how many of
those the GPU carries at the same moment. Two users each at 8k cost twice one user at 8k.

The three architecture numbers come from the model's `config.json`, not from memory:

| Factor | `config.json` field | Note |
|---|---|---|
| `num_layers` | `num_hidden_layers` | every layer keeps its own K and V |
| `num_kv_heads` | `num_key_value_heads` | **fewer than attention heads = GQA**, which shrinks the cache. That is the point of GQA |
| `head_dim` | `hidden_size / num_attention_heads` | size of one head's vector |
| `bytes_per_element` | serving dtype | fp16/bf16 = 2, fp8 = 1. Halving it halves the cache |

### Where those three numbers come from

Every model ships a `config.json` (on its model card / in its repo). For the Qwen2.5-7B this
course benchmarks, the relevant fields read (trimmed; confirm on the model card):

```json
{
  "num_hidden_layers": 28,
  "num_attention_heads": 28,
  "num_key_value_heads": 4,
  "hidden_size": 3584
}
```

Read the three inputs straight off it, do not guess:

- `num_layers`   = `num_hidden_layers` = **28**
- `num_kv_heads` = `num_key_value_heads` = **4** (GQA: far below the 28 attention heads, which
  is exactly why the cache is small)
- `head_dim`     = `hidden_size / num_attention_heads` = 3584 / 28 = **128**

Those are the defaults `kv-calc.py` ships with. For any other model, open its `config.json` and
substitute.

> **What is GQA, and why is `num_kv_heads` the one that counts?** In the original attention
> design (MHA), every attention head keeps its **own** K and V, so the KV cache grows with the
> *attention* head count. **Grouped-Query Attention (GQA)** lets several query heads **share**
> one K/V head. Qwen2.5-7B has **28 query heads but only 4 KV heads**, so 7 query heads share
> each K/V pair. Quality holds up in practice, but the KV cache counts **KV heads, not attention
> heads**, so it is **7x smaller** than it would be without GQA. That is why the formula uses
> `num_key_value_heads`, and why the "turn off GQA" drill below (forcing it to 28) makes the
> cache explode.

---

## Hands-on: size it yourself (free)

[`kv-calc.py`](kv-calc.py) is stdlib Python (no install). Defaults model a 7B-class GQA model;
override any factor with a flag.

```bash
cd portfolio-lab/04-inference-serving/kv-cache
python3 kv-calc.py
```

```
KV cache calculator  (ILLUSTRATIVE arch; confirm against config.json)
--------------------------------------------------------------------
Model      : 28 layers, 4 KV heads, head_dim 128, KV dtype fp16 (2 B)
Weights    : ~7B params @ fp16  ->  13.04 GiB
GPU memory : 48 GiB   (reserve 2 GiB for activations/overhead)
Free for KV: 32.96 GiB

KV per token (one sequence):  2 x 28 x 4 x 128 x 2 B  =  57,344 B  (0.0547 MiB/token)
KV per request @ 4,096 tokens:  224.0 MiB

Max concurrent requests @ 4,096 context:  ~150
(This, not tokens/sec, is usually what caps how many users you serve at once.)

Context length vs concurrency (same GPU):
   context       KV/req  max concurrent
     1,024      56.0 MiB             602
     2,048     112.0 MiB             301
     4,096     224.0 MiB             150  <- your setting
     8,192     448.0 MiB              75
    16,384     896.0 MiB              37
    32,768   1,792.0 MiB              18
  Double the context, halve the concurrency. Context length is a capacity cost.

Prefix caching: 50 requests sharing a 1,024-token prompt
  store the shared prefix ONCE instead of 50 times  ->  save 2.68 GiB  (~12 more concurrent @ 4,096 ctx)
  This is why a shared system prompt / few-shot preamble is nearly free to reuse.
```

✅ **Checkpoint:** you can point at the one row that is your real capacity number
(`max concurrent @ your context`) and explain why it, not tokens/sec, is the limit.

## What the result is for (the decision)

The point of the number is a decision, and it runs in **both directions**. Yes: this is how you
match a GPU to how many concurrent requests you need to serve.

**You have a GPU. How many requests can I serve at once?**
`max concurrent @ your context` is the ceiling: the most requests that can be **in flight**
before the KV cache is full. What you do with it: cap the server there so extra load **queues**
instead of running the GPU out of memory. In vLLM that cap is `--max-num-seqs` (and
`--max-model-len` sets the context); confirm the flag names against your version. That ceiling
is also the per-replica capacity number [Lesson 4A](../README.md)'s Little's-Law plan feeds on.

**You have a target load. Which GPU, and how many replicas?**
Flip the calculation. Say the requirement is **300 concurrent requests at 8k context**:

1. `KV per request` at 8k = **448 MiB** (the calculator's 8k row).
2. `x 300` = **~131 GiB** of KV in flight at once.
3. `+ weights + overhead` (~13 + 2 GiB) = **~146 GiB** total GPU memory needed.
4. That exceeds any single card, so you need replicas. One 48 GiB card fits **~75** requests at
   8k (the calculator again), so `ceil(300 / 75)` = **4 replicas**.

If step 3 had fit one card, you would simply pick the smallest card with that much VRAM (and,
for example, rule out a 24 GB one).

**If it does not fit,** you have four levers, and each one moves a row in the table below: a
shorter max context, a **GQA** model, **quantized** weights (more room for KV), or **KV
offload** to CPU/NVMe. Pick the one your latency budget can afford.

> In one line: **concurrency you need + context length -> KV memory -> the GPU (or the number
> of GPUs).** The calculator is the "-> KV memory" step; the rest is arithmetic you now control.

### Drills - move one lever at a time

| Drill | Command | What to look for |
|---|---|---|
| **Context is a cost** | `python3 kv-calc.py --context 8192` | concurrency roughly halves vs 4,096. Long-context serving is expensive in *memory*, not just speed |
| **Quantize the weights** | `python3 kv-calc.py --weight-dtype int8` | weights shrink, so `Free for KV` grows and concurrency rises. Quantization buys KV room, not just smaller weights |
| **Turn off GQA** | `python3 kv-calc.py --kv-heads 28` | KV per token jumps 7x (4 -> 28 heads); concurrency collapses. This is why modern models use GQA |
| **A 24 GB card** | `python3 kv-calc.py --gpu-mem-gib 24` | the same model, far fewer concurrent requests. Card memory is a concurrency budget |
| **Prefix caching** | `python3 kv-calc.py --prefix-requests 200 --prefix-tokens 2048` | a bigger shared prompt across more requests saves more GiB. Shared preambles are nearly free to reuse |

---

## Lifecycle: sessions, and when KV is freed

A common misunderstanding is that every user chat session permanently holds a KV cache on the
GPU. In conventional **stateless** LLM serving, it does not. The application or API layer keeps
the conversation history and submits the relevant history as part of **each** request; the
inference engine allocates KV-cache blocks for **active sequences**, not permanently for user
identities. The "session" lives in your app, not in GPU memory.

**Reuse is by content, not by user.** When prefix caching is enabled, completed KV blocks may
stay resident after a request finishes and be reused by a later request with the same compatible
token prefix. The match is on the **exact tokenized content plus the cache namespace**, the
model, any adapter, multimodal inputs, or a tenant cache salt, not simply on who sent the
request. Two different users with the same system prompt (and namespace) can hit the same cached
prefix.

**When is KV freed?** A completing request does not so much "free" its cache as **release its
references** to the blocks. What happens next, none of it a session timeout:

| Event | What happens to the blocks |
|---|---|
| **Request completes** (EOS or `max_tokens`) | its references are released; reusable full blocks may remain cached |
| **Memory is needed** | unreferenced blocks are evicted by an engine policy (LRU or prioritized LRU) |
| **KV pressure on active requests** | a running request may be **preempted** and resumed later by recomputation, or offload and restore |

The cache is **memory-bounded**, not time-bounded.

**What this means for sizing.** Size KV capacity around the **peak active-token footprint across
concurrent requests**, with headroom for the context and output lengths you expect, not around a
count of long-lived user sessions. That footprint is exactly what the calculator sums
(`KV/token x context x concurrency`); the calculator is your estimate of it.

**In a multi-replica deployment**, prefix-cache-aware routing can send a follow-up request to a
replica that still holds the matching conversation prefix, balancing that cache affinity against
replica load. That routing is [Lesson 4D](../README.md) (planned).

## PagedAttention: why real servers get close to these numbers

The calculator assumes every request's KV cache is packed perfectly. A naive server cannot do
that: if it reserves `max_context` worth of KV per request up front, most of it sits empty
(few requests actually reach max context), and that reserved-but-unused memory is pure waste.
Real concurrency ends up a fraction of the calculator's number.

**PagedAttention** (the core idea in vLLM) fixes this the way an operating system fixes memory
fragmentation: it allocates KV cache in small fixed **blocks (pages)** on demand, as a request
generates tokens, instead of reserving the worst case. Requests only hold the pages they
actually use, so the server packs close to the theoretical limit this calculator prints. When
you see a real server sustain concurrency near these numbers, paging is why.

## Prefix caching: the KV cache being smart about reuse

**Prefix caching is not a second cache.** It is the *same* KV cache with one change to the
lifecycle above: instead of freeing a prefix's KV when a request finishes, the server **keeps**
it, so the next request that starts with the same tokens can reuse it and skip the prefill for
that shared part.

So the two words name different things, not two caches:

- **KV cache** = the storage: the K and V for tokens that are (or were) in flight.
- **Prefix caching** = a **retention-and-reuse policy** on that storage: hold a shared prefix's
  KV instead of dropping it, and hand it to the next request that matches.

When requests share a prefix, a **system prompt**, a few-shot preamble, or a common document,
that KV is stored **once** and reused. Two wins:

- **Memory:** the shared prefix is not duplicated per request (the `kv-calc.py` prefix section
  quantifies this).
- **Latency:** the shared part skips prefill, so **TTFT drops** on a cache hit.

This is why a fixed system prompt is nearly free to reuse, why a multi-turn chat gets cheaper
per turn, and why prompt design (put the shared, stable text first) has a real serving cost
consequence.

## KV offload: when it will not fit

If the working set exceeds GPU memory, the cache can spill to **CPU RAM or NVMe** (projects
like LMCache and Mooncake), extending effective capacity at the cost of a transfer when a
spilled entry is needed again. Treat it as a capacity-vs-latency trade, and measure the
transfer cost before claiming a win; do not assume it is free.

---

## On real hardware (the real-GPU half, still to capture)

The calculator **predicts**; a real server **reports**. Lesson 6
[Part D](../inference-realgpu/README.md) stands up vLLM on a real card, but it benchmarks
**throughput and latency**, it does **not** observe the KV cache. Watching the cache on that
same server is the real-GPU half of *this* lesson, and it is **not captured yet**.

When you do it, these are the KV signals to watch (the same vLLM server exposes them):

- **KV cache usage %** climbing as you raise concurrency and context, flattening near full.
- **Prefix-cache hit rate** rising when requests share a prompt, with TTFT dropping on hits.
- The moment the cache is **full**: new requests wait or get **preempted** (the waiting-requests
  and preemption counters move), the memory limit turning into a latency problem in real time.

Confirm the exact metric names against your vLLM version, and capture the output into a
validation report; that captured behaviour is what would turn this from predicted to proven
(house rule 2).

## What you proved, and what you did not

**Proved (free):** the KV memory model and its levers, computed from a model's real
architecture. You can now size concurrency for any model/GPU/context before renting anything.

**Not proved here:** the live cache behaviour, PagedAttention's real anti-fragmentation win,
and prefix-hit rates under load. Those are runtime facts that need the real server (Lesson 6).

## What's in this directory

- [`kv-calc.py`](kv-calc.py) - the KV cache calculator (stdlib, no install).

➡️ **Next:** [Lesson 5 - BCM-Style Cluster Lifecycle](../../05-bcm-style-cluster-lifecycle/README.md)
(Lesson 4C, Prefill/Decode disaggregation, is planned), or back to
[Lesson 4A](../README.md).

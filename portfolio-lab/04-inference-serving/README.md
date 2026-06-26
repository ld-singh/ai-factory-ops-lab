# Lesson 4 - Inference Serving

> Course home: [AI Factory Operations Lab](../../README.md) · Previous:
> [Lesson 3 - Observability](../03-observability/README.md) · Next:
> [Lesson 5 - BCM-Style Cluster Lifecycle](../05-bcm-style-cluster-lifecycle/README.md)

> ✅ **STATUS: RUNNABLE.** A tiny CPU-served model plus a stdlib load generator let you
> study what makes LLM serving its own discipline - the prefill/decode split, latency
> contention, the goodput cliff, and capacity planning - on your laptop, for free.

The point of all that scheduling and observability is to *serve something*. This lesson
stands up an inference server, drives load through it, and teaches you to read it like an
operator: not "how fast is it" but "where does it break, and why."

You study this on CPU because the **behaviour** you're learning - how latency, throughput,
and goodput move as you change load, prompt length, and output length - is the same shape on
any hardware. What CPU can't give you is throughput *numbers* for a specific GPU; those come
from the same harness pointed at a real card in [Lesson 6](../real-gpu-session/README.md).

🎯 **Learning objectives** - you'll be able to:

1. Run a load test and read the SLOs that matter: **TTFT**, **TPOT/ITL**, **p95/p99**,
   **tokens/sec**, **goodput**, error rate - and say which one is the *real* number.
2. **See latency contention** - watch an interactive request's TTFT inflate under heavy
   in-flight load, and explain how continuous batching mitigates it.
3. **Separate prefill from decode** - drive TTFT with input length and TPOT with output
   length, the two-bottleneck mental model of LLM serving.
4. **Find the knee** - push past sustainable load and watch goodput collapse while
   throughput keeps "climbing."
5. Turn those numbers into a **capacity plan** (Little's Law + $/1M tokens) - the
   provisioning decision the metrics exist for.
6. Contrast inference vs training vs batch, and reason about which scheduler fits each.

🧭 **Mode:** 🟦 Runs on CPU, on your laptop, free. The same drills run against a real GPU in
[Lesson 6](../real-gpu-session/README.md) when you want hardware throughput numbers.

---

## First, the vocabulary (read this before you run anything)

If you've operated web services, most of this lesson will *feel* familiar - requests,
latency, throughput, replicas - but LLM serving bends those words in ways that trip people
up. Here's the whole vocabulary the lesson uses, in plain English, so the drills land
instead of washing over you. Skim it now; each term gets demonstrated by a drill below.

**How a request actually works.** You send a **prompt** (the input text). The server turns
it into **tokens** (word-ish chunks - roughly ¾ of a word each). Generating a reply happens
in two distinct phases, and *they cost differently*:

| Term | Plain meaning | Why an operator cares |
|---|---|---|
| **Token** | The unit a model reads/writes (~¾ of a word) | Everything is billed and measured in tokens, not requests |
| **Prompt / input** | The text you send in | Longer input = more **prefill** work before any reply |
| **Prefill** | Processing the whole prompt to produce the *first* token | Compute-heavy; sets your **TTFT**. Grows with input length |
| **Decode** | Generating each *subsequent* token, one at a time | Memory-bandwidth-bound; sets your **TPOT**. Grows with output length |
| **Batch / continuous batching** | The server runs many requests together, adding new ones mid-flight | The #1 reason real LLM servers are fast - and why one request can slow another |
| **KV cache** | GPU memory each in-flight request holds for its context | The real capacity limit: "how many fit" is a *memory* question, not a speed one |

**How you measure it.** The metrics below are exactly the columns the harness prints, so you
can read any drill's table straight off this list. The trap: "fast" has several meanings that
disagree, and the honest one (goodput) is the least obvious.

| Term (table column) | Plain meaning | Why an operator cares |
|---|---|---|
| **TTFT** (`ttft_p50` / `ttft_p95`) | Time to **first** token - how long until the reply *starts* | What an interactive user feels as "lag" |
| **TPOT / ITL** (`tpot_p50`) | Time **per** output token - the gap between streamed tokens | Streaming smoothness; it's a *steady per-token cost*, so it stays ~flat |
| **e2e** (`e2e_p95` / `e2e_p99`) | **End-to-end** latency: the *whole* request, start to last token, at the slow tail | The total wait a user sees; `e2e ≈ ttft + tpot × gen` |
| **gen** (`gen`) | Output tokens **actually generated** (not just the cap you asked for) | Tells you if a `max_tokens` cap really bit; e2e tracks `gen`, not the cap |
| **Throughput** (`tok/s`) | Total output tokens/sec the server pushes out | The capacity number you provision against |
| **Goodput** (`goodput%`) | Share of requests that met their SLO | The **honest** number - high `tok/s` with blown e2e is still failure |
| **Errors** (`err`) | Requests that timed out / were rejected | What rises first when the server is overloaded |

> `p50/p95/p99` just mean "the median / 95th / 99th-percentile (slow-tail) value." SLOs live
> in the tail (`p95`/`p99`) because the average hides your worst-served users.

**How you plan with it.** Once you can read a server, you size a fleet:

| Term | Plain meaning | Why an operator cares |
|---|---|---|
| **SLO** (service-level objective) | The target you promise (e.g. "TTFT < 1s for 99%") | Defines pass/fail; everything above is measured against it |
| **Replica** | One running copy of the model server | You scale capacity by adding replicas |
| **Little's Law** | in-flight = arrival-rate × latency | The math that turns demand into a replica count (Step 5) |
| **Knee / saturation** | The load where adding more makes things *worse* | The operating limit you must find before users do (Step 4) |

> 🧠 **The one idea to hold onto:** LLM serving is a constant trade-off between **throughput**
> (serve many, cheaply) and **latency** (serve each one fast), and the dial between them is
> **batch size**. Every drill in this lesson is a different view of that one trade-off.

---

## Setup - serve the CPU model (once)

```bash
make phase5-serve-cpu   # Ollama-in-Docker serves a tiny model on CPU (OpenAI-compatible /v1)
```

Leave it running. Stop it with `make phase5-down` when you're done with the whole lesson.

---

## The learning path (run these in order)

Each step is one `make` target and teaches one idea. Run it, then read the "what you're
seeing" note before moving on.

### Step 1 - The baseline trade-off (concurrency sweep)

```bash
make phase5-bench
```

This fires the same set of requests four times, each time with more of them **in flight at
once** - that's what the `conc` column means: `1` = one request at a time (one simulated
user), `2` = two simultaneously, then `4`, then `8`. Higher concurrency = a busier server.

**What you're seeing:** as `conc` rises, the server pushes more total work out (`tok/s`
climbs - it overlaps requests) but **each individual request waits longer**, so `ttft_p95`
and `e2e_p99` climb. That's the one trade-off at the heart of serving: *throughput vs
latency*. You can serve more users at once, but each gets a slower response.

So how busy should you run it? That's what `goodput%` answers - the share of requests that
still beat the **TTFT SLO** (your promise to users; here "first token within 1s").

**Worked example** - say a run prints this:

```
 conc  ttft_p95   tok/s   goodput%
    1     0.20s    74.1     100.0     <- quiet: everyone gets a token in 0.2s
    2     0.82s    86.1     100.0     <- busier, still under 1s -> all good
    4     4.52s    90.9      25.0     <- overloaded: 75% now miss the 1s promise
```

Read it as a story: going from `conc 1 -> 4`, `tok/s` actually *climbs* (74 -> 91), so by the
"how many tokens/sec" measure the server looks **faster**. But `ttft_p95` blows past 1s and
`goodput%` craters to 25% - three out of four users now wait too long. The higher throughput
is a lie; you're serving more people *worse*.

**Your capacity is `conc 2`** here: the highest concurrency where `goodput%` is still high
(100%). You'd run the server at 2, not 4 - and if you need to serve more than that, you add a
second replica (Step 5) rather than overloading this one. That single decision - "find the
highest load that still keeps the promise" - is the whole point of the sweep.

(Raw results write to `06-validation-reports/evidence/`.)

### Step 2 - Watch in-flight load steal an interactive request's latency

```bash
make phase5-batching
```

Runs short interactive requests **alone**, then the **same** short requests while eight
long (512-token) requests saturate the server.

**What you're seeing:** the short request's `ttft_p95` jumps an order of magnitude (≈50× -
the script prints the multiplier). The lesson is concrete: **a request's latency is not its
own** - it depends on everything else in flight. That's *contention*, and it's the reason LLM
serving needs more than a round-robin load balancer.

**Continuous batching** is how production servers (vLLM) keep this in check: new requests are
admitted into the running batch instead of queueing behind it. This lab teaches the
contention; you measure how much continuous batching buys you back when you run the same drill
on a real GPU in [Lesson 6](../real-gpu-session/README.md).

### Step 3 - Separate prefill from decode

```bash
make phase5-prefill     # grow the PROMPT (input)  -> ttft climbs, tpot stays ~flat
make phase5-decode      # grow the OUTPUT (gen)     -> e2e climbs, tpot stays ~flat
```

**What you're seeing:** two different bottlenecks, and one thing that *doesn't* move.

- `prefill` grows the **input** (`in_tok`): `ttft` rises because the model must read the
  whole prompt before the first token (prefill is compute-heavy). Output is fixed.
- `decode` grows the **output**: watch the **`gen`** column - that's tokens *actually*
  generated (the cap only bites if the model doesn't stop first, which is why the drill uses
  a "keep counting" prompt). As `gen` rises, **`e2e` rises with it** - each token is another
  forward pass.

The thing that stays ~flat in *both* is **`tpot`** (time *per* token): decode is a steady
per-token cost. So a long answer isn't *slower per token* - it just has *more* tokens. The
mental model the whole step builds: **`e2e ≈ ttft + tpot × gen`** - prefill sets the first
term, decode multiplies the last. Knowing which half you're paying for is how you tune a
server.

### Step 4 - Find the knee (the goodput cliff)

```bash
make phase5-overload
```

Climbs concurrency `1…32`. **What you're seeing:** `tok/s` keeps rising even as
`goodput%` falls off a cliff and `err` climbs - because throughput counts tokens, goodput
counts *requests that met the SLO*. The lesson: a server can look "faster" (more tok/s)
while serving everyone worse. Goodput is the number you defend; tok/s alone is marketing.

### Step 5 - Turn it into a capacity plan

```bash
make phase5-capacity
# or with your own measured numbers:
make phase5-capacity ARGS="--target-tokens-per-s 5000 --replica-tokens-per-s 700 --price-per-hour 1.2"
```

**What you're seeing:** the provisioning math the SLOs exist for - Little's Law
(`requests-in-flight = arrival_rate × latency`) for the concurrency you must hold, replica
count for the token demand, and the resulting `$/1M tokens`. Plug in a single replica's
best SLO-passing row and you've sized a fleet. Run it with the defaults to learn the method;
plug in a GPU sweep's numbers when you want a fleet size for real hardware.

---

## On real hardware (Lesson 6, Part C)

Everything above is the method - learned on CPU for free. To get throughput *numbers* for an
actual GPU, you serve a model with vLLM and run the **same drills** against it. That's its own
lab: **[Part C - Real inference benchmark](./inference-realgpu/README.md)** (serve with
`make phase5-serve-gpu`, point the drills at `:8000`, capture the numbers).

💡 **Why learn it on CPU first:** a correct load generator (streaming TTFT capture, percentile
math, concurrency control) is real work, and you'd rather not debug it while the GPU meter
runs. You get the harness solid for free here, then spend the rented GPU time *measuring*. The
[`harness/loadgen.py`](./harness/loadgen.py) is identical for both - it doesn't care whether a
CPU or a GPU is behind the endpoint.

---

## Concept 1 - Why LLM serving isn't web serving

1. **Requests are wildly non-uniform:** a 10-token answer and a 2 000-token answer differ by
   200× in work (you measured this in Step 3), so naive load balancing fails.
2. **Continuous batching:** the server admits new requests into the running batch at token
   boundaries instead of waiting for it to drain - the single biggest reason vLLM-class
   servers beat naive serving by an order of magnitude. You watched its cost in Step 2.
3. **KV cache is the real capacity limit:** each in-flight sequence holds GPU memory
   proportional to its context length. "How many concurrent requests fit" is a *memory*
   question, not a compute one - which connects to Step 4's saturation and Lesson 3's
   FB_USED panel / [gpu-memory-pressure runbook](../../runbooks/gpu-memory-pressure.md).
   (Measuring the memory itself needs the GPU - Lesson 6.)

## Concept 2 - Workload shapes, and which scheduler fits

| Property | Inference | Training | Batch/experiments |
|---|---|---|---|
| Lifetime | Long-running service | Days–weeks job | Minutes–hours jobs |
| Demand | Diurnal, spiky | Constant while running | Bursty |
| Failure response | Restart fast, keep SLO | Checkpoint/resume | Re-queue |
| Gang requirement | No (per-replica) | Yes (all ranks or none) | Rarely |
| Natural scheduler | Kubernetes (+ sharing, Lesson 1C) | Slurm or K8s+KAI gang (1B/3) | Either, queue-policy driven |

This table is the course's capstone argument: Lessons 1–2 weren't scheduler trivia - they
were the decision framework for *placing* these three shapes.

## What's in this directory

- [`harness/loadgen.py`](./harness/loadgen.py) - the load generator (stdlib only): streaming
  TTFT capture, TPOT, p50/p95/p99, tokens/sec, goodput-at-SLO. Modes: `sweep`
  (concurrency / input / output axis) and `mixed` (the batching drill).
- [`harness/drills.sh`](./harness/drills.sh) - the four $0 drills (`batching` / `prefill` /
  `decode` / `overload`) behind the `make phase5-*` targets.
- [`harness/run-bench.sh`](./harness/run-bench.sh) - the concurrency sweep wrapper that
  writes raw results to the evidence tree. Override `ENDPOINT` / `MODEL` / `CONCURRENCY`.
- [`harness/capacity-plan.py`](./harness/capacity-plan.py) - the Little's-Law + $/1M-tokens
  capacity exercise.
- [`scripts/serve-cpu.sh`](./scripts/serve-cpu.sh) - the $0 Ollama-on-CPU server;
  [`scripts/down.sh`](./scripts/down.sh) stops it.
- [`scripts/serve-gpu.sh`](./scripts/serve-gpu.sh) - the real-GPU counterpart: deploys vLLM as
  a k3s pod on the Lesson 6 VM, same OpenAI API on :8000 (`make phase5-serve-gpu`).

**On the GPU (Lesson 6) you add:** a throughput-vs-latency plot from real vLLM numbers, and
the [Lesson 1C](../01-k8s-gpu-platform/hami/README.md) tie-in - two model replicas sharing one
GPU via HAMi slices vs one dedicated replica, measuring what sharing costs in p99.

📊 **What this lesson teaches:** how to serve a model, read its SLOs, and find its operating
point and capacity - the serving operator's core skills, all on your laptop. The GPU run adds
hardware throughput numbers and KV-cache memory limits. Full map of what each tier covers:
[`fake-vs-real-limitations.md`](../06-validation-reports/fake-vs-real-limitations.md).

➡️ **Next:** [Lesson 5 - BCM-Style Cluster Lifecycle](../05-bcm-style-cluster-lifecycle/README.md).

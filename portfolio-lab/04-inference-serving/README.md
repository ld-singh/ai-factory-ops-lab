# Lesson 5 — Inference Serving

> Course home: [AI Factory Operations Lab](../../README.md) · Previous:
> [Lesson 4 — Observability](../03-observability/README.md) · Next:
> [Lesson 6 — BCM-Style Cluster Lifecycle](../05-bcm-style-cluster-lifecycle/README.md)

> 🚧 **STATUS: PLANNED (Phase 5).** The concept sections below are teachable now;
> runnable steps (server deploy, load generator, benchmark harness) land with
> Phase 5.

The point of all that scheduling and observability is to *serve something*. This
lesson stands up an inference server, drives load through it, and benchmarks it with
SLOs that actually matter.

🎯 **Learning objectives** — when this lesson is runnable you'll be able to:

1. Serve a lightweight model with Triton and/or vLLM behind a gateway/router.
2. Run load tests and read the SLOs that matter for inference: **TTFT**, **TPOT/ITL**,
   **p95/p99 latency**, **tokens/sec**, **goodput**, GPU utilization/memory, and
   error rate.
3. Explain continuous batching and KV-cache pressure — the two ideas that make LLM
   serving different from classic web serving.
4. Contrast inference vs training vs batch workload characteristics, and reason about
   which scheduler (Kubernetes vs Slurm) fits each.

🧭 **Mode:** 🟥 Real GPU. A small model on a single mid-range GPU is enough for
meaningful benchmarking — reuse the Lesson 2 machine (and the
[cheap-rental playbook](../01-k8s-gpu-platform/gpu-operator-real/README.md#renting-the-gpu-cheaply)).

> **Note:** benchmark numbers are only ever published from real GPU runs. Anything
> else in the report is an unloaded template — a number you can't reproduce on
> hardware doesn't belong in a benchmark.

---

## Concept 1 — The SLO vocabulary

| Metric | Definition | Why it matters |
|---|---|---|
| **TTFT** (time to first token) | Request arrival → first output token | What an interactive user *feels*; dominated by queueing + prefill |
| **TPOT / ITL** (time per output token / inter-token latency) | Average gap between subsequent tokens | Streaming smoothness; dominated by decode throughput |
| **p95/p99 latency** | Tail of end-to-end request latency | SLOs are tail-based; averages hide the pain |
| **Tokens/sec** | Aggregate output throughput | The capacity number; what you provision against |
| **Requests/sec** | Request-level throughput | Only meaningful alongside token lengths |
| **Goodput** | Throughput counting *only* requests that met their SLO | The honest number — high tokens/sec with blown p99 is failure |
| **Error rate** | Non-2xx / timeouts / OOM-rejected | The thing batching pushes on when KV cache fills |

💡 **The core tension to demonstrate:** throughput and latency trade off through
batch size. Bigger batches → better tokens/sec (GPU efficiency) → worse TTFT and
ITL for individuals. A benchmark that reports one without the other is marketing.
Phase 5's harness sweeps concurrency and plots both curves.

## Concept 2 — Why LLM serving isn't web serving

1. **Requests are wildly non-uniform:** a 10-token answer and a 2 000-token answer
   differ by 200× in work, so naive load balancing fails.
2. **Continuous batching:** the server admits new requests into the running batch at
   token boundaries instead of waiting for the batch to drain — this is the single
   biggest reason vLLM-class servers beat naive serving by an order of magnitude.
3. **KV cache is the real capacity limit:** each in-flight sequence holds GPU memory
   proportional to its context length. "How many concurrent requests fit" is a
   memory question, not a compute one — which connects straight back to Lesson 4's
   FB_USED panel and the [gpu-memory-pressure runbook](../../runbooks/gpu-memory-pressure.md).

## Concept 3 — Workload shapes, and which scheduler fits

| Property | Inference | Training | Batch/experiments |
|---|---|---|---|
| Lifetime | Long-running service | Days–weeks job | Minutes–hours jobs |
| Demand | Diurnal, spiky | Constant while running | Bursty |
| Failure response | Restart fast, keep SLO | Checkpoint/resume | Re-queue |
| Gang requirement | No (per-replica) | Yes (all ranks or none) | Rarely |
| Natural scheduler | Kubernetes (+ sharing, Lesson 1C) | Slurm or K8s+KAI gang (1B/3) | Either, queue-policy driven |

This table is the course's capstone argument: Lessons 1–3 weren't scheduler
trivia — they were the decision framework for *placing* these three shapes.

## What Phase 5 will ship

- A small open model served via vLLM (OpenAI-compatible endpoint) and/or Triton,
  deployed onto the Lesson 2 single-GPU cluster.
- A load-generation harness sweeping concurrency levels, emitting
  TTFT/TPOT/p95/p99/tokens-per-sec per level.
- The throughput-vs-latency curve plotted from real runs, plus a goodput analysis at
  a declared SLO.
- An optional [Lesson 1C](../01-k8s-gpu-platform/hami/README.md) tie-in: two small
  model replicas sharing one GPU via HAMi slices vs one dedicated replica —
  measuring what sharing costs in p99.

✅ **Evidence (when implemented):** lands in
[`../06-validation-reports/inference-benchmark-report.md`](../06-validation-reports/inference-benchmark-report.md).

🔬 **Sim vs real:** there is no honest simulation tier for benchmark *numbers* —
this lesson is 🟥 by nature. What you can do for free now: the concepts above, the
harness code, and the dashboard panels (Lesson 4) that will receive the metrics.

➡️ **Next:** [Lesson 6 — BCM-Style Cluster Lifecycle](../05-bcm-style-cluster-lifecycle/README.md).

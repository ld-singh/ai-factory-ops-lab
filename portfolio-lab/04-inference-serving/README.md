# Lesson 5 — Inference Serving

> Course home: [AI Factory Operations Lab](../../README.md) · Previous:
> [Lesson 4 — Observability](../03-observability/README.md) · Next:
> [Lesson 6 — BCM-Style Cluster Lifecycle](../05-bcm-style-cluster-lifecycle/README.md)

> 🚧 **STATUS: PLANNED (Phase 5).** Concepts and objectives now; runnable steps land
> with Phase 5.

The point of all that scheduling and observability is to *serve something*. This
lesson stands up an inference server, drives load through it, and benchmarks it with
SLOs that actually matter.

🎯 **Learning objectives** — when this lesson is runnable you'll be able to:

1. Serve a lightweight model with Triton and/or vLLM behind a gateway/router.
2. Run load tests and read the SLOs that matter for inference: **TTFT** (time to
   first token), **p95/p99 latency**, **tokens/sec**, **requests/sec**, GPU
   utilization/memory, and error rate.
3. Contrast inference vs training vs batch workload characteristics, and reason about
   which scheduler (Kubernetes vs Slurm) fits each.

🧭 **Mode:** 🟥 Real GPU. A small model on a single mid-range GPU is enough for
meaningful benchmarking — reuse the Lesson 2 machine.

> **HONESTY MARKER:** benchmark numbers will only ever be published from real GPU
> runs. Anything else in the report is an unloaded template — a number you can't
> reproduce on hardware doesn't belong in a benchmark.

✅ **Evidence (when implemented):** lands in
[`../06-validation-reports/inference-benchmark-report.md`](../06-validation-reports/inference-benchmark-report.md).

➡️ **Next:** [Lesson 6 — BCM-Style Cluster Lifecycle](../05-bcm-style-cluster-lifecycle/README.md).

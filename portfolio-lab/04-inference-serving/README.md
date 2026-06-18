# Lesson 4 - Inference Serving

> Course home: [AI Factory Operations Lab](../../README.md) · Previous:
> [Lesson 3 - Observability](../03-observability/README.md) · Next:
> [Lesson 5 - BCM-Style Cluster Lifecycle](../05-bcm-style-cluster-lifecycle/README.md)

> 🟡 **STATUS: HARNESS RUNNABLE (Phase 5).** The load-test harness is built and
> validated - you can run a full concurrency sweep ($0) against a CPU-served model
> *today* to learn the harness and the SLOs. The harness emits TTFT / TPOT /
> p95-p99 / tokens-per-sec / goodput. **Benchmark *numbers* are only meaningful from
> a real-GPU server** (Lesson 6 machine) - the CPU tier validates the harness, not
> the hardware.

The point of all that scheduling and observability is to *serve something*. This
lesson stands up an inference server, drives load through it, and benchmarks it with
SLOs that actually matter.

🎯 **Learning objectives** - when this lesson is runnable you'll be able to:

1. Serve a lightweight model with Triton and/or vLLM behind a gateway/router.
2. Run load tests and read the SLOs that matter for inference: **TTFT**, **TPOT/ITL**,
   **p95/p99 latency**, **tokens/sec**, **goodput**, GPU utilization/memory, and
   error rate.
3. Explain continuous batching and KV-cache pressure - the two ideas that make LLM
   serving different from classic web serving.
4. Contrast inference vs training vs batch workload characteristics, and reason about
   which scheduler (Kubernetes vs Slurm) fits each.

🧭 **Mode:** 🟦 Simulation/harness for the lesson body - the **$0 CPU tier** runs the
full concurrency sweep on your laptop, no GPU. The 🟥 **real benchmark numbers** come
from one mid-range GPU and are produced **as part of
[Lesson 6 - Real GPU](../real-gpu-session/README.md)**, in the same rental session
(cheap-rental tactics: [the renting guide](../01-k8s-gpu-platform/gpu-operator-real/README.md#renting-the-gpu-cheaply)).

> **Note:** benchmark numbers are only ever published from real GPU runs. Anything
> else in the report is an unloaded template - a number you can't reproduce on
> hardware doesn't belong in a benchmark.

---

## The loop (run this)

**$0 harness-validation tier** (CPU; numbers are NOT a benchmark):

```bash
make phase5-serve-cpu   # Ollama-in-Docker serves a tiny model on CPU (OpenAI-compatible /v1)
make phase5-bench       # sweep concurrency; print TTFT/TPOT/p95-p99/tokens-per-sec/goodput
make phase5-down        # stop the CPU server
```

**Real benchmark tier** (🟥, run in [Lesson 6 - Real GPU](../real-gpu-session/README.md)):
serve a model with vLLM on the rented GPU, then point the same harness at it:

```bash
ENDPOINT=http://<gpu-host>:8000 MODEL=<served-model> make phase5-bench
```

✅ **Checkpoint:** the harness prints a table where, as concurrency rises, **tokens/sec
climbs while ttft_p95 / e2e_p99 degrade** - the throughput-vs-latency trade-off made
visible. The right operating point is the highest concurrency that still meets your
goodput SLO. Raw results are written to `06-validation-reports/evidence/`.

💡 **Why a CPU tier at all:** building a correct load generator (streaming TTFT
capture, percentile math, concurrency control) is real work you shouldn't debug while
paying for a GPU. Validate the harness for free here, then spend the rented GPU hour
*measuring*, not debugging. The harness is
[`harness/loadgen.py`](./harness/loadgen.py) - stdlib only, no pip install.

---

## Concept 1 - The SLO vocabulary

| Metric | Definition | Why it matters |
|---|---|---|
| **TTFT** (time to first token) | Request arrival → first output token | What an interactive user *feels*; dominated by queueing + prefill |
| **TPOT / ITL** (time per output token / inter-token latency) | Average gap between subsequent tokens | Streaming smoothness; dominated by decode throughput |
| **p95/p99 latency** | Tail of end-to-end request latency | SLOs are tail-based; averages hide the pain |
| **Tokens/sec** | Aggregate output throughput | The capacity number; what you provision against |
| **Requests/sec** | Request-level throughput | Only meaningful alongside token lengths |
| **Goodput** | Throughput counting *only* requests that met their SLO | The true number - high tokens/sec with blown p99 is failure |
| **Error rate** | Non-2xx / timeouts / OOM-rejected | The thing batching pushes on when KV cache fills |

💡 **The core tension to demonstrate:** throughput and latency trade off through
batch size. Bigger batches → better tokens/sec (GPU efficiency) → worse TTFT and
ITL for individuals. A benchmark that reports one without the other is marketing.
Phase 5's harness sweeps concurrency and plots both curves.

## Concept 2 - Why LLM serving isn't web serving

1. **Requests are wildly non-uniform:** a 10-token answer and a 2 000-token answer
   differ by 200× in work, so naive load balancing fails.
2. **Continuous batching:** the server admits new requests into the running batch at
   token boundaries instead of waiting for the batch to drain - this is the single
   biggest reason vLLM-class servers beat naive serving by an order of magnitude.
3. **KV cache is the real capacity limit:** each in-flight sequence holds GPU memory
   proportional to its context length. "How many concurrent requests fit" is a
   memory question, not a compute one - which connects straight back to Lesson 3's
   FB_USED panel and the [gpu-memory-pressure runbook](../../runbooks/gpu-memory-pressure.md).

## Concept 3 - Workload shapes, and which scheduler fits

| Property | Inference | Training | Batch/experiments |
|---|---|---|---|
| Lifetime | Long-running service | Days–weeks job | Minutes–hours jobs |
| Demand | Diurnal, spiky | Constant while running | Bursty |
| Failure response | Restart fast, keep SLO | Checkpoint/resume | Re-queue |
| Gang requirement | No (per-replica) | Yes (all ranks or none) | Rarely |
| Natural scheduler | Kubernetes (+ sharing, Lesson 1C) | Slurm or K8s+KAI gang (1B/3) | Either, queue-policy driven |

This table is the course's capstone argument: Lessons 1–2 weren't scheduler
trivia - they were the decision framework for *placing* these three shapes.

## What's in this directory

- [`harness/loadgen.py`](./harness/loadgen.py) - the concurrency-sweeping load
  generator (stdlib only): streaming TTFT capture, TPOT, p50/p95/p99, tokens-per-sec,
  goodput-at-SLO.
- [`harness/run-bench.sh`](./harness/run-bench.sh) - wraps it, writes raw results to
  the evidence tree. Override `ENDPOINT` / `MODEL` / `CONCURRENCY`.
- [`scripts/serve-cpu.sh`](./scripts/serve-cpu.sh) - the $0 Ollama-on-CPU server for
  harness validation; [`scripts/down.sh`](./scripts/down.sh) stops it.

**Still to come (needs the GPU run):** a committed throughput-vs-latency plot from
real vLLM numbers, and the [Lesson 1C](../01-k8s-gpu-platform/hami/README.md) tie-in -
two model replicas sharing one GPU via HAMi slices vs one dedicated replica,
measuring what sharing costs in p99.

✅ **Evidence (when implemented):** lands in
[`../06-validation-reports/inference-benchmark-report.md`](../06-validation-reports/inference-benchmark-report.md).

🔬 **Sim vs real:** there is no meaningful simulation tier for benchmark *numbers* -
this lesson is 🟥 by nature. What you can do for free now: the concepts above, the
harness code, and the dashboard panels (Lesson 3) that will receive the metrics.

➡️ **Next:** [Lesson 5 - BCM-Style Cluster Lifecycle](../05-bcm-style-cluster-lifecycle/README.md).

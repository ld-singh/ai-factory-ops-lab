# Lesson 3B - Inference observability

> Part of [Lesson 3 - GPU Observability](../README.md) · Course home:
> [AI Factory Operations Lab](../../../README.md). Best read after
> [Lesson 4A](../../04-inference-serving/README.md) (for the TTFT / TPOT / goodput vocabulary).

> ✅ **STATUS: RUNNABLE.** A synthetic vLLM metrics exporter, the token-SLO queries, and the
> alert rules all run on your laptop, free. The numbers are fabricated, so this proves
> dashboard and alert **design**; real inference telemetry comes from a real vLLM server
> ([Lesson 6](../../real-gpu-session/README.md)).

Lesson 3 watched the **GPU** (DCGM: utilization, memory, temperature). That tells you the card
is busy, not whether you are **serving well**. Inference observability is the other half: the
**token-level SLOs** you actually page on, TTFT, TPOT, goodput, queue depth, KV cache usage,
read from the serving layer's own metrics. You build the pipeline (scrape, dashboard, alert)
here for free, then point it at a real vLLM server later.

🎯 **Learning objectives** - you'll be able to:

1. Name the vLLM metrics that matter and what each one tells an operator.
2. Turn raw metrics into **SLOs** with PromQL: p95 TTFT from a histogram, goodput, tokens/sec,
   queue depth, KV cache usage, prefix-hit rate.
3. Write **inference SLO alerts** and trip them on purpose with a saturation drill.
4. Explain why GPU-busy and serving-well are different questions that need different dashboards.

🧭 **Mode:** 🟦 Free, no GPU. Synthetic metrics with the real vLLM names, the same Prometheus /
Grafana stack as Lesson 3. 🟥 A real vLLM server (Lesson 6) swaps the exporter for the real
`/metrics`; the dashboards and alerts are unchanged.

📋 **Prerequisites:** [Lesson 3](../README.md) (the Prometheus/Grafana stack and the break-it
drill), and the [Lesson 4A](../../04-inference-serving/README.md) vocabulary (TTFT, TPOT,
goodput). [Lesson 4B](../../04-inference-serving/kv-cache/README.md) explains the KV cache this
lesson watches fill.

---

## The vLLM metrics that matter

vLLM exposes Prometheus metrics (the `vllm:` family) on its API port. Names shift between
versions, so confirm against the vLLM you run:
[vLLM metrics docs](https://docs.vllm.ai/en/latest/serving/metrics.html).

| Metric | Type | What it tells you |
|---|---|---|
| `vllm:num_requests_running` | gauge | requests in the running batch right now |
| `vllm:num_requests_waiting` | gauge | requests **queued** for a slot: the backpressure signal |
| `vllm:gpu_cache_usage_perc` | gauge | KV cache in use (0..1); near 1.0 means capacity |
| `vllm:time_to_first_token_seconds` | histogram | TTFT distribution: take p95 for the interactive SLO |
| `vllm:time_per_output_token_seconds` | histogram | TPOT/ITL: streaming smoothness |
| `vllm:e2e_request_latency_seconds` | histogram | whole-request latency |
| `vllm:generation_tokens_total` | counter | output tokens: `rate()` it for tokens/sec |
| `vllm:request_success_total` / `vllm:request_failure_total` | counter | for goodput / error rate |
| `vllm:num_preemptions_total` | counter | requests evicted under KV pressure: the memory limit biting |
| `vllm:prefix_cache_hits_total` / `vllm:prefix_cache_queries_total` | counter | prefix-cache hit rate |

---

## Hands-on: run the synthetic exporter

[`fake-vllm-exporter/app.py`](fake-vllm-exporter/app.py) serves those exact metric names with
synthetic, scenario-driven values (stdlib, no install), the same idea as Lesson 3's fake DCGM
exporter.

```bash
cd portfolio-lab/03-observability/inference-observability/fake-vllm-exporter
python3 app.py           # serves on :8000/metrics
# in another terminal:
curl -s localhost:8000/metrics | grep -vE '^#' | head
```

```
vllm:num_requests_running{model_name="Qwen/Qwen2.5-7B-Instruct"} 6
vllm:num_requests_waiting{model_name="Qwen/Qwen2.5-7B-Instruct"} 0
vllm:gpu_cache_usage_perc{model_name="Qwen/Qwen2.5-7B-Instruct"} 0.35
vllm:generation_tokens_total{model_name="Qwen/Qwen2.5-7B-Instruct"} 2911
vllm:num_preemptions_total{model_name="Qwen/Qwen2.5-7B-Instruct"} 0
vllm:time_to_first_token_seconds_bucket{model_name="Qwen/Qwen2.5-7B-Instruct",le="0.5"} 16
```

✅ **Checkpoint:** you have vLLM-shaped metrics on `:8000/metrics`, with cumulative histogram
buckets (`..._bucket`, `..._sum`, `..._count`) ready for `histogram_quantile`.

---

## From metrics to SLOs (the queries)

Metrics are raw; SLOs are the questions you actually ask. These are the PromQL panels of an
inference dashboard:

```promql
# p95 TTFT (the interactive SLO) - from the histogram
histogram_quantile(0.95, sum(rate(vllm:time_to_first_token_seconds_bucket[5m])) by (le))

# p95 TPOT (streaming smoothness)
histogram_quantile(0.95, sum(rate(vllm:time_per_output_token_seconds_bucket[5m])) by (le))

# throughput: output tokens/sec
sum(rate(vllm:generation_tokens_total[5m]))

# goodput proxy: success share
sum(rate(vllm:request_success_total[5m]))
  / sum(rate(vllm:request_success_total[5m]) + rate(vllm:request_failure_total[5m]))

# queue depth and KV pressure (raw gauges)
vllm:num_requests_waiting
vllm:gpu_cache_usage_perc

# prefix-cache hit rate
sum(rate(vllm:prefix_cache_hits_total[5m])) / sum(rate(vllm:prefix_cache_queries_total[5m]))
```

> 💡 The one to internalize: **`num_requests_waiting` rising while `tok/s` is flat** is
> saturation. Throughput looks fine, but users are queuing. That is the inference version of the
> Lesson 4A goodput cliff, seen from the server side.

---

## Inference SLO alerts

[`manifests/inference-alerts.yaml`](manifests/inference-alerts.yaml) is a `PrometheusRule` (same
shape as Lesson 3's `gpu-alerts`) with the token-level alerts:

| Alert | Fires when |
|---|---|
| `InferenceTTFTSLOBreached` | p95 TTFT over 1s |
| `InferenceErrorRateHigh` | failure share over 1% |
| `InferenceQueueBacklog` | `num_requests_waiting` over 20 |
| `InferenceKVCacheNearFull` | `gpu_cache_usage_perc` over 0.95 |
| `InferencePreemptions` | any preemptions happening (KV ran out) |
| `VLLMMetricsAbsent` | the `vllm:` metrics stop being scraped |

Each carries a `runbook` annotation, the same discipline as Lesson 3: an alert is only as good
as the runbook it points to.

## Break it on purpose

The point of the lesson: make the alerts fire.

```bash
# drive the server into saturation
curl -XPOST localhost:8000/scenario?name=saturation
```

Watch it land: `num_requests_waiting` jumps to ~90, `gpu_cache_usage_perc` hits ~0.98,
`num_preemptions_total` starts climbing, and p95 TTFT blows past 1s. In a wired-up stack the
`InferenceQueueBacklog`, `InferenceKVCacheNearFull`, `InferencePreemptions`, and
`InferenceTTFTSLOBreached` alerts move to firing. Flip back with `?name=normal` (or `?name=ramp`
for a healthy busy state).

---

## What you proved, and what you did not

**Proved (free):** the inference observability pipeline, the metrics that matter, the SLO
queries, and alerts that fire under saturation. The design is correct regardless of whether the
numbers are real.

**Not proved here:** real serving behaviour. The values are synthetic. Pointed at a real vLLM
server (Lesson 6), the **same** dashboards and alerts read live TTFT/TPOT, real KV cache usage,
and real preemptions; capturing that is the real-GPU half.

## What's in this directory

- [`fake-vllm-exporter/app.py`](fake-vllm-exporter/app.py) - synthetic vLLM metrics (stdlib),
  with a `/scenario` endpoint for the break-it drill.
- [`manifests/inference-alerts.yaml`](manifests/inference-alerts.yaml) - the inference SLO
  `PrometheusRule`.

➡️ **Next:** back to [Lesson 3](../README.md), or the inference lessons that supply the
vocabulary and the KV cache this watches: [Lesson 4A](../../04-inference-serving/README.md) and
[Lesson 4B](../../04-inference-serving/kv-cache/README.md).

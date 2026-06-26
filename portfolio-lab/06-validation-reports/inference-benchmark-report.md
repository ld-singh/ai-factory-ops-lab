# Inference Benchmark Report

> 🟡 STATUS: RUNNABLE - fill this in from a real GPU run (Lesson 6 Part C). Serve a model
> with `make phase5-serve-gpu`, run `make phase5-bench` / `phase5-overload` against it, and
> record the numbers below. Benchmark numbers are only meaningful from the real GPU run.

## Environment (fill in)

| | |
|---|---|
| GPU | (e.g. RTX A6000 48 GB, Hyperstack) |
| Model served | (e.g. `Qwen/Qwen2.5-0.5B-Instruct` via vLLM) |
| vLLM image | `vllm/vllm-openai:latest` (record the resolved version) |
| Date | |

## Concurrency sweep (`make phase5-bench`)

Paste the harness table. Expected shape: as concurrency rises, `tok/s` climbs while
`ttft_p95` / `e2e_p99` degrade, and `goodput%` holds until the knee.

```
(paste conc / gen / ttft_p95 / e2e_p99 / tok/s / goodput% table here)
```

## Overload - the knee (`make phase5-overload`)

```
(paste the high-concurrency sweep; note the concurrency where goodput% falls off)
```

**Operating point:** the highest concurrency that still met the TTFT SLO — _____.

## What this proves

Real single-GPU serving throughput and latency under load, and where this card/model
saturates. It does **not** prove multi-node scale, NVLink/topology effects, or sharing
performance under sustained load. Ledger: [`fake-vs-real-limitations.md`](./fake-vs-real-limitations.md).

# Inference Benchmark Report

> ✅ STATUS: VALIDATED - captured on a real NVIDIA RTX A6000 (48 GB), 2026-06-27. Served with
> vLLM and driven by the Lesson 4 harness (`make phase5-bench` and drills). Benchmark numbers
> are only meaningful from the real GPU run; these are it.

## Environment

| | |
|---|---|
| GPU | NVIDIA RTX A6000 (48 GB) |
| Model served | `Qwen/Qwen2.5-7B-Instruct` via vLLM (served name `local`) |
| vLLM | `vllm/vllm-openai:latest` (v0.23.0) on k3s, `runtimeClassName: nvidia`, `nvidia.com/gpu: 1` |
| Harness | `portfolio-lab/04-inference-serving/harness/loadgen.py` (stdlib) |
| Date | 2026-06-27 |

## Baseline sweep (`make phase5-bench`)

```
 conc  reqs  err  gen  ttft_p50  ttft_p95  tpot_p50  e2e_p95  e2e_p99   tok/s  goodput%
    1    12    0   53     0.047     1.121    0.0219    2.261    2.640    42.3    100.0
    2    12    0   51     0.067     0.068    0.0220    1.378    1.423    84.0    100.0
    4    12    0   51     0.067     0.068    0.0221    1.316    1.335   153.1    100.0
    8    12    0   51     0.171     0.177    0.0223    1.357    1.381   240.4    100.0
```

`tok/s` scales cleanly (42 → 240) with goodput pinned at 100% - plenty of headroom at this load.
(The conc-1 `ttft_p95` value is first-request warmup.)

## Saturation - the knee (`CONCURRENCY=64,128,256,512 REQUESTS_PER_LEVEL=512`)

```
 conc  reqs  err  gen  ttft_p50  ttft_p95  tpot_p50  e2e_p95  e2e_p99    tok/s  goodput%
   64   512    0   51     0.087     0.163    0.0275    1.678    1.792   2127.6    100.0
  128   512    0   52     0.126     0.325    0.0360    2.291    2.421   3138.1    100.0
  256   512    0   52     0.299     0.517    0.0531    3.535    3.784   4039.9    100.0
  512   512    0   52     1.043     3.564    0.0564    5.828    5.946   3896.1     50.0
```

**Operating point: conc 256** (~4040 tok/s at 100% goodput). Throughput peaks there and *falls*
at conc512 (3896 tok/s) while `ttft_p95` spikes 0.52s → 3.56s and `goodput` cliffs to 50%. Past
the knee, more load buys no throughput and halves the SLO - the classic throughput-vs-latency
trade-off, on real hardware.

## Supporting drills

- **Continuous batching** (`make phase5-batching`): a short request's `ttft_p95` rose only
  **0.053s → 0.069s (1.3x)** with eight long requests in flight - versus ~50x for the same drill
  on the CPU tier. That ratio is the measured value of continuous batching (vLLM admits new
  requests into the running batch instead of queueing them).
- **Prefill** (`make phase5-prefill`): `ttft_p95` rose 0.049s → 0.150s as input grew 16 → 1024
  tokens; `tpot` stayed ~0.022s. Input length is a TTFT (prefill) cost.
- **Decode** (`make phase5-decode`): `e2e` grew with generated tokens while `tpot` (~0.022s) and
  `ttft` stayed flat - `e2e ≈ ttft + tpot × gen`. Output length is a duration cost.

## What this proves - and does not

Proves real single-GPU serving for this card+model: throughput scaling, the saturation knee and
operating point, continuous batching protecting TTFT, and the prefill/decode split - all in real
numbers. It does **not** prove multi-replica routing, multi-node scale, NVLink/topology effects,
or sharing-performance under sustained load. Ledger:
[`fake-vs-real-limitations.md`](./fake-vs-real-limitations.md).

#!/usr/bin/env python3
"""loadgen — a concurrency-sweeping load generator for OpenAI-compatible
inference endpoints (vLLM, llama.cpp server, Ollama's /v1, etc.).

It measures the SLOs that actually matter for LLM serving:
  - TTFT   time to first token (streaming)
  - TPOT   time per output token (a.k.a. inter-token latency)
  - e2e    end-to-end request latency (p50/p95/p99)
  - tokens/sec aggregate output throughput
  - goodput requests that met a TTFT SLO

It sweeps a list of concurrency levels and prints a table plus the
throughput-vs-latency trade-off, which is the whole point: bigger batches buy
throughput at the cost of per-request latency.

HONESTY MARKER: numbers are only a *benchmark* when produced against a real GPU
server (Lesson 2 machine). Run against a CPU-served model first only to validate
that this harness works end to end — those numbers are meaningless as a benchmark.

Stdlib only (urllib + threads) so it runs anywhere with no pip install.
"""
import argparse
import json
import statistics
import sys
import threading
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

PROMPT = "Explain what a GPU scheduler does, in two sentences."


def stream_request(base_url, model, ttft_slo_s, max_tokens):
    """Fire one streaming chat completion; return per-request metrics."""
    url = base_url.rstrip("/") + "/v1/chat/completions"
    body = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": PROMPT}],
        "stream": True,
        "max_tokens": max_tokens,
        "temperature": 0.7,
    }).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})

    start = time.perf_counter()
    ttft = None
    token_times = []
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            for raw in resp:
                line = raw.decode("utf-8", "ignore").strip()
                if not line or not line.startswith("data:"):
                    continue
                payload = line[len("data:"):].strip()
                if payload == "[DONE]":
                    break
                now = time.perf_counter()
                if ttft is None:
                    ttft = now - start
                token_times.append(now)
        end = time.perf_counter()
        n_tokens = max(len(token_times), 1)
        tpot = ((end - start) - (ttft or 0)) / max(n_tokens - 1, 1)
        return {
            "ok": True, "ttft": ttft if ttft is not None else (end - start),
            "e2e": end - start, "tpot": tpot, "tokens": n_tokens,
            "met_slo": (ttft is not None and ttft <= ttft_slo_s),
        }
    except Exception as e:  # noqa: BLE001 — record, don't crash the sweep
        return {"ok": False, "error": str(e), "e2e": time.perf_counter() - start}


def pct(values, p):
    if not values:
        return float("nan")
    return statistics.quantiles(values, n=100)[p - 1] if len(values) > 1 else values[0]


def run_level(base_url, model, concurrency, requests, ttft_slo_s, max_tokens):
    results = []
    wall_start = time.perf_counter()
    with ThreadPoolExecutor(max_workers=concurrency) as pool:
        futs = [pool.submit(stream_request, base_url, model, ttft_slo_s, max_tokens)
                for _ in range(requests)]
        for f in as_completed(futs):
            results.append(f.result())
    wall = time.perf_counter() - wall_start

    ok = [r for r in results if r.get("ok")]
    errs = len(results) - len(ok)
    ttfts = sorted(r["ttft"] for r in ok)
    e2es = sorted(r["e2e"] for r in ok)
    tpots = sorted(r["tpot"] for r in ok)
    total_tokens = sum(r["tokens"] for r in ok)
    goodput = sum(1 for r in ok if r["met_slo"])

    return {
        "concurrency": concurrency, "requests": requests, "errors": errs,
        "ttft_p50": pct(ttfts, 50), "ttft_p95": pct(ttfts, 95),
        "e2e_p50": pct(e2es, 50), "e2e_p95": pct(e2es, 95), "e2e_p99": pct(e2es, 99),
        "tpot_p50": pct(tpots, 50),
        "tokens_per_s": total_tokens / wall if wall > 0 else 0,
        "req_per_s": len(results) / wall if wall > 0 else 0,
        "goodput_pct": 100.0 * goodput / len(results) if results else 0,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--url", default="http://localhost:8000", help="OpenAI-compatible base URL")
    ap.add_argument("--model", default="local", help="model name the server expects")
    ap.add_argument("--concurrency", default="1,2,4,8", help="comma list of concurrency levels")
    ap.add_argument("--requests-per-level", type=int, default=16)
    ap.add_argument("--ttft-slo", type=float, default=1.0, help="TTFT SLO in seconds for goodput")
    ap.add_argument("--max-tokens", type=int, default=128)
    ap.add_argument("--json-out", default="", help="optional path to write raw results JSON")
    args = ap.parse_args()

    levels = [int(x) for x in args.concurrency.split(",") if x.strip()]
    print(f"Target: {args.url}  model={args.model}  TTFT-SLO={args.ttft_slo}s")
    print("!! Numbers are a real benchmark ONLY against a real-GPU server (Lesson 2). !!\n")
    hdr = ("conc", "reqs", "err", "ttft_p50", "ttft_p95", "e2e_p95", "e2e_p99",
           "tok/s", "req/s", "goodput%")
    print("{:>4} {:>5} {:>4} {:>9} {:>9} {:>8} {:>8} {:>8} {:>7} {:>9}".format(*hdr))

    all_rows = []
    for c in levels:
        row = run_level(args.url, args.model, c, args.requests_per_level,
                        args.ttft_slo, args.max_tokens)
        all_rows.append(row)
        print("{:>4} {:>5} {:>4} {:>9.3f} {:>9.3f} {:>8.3f} {:>8.3f} {:>8.1f} {:>7.2f} {:>9.1f}".format(
            row["concurrency"], row["requests"], row["errors"], row["ttft_p50"],
            row["ttft_p95"], row["e2e_p95"], row["e2e_p99"], row["tokens_per_s"],
            row["req_per_s"], row["goodput_pct"]))

    print("\nRead it as a trade-off: as concurrency rises, tok/s should climb while")
    print("ttft_p95 / e2e_p99 degrade. The right operating point is the highest")
    print("concurrency that still meets your goodput SLO.")

    if args.json_out:
        with open(args.json_out, "w") as fh:
            json.dump(all_rows, fh, indent=2)
        print(f"\nWrote raw results to {args.json_out}")


if __name__ == "__main__":
    sys.exit(main())

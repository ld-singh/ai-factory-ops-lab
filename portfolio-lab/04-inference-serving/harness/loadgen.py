#!/usr/bin/env python3
"""loadgen - a load generator for OpenAI-compatible inference endpoints
(vLLM, llama.cpp server, Ollama's /v1, etc.) that makes the *behaviour* of LLM
serving observable, not just the headline throughput number.

It measures the SLOs that actually matter for LLM serving:
  - TTFT   time to first token (streaming)        -> dominated by queueing + prefill
  - TPOT   time per output token (inter-token)     -> dominated by decode throughput
  - e2e    end-to-end request latency (p50/p95/p99)
  - tokens/sec aggregate output throughput
  - goodput requests that met a TTFT SLO

Two modes:
  --mode sweep  : vary one axis (concurrency | input length | output length) and
                  watch the trade-off curve. This is the core drill.
  --mode mixed  : run short requests alone, then again while long requests hog the
                  running batch - so you *see* continuous batching interfere with
                  an interactive request's TTFT.

The behaviour these curves show (TTFT rising with input length, e2e with output
length, goodput collapsing past the knee) is the same on any hardware, so you
learn it on CPU for free. Point the same harness at a real GPU (Lesson 6) when
you want throughput numbers for a specific card.

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

SHORT_PROMPT = "Explain what a GPU scheduler does, in two sentences."

# For the OUTPUT-length sweep we need the model to keep generating until the token cap
# actually bites (a normal prompt hits end-of-sequence early, so raising max_tokens would
# change nothing). A counting prompt rarely wants to stop, so output length ~= the cap.
COUNT_PROMPT = "Count upward from 1, writing one number per line. Keep going and do not stop."

# Filler words used to build a prompt of an approximate length, for the input-length
# (prefill) sweep. Length is what matters here, not meaning.
_FILLER = ("gpu scheduler memory bandwidth kernel batching latency throughput tensor "
           "core occupancy prefill decode kv cache token replica goodput percentile").split()


def build_prompt(approx_tokens):
    """Return a prompt of roughly `approx_tokens` tokens (0 / None -> the short default).

    Uses a crude ~0.75-tokens-per-word heuristic. It only needs to be *monotone* -
    longer asks for more prefill work - not exact; real tokenization varies by model.
    """
    if not approx_tokens:
        return SHORT_PROMPT
    words_needed = max(1, int(approx_tokens / 0.75))
    words = (_FILLER * (words_needed // len(_FILLER) + 1))[:words_needed]
    return "Summarize this note in one short sentence: " + " ".join(words)


def stream_request(base_url, model, ttft_slo_s, max_tokens, prompt, e2e_slo_s=0):
    """Fire one streaming chat completion; return per-request metrics.

    A request counts toward goodput if its TTFT meets ttft_slo_s AND (when e2e_slo_s > 0)
    its end-to-end time meets e2e_slo_s. The e2e gate is what catches throughput
    saturation - under continuous batching TTFT can stay low while total time degrades.
    """
    url = base_url.rstrip("/") + "/v1/chat/completions"
    body = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "stream": True,
        "max_tokens": max_tokens,
        "temperature": 0.7,
    }).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})

    start = time.perf_counter()
    ttft = None
    token_times = []
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
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
        e2e = end - start
        met = (ttft is not None and ttft <= ttft_slo_s) and (e2e_slo_s <= 0 or e2e <= e2e_slo_s)
        return {
            "ok": True, "ttft": ttft if ttft is not None else e2e,
            "e2e": e2e, "tpot": tpot, "tokens": n_tokens, "met_slo": met,
        }
    except Exception as e:  # noqa: BLE001 - record, don't crash the sweep
        return {"ok": False, "error": str(e), "e2e": time.perf_counter() - start}


def pct(values, p):
    if not values:
        return float("nan")
    return statistics.quantiles(values, n=100)[p - 1] if len(values) > 1 else values[0]


def summarize(results, wall):
    """Aggregate a list of per-request results into one row of SLO numbers."""
    ok = [r for r in results if r.get("ok")]
    errs = len(results) - len(ok)
    ttfts = sorted(r["ttft"] for r in ok)
    e2es = sorted(r["e2e"] for r in ok)
    tpots = sorted(r["tpot"] for r in ok)
    total_tokens = sum(r["tokens"] for r in ok)
    goodput = sum(1 for r in ok if r["met_slo"])
    sample_error = next((r.get("error") for r in results if not r.get("ok")), None)
    gens = sorted(r["tokens"] for r in ok)
    return {
        "requests": len(results), "errors": errs, "sample_error": sample_error,
        "gen_p50": int(statistics.median(gens)) if gens else 0,
        "ttft_p50": pct(ttfts, 50), "ttft_p95": pct(ttfts, 95),
        "tpot_p50": pct(tpots, 50),
        "e2e_p95": pct(e2es, 95), "e2e_p99": pct(e2es, 99),
        "tokens_per_s": total_tokens / wall if wall > 0 else 0,
        "goodput_pct": 100.0 * goodput / len(results) if results else 0,
    }


def run_level(base_url, model, concurrency, requests, ttft_slo_s, max_tokens, prompt, e2e_slo_s=0):
    """Run `requests` requests at a fixed concurrency; return one summary row."""
    results = []
    wall_start = time.perf_counter()
    with ThreadPoolExecutor(max_workers=concurrency) as pool:
        futs = [pool.submit(stream_request, base_url, model, ttft_slo_s, max_tokens, prompt, e2e_slo_s)
                for _ in range(requests)]
        for f in as_completed(futs):
            results.append(f.result())
    return summarize(results, time.perf_counter() - wall_start)


HDR = ("axis", "reqs", "err", "gen", "ttft_p50", "ttft_p95", "tpot_p50",
       "e2e_p95", "e2e_p99", "tok/s", "goodput%")
ROW_FMT = "{:>9} {:>5} {:>4} {:>5} {:>9.3f} {:>9.3f} {:>9.4f} {:>8.3f} {:>8.3f} {:>8.1f} {:>9.1f}"


def print_header(axis_label):
    cols = (axis_label,) + HDR[1:]
    print("{:>9} {:>5} {:>4} {:>5} {:>9} {:>9} {:>9} {:>8} {:>8} {:>8} {:>9}".format(*cols))


def print_row(axis_value, row):
    print(ROW_FMT.format(axis_value, row["requests"], row["errors"], row["gen_p50"],
                         row["ttft_p50"], row["ttft_p95"], row["tpot_p50"], row["e2e_p95"],
                         row["e2e_p99"], row["tokens_per_s"], row["goodput_pct"]))


def first(int_list):
    return int_list[0]


def parse_ints(s):
    return [int(x) for x in str(s).split(",") if str(x).strip()]


def do_sweep(args):
    axis = args.sweep
    conc = parse_ints(args.concurrency)
    inputs = parse_ints(args.input_tokens) if args.input_tokens else [0]
    outputs = parse_ints(args.max_tokens)

    intro = {
        "concurrency": ("'conc' = how many requests hit the server AT THE SAME TIME (1, then 2,\n"
                        "         4, 8 - like 1/2/4/8 simultaneous users). Each row fires the same\n"
                        "         total requests, just more of them at once."),
        "input": "'in_tok' = approx PROMPT length. Bigger prompt = more prefill work.",
        "output": "'out_tok' = OUTPUT length cap. More tokens = more decode steps.",
    }[axis]
    slo = f"TTFT-SLO={args.ttft_slo}s" + (f" + e2e-SLO={args.e2e_slo}s" if args.e2e_slo > 0 else "")
    print(f"Target: {args.url}  model={args.model}  mode=sweep:{axis}  {slo}")
    print(f"Reading: {intro}\n")
    print_header({"concurrency": "conc", "input": "in_tok", "output": "out_tok"}[axis])

    e2e = args.e2e_slo
    all_rows = []
    if axis == "concurrency":
        prompt = build_prompt(first(inputs)); mt = first(outputs)
        for c in conc:
            # Each level must fire at least `c` requests, or the pool never reaches concurrency
            # c and the row is meaningless (you'd be testing min(requests, c) in flight).
            reqs = max(args.requests_per_level, c)
            row = run_level(args.url, args.model, c, reqs, args.ttft_slo, mt, prompt, e2e)
            row["axis"] = c; all_rows.append(row); print_row(c, row)
    elif axis == "input":
        c = first(conc); mt = first(outputs)
        for n in inputs:
            row = run_level(args.url, args.model, c, args.requests_per_level,
                            args.ttft_slo, mt, build_prompt(n), e2e)
            row["axis"] = n; all_rows.append(row); print_row(n, row)
    else:  # output
        c = first(conc); prompt = COUNT_PROMPT  # forces generation up to the token cap
        for mt in outputs:
            row = run_level(args.url, args.model, c, args.requests_per_level,
                            args.ttft_slo, mt, prompt, e2e)
            row["axis"] = mt; all_rows.append(row); print_row(mt, row)

    takeaway = {
        "concurrency": [
            "Takeaway: as concurrency rises, the server pushes more total tokens (tok/s up)",
            "but each request waits longer (ttft_p95 / e2e_p99 up) - the throughput-vs-latency",
            "trade-off. 'goodput%' is the share of requests that still beat the TTFT SLO",
            f"({args.ttft_slo}s). Your capacity = the highest concurrency where goodput stays high;",
            "past that you're serving more requests but serving them worse.",
        ],
        "input": [
            "Takeaway: longer prompts push ttft up (the model must read the whole prompt before",
            "the first token = prefill) while tpot stays ~flat. Input length is a TTFT cost.",
        ],
        "output": [
            "Takeaway: watch the 'gen' column - that's tokens actually generated (the cap only",
            "bites if the model doesn't stop first). As gen grows: 'e2e' grows with it (more",
            "tokens = more decode steps) while 'tpot' stays ~FLAT and 'ttft' stays ~flat. tpot is",
            "a steady PER-token cost; output length is a total-DURATION cost, not a per-token or",
            "TTFT one. Rule of thumb: e2e ~= ttft + tpot * gen.",
        ],
    }[axis]
    print("\n" + "\n".join(takeaway))
    return all_rows


def do_mixed(args):
    """Drill 1: make continuous batching observable.

    Phase A: run short interactive requests alone.
    Phase B: run the SAME short requests while `--long-count` long-output requests
    are in flight, hogging the running batch. The short request's TTFT inflates -
    that gap is continuous batching / queueing you can watch, not just read about.
    """
    short_prompt = build_prompt(0)
    long_prompt = build_prompt(0)
    print(f"Target: {args.url}  model={args.model}  mode=mixed  TTFT-SLO={args.ttft_slo}s")
    print("Drill: short requests alone, then again behind long-output requests.\n")

    print("Phase A - short requests alone:")
    a = run_level(args.url, args.model, args.concurrency_mixed, args.requests_per_level,
                  args.ttft_slo, args.short_tokens, short_prompt)
    print_header("phase"); print_row("A-alone", a)

    print(f"\nPhase B - same short requests + {args.long_count} long ({args.long_tokens}-tok) in flight:")
    longs = []
    pool = ThreadPoolExecutor(max_workers=args.long_count)
    for _ in range(args.long_count):
        longs.append(pool.submit(stream_request, args.url, args.model,
                                 args.ttft_slo, args.long_tokens, long_prompt))
    time.sleep(0.5)  # let the long requests enter the batch first
    b = run_level(args.url, args.model, args.concurrency_mixed, args.requests_per_level,
                  args.ttft_slo, args.short_tokens, short_prompt)
    print_row("B-loaded", b)
    pool.shutdown(wait=True)  # let the long requests drain

    infl = (b["ttft_p95"] / a["ttft_p95"]) if a["ttft_p95"] else float("nan")
    print(f"\nShort-request ttft_p95 went {a['ttft_p95']:.3f}s -> {b['ttft_p95']:.3f}s "
          f"({infl:.1f}x) when the server filled with long requests.")
    print("A request's latency is not its own - it depends on what else is in flight.")
    print("Continuous batching is how production servers (vLLM) keep this in check: new")
    print("requests are admitted into the running batch instead of queueing behind it.")
    print("Run this drill on a GPU (Lesson 6) to measure how much it buys back.")
    return [{"phase": "A", **a}, {"phase": "B", **b}]


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url", default="http://localhost:8000", help="OpenAI-compatible base URL")
    ap.add_argument("--model", default="local", help="model name the server expects")
    ap.add_argument("--mode", choices=["sweep", "mixed"], default="sweep")
    ap.add_argument("--sweep", choices=["concurrency", "input", "output"], default="concurrency",
                    help="which axis to vary in --mode sweep")
    ap.add_argument("--concurrency", default="1,2,4,8", help="comma list (sweep=concurrency)")
    ap.add_argument("--input-tokens", default="", help="comma list of approx prompt tokens (sweep=input)")
    ap.add_argument("--max-tokens", default="128", help="comma list of output tokens (sweep=output)")
    ap.add_argument("--requests-per-level", type=int, default=16)
    ap.add_argument("--ttft-slo", type=float, default=1.0, help="TTFT SLO in seconds for goodput")
    ap.add_argument("--e2e-slo", type=float, default=0.0,
                    help="optional end-to-end latency SLO (s); 0 = off. Add this to make goodput "
                         "reflect throughput saturation, which TTFT alone misses.")
    # mixed-mode knobs:
    ap.add_argument("--concurrency-mixed", type=int, default=2, help="short-request concurrency (mixed)")
    ap.add_argument("--short-tokens", type=int, default=32, help="output tokens for short requests (mixed)")
    ap.add_argument("--long-tokens", type=int, default=512, help="output tokens for the long batch (mixed)")
    ap.add_argument("--long-count", type=int, default=4, help="how many long requests in flight (mixed)")
    ap.add_argument("--json-out", default="", help="optional path to write raw results JSON")
    args = ap.parse_args()

    rows = do_mixed(args) if args.mode == "mixed" else do_sweep(args)

    # Surface errors loudly: an all-NaN table almost always means every request failed
    # (wrong --model, server down), not a measurement of zero.
    total_err = sum(r.get("errors", 0) for r in rows)
    if total_err:
        sample = next((r.get("sample_error") for r in rows if r.get("sample_error")), None)
        print(f"\n⚠  {total_err} request(s) errored - NaNs above mean no successful samples.")
        if sample:
            print(f"   First error: {sample}")
        print("   Check: --model matches the served model (serve-cpu.sh serves qwen2:0.5b),")
        print("   the server is up, and --url is correct.")

    if args.json_out:
        with open(args.json_out, "w") as fh:
            json.dump(rows, fh, indent=2)
        print(f"\nWrote raw results to {args.json_out}")


if __name__ == "__main__":
    sys.exit(main())

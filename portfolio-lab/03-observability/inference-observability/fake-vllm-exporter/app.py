#!/usr/bin/env python3
"""fake-vllm-exporter - emit vLLM-shaped Prometheus metrics with NO GPU.

Why this exists
---------------
Lesson 3 taught GPU (DCGM) observability. This expansion (3B) is INFERENCE
observability: the token-level SLOs you actually alert on when serving an LLM. As
with the fake DCGM exporter, dashboards and alert rules are just queries and
thresholds, they are correct or not regardless of whether the numbers are real. So
we serve metrics with the real vLLM metric names (the `vllm:` family) and synthetic,
scenario-driven values, so you can build the token-SLO dashboard + alerts and trip
them on purpose, on your laptop, free.

SCOPE NOTE: every value here is fabricated. A dashboard built on this proves
dashboard/alert DESIGN only. Real inference telemetry comes from a real vLLM server
(Lesson 6's hardware run stands one up). Metric names follow vLLM's documented
Prometheus set, but names shift between versions, so CONFIRM against the vLLM you run:
https://docs.vllm.ai/en/latest/serving/metrics.html

The synthetic model is deliberately *interesting*: a healthy baseline, and a
`saturation` scenario (POST /scenario) where the queue grows, TTFT's tail balloons,
the KV cache fills, preemptions climb, and goodput falls, so the break-it drill trips
the inference SLO alerts on demand.
"""
import os
import random
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MODEL = os.environ.get("MODEL_NAME", "Qwen/Qwen2.5-7B-Instruct")

# Histogram bucket boundaries (seconds). Cumulative "le" buckets, plus +Inf.
TTFT_BUCKETS = [0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0]
TPOT_BUCKETS = [0.01, 0.025, 0.05, 0.1, 0.25, 0.5]
E2E_BUCKETS = [0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0]

# Per-scenario behaviour: (completions/sec, running, waiting, kv_usage 0..1,
#   ttft_typical_s, ttft_tail_frac, tpot_typical_s, gen_tokens, fail_frac, preempt/sec)
SCENARIOS = {
    "normal":     dict(rate=8.0,  running=6,   waiting=0,   kv=0.35, ttft=0.3, tail=0.02, tpot=0.03, gen=180, fail=0.0,  preempt=0.0),
    "ramp":       dict(rate=14.0, running=32,  waiting=4,   kv=0.72, ttft=0.6, tail=0.08, tpot=0.04, gen=200, fail=0.0,  preempt=0.0),
    "saturation": dict(rate=9.0,  running=64,  waiting=90,  kv=0.98, ttft=3.5, tail=0.55, tpot=0.06, gen=210, fail=0.03, preempt=1.5),
}

STATE = {
    "scenario": "normal",
    "since": time.time(),
    "last": time.time(),
    # cumulative counters + histograms, advanced over real time so they are monotonic
    "prompt_tokens": 0.0,
    "generation_tokens": 0.0,
    "success": 0.0,
    "failure": 0.0,
    "preemptions": 0.0,
    "prefix_queries": 0.0,
    "prefix_hits": 0.0,
    "hist": {
        "ttft": {"buckets": [0.0] * (len(TTFT_BUCKETS) + 1), "sum": 0.0, "count": 0.0},
        "tpot": {"buckets": [0.0] * (len(TPOT_BUCKETS) + 1), "sum": 0.0, "count": 0.0},
        "e2e":  {"buckets": [0.0] * (len(E2E_BUCKETS) + 1),  "sum": 0.0, "count": 0.0},
    },
}


def _observe(hist, buckets, value):
    """Add one observation to a cumulative histogram (all le >= value, plus +Inf)."""
    for i, b in enumerate(buckets):
        if value <= b:
            hist["buckets"][i] += 1
    hist["buckets"][-1] += 1  # +Inf always
    hist["sum"] += value
    hist["count"] += 1


def _sample_ttft(cfg):
    # Mostly near-typical, a tail fraction spikes high (the saturation signature).
    if random.random() < cfg["tail"]:
        return cfg["ttft"] * random.uniform(1.8, 3.0)
    return max(0.02, random.gauss(cfg["ttft"], cfg["ttft"] * 0.25))


def _advance():
    """Advance counters/histograms by real elapsed time under the current scenario."""
    now = time.time()
    dt = now - STATE["last"]
    STATE["last"] = now
    cfg = SCENARIOS[STATE["scenario"]]

    completions = cfg["rate"] * dt
    n = int(completions) + (1 if random.random() < (completions % 1) else 0)
    for _ in range(n):
        ttft = _sample_ttft(cfg)
        tpot = max(0.005, random.gauss(cfg["tpot"], cfg["tpot"] * 0.2))
        gen = max(1, int(random.gauss(cfg["gen"], 20)))
        e2e = ttft + tpot * gen
        _observe(STATE["hist"]["ttft"], TTFT_BUCKETS, ttft)
        _observe(STATE["hist"]["tpot"], TPOT_BUCKETS, tpot)
        _observe(STATE["hist"]["e2e"], E2E_BUCKETS, e2e)
        if random.random() < cfg["fail"]:
            STATE["failure"] += 1
        else:
            STATE["success"] += 1
        STATE["prompt_tokens"] += random.randint(200, 1200)
        STATE["generation_tokens"] += gen
        STATE["prefix_queries"] += 1
        if random.random() < 0.6:            # ~60% prefix-cache hit rate (shared prompts)
            STATE["prefix_hits"] += 1

    STATE["preemptions"] += cfg["preempt"] * dt


def render_metrics():
    _advance()
    cfg = SCENARIOS[STATE["scenario"]]
    lbl = f'model_name="{MODEL}"'
    out = []

    def g(name, help_text, value):
        out.append(f"# HELP {name} {help_text}")
        out.append(f"# TYPE {name} gauge")
        out.append(f"{name}{{{lbl}}} {value}")

    def c(name, help_text, value):
        out.append(f"# HELP {name} {help_text}")
        out.append(f"# TYPE {name} counter")
        out.append(f"{name}{{{lbl}}} {value}")

    def hist(name, help_text, buckets, state):
        out.append(f"# HELP {name} {help_text}")
        out.append(f"# TYPE {name} histogram")
        les = [str(b) for b in buckets] + ["+Inf"]
        for le, count in zip(les, state["buckets"]):
            out.append(f'{name}_bucket{{{lbl},le="{le}"}} {int(count)}')
        out.append(f"{name}_sum{{{lbl}}} {round(state['sum'], 3)}")
        out.append(f"{name}_count{{{lbl}}} {int(state['count'])}")

    g("vllm:num_requests_running", "Requests currently in the running batch.", cfg["running"])
    g("vllm:num_requests_waiting", "Requests queued, waiting for a slot.", cfg["waiting"])
    g("vllm:gpu_cache_usage_perc", "KV cache blocks in use (0..1).", round(cfg["kv"], 3))

    c("vllm:prompt_tokens_total", "Prompt (prefill) tokens processed.", int(STATE["prompt_tokens"]))
    c("vllm:generation_tokens_total", "Generated (decode) tokens.", int(STATE["generation_tokens"]))
    c("vllm:request_success_total", "Requests that completed successfully.", int(STATE["success"]))
    c("vllm:request_failure_total", "Requests that failed / were dropped.", int(STATE["failure"]))
    c("vllm:num_preemptions_total", "Requests preempted under KV pressure.", int(STATE["preemptions"]))
    c("vllm:prefix_cache_queries_total", "Prefix-cache lookups.", int(STATE["prefix_queries"]))
    c("vllm:prefix_cache_hits_total", "Prefix-cache lookups that hit.", int(STATE["prefix_hits"]))

    hist("vllm:time_to_first_token_seconds", "Time to first token (TTFT).", TTFT_BUCKETS, STATE["hist"]["ttft"])
    hist("vllm:time_per_output_token_seconds", "Time per output token (TPOT/ITL).", TPOT_BUCKETS, STATE["hist"]["tpot"])
    hist("vllm:e2e_request_latency_seconds", "End-to-end request latency.", E2E_BUCKETS, STATE["hist"]["e2e"])

    return "\n".join(out) + "\n"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/metrics"):
            body = render_metrics().encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path == "/healthz":
            self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
        else:
            self.send_response(404); self.end_headers()

    def do_POST(self):
        # POST /scenario?name=normal|ramp|saturation
        if self.path.startswith("/scenario"):
            from urllib.parse import urlparse, parse_qs
            q = parse_qs(urlparse(self.path).query)
            name = q.get("name", ["normal"])[0]
            if name not in SCENARIOS:
                self.send_response(400); self.end_headers()
                self.wfile.write(f"unknown scenario '{name}'; use: {', '.join(SCENARIOS)}\n".encode())
                return
            STATE["scenario"] = name
            STATE["since"] = time.time()
            self.send_response(200); self.end_headers()
            self.wfile.write(f"scenario={name}\n".encode())
        else:
            self.send_response(404); self.end_headers()

    def log_message(self, *args):  # quiet
        pass


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8000"))  # vLLM serves /metrics on its API port
    print(f"fake-vllm-exporter (SYNTHETIC metrics) on :{port}/metrics  model={MODEL}")
    print("flip load with:  curl -XPOST localhost:%d/scenario?name=saturation" % port)
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()

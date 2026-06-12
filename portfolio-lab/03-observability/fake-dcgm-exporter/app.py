#!/usr/bin/env python3
"""fake-dcgm-exporter - emit DCGM-shaped Prometheus metrics with NO GPU.

Why this exists
---------------
Lesson 4 teaches you to build the *observability pipeline* (scrape -> dashboard ->
alert -> runbook) before owning a GPU. Dashboards and alert rules are queries and
thresholds; they are correct or not regardless of whether the numbers are real. So
we serve metrics with the EXACT field names and labels that NVIDIA's real DCGM
Exporter uses (DCGM_FI_DEV_* / DCGM_FI_PROF_*), but with synthetic values.

HONESTY MARKER: every value here is fabricated. A dashboard built on this proves
dashboard/alert DESIGN only. Real telemetry comes from the Lesson 2 hardware run.
Field names follow DCGM Exporter's documented set:
https://github.com/NVIDIA/dcgm-exporter

The synthetic model is deliberately *interesting*, not flat: a few GPUs run hot and
busy, one sits allocated-but-idle (the money-fire the idle-GPU dashboard hunts),
and one can be pushed into memory pressure via the /scenario endpoint so the
break-it drill can trip an alert on demand.
"""
import math
import os
import random
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# A small synthetic fleet. Labels mirror what real DCGM Exporter attaches.
GPUS = [
    # (gpu_index, uuid, modelName, hostname, persona)
    ("0", "GPU-00000000-0000-0000-0000-000000000000", "NVIDIA A100-SXM4-80GB", "sim-node-a100-0", "busy"),
    ("1", "GPU-11111111-1111-1111-1111-111111111111", "NVIDIA A100-SXM4-80GB", "sim-node-a100-0", "busy"),
    ("2", "GPU-22222222-2222-2222-2222-222222222222", "NVIDIA H100-80GB-HBM3",  "sim-node-h100-0", "spiky"),
    ("3", "GPU-33333333-3333-3333-3333-333333333333", "NVIDIA L40S",            "sim-node-l40s-0", "idle"),
]

FB_TOTAL_MIB = {"NVIDIA A100-SXM4-80GB": 81920, "NVIDIA H100-80GB-HBM3": 81559, "NVIDIA L40S": 46068}

# Mutable scenario state, flipped by POST /scenario?name=...
STATE = {"scenario": "normal", "since": time.time()}


def _persona_values(persona, total_mib, t):
    """Return (sm_active_frac, fb_used_mib, power_w, temp_c) for a persona."""
    if persona == "idle":
        # Allocated to a pod, but doing ~nothing: the classic stranded GPU.
        return 0.01, int(total_mib * 0.04), 55.0, 38.0
    if persona == "spiky":
        # Oscillates between near-idle and near-full.
        phase = (math.sin(t / 20.0) + 1) / 2  # 0..1
        return 0.05 + 0.9 * phase, int(total_mib * (0.1 + 0.7 * phase)), 90 + 250 * phase, 40 + 35 * phase
    # busy
    return 0.85 + random.uniform(-0.05, 0.1), int(total_mib * 0.78), 380.0, 68.0


def render_metrics():
    t = time.time()
    lines = []

    def metric(name, help_text, mtype, samples):
        lines.append(f"# HELP {name} {help_text}")
        lines.append(f"# TYPE {name} {mtype}")
        lines.extend(samples)

    util_samples, sm_samples, fb_used_samples, fb_free_samples = [], [], [], []
    power_samples, temp_samples, xid_samples = [], [], []

    for idx, uuid, model, host, persona in GPUS:
        total = FB_TOTAL_MIB[model]
        sm_active, fb_used, power, temp = _persona_values(persona, total, t)

        # Scenario overrides for the break-it drill.
        if STATE["scenario"] == "mem-pressure" and persona == "busy":
            fb_used = int(total * 0.985)          # trip GPUMemoryPressure
        if STATE["scenario"] == "thermal" and persona == "spiky":
            temp = 92.0                            # trip a thermal alert
        if STATE["scenario"] == "xid" and idx == "0":
            xid = 1                                # a driver error event
        else:
            xid = 0

        fb_used = max(0, min(fb_used, total))
        lbl = (f'gpu="{idx}",UUID="{uuid}",modelName="{model}",Hostname="{host}",'
               f'device="nvidia{idx}"')

        util_samples.append(f"DCGM_FI_DEV_GPU_UTIL{{{lbl}}} {round(min(1.0, sm_active) * 100)}")
        sm_samples.append(f"DCGM_FI_PROF_SM_ACTIVE{{{lbl}}} {round(min(1.0, sm_active), 4)}")
        fb_used_samples.append(f"DCGM_FI_DEV_FB_USED{{{lbl}}} {fb_used}")
        fb_free_samples.append(f"DCGM_FI_DEV_FB_FREE{{{lbl}}} {total - fb_used}")
        power_samples.append(f"DCGM_FI_DEV_POWER_USAGE{{{lbl}}} {round(power, 1)}")
        temp_samples.append(f"DCGM_FI_DEV_GPU_TEMP{{{lbl}}} {round(temp, 1)}")
        xid_samples.append(f"DCGM_FI_DEV_XID_ERRORS{{{lbl}}} {xid}")

    metric("DCGM_FI_DEV_GPU_UTIL", "GPU utilization (%) - the misleading one; see SM_ACTIVE.", "gauge", util_samples)
    metric("DCGM_FI_PROF_SM_ACTIVE", "Fraction of time SMs were active (the honest signal).", "gauge", sm_samples)
    metric("DCGM_FI_DEV_FB_USED", "Framebuffer memory used (MiB).", "gauge", fb_used_samples)
    metric("DCGM_FI_DEV_FB_FREE", "Framebuffer memory free (MiB).", "gauge", fb_free_samples)
    metric("DCGM_FI_DEV_POWER_USAGE", "Power draw (W).", "gauge", power_samples)
    metric("DCGM_FI_DEV_GPU_TEMP", "GPU temperature (C).", "gauge", temp_samples)
    metric("DCGM_FI_DEV_XID_ERRORS", "Count of XID errors observed (driver health canary).", "gauge", xid_samples)

    return "\n".join(lines) + "\n"


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
        # POST /scenario?name=normal|mem-pressure|thermal|xid
        if self.path.startswith("/scenario"):
            from urllib.parse import urlparse, parse_qs
            q = parse_qs(urlparse(self.path).query)
            name = (q.get("name", ["normal"])[0])
            STATE["scenario"] = name
            STATE["since"] = time.time()
            self.send_response(200); self.end_headers()
            self.wfile.write(f"scenario={name}\n".encode())
        else:
            self.send_response(404); self.end_headers()

    def log_message(self, *args):  # quiet
        pass


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "9400"))  # 9400 = DCGM Exporter's real port
    print(f"fake-dcgm-exporter (SYNTHETIC metrics) listening on :{port}/metrics")
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()

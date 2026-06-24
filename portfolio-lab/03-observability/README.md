# Lesson 3 - GPU Observability

> Course home: [AI Factory Operations Lab](../../README.md) · Previous:
> [Lesson 2 - Slurm GPU Platform](../02-slurm-gpu-platform/README.md) · Next:
> [Lesson 4 - Inference Serving](../04-inference-serving/README.md)

> ✅ **STATUS: RUNNABLE.** One self-contained lab. You stand up a real
> Prometheus/Grafana stack, point it at a **synthetic DCGM exporter** (no GPU),
> import two dashboards, then trip the alerts on purpose and watch each one point at
> its runbook. Validated end to end. The metric *names* are the real DCGM Exporter
> field names; only the *values* are synthetic.

You've scheduled GPU work under both Kubernetes (Lesson 1) and Slurm (Lesson 2). Now
you make a fleet **observable** - so you can see utilization, catch problems before
users do, and back every alert with a runbook. You'll build the whole pipeline
(scrape → dashboard → alert → runbook) without owning a GPU.

🧭 **Mode:** 🟦 Simulation. 💰 **Cost:** free. ⏱️ **Time:** ~20 minutes.

💡 **Why you can build this before owning a GPU:** dashboards and alert rules are just
*queries and thresholds* - they're correct or not regardless of whether the numbers
underneath are real. So you design and validate the *pipeline* on synthetic metrics
here, then point the exact same pipeline at real DCGM data in
[Lesson 6](../01-k8s-gpu-platform/gpu-operator-real/README.md). Dashboards built on
synthetic metrics are labelled `[DESIGN]`; real telemetry evidence comes from Lesson 6
hardware only.

---

## Before you start

You need the **Phase 1 kind cluster** running (everything here installs on top of it):

```bash
make phase1-up        # local kind cluster + the fake GPU fleet (no GPU)
```

That's the only prerequisite. No GPU, no cloud, no image build.

---

## The walkthrough (five steps)

Run these in order. Each step says **what you're doing** and **what to look for** before
moving on.

### Step 1 - Stand up the monitoring stack

```bash
make phase4-up
```

This one command installs everything: the **kube-prometheus-stack** (Prometheus +
Grafana + Alertmanager + kube-state-metrics) via Helm, the **synthetic DCGM exporter**
(more on it in Step 2), a **ServiceMonitor** that tells Prometheus to scrape it, six
**alert rules**, and two **Grafana dashboards**. First run pulls a few images, so give it
a couple of minutes.

✅ **Look for:** the script ends with `==> Done.` and prints the two port-forward
commands. The exporter pod is `Running`:

```bash
kubectl -n gpu-observability get pods
```

### Step 2 - Meet the synthetic exporter (what's feeding the dashboards)

The data source is [`fake-dcgm-exporter/app.py`](./fake-dcgm-exporter/app.py) - a small
Python app that serves Prometheus metrics with the **exact field names and labels** of
NVIDIA's real [DCGM Exporter](https://github.com/NVIDIA/dcgm-exporter) (`DCGM_FI_DEV_*`,
`DCGM_FI_PROF_*`), but every value is fabricated. It's deployed straight from a ConfigMap
on a stock `python` image - no build, no registry.

It exposes a **four-GPU fleet** with deliberately interesting personalities, so the
dashboards and alerts have something real-looking to show:

| GPU | Model | Persona | Why it's here |
|---|---|---|---|
| 0, 1 | A100 | busy | high SM-active - the normal, healthy case |
| 2 | H100 | spiky | oscillates idle↔full - exercises the time-series panels |
| 3 | L40S | **idle** | memory allocated, ~0 SM-active - the "money fire" the idle dashboard hunts |

You can look at the raw metrics yourself. Either inspect the live pod's output, or run the
app standalone:

```bash
# standalone, on your laptop - no cluster needed. Run from the repo root
# (same place you run the make targets):
PORT=9400 python3 portfolio-lab/03-observability/fake-dcgm-exporter/app.py &
curl -s localhost:9400/metrics | grep DCGM_FI_PROF_SM_ACTIVE
```

✅ **Look for:** one `DCGM_FI_PROF_SM_ACTIVE` series per GPU, with GPU 3 (the L40S)
sitting near zero. That stranded GPU is the whole point of the idle dashboard later.

### Step 3 - Open Prometheus and Grafana

In two terminals (or background them), forward the UIs:

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80      # → http://localhost:3000  (admin / admin)
```

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090 # → http://localhost:9090
```

In **Prometheus** (`localhost:9090`): go to **Status → Targets** and confirm the
`fake-dcgm-exporter` target is `UP`. Then run a query - paste `DCGM_FI_PROF_SM_ACTIVE`
into the expression bar and hit Execute; you should get one series per GPU.

In **Grafana** (`localhost:3000`, log in `admin` / `admin`): open **Dashboards** and find
the two auto-imported ones, **`[DESIGN] GPU Fleet Overview`** and
**`[DESIGN] Idle-GPU / Money-Fire`**. The idle dashboard is the one that flags GPU 3.

✅ **Look for:** target `UP` in Prometheus, and both `[DESIGN]` dashboards rendering with
data in Grafana.

### Step 4 - Break it on purpose (the point of the lesson)

An alert you've never watched fire is one you don't trust. This drill trips three alerts
and shows each one carrying a `runbook` annotation:

```bash
make phase4-break
```

It runs three scenarios back to back, querying Prometheus after each so you watch the
alert flip to `firing`:

1. **`DCGMExporterAbsent`** - it scales the exporter to zero, so metrics stop scraping
   (`absent()` trips after ~60s), then restores it.
2. **`GPUMemoryPressure`** - it pushes a GPU to 98% framebuffer (`mem-pressure` scenario).
3. **`GPUXidErrors`** - it injects an XID driver error (`xid` scenario), then resets to
   normal.

Under the hood, the drill flips the exporter's numbers through its `/scenario` endpoint -
the same switch you can drive by hand:

```bash
# from inside the pod, or against a standalone exporter on :9400
curl -X POST "localhost:9400/scenario?name=mem-pressure"   # a GPU → 98% framebuffer
curl -X POST "localhost:9400/scenario?name=thermal"        # GPU 2 → 92 °C
curl -X POST "localhost:9400/scenario?name=xid"            # a GPU → XID error
curl -X POST "localhost:9400/scenario?name=normal"         # reset everything
```

**Where to watch it (open these while the drill runs):**

- **Prometheus → Alerts** (`localhost:9090/alerts`): you'll see `DCGMExporterAbsent`, then
  `GPUMemoryPressure`, then `GPUXidErrors` move from green → **yellow (Pending)** →
  **red (Firing)** as each scenario lands. `GPUAllocatedButIdle` (the stranded L40S) sits
  firing the whole time - that's the "money fire," independent of the drill.
- **Prometheus → Status → Targets** (`localhost:9090/targets`): during drill 1 the
  `fake-dcgm-exporter` target flips **DOWN**, then back **UP** when the exporter is restored.
- **Prometheus → Graph** (`localhost:9090/graph`): query `DCGM_FI_DEV_FB_USED` and watch one
  GPU spike toward ~98% during the mem-pressure drill; query `DCGM_FI_DEV_XID_ERRORS` and
  watch it jump to `1` during the xid drill.
- **Grafana** (`localhost:3000`): the `[DESIGN]` dashboards move with the metrics - the
  framebuffer panel climbs under mem-pressure, and the **Idle-GPU / Money-Fire** dashboard
  keeps flagging GPU 3.

> ⏱️ **Alerts fire on a delay, not instantly.** Each rule has a `for:` window, so an alert
> turns red a few tens of seconds *after* its scenario is set - watch the **Alerts** tab
> live rather than expecting the script's one-shot snapshot to catch every alert (its
> snapshot for one drill sometimes still shows the previous drill's alert).

✅ **Look for:** in **Prometheus → Alerts** each drill's alert reaches **Firing**. Every one
carries a `runbook` annotation linking into [`/runbooks`](../../runbooks/) (visible in the
alert's labels/annotations, and in Alertmanager) - that alert→runbook wiring is what you're
proving works *before* a real incident exercises it.

### Step 5 - Capture evidence, then tear down

```bash
make phase4-evidence  # snapshot Prometheus targets, rules, and alert state
make phase4-down      # remove the monitoring stack (keeps the kind cluster)
```

✅ **Done.** You stood up a full GPU-observability pipeline, saw real DCGM metric shapes
flow through it, and watched alerts fire into runbooks - all with no GPU.

---

## Understand what you built

The walkthrough is the *how*. These four concepts are the *why* - the reasoning behind
every panel and alert you just stood up.

### 1. The metrics that matter (and the one that lies)

DCGM Exporter publishes per-GPU Prometheus metrics. The working set:

| Metric | What it tells you | Watch out |
|---|---|---|
| `DCGM_FI_DEV_GPU_UTIL` | % of time ≥1 kernel was executing | **The liar** - see below |
| `DCGM_FI_PROF_SM_ACTIVE` | Fraction of time SMs actually had work | The true utilization signal |
| `DCGM_FI_PROF_SM_OCCUPANCY` | How full the active SMs were | Distinguishes "busy" from "efficient" |
| `DCGM_FI_DEV_FB_USED` / `FB_FREE` | Framebuffer (GPU memory) used/free | The capacity-planning input |
| `DCGM_FI_DEV_GPU_TEMP` | Temperature | Sustained high → throttling |
| `DCGM_FI_DEV_POWER_USAGE` | Power draw | Near cap + low SM_ACTIVE = something's wrong |
| `DCGM_FI_DEV_XID_ERRORS` | Driver-reported error events (Xid codes) | The hardware-health canary; page on it |
| `DCGM_FI_PROF_PCIE_TX_BYTES` / `RX` | PCIe traffic | Data-starvation diagnosis |

💡 **Why GPU_UTIL lies:** it reads 100% if *any* kernel was resident in the sample
window - a GPU running one tiny kernel at a time shows "100% utilized" while doing 5% of
the work it could. Real fleets bill by the GPU-hour, so the gap between GPU_UTIL and
SM_ACTIVE/SM_OCCUPANCY is literally money. The idle-GPU dashboard is built on exactly this
distinction - it's the highest-leverage insight in this lesson.

### 2. USE method, applied to a GPU fleet

The classic USE method (Utilization, Saturation, Errors) maps cleanly:

- **Utilization:** SM_ACTIVE (compute), FB_USED/total (memory), PCIe bytes (I/O).
- **Saturation:** Pending GPU pods (Lesson 1's signal), Slurm `Resources`-pending jobs
  (Lesson 2's), inference queue depth (Lesson 4's).
- **Errors:** XID events, thermal throttling, DCGM health checks, NotReady GPU nodes.

Notice **saturation lives in the schedulers, not in DCGM** - queue depth is a
control-plane metric. That's why this lesson can wire saturation panels entirely from the
free simulation, while utilization panels need either synthetic DCGM (design) or Lesson 6
hardware (validated).

### 3. The five dashboards, and the question each answers

| Dashboard | The question it answers | Primary sources |
|---|---|---|
| GPU fleet overview | "Is the fleet healthy right now?" | DCGM temp/power/XID, node status |
| K8s GPU workloads | "Who is using which GPUs, and what's stuck Pending, why?" | kube-state-metrics, DCGM per-pod attribution |
| Slurm queue pressure | "How long are jobs waiting and which reason dominates?" | Slurm exporter / sacct-derived |
| Inference SLOs | "Are we serving within TTFT/p95/p99 targets?" | Server metrics (Lesson 4) |
| Idle-GPU & capacity | "Which allocated GPUs are doing nothing, and when do we run out?" | SM_ACTIVE vs allocation joins |

This lab ships two of the five (fleet overview + idle-GPU); the other three extend
naturally from the same Prometheus once Lessons 2/4 feed it.

💡 The idle-GPU dashboard is the one platform teams get paged about by *finance*, not ops:
an allocated-but-idle GPU looks "used" to the scheduler and "idle" to DCGM. Joining the
two views (allocation from the control plane, activity from telemetry) is the actual
engineering content of that dashboard.

### 4. Alerts are only as good as their runbooks

The rule here: **no alert ships without a linked runbook.** The wiring you tripped in
Step 4 is part of a larger set:

| Alert | Fires when | Runbook |
|---|---|---|
| `GPUXidErrors` | Any XID event on a node | [gpu-node-not-ready.md](../../runbooks/gpu-node-not-ready.md) |
| `DCGMExporterAbsent` | DCGM metrics stop scraping | [dcgm-exporter-no-metrics.md](../../runbooks/dcgm-exporter-no-metrics.md) |
| `GPUMemoryPressure` | FB_USED sustained near capacity | [gpu-memory-pressure.md](../../runbooks/gpu-memory-pressure.md) |
| `GPUPodsPendingHigh` | Pending GPU pods sustained above threshold | [gpu-capacity-planning.md](../../runbooks/gpu-capacity-planning.md) |
| `DevicePluginDown` | Node stops advertising `nvidia.com/gpu` | [device-plugin-not-advertising-gpus.md](../../runbooks/device-plugin-not-advertising-gpus.md) |
| `QueueStarvation` | A queue's share stays ~0 while it has demand | [kai-scheduler-queue-starvation.md](../../runbooks/kai-scheduler-queue-starvation.md) |

Several of these fire correctly against the **fake** fleet (Pending pods, device plugin
absent, queue starvation) - control-plane alerts are fully testable for free.

---

## What's in this directory

- [`fake-dcgm-exporter/app.py`](./fake-dcgm-exporter/app.py) - the synthetic DCGM metrics
  source (~150 lines of Python) and its `/scenario` switch.
- [`manifests/`](./manifests/) - `exporter.yaml`, `servicemonitor.yaml`, and `alerts.yaml`
  (the six PrometheusRules above, each with a `runbook` annotation).
- [`dashboards/`](./dashboards/) - `gpu-fleet-overview.json` and `idle-gpu.json`, both
  tagged `[DESIGN]`, auto-imported by Grafana's sidecar.
- [`scripts/`](./scripts/) - `up` / `break-it` / `collect-evidence` / `down`, behind the
  `make phase4-*` targets.

> **Already have a DCGM stream from Lesson 1?** Since Lesson 1 runs the
> [fake-gpu-operator](../01-k8s-gpu-platform/fake-gpu-operator/README.md), the
> `make phase1-up` fleet already exposes a per-node DCGM exporter
> (`svc/nvidia-dcgm-exporter` in the `gpu-operator` namespace) with **per-pod attribution**
> - richer than this lesson's standalone exporter. You can point Prometheus there instead;
> the standalone exporter here stays as a self-contained option (and its `/scenario` switch
> drives the break-it drill). Either way the values are synthetic; only the shape is real.

🔬 **What the sim will and won't prove:** pipeline design, query correctness, control-plane
alerting, and dashboard/runbook wiring - all provable for free. Real GPU telemetry *values*,
XID behaviour, and thermals require Lesson 6 hardware. Ledger:
[`fake-vs-real-limitations.md`](../06-validation-reports/fake-vs-real-limitations.md).

➡️ **Next:** [Lesson 4 - Inference Serving](../04-inference-serving/README.md).

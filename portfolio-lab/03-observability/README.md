# Lesson 4 — GPU Observability

> Course home: [AI Factory Operations Lab](../../README.md) · Previous:
> [Lesson 3 — Slurm GPU Platform](../02-slurm-gpu-platform/README.md) · Next:
> [Lesson 5 — Inference Serving](../04-inference-serving/README.md)

> ✅ **STATUS: RUNNABLE (Phase 4).** This lesson installs a real Prometheus/Grafana
> stack onto the Phase 1 kind cluster, scrapes a **synthetic DCGM exporter**, ships
> two dashboards and six alert rules, and trips the alerts on purpose — all with **no
> GPU**. Validated end to end (target scraping, rules loading, alerts firing,
> dashboards importing). Metric names are the standard DCGM Exporter field names.

You've scheduled GPU work under both Kubernetes (Lessons 1–2) and Slurm (Lesson 3).
Now you make a fleet *observable* — so you can see utilization, catch problems before
users do, and back every alert with a runbook.

🎯 **Learning objectives** — when this lesson is runnable you'll be able to:

1. Stand up a Prometheus/Grafana stack and scrape DCGM metrics.
2. Build the core dashboards: GPU fleet overview, K8s GPU workloads, Slurm queue
   pressure, inference SLOs, and idle-GPU / capacity analysis.
3. Write SLO-oriented alert rules and wire each one to a runbook in
   [`/runbooks`](../../runbooks/).
4. Explain why "GPU utilization" is a misleading metric and what to read instead.
5. Distinguish a *design* artifact (dashboard built on synthetic metrics) from a
   *validated* one (built on real DCGM data).

🧭 **Mode:** 🟦 Simulation — the whole pipeline runs against a **synthetic DCGM
exporter** ([`fake-dcgm-exporter/`](./fake-dcgm-exporter/README.md)) shipped with
this lesson; [run.ai's fake-gpu-operator](../01-k8s-gpu-platform/fake-gpu-operator/README.md)
is an alternative source.

💡 **Why you can build observability before owning a GPU:** dashboards and alert
rules are queries and thresholds — they're correct or not regardless of whether the
underlying numbers are real. So you design and validate the *pipeline* on synthetic
metrics, then point it at real DCGM data from [Lesson 2](../01-k8s-gpu-platform/gpu-operator-real/README.md).

> **Note:** synthetic-metric dashboards are labelled `[DESIGN]`. Real DCGM evidence
> comes from Lesson 2 hardware runs only.

---

## The loop (run this)

Needs the Phase 1 kind cluster up (`make phase1-up`). No GPU.

```bash
make phase4-up        # kube-prometheus-stack + fake-DCGM exporter + dashboards + alerts
make phase4-break     # trip DCGMExporterAbsent / GPUMemoryPressure / GPUXidErrors on purpose
make phase4-evidence  # snapshot Prometheus targets, rules, and alert state
make phase4-down      # remove the stack (keeps the kind cluster)
```

Open the UIs:

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80      # admin/admin
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
```

✅ **Checkpoint:** after `make phase4-up`, the exporter target is `up` in Prometheus
and `DCGM_FI_PROF_SM_ACTIVE` returns one series per simulated GPU (one — the L40S —
sits near zero: the stranded GPU the idle dashboard hunts). After `make phase4-break`,
`GPUMemoryPressure` and `DCGMExporterAbsent` move to firing, each carrying a `runbook`
annotation into [`/runbooks`](../../runbooks/).

💡 **The break-it drill is the point.** An alert you've never watched fire is one you
don't trust. The drill deletes the exporter (→ absent), pushes a GPU to 98%
framebuffer (→ memory pressure), and injects an XID (→ driver health), so you see the
alert→runbook wiring work *before* a real incident exercises it. These are all
control-plane alerts — fully testable for free.

> **How it works with no GPU:** [`fake-dcgm-exporter/app.py`](./fake-dcgm-exporter/app.py)
> serves the *exact* DCGM field names and labels with synthetic values, delivered as
> a ConfigMap-mounted script on a stock `python` image (no image build). A `/scenario`
> endpoint lets the drill change the numbers on demand.

---

## Concept 1 — The metrics that matter (and the one that lies)

DCGM Exporter publishes per-GPU Prometheus metrics. The working set:

| Metric | What it tells you | Watch out |
|---|---|---|
| `DCGM_FI_DEV_GPU_UTIL` | % of time ≥1 kernel was executing | **The liar** — see below |
| `DCGM_FI_PROF_SM_ACTIVE` | Fraction of time SMs actually had work | The honest utilization signal |
| `DCGM_FI_PROF_SM_OCCUPANCY` | How full the active SMs were | Distinguishes "busy" from "efficient" |
| `DCGM_FI_DEV_FB_USED` / `FB_FREE` | Framebuffer (GPU memory) used/free | The capacity-planning input |
| `DCGM_FI_DEV_GPU_TEMP` | Temperature | Sustained high → throttling |
| `DCGM_FI_DEV_POWER_USAGE` | Power draw | Near cap + low SM_ACTIVE = something's wrong |
| `DCGM_FI_DEV_XID_ERRORS` | Driver-reported error events (Xid codes) | The hardware-health canary; page on it |
| `DCGM_FI_PROF_PCIE_TX_BYTES` / `RX` | PCIe traffic | Data-starvation diagnosis |

💡 **Why GPU_UTIL lies:** it reads 100% if *any* kernel was resident in the sample
window — a GPU running one tiny kernel at a time shows "100% utilized" while doing
5% of the work it could. Real fleets bill by the GPU-hour, so the difference between
GPU_UTIL and SM_ACTIVE/SM_OCCUPANCY is literally money. The idle-GPU dashboard below
is built on this distinction, and it's the highest-leverage insight in this lesson —
state it in any interview about GPU observability.

## Concept 2 — USE method, applied to a GPU fleet

The classic USE method (Utilization, Saturation, Errors) maps cleanly:

- **Utilization:** SM_ACTIVE (compute), FB_USED/total (memory), PCIe bytes (I/O).
- **Saturation:** Pending GPU pods (Lesson 1's signal!), Slurm `Resources`-pending
  jobs (Lesson 3's), inference queue depth (Lesson 5's).
- **Errors:** XID events, thermal throttling, DCGM health checks, NotReady GPU nodes.

Notice that *saturation lives in the schedulers, not in DCGM* — queue depth is a
control-plane metric. That's why this lesson can wire saturation panels entirely
from the free simulation (kube-state-metrics over the fake fleet), while utilization
panels need either synthetic DCGM (design) or Lesson 2 hardware (validated).

## Concept 3 — The five dashboards, and the question each answers

| Dashboard | The question it answers | Primary sources |
|---|---|---|
| GPU fleet overview | "Is the fleet healthy right now?" | DCGM temp/power/XID, node status |
| K8s GPU workloads | "Who is using which GPUs, and what's stuck Pending, why?" | kube-state-metrics, DCGM per-pod attribution |
| Slurm queue pressure | "How long are jobs waiting and which reason dominates?" | Slurm exporter / sacct-derived |
| Inference SLOs | "Are we serving within TTFT/p95/p99 targets?" | Server metrics (Lesson 5) |
| Idle-GPU & capacity | "Which allocated GPUs are doing nothing, and when do we run out?" | SM_ACTIVE vs allocation joins |

💡 The idle-GPU dashboard is the one platform teams get paged about by finance, not
by ops: an allocated-but-idle GPU looks "used" to the scheduler and "idle" to DCGM.
Joining the two views (allocation from the control plane, activity from telemetry)
is the actual engineering content of this dashboard.

## Concept 4 — Alerts are only as good as their runbooks

Phase 4's rule: **no alert ships without a linked runbook.** The planned wiring:

| Alert (sketch) | Fires when | Runbook |
|---|---|---|
| `GPUXidErrors` | Any XID event on a node | [gpu-node-not-ready.md](../../runbooks/gpu-node-not-ready.md) |
| `DCGMExporterAbsent` | DCGM metrics stop scraping | [dcgm-exporter-no-metrics.md](../../runbooks/dcgm-exporter-no-metrics.md) |
| `GPUMemoryPressure` | FB_USED sustained near capacity | [gpu-memory-pressure.md](../../runbooks/gpu-memory-pressure.md) |
| `GPUPodsPendingHigh` | Pending GPU pods sustained above threshold | [gpu-capacity-planning.md](../../runbooks/gpu-capacity-planning.md) |
| `DevicePluginDown` | Node stops advertising `nvidia.com/gpu` | [device-plugin-not-advertising-gpus.md](../../runbooks/device-plugin-not-advertising-gpus.md) |
| `QueueStarvation` | A queue's share stays ~0 while it has demand | [kai-scheduler-queue-starvation.md](../../runbooks/kai-scheduler-queue-starvation.md) |

The alert thresholds are design decisions you can defend; the runbook is the
operational muscle behind each. Several of these fire correctly against the **fake**
fleet (Pending pods, device plugin absent, queue starvation) — control-plane alerts
are fully testable for free, which is itself a Phase 4 exercise: break the sim
cluster on purpose and watch the right alert fire.

## What's in this directory

- [`fake-dcgm-exporter/`](./fake-dcgm-exporter/README.md) — the synthetic DCGM
  metrics source (a ~150-line Python app + its honesty marker and `/scenario` switch).
- [`manifests/`](./manifests/) — `exporter.yaml`, `servicemonitor.yaml`, and
  `alerts.yaml` (the six PrometheusRules above, each with a `runbook` annotation).
- [`dashboards/`](./dashboards/) — `gpu-fleet-overview.json` and `idle-gpu.json`,
  both tagged `[DESIGN]`, auto-imported by Grafana's sidecar.
- [`scripts/`](./scripts/) — `up` / `break-it` / `collect-evidence` / `down`.

Phase 4 ships two of the five dashboards from Concept 3 (fleet overview + idle-GPU);
the Slurm-queue, K8s-workloads, and inference-SLO panels extend naturally from the
same Prometheus once Phases 3/5 feed it. The control-plane alerts (`GPUPodsPendingHigh`,
`DCGMExporterAbsent`) fire against the fake fleet today.

🔬 **What the sim will and won't prove:** pipeline design, query correctness,
control-plane alerting, and dashboard/runbook wiring — all provable for free.
Real GPU telemetry values, XID behaviour, and thermals require Lesson 2 hardware.
Ledger: [`fake-vs-real-limitations.md`](../06-validation-reports/fake-vs-real-limitations.md).

➡️ **Next:** [Lesson 5 — Inference Serving](../04-inference-serving/README.md).

# Lesson 4 — GPU Observability

> Course home: [AI Factory Operations Lab](../../README.md) · Previous:
> [Lesson 3 — Slurm GPU Platform](../02-slurm-gpu-platform/README.md) · Next:
> [Lesson 5 — Inference Serving](../04-inference-serving/README.md)

> 🚧 **STATUS: PLANNED (Phase 4).** The concept sections below are teachable now;
> runnable steps (kube-prometheus-stack install, dashboard JSON, alert rules) land
> with Phase 4. Metric names cited are standard DCGM Exporter field names — verify
> against the exporter version you deploy.

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

🧭 **Mode:** 🟦 Simulation — you can build the entire pipeline against the synthetic
DCGM-shaped metrics from [fake-gpu-operator](../01-k8s-gpu-platform/fake-gpu-operator/README.md).

💡 **Why you can build observability before owning a GPU:** dashboards and alert
rules are queries and thresholds — they're correct or not regardless of whether the
underlying numbers are real. So you design and validate the *pipeline* on synthetic
metrics, then point it at real DCGM data from [Lesson 2](../01-k8s-gpu-platform/gpu-operator-real/README.md).

> **Note:** synthetic-metric dashboards (fake-gpu-operator) are labelled as design
> artifacts. Real DCGM evidence comes from Lesson 2 hardware runs only.

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

## What Phase 4 will ship

- kube-prometheus-stack install with a scrape config for DCGM Exporter (synthetic
  first, real later) and kube-state-metrics over the fake fleet.
- The five dashboards as committed JSON, each labelled **design** or **validated**.
- The alert rules above as PrometheusRule manifests, each linking its runbook.
- A break-it drill per control-plane alert (delete the device plugin, starve a
  queue, flood Pending pods) with captured firing evidence.

🔬 **What the sim will and won't prove:** pipeline design, query correctness,
control-plane alerting, and dashboard/runbook wiring — all provable for free.
Real GPU telemetry values, XID behaviour, and thermals require Lesson 2 hardware.
Ledger: [`fake-vs-real-limitations.md`](../06-validation-reports/fake-vs-real-limitations.md).

➡️ **Next:** [Lesson 5 — Inference Serving](../04-inference-serving/README.md).

# Lesson 4 — GPU Observability

> Course home: [AI Factory Operations Lab](../../README.md) · Previous:
> [Lesson 3 — Slurm GPU Platform](../02-slurm-gpu-platform/README.md) · Next:
> [Lesson 5 — Inference Serving](../04-inference-serving/README.md)

> 🚧 **STATUS: PLANNED (Phase 4).** Concepts and objectives now; runnable steps land
> with Phase 4.

You've scheduled GPU work under both Kubernetes (Lessons 1–2) and Slurm (Lesson 3).
Now you make a fleet *observable* — so you can see utilization, catch problems before
users do, and back every alert with a runbook.

🎯 **Learning objectives** — when this lesson is runnable you'll be able to:

1. Stand up a Prometheus/Grafana stack and scrape DCGM metrics.
2. Build the core dashboards: GPU fleet overview, K8s GPU workloads, Slurm queue
   pressure, inference SLOs, and idle-GPU / capacity analysis.
3. Write SLO-oriented alert rules and wire each one to a runbook in
   [`/runbooks`](../../runbooks/).
4. Distinguish a *design* artifact (dashboard built on synthetic metrics) from a
   *validated* one (built on real DCGM data).

🧭 **Mode:** 🟦 Simulation — you can build the entire pipeline against the synthetic
DCGM-shaped metrics from [fake-gpu-operator](../01-k8s-gpu-platform/fake-gpu-operator/README.md).

💡 **Why you can build observability before owning a GPU:** dashboards and alert
rules are queries and thresholds — they're correct or not regardless of whether the
underlying numbers are real. So you design and validate the *pipeline* on synthetic
metrics, then point it at real DCGM data from [Lesson 2](../01-k8s-gpu-platform/gpu-operator-real/README.md).

> **HONESTY MARKER:** synthetic-metric dashboards (fake-gpu-operator) will be labelled
> as design artifacts. Real DCGM evidence comes from Lesson 2 hardware runs only.

📎 **The runbooks this lesson's alerts link to already exist** — browse
[`/runbooks`](../../runbooks/) (e.g.
[dcgm-exporter-no-metrics.md](../../runbooks/dcgm-exporter-no-metrics.md),
[gpu-memory-pressure.md](../../runbooks/gpu-memory-pressure.md),
[gpu-capacity-planning.md](../../runbooks/gpu-capacity-planning.md)).

➡️ **Next:** [Lesson 5 — Inference Serving](../04-inference-serving/README.md).

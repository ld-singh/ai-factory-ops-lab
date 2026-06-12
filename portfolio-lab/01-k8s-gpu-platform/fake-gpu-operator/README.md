# Lesson 1 · Optional - A richer simulation (fake-gpu-operator)

> Part of [Lesson 1 - Kubernetes GPU Scheduling](../README.md). Optional. Most
> valuable as a bridge to [Lesson 4 - Observability](../../03-observability/README.md).

🎯 **Objective:** know when plain KWOK fake nodes are enough and when
[run.ai's fake-gpu-operator](https://github.com/run-ai/fake-gpu-operator) earns its
extra setup weight - specifically, when you need a metrics endpoint that *looks like*
DCGM before any real GPU exists.

## KWOK fake nodes vs fake-gpu-operator

| | KWOK fake nodes (this lesson's default) | fake-gpu-operator |
|---|---|---|
| What is fake | The entire node | GPUs on real (CPU) nodes |
| Pods actually run | No (lifecycle simulated) | Yes (real containers, fake GPUs) |
| GPU-Operator-shaped components | No | Yes (device-plugin-like, DCGM-exporter-like) |
| Fake DCGM-style metrics | No | Yes - useful for Lesson 4 dashboards |
| Setup weight | Very light | Heavier (Helm chart, node labelling) |
| Best for | Pure scheduling/placement studies at any scale | Observability pipelines and operator-shaped topology without GPUs |

💡 **Why the default is KWOK:** Lesson 1 is about scheduler behaviour, and KWOK
scales to large fake fleets trivially. fake-gpu-operator becomes attractive in
[Lesson 4 (observability)](../../03-observability/README.md), where having a metrics
endpoint that *looks like* DCGM Exporter lets you build dashboards and alerts before
any real GPU exists.

> **HONESTY MARKER:** install steps are not reproduced here - follow the project's
> README directly to avoid drift: https://github.com/run-ai/fake-gpu-operator
> Any metrics produced this way are synthetic. Dashboards built on them prove
> dashboard/alert *design*, not real GPU telemetry. Real DCGM evidence belongs in
> [`../gpu-operator-real/`](../gpu-operator-real/README.md) and Lesson 2's validation
> report.

✅ **Checkpoint:** you can state, in one sentence each, the one thing fake-gpu-operator
gives you that KWOK doesn't (synthetic DCGM-shaped metrics + real container
execution) and the one thing neither gives you (real GPU telemetry).

➡️ **Back to:** [Lesson 1](../README.md) · **Leads to:**
[Lesson 4 - Observability](../../03-observability/README.md).

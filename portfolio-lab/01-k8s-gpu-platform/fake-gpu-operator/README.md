# fake-gpu-operator/

Notes on [run.ai's fake-gpu-operator](https://github.com/run-ai/fake-gpu-operator)
as a richer alternative to plain KWOK fake nodes.

## KWOK fake nodes vs fake-gpu-operator

| | KWOK fake nodes (this lab's default) | fake-gpu-operator |
|---|---|---|
| What is fake | The entire node | GPUs on real (CPU) nodes |
| Pods actually run | No (lifecycle simulated) | Yes (real containers, fake GPUs) |
| GPU-Operator-shaped components | No | Yes (device-plugin-like, DCGM-exporter-like) |
| Fake DCGM-style metrics | No | Yes — useful for Phase 4 dashboards |
| Setup weight | Very light | Heavier (Helm chart, node labelling) |
| Best for | Pure scheduling/placement studies at any scale | Observability pipelines and operator-shaped topology without GPUs |

This lab defaults to KWOK because Phase 1 is about scheduler behaviour and KWOK
scales to large fake fleets trivially. fake-gpu-operator becomes attractive in
Phase 4 (observability), where having a metrics endpoint that *looks like* DCGM
Exporter lets dashboards and alerts be built before any real GPU exists.

> **HONESTY MARKER:** install steps are not reproduced here — follow the
> project's README directly to avoid drift:
> https://github.com/run-ai/fake-gpu-operator
> Any metrics produced this way are synthetic. Dashboards built on them prove
> dashboard/alert design, not real GPU telemetry. Real DCGM evidence belongs in
> `../gpu-operator-real/` and Phase 2's validation report.

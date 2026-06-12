# fake-dcgm-exporter - synthetic DCGM metrics, no GPU

[`app.py`](./app.py) serves Prometheus metrics using the **exact field names and
labels** of NVIDIA's real [DCGM Exporter](https://github.com/NVIDIA/dcgm-exporter)
(`DCGM_FI_DEV_*`, `DCGM_FI_PROF_*`) - but every value is fabricated. It exists so
Lesson 4 can build and validate the entire observability pipeline (scrape →
dashboard → alert → runbook) before any real GPU exists.

> **HONESTY MARKER:** synthetic values. A dashboard or alert built on this proves
> **design**, not real telemetry. Real DCGM evidence comes only from the
> [Lesson 2](../../01-k8s-gpu-platform/gpu-operator-real/README.md) hardware run.

## The synthetic fleet

Four GPUs with deliberately *interesting* personas, so the dashboards and alerts
have something real to show:

| GPU | Model | Persona | Why |
|---|---|---|---|
| 0, 1 | A100 | busy | high SM-active, the normal case |
| 2 | H100 | spiky | oscillates idle↔full, exercises time-series panels |
| 3 | L40S | **idle** | allocated memory, ~0 SM-active - the money-fire the idle dashboard hunts |

## The `/scenario` switch

The break-it drill (`make phase4-break`) POSTs to flip the synthetic state:

```bash
curl -X POST "http://<exporter>:9400/scenario?name=mem-pressure"   # GPU 0 → 98% FB
curl -X POST "http://<exporter>:9400/scenario?name=thermal"        # GPU 2 → 92 °C
curl -X POST "http://<exporter>:9400/scenario?name=xid"            # GPU 0 → XID error
curl -X POST "http://<exporter>:9400/scenario?name=normal"         # reset
```

## How it's deployed

[`../scripts/up.sh`](../scripts/up.sh) creates a ConfigMap from `app.py` and runs it
on a stock `python:3.12-slim` image - **no image build, no registry**. The
[`../manifests/servicemonitor.yaml`](../manifests/servicemonitor.yaml) points
Prometheus at it; [`../manifests/alerts.yaml`](../manifests/alerts.yaml) defines the
rules.

Run it standalone to inspect the output:

```bash
PORT=9400 python3 app.py &
curl -s localhost:9400/metrics | grep DCGM_FI_PROF_SM_ACTIVE
```

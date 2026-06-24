# fake-dcgm-exporter - synthetic DCGM metrics, no GPU

> 📖 This is a code companion. The full tutorial - how this exporter fits the scrape →
> dashboard → alert → runbook pipeline, the four-GPU fleet, and the break-it drill - lives
> in the lesson: **[Lesson 3 - GPU Observability](../README.md)**.

[`app.py`](./app.py) serves Prometheus metrics using the **exact field names and labels**
of NVIDIA's real [DCGM Exporter](https://github.com/NVIDIA/dcgm-exporter) (`DCGM_FI_DEV_*`,
`DCGM_FI_PROF_*`) - but every value is fabricated. It lets Lesson 3 build and validate the
whole observability pipeline before any real GPU exists.

> **SCOPE NOTE:** synthetic values. A dashboard or alert built on this proves **design**,
> not real telemetry. Real DCGM evidence comes only from the
> [Lesson 6](../../01-k8s-gpu-platform/gpu-operator-real/README.md) hardware run.

## Run it standalone

```bash
# run from the repo root (same place you run the make targets):
PORT=9400 python3 portfolio-lab/03-observability/fake-dcgm-exporter/app.py &
curl -s localhost:9400/metrics | grep DCGM_FI_PROF_SM_ACTIVE
```

## The `/scenario` switch

POST to flip the synthetic state (this is what `make phase4-break` drives):

```bash
curl -X POST "localhost:9400/scenario?name=mem-pressure"   # a GPU → 98% framebuffer
curl -X POST "localhost:9400/scenario?name=thermal"        # GPU 2 → 92 °C
curl -X POST "localhost:9400/scenario?name=xid"            # a GPU → XID error
curl -X POST "localhost:9400/scenario?name=normal"         # reset
```

## How it's deployed

[`../scripts/up.sh`](../scripts/up.sh) creates a ConfigMap from `app.py` and runs it on a
stock `python:3.12-slim` image - **no image build, no registry**.
[`../manifests/servicemonitor.yaml`](../manifests/servicemonitor.yaml) points Prometheus at
it; [`../manifests/alerts.yaml`](../manifests/alerts.yaml) defines the rules.

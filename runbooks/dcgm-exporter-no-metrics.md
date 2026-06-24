# Runbook - DCGM Exporter Producing No Metrics

**Severity:** Medium-High - GPU telemetry goes dark: dashboards empty out and
*every* utilization/health alert silently stops evaluating. You lose visibility right
when you might need it most. **Applies to:** any cluster scraping a DCGM exporter -
the real NVIDIA [DCGM Exporter](https://github.com/NVIDIA/dcgm-exporter) (GPU Operator)
or this course's synthetic `fake-dcgm-exporter` (Lesson 3). Triage is the same; only the
bottom layer (real DCGM vs the Python stand-in) differs.

> 🔔 **This is what `DCGMExporterAbsent` pages on.** That alert uses `absent()` on the
> DCGM metrics, so it trips ~60s after the series disappear. The Lesson 3 break-it drill
> (`make phase4-break`) fires it on purpose by scaling the exporter to zero - run that to
> rehearse this runbook end to end.

## Symptom

- Grafana GPU panels read "No data"; `DCGM_FI_*` queries in Prometheus return nothing.
- `DCGMExporterAbsent` is firing (and downstream GPU alerts have gone quiet because their
  input series are gone).
- In **Prometheus → Status → Targets**, the exporter target is **DOWN** or absent.

## Triage order (top of the scrape path down)

Walk from "is Prometheus even getting it?" down to "is the exporter producing it?".

### 1. Confirm the scope

```bash
# Is it all GPUs, or one node? Empty result = nothing is being scraped.
# (run via a port-forward to Prometheus on :9090)
curl -s 'http://localhost:9090/api/v1/query?query=count(DCGM_FI_DEV_GPU_TEMP)' | jq '.data.result'
```

- One node missing → exporter/DCGM problem on that node (skip to step 4/5).
- *All* gone → scrape wiring or the exporter Deployment (steps 2-4).

### 2. Is the Prometheus target up?

In **Status → Targets**, find the exporter job, or query it:

```bash
curl -s 'http://localhost:9090/api/v1/query?query=up{job=~".*dcgm.*"}' | jq '.data.result'
```

- Target **DOWN** with a connection error → exporter not reachable (step 3).
- Target **missing entirely** → Prometheus isn't discovering it; the ServiceMonitor
  isn't matching (step 4).

### 3. Is the exporter pod running and serving?

```bash
# Lesson 3 (synthetic): namespace gpu-observability
kubectl -n gpu-observability get pods -l app=fake-dcgm-exporter
# real cluster: the GPU Operator's exporter
kubectl -n gpu-operator get pods -l app=nvidia-dcgm-exporter
```

Pod not `Running`/`Ready`:
- `Pending` / `ContainerCreating` for a long time → usually a slow image pull or no
  schedulable node; `kubectl describe pod` and read the events.
- `CrashLoopBackOff` → `kubectl logs` it; on real hardware this is often DCGM/
  `nv-hostengine` not reachable on the node (step 5).

Pod *is* Ready but the target was down → scrape the exporter directly to split "exporter
broken" from "Prometheus can't reach it":

```bash
kubectl -n gpu-observability exec deploy/fake-dcgm-exporter -- \
  python -c "import urllib.request;print(urllib.request.urlopen('http://localhost:9400/metrics').read()[:200])"
```

- Metrics come back here but the target is still down → it's the scrape wiring (step 4),
  not the exporter.

### 4. Is the ServiceMonitor matching?

Prometheus only scrapes what a ServiceMonitor selects. A label/namespace mismatch makes
the target vanish silently.

```bash
kubectl get servicemonitor -A | grep -i dcgm
kubectl -n gpu-observability get svc -l app=fake-dcgm-exporter --show-labels
```

- The ServiceMonitor's `selector.matchLabels` must match the **Service's** labels, and its
  port name must match the Service's port name. The Operator's `kube-prometheus-stack`
  also restricts which ServiceMonitors it picks up via
  `serviceMonitorSelector` / `serviceMonitorNamespaceSelector` - confirm yours is in scope.

### 5. Real hardware only - is DCGM itself healthy on the node?

The synthetic exporter has no GPU dependency, so skip this in the sim. On a real node the
exporter reads from DCGM / `nv-hostengine`:

```bash
nvidia-smi                      # driver alive?
dcgmi discovery -l              # DCGM sees the GPUs?
```

- `nvidia-smi` fails → driver problem first; see
  [gpu-node-not-ready.md](gpu-node-not-ready.md).
- `nvidia-smi` works but `dcgmi` can't talk to the host engine → restart the exporter pod
  (it embeds/contacts `nv-hostengine`); check its logs for the DCGM connection error.

## Resolution verification

```bash
# target back UP:
curl -s 'http://localhost:9090/api/v1/query?query=up{job=~".*dcgm.*"}' | jq '.data.result[].value[1]'
# series flowing again (one per GPU):
curl -s 'http://localhost:9090/api/v1/query?query=DCGM_FI_PROF_SM_ACTIVE' | jq '.data.result | length'
```

`DCGMExporterAbsent` clears on its own once the series return.

## Prevention

- Keep `DCGMExporterAbsent` (an `absent()` rule) so a silent exporter pages instead of
  just blanking dashboards - the failure mode here is *invisible* without it.
- Treat the exporter as critical infra: set resource requests so it isn't evicted, and
  alert on its target being `up == 0` as well as on `absent()`.
- Pin the exporter/ServiceMonitor labels; a relabel in a chart upgrade is the classic way
  a target silently stops being scraped.

## Drill in this lab

Lesson 3 (simulation): `make phase4-up`, then `make phase4-break` - drill 1 scales the
exporter to zero and you watch the target go **DOWN** and `DCGMExporterAbsent` fire
(~60s), then it restores. Walk steps 1-4 above while it's down. Real mode: on the
Lesson 6 GPU node, stop the GPU Operator's `nvidia-dcgm-exporter` and walk the same path
including step 5, capturing output for the validation report.

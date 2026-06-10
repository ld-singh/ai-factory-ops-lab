# kind/

Local Kubernetes cluster for simulation mode.

```bash
kind create cluster --config kind-config.yaml
```

Or from the repo root: `make phase1-up` (idempotent — skips creation if the
cluster already exists).

Why kind and not k3d? Either works; kind is used here because KWOK examples and
most scheduler-development workflows assume it. Swap freely if you prefer k3d.

# Lesson 1 · Deep dive - The local cluster (kind)

> Part of [Lesson 1 - Kubernetes GPU Scheduling](../README.md).

🎯 **Objective:** know what `make phase1-up` actually creates under the hood and why
the cluster shape was chosen.

Local Kubernetes cluster for simulation mode. `make phase1-up` calls this for you,
but you can create it directly:

```bash
kind create cluster --config kind-config.yaml
```

💡 **Why this shape:** the [config](./kind-config.yaml) is one control-plane node and
one *real* worker. The real worker hosts system pods (KWOK controller, CoreDNS). All
the "GPU nodes" are KWOK fake nodes added afterward - they exist only as API objects,
which is exactly the point: the scheduler treats `nvidia.com/gpu` as an opaque
integer either way.

From the repo root: `make phase1-up` is idempotent - it skips creation if the cluster
already exists (see [`../scripts/setup-kind.sh`](../scripts/setup-kind.sh)).

💡 **kind vs k3d?** Either works; kind is used here because KWOK examples and most
scheduler-development workflows assume it. Swap freely if you prefer k3d.

✅ **Checkpoint:** `kubectl get nodes` shows a control-plane node and one worker
(the `kwok-gpu-*` nodes appear only after Step 1's later scripts run).

➡️ **Back to:** [Lesson 1, Step 1](../README.md#step-1---stand-up-the-simulated-fleet).

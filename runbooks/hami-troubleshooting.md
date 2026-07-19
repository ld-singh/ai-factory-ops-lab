# Runbook - HAMi Troubleshooting (GPU sharing)

**Severity:** High - GPU pods stay Pending, land on the wrong scheduler, or run without their
memory slice enforced.
**Applies to:** clusters running [HAMi](https://project-hami.io/) for fractional GPU sharing.
Grounded in the validated Lesson 6 runs:
[Part B - HAMi isolation](../portfolio-lab/06-validation-reports/hami-isolation-validation.md)
and
[Part C - HAMi + GPU Operator coexistence](../portfolio-lab/06-validation-reports/hami-gpu-operator-coexistence-validation.md).

HAMi has a handful of failure modes that each look like something else. This runbook is
symptom-first: find your symptom, confirm the cause, apply the fix.

| Symptom | Most likely cause | Section |
|---|---|---|
| Pod Pending, `Insufficient nvidia.com/gpumem` from **default-scheduler** | the webhook did not route the pod | [1](#1-pod-pending-with-insufficient-nvidiacomgpumem) |
| `nvidia.com/gpumem` missing from `kubectl describe node` | by design, it is not an allocatable resource | [2](#2-gpumem-is-not-in-node-allocatable) |
| In-pod `nvidia-smi` shows the **full** card, not the slice | `nvidia` is not the default runtime | [3](#3-in-pod-nvidia-smi-shows-the-whole-card) |
| Two device plugins, GPU pods flapping / double-counted | HAMi and another device plugin coexisting | [4](#4-hami-and-the-gpu-operators-device-plugin-conflict) |
| `hami-scheduler` pod `ImagePullBackOff` | the kube-scheduler sidecar's default registry | [5](#5-hami-scheduler-imagepullbackoff) |
| Node shows `nvidia.com/gpu: 10` for one card | `deviceSplitCount`, working as intended | [6](#6-nvidiacomgpu-shows-10-for-one-card) |
| Node "unregistered" or empty register annotation | device plugin cannot see the GPU or node unlabelled | [7](#7-node-unregistered-or-empty-register-annotation) |

---

## 1. Pod Pending with `Insufficient nvidia.com/gpumem`

The single most confusing HAMi failure, because the error names a resource and looks like a
capacity problem.

**Symptom**

```
Warning  FailedScheduling  default-scheduler  0/1 nodes are available:
  1 Insufficient nvidia.com/gpumem, 1 Insufficient nvidia.com/gpucores.
```

**The giveaway is `From: default-scheduler`.** HAMi pods are supposed to be handled by
`hami-scheduler`. `gpumem`/`gpucores` are never in node allocatable (see section 2), so any
pod that reaches the **default** scheduler fails exactly this way.

**Cause.** HAMi's mutating webhook rewrites the pod's `schedulerName` to `hami-scheduler`. It
is registered with **`failurePolicy: Ignore`**, so if the webhook cannot be reached (most
often because `hami-scheduler` is still rolling out, or its Service has no endpoints), the pod
is admitted **unmutated** rather than rejected. It keeps `default-scheduler` and fails.

**Confirm**

```bash
kubectl get pod <pod> -o jsonpath='{.spec.schedulerName}'; echo
# hami-scheduler  -> webhook fired (look elsewhere)
# default-scheduler -> the webhook missed this pod

kubectl -n kube-system get endpoints hami-scheduler          # must be non-empty
kubectl -n kube-system rollout status deploy/hami-scheduler
```

**Fix.** The webhook only fires on **CREATE**, so waiting does not repair an existing pod.
Wait for the scheduler to be Ready, then **delete and re-apply**:

```bash
kubectl -n kube-system rollout status deploy/hami-scheduler --timeout=180s
kubectl delete -f <your-pod-manifest> && kubectl apply -f <your-pod-manifest>
kubectl get pod <pod> -o jsonpath='{.spec.schedulerName}'; echo   # want: hami-scheduler
```

If it still says `default-scheduler` after the scheduler is Ready, the webhook itself is
broken. Check the webhook config and the extender logs:

```bash
kubectl get mutatingwebhookconfiguration hami-webhook -o yaml | grep -A6 clientConfig
kubectl -n kube-system logs deploy/hami-scheduler -c vgpu-scheduler-extender --tail=50
```

---

## 2. `gpumem` is not in node allocatable

**Symptom.** `kubectl describe node` shows `nvidia.com/gpu` but no `nvidia.com/gpumem` or
`nvidia.com/gpucores`, and you assume the node is misconfigured.

**This is by design, not a bug.** HAMi advertises **only `nvidia.com/gpu`** in
`status.allocatable`. The shareable memory and compute are recorded in the
**`hami.io/node-nvidia-register`** node annotation, which the HAMi scheduler scores against and
HAMi-core enforces per-pod. So the health check is `nvidia.com/gpu` present **and** the
annotation populated:

```bash
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl get node "$NODE" -o jsonpath='{.status.allocatable.nvidia\.com/gpu}'; echo
kubectl get node "$NODE" -o jsonpath='{.metadata.annotations.hami\.io/node-nvidia-register}'; echo
```

The annotation looks like (one entry per physical GPU):

```
[{"id":"GPU-...","count":10,"devmem":49140,"devcore":100,"type":"NVIDIA L40","mode":"hami-core",...}]
```

`devmem` (MiB) and `devcore` (percent) are what a pod's `nvidia.com/gpumem` /
`nvidia.com/gpucores` requests are scored against. If the annotation is empty, go to
[section 7](#7-node-unregistered-or-empty-register-annotation).

---

## 3. In-pod `nvidia-smi` shows the whole card

**Symptom.** A pod requesting `nvidia.com/gpumem: 4000` is Running, but `kubectl exec <pod> --
nvidia-smi` reports the full card (e.g. `49140MiB`) instead of the `4000MiB` slice. HAMi-core
is not enforcing the cap.

**Cause.** HAMi's pods do **not** set `runtimeClassName`, so HAMi-core (`libvgpu.so`) is only
injected when `nvidia` is the node's **default** container runtime. A `nvidia` RuntimeClass
alone is not enough: a RuntimeClass is opt-in per pod, and HAMi never opts in.

**Confirm** (on a k3s node)

```bash
sudo grep default_runtime_name /var/lib/rancher/k3s/agent/etc/containerd/config.toml
# want: default_runtime_name = "nvidia"

kubectl exec <pod> -- bash -c 'env | grep -iE "CUDA_DEVICE_MEMORY_LIMIT|libvgpu"'
# want: CUDA_DEVICE_MEMORY_LIMIT_0=4000m   and libvgpu.so present
```

**Fix.** Make `nvidia` the default runtime the clean way (k3s's own `--default-runtime` flag,
not a hand-edited containerd config), then recreate the pod. Full procedure:
[k3s default runtime / containerd config](k3s-default-runtime-containerd-config.md).

---

## 4. HAMi and the GPU Operator's device plugin conflict

**Symptom.** GPU pods flap, `nvidia.com/gpu` counts look wrong or double, or scheduling is
inconsistent. Two device plugins are advertising `nvidia.com/gpu` on the same node.

**Cause.** HAMi ships its **own** device plugin. The NVIDIA GPU Operator (and the standalone
NVIDIA k8s device plugin) ship one too. Two device plugins owning the same resource name on
one node conflict, and for fractional sharing the owner must be HAMi's.

**Fix depends on what you want:**

- **HAMi alone** (the simplest, Lesson 6 Part B): run HAMi with **no** GPU Operator. Install
  the driver + toolkit on the host, set `nvidia` as the default runtime, install HAMi. HAMi's
  `install-hami.sh` refuses to run if it finds another device plugin, precisely to prevent
  this.
- **HAMi + GPU Operator together** (Lesson 6 Part C): keep the Operator for the base stack but
  **disable its device plugin** so HAMi owns the role:

  ```bash
  helm upgrade --install gpu-operator nvidia/gpu-operator -n gpu-operator \
    --set devicePlugin.enabled=false
  ```

  The Operator's driver, toolkit, NFD, validator, and DCGM Exporter keep running and do not
  conflict; only its device plugin is turned off. Validated end to end in
  [Part C - coexistence](../portfolio-lab/01-k8s-gpu-platform/hami/hami-gpu-operator-coexistence/README.md).

**Confirm** the Operator's device plugin is gone and HAMi's is present:

```bash
kubectl get pods -n gpu-operator | grep -i device-plugin   # expect no output
kubectl -n kube-system get pods | grep -i hami-device-plugin
```

---

## 5. `hami-scheduler` ImagePullBackOff

**Symptom.** The `hami-scheduler` pod is stuck; describing it shows the **kube-scheduler
sidecar** (not the HAMi container) failing to pull:

```
Failed to pull image "registry.cn-hangzhou.aliyuncs.com/google_containers/kube-scheduler:vX.Y.Z"
read tcp ...:80: read: connection timed out
```

**Cause.** HAMi's chart defaults the kube-scheduler sidecar image to an **Aliyun (China)
registry** that times out from most networks outside China. The HAMi container itself comes
from Docker Hub and pulls fine, so **only the sidecar fails**, which makes this look stranger
than it is.

**Fix.** Point the sidecar at the upstream registry (reinstall or upgrade):

```bash
helm upgrade --install hami hami-charts/hami -n kube-system \
  --set scheduler.kubeScheduler.image.registry=registry.k8s.io \
  --set scheduler.kubeScheduler.image.repository=kube-scheduler
```

In China, keep the Aliyun default (drop the two `--set` flags). Do **not** use
`--set global.imageRegistry=...`: it rewrites **every** image, including
`docker.io/projecthami/hami`, into a path that does not exist.

**Related trap: the sidecar tag must match the Kubernetes server version** (a top HAMi failure
mode). Chart 2.9.0 resolves it automatically from the cluster (stripping the k3s suffix, so
`v1.36.2+k3s1` becomes `v1.36.2`). To pin it by hand the key is
`scheduler.kubeScheduler.image.tag` (note: **not** `scheduler.kubeScheduler.imageTag`, which is
not a chart key and is silently ignored).

---

## 6. `nvidia.com/gpu` shows 10 for one card

**Symptom.** One physical GPU, but `kubectl get node -o ...allocatable.nvidia\.com/gpu`
returns `10` (or some multiple), and you think the node is miscounting.

**Working as intended.** HAMi advertises `nvidia.com/gpu = physical GPUs × deviceSplitCount`,
and `deviceSplitCount` defaults to **10**. It is the maximum number of pods (tasks) that can
share one physical GPU. So one card presents as ten schedulable slots; the real limits on
co-residency are the per-pod `gpumem`/`gpucores` requests against the card's `devmem`/`devcore`
(section 2), not this count.

Set it at install time if you want a different fan-out:

```bash
helm upgrade --install hami hami-charts/hami -n kube-system --set deviceSplitCount=5
```

DCGM (if you run the GPU Operator alongside) still reports the **one physical** card, which is
correct: HAMi's count is virtual, DCGM's is hardware.

---

## 7. Node unregistered or empty register annotation

**Symptom.** The HAMi scheduler logs "node unregistered", or
`hami.io/node-nvidia-register` is empty, so no fractional scheduling happens.

**Triage**

1. **Node label.** HAMi's device plugin only registers nodes labelled `gpu=on` by default.

   ```bash
   kubectl get nodes --show-labels | grep -i gpu
   kubectl label node <node> gpu=on --overwrite    # if missing
   ```

2. **Device plugin can see the GPU.** If the plugin pod cannot reach the GPU (missing driver,
   wrong default runtime), it registers nothing.

   ```bash
   kubectl -n kube-system get pods | grep hami-device-plugin
   kubectl -n kube-system logs <hami-device-plugin-pod> --all-containers --tail=50
   ```

   NVML errors here usually mean the driver or the default runtime (section 3) is the real
   problem.

3. **Simulation only:** on a fake-GPU fleet there is no real plugin to write the annotation, so
   the sim lab writes it explicitly with `register-hami.sh`. On real hardware the device plugin
   writes it; do not set it by hand.

---

## Prevention

- **Gate on the webhook before creating GPU pods.** After installing HAMi, wait for
  `hami-scheduler` to be Ready and its Service to have endpoints. The lab's
  [`install-hami.sh`](../portfolio-lab/01-k8s-gpu-platform/hami/hami-isolation-realgpu/scripts/install-hami.sh)
  does this, and always verify a test pod's `schedulerName` is `hami-scheduler`.
- **Pin the scheduler sidecar tag to the cluster version** and use a reachable registry.
- **Treat `nvidia` as the default runtime** as a hard prerequisite, checked after every node
  provision or reboot.
- **Alert on `nvidia.com/gpu` allocatable dropping** below `physical × deviceSplitCount`, and
  on the register annotation going empty.

## Drill in this lab

- **Simulation (no GPU):**
  [HAMi scheduling sim](../portfolio-lab/01-k8s-gpu-platform/hami/hami-scheduling-sim/README.md)
  reproduces the register-annotation and placement behaviour on a fake fleet.
- **Real GPU:**
  [Part B - HAMi isolation](../portfolio-lab/01-k8s-gpu-platform/hami/hami-isolation-realgpu/README.md)
  and
  [Part C - coexistence](../portfolio-lab/01-k8s-gpu-platform/hami/hami-gpu-operator-coexistence/README.md)
  exercise sections 2 to 6 end to end, with captured evidence in the validation reports.

## Related runbooks

- [Device plugin not advertising GPUs](device-plugin-not-advertising-gpus.md)
- [k3s default runtime / containerd config](k3s-default-runtime-containerd-config.md)
- [GPU memory pressure](gpu-memory-pressure.md)

> Confirm chart keys, resource names, and defaults against the HAMi version you installed:
> [project-hami.io](https://project-hami.io/) and
> [github.com/Project-HAMi/HAMi](https://github.com/Project-HAMi/HAMi). They can change
> between releases.

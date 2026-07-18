# HAMi with the NVIDIA GPU Operator (coexistence)

> Part C of the [Lesson 6 real-GPU capstone](../../../real-gpu-session/README.md), and the
> getting-to-production companion to [Lesson 1C: GPU sharing with HAMi](../README.md) · Course
> home: [AI Factory Operations Lab](../../../../README.md)

> 🟡 **STATUS: RUN-READY GUIDE, pending real-hardware validation.** It is built on the
> documented device-plugin conflict, the known workaround, and the reboot behaviour reported
> upstream. Confirm every command against the current HAMi and GPU Operator docs before you
> rely on it, and capture your own output when you run it.

## Why this comes up

[Part B](../hami-isolation-realgpu/README.md) runs HAMi on its own, with no GPU Operator. That
keeps the lesson clean, but it is not how most clusters are built. The GPU Operator is how the
GPU stack normally gets installed and managed: driver, container toolkit, device plugin, node
feature discovery, DCGM, and validation, all as one Helm release.

Put HAMi next to it and you hit one sharp edge. Both the GPU Operator and HAMi ship a device
plugin, and both advertise `nvidia.com/gpu`. Two device plugins for the same resource on the
same node conflict. You want exactly one owning it, and for fractional sharing that has to be
HAMi's.

The fix is a division of labour: **the Operator keeps the base stack, HAMi takes the device
plugin.** That is what this part sets up.

## Prerequisites

- A GPU node (any non-MIG card, as in [Lesson 6](../../../real-gpu-session/README.md)).
- Its **own cluster.** Do not reuse Part A's VM as-is, since Part A installs the Operator
  *with* its device plugin enabled. Either a fresh VM or this one after
  `helm uninstall gpu-operator`.
- `kubectl` and `helm` on the VM. `host-setup.sh` (Step 1) installs k3s and brings `kubectl`
  with it, but **not** `helm`. Step 3 installs helm if you do not have it.

---

## Setup

### Step 0: Get the lab onto the VM

```bash
# ON THE GPU VM
git clone https://github.com/ld-singh/ai-factory-ops-lab.git
cd ai-factory-ops-lab
```

Run everything below **from the repo root, on the VM.**

### Step 1: Base host (k3s + the NVIDIA Container Toolkit)

Same script every Lesson 6 part starts from. It installs the NVIDIA Container Toolkit and k3s,
creates the `nvidia` RuntimeClass, and labels the node `gpu=on` (HAMi schedules onto that
label).

```bash
sudo PUBLIC_IP=<vm-ip> bash portfolio-lab/real-gpu-session/scripts/host-setup.sh
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

✅ **Gate:** `nvidia-smi` works on the host and `kubectl get nodes` is Ready.

Full walkthrough of this script: [setup scripts](../../../real-gpu-session/scripts/README.md).

### Step 2: Make nvidia the default container runtime

HAMi's pods do not set `runtimeClassName`, so HAMi-core is only injected if `nvidia` is the
node's **default** containerd runtime. The `nvidia` RuntimeClass that `host-setup.sh` creates
is not enough on its own: a RuntimeClass is opt-in per pod, and HAMi never opts in.

Part B already scripts this. Run it (from the repo root, on the VM, as root):

```bash
sudo bash portfolio-lab/01-k8s-gpu-platform/hami/hami-isolation-realgpu/scripts/set-default-runtime.sh
```

It sets `default-runtime: nvidia` in `/etc/rancher/k3s/config.yaml` using k3s's own
`--default-runtime` flag, restarts k3s, waits for the node to come back Ready, and verifies the
generated containerd config. It is idempotent, so re-running it is safe. Nothing here edits
containerd's `config.toml` directly: k3s regenerates that file on every start, so hand-edits are
either overwritten or break the node.

> ⚠️ **Ignore the script's `./install-hami.sh` suggestion.** That script is shared with Part B,
> which installs HAMi next because it runs without the Operator. **Here the GPU Operator has to
> go in first** (Step 3), with its device plugin disabled. Installing HAMi now would leave the
> Operator's device plugin owning `nvidia.com/gpu`, which is the exact conflict this part
> exists to avoid.

✅ **Verify:**

```bash
sudo grep default_runtime_name /var/lib/rancher/k3s/agent/etc/containerd/config.toml
# expect: default_runtime_name = "nvidia"
systemctl is-active k3s     # expect: active
kubectl get nodes           # expect: Ready
```

✅ **Gate:** a pod with **no** `runtimeClassName` can still see the GPU.

> ⚠️ **If k3s will not restart**, you probably have a stale containerd template from an earlier
> attempt. Remove it and let k3s regenerate a clean config:
> `sudo rm -f /var/lib/rancher/k3s/agent/etc/containerd/config*.toml.tmpl && sudo systemctl restart k3s`.
> Full diagnosis, including the containerd v2 vs v3 schema trap and what to do if your k3s
> build lacks `--default-runtime`:
> [k3s default runtime runbook](../../../../runbooks/k3s-default-runtime-containerd-config.md).

### Step 3: Install the GPU Operator with its device plugin off

Steps 3 and 4 use `helm`, which `host-setup.sh` does **not** install. If you get
`Command 'helm' not found`, install it with the official script (the same one
[Part A's installer](../../../real-gpu-session/scripts/install-gpu-operator.sh) uses):

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | sudo bash
helm version
```

> Prefer this over `snap install helm`. The snap runs under confinement that can struggle to
> read `/etc/rancher/k3s/k3s.yaml` and your `KUBECONFIG`, which turns into confusing permission
> errors later.

Now the actual step. This is the whole trick: one flag, `devicePlugin.enabled=false`, leaves the
device-plugin role open for HAMi.

```bash
# ILLUSTRATIVE. Confirm current values against the GPU Operator docs.
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update nvidia

helm upgrade --install gpu-operator nvidia/gpu-operator \
  -n gpu-operator --create-namespace \
  --set driver.enabled=false \
  --set toolkit.enabled=false \
  --set devicePlugin.enabled=false \
  --wait --timeout 10m
```

**Why `driver` and `toolkit` are also off here.** On this course's VM the driver comes from the
deep-learning image and the toolkit came from `host-setup.sh` in Step 1, so the Operator must
not install them again. This matches
[Part A's installer](../../../real-gpu-session/scripts/install-gpu-operator.sh), which sets the
same two flags. What the Operator still gives you is **DCGM Exporter, GPU Feature Discovery,
node feature discovery, and the validator**, none of which conflict with HAMi.

> **In a production cluster the Operator usually does own the driver and toolkit**
> (`driver.enabled=true`, `toolkit.enabled=true`). The device-plugin flag is the same either
> way. That case is where the [reboot gotcha](#the-reboot-gotcha) below matters.

✅ **Check:** no Operator device-plugin pod, but DCGM and the validator are Running.

```bash
kubectl get pods -n gpu-operator
kubectl get pods -n gpu-operator | grep -i device-plugin   # expect no output
```

At this point the node advertises **no** `nvidia.com/gpu` at all. Nothing owns the resource
yet. That is expected, and Step 4 fixes it.

### Step 4: Install HAMi and let it own the device plugin

```bash
# ILLUSTRATIVE. Confirm the repo, chart, and values against the HAMi install docs.
helm repo add hami-charts https://project-hami.github.io/HAMi
helm repo update hami-charts

helm upgrade --install hami hami-charts/hami \
  --version 2.9.0 \
  -n kube-system \
  --set scheduler.kubeScheduler.image.registry=registry.k8s.io \
  --set scheduler.kubeScheduler.image.repository=kube-scheduler \
  --wait --timeout 5m
```

> ⚠️ **Why the two `image` overrides.** HAMi's scheduler pod runs a `kube-scheduler` sidecar,
> and the chart defaults its image to an **Aliyun (China) registry**. From most VMs outside
> China that pull times out and the pod sits in `ImagePullBackOff`:
>
> ```
> Failed to pull image "registry.cn-hangzhou.aliyuncs.com/google_containers/kube-scheduler:v1.36.2"
> read tcp ...:80: read: connection timed out
> ```
>
> The HAMi container itself comes from Docker Hub and pulls fine, so **only the sidecar
> fails**, which makes this look stranger than it is. If you *are* in China, drop the two
> overrides and use the chart default.
>
> Do **not** reach for `--set global.imageRegistry=...` here. It rewrites *every* image,
> turning `docker.io/projecthami/hami` into a path that does not exist.

The sidecar's **tag must match your Kubernetes server version**, which is the most common HAMi
failure. Chart 2.9.0 resolves it automatically from the cluster (stripping the k3s suffix, so
`v1.36.2+k3s1` becomes `v1.36.2`), so you do not normally set it. To pin it by hand, the key is
`scheduler.kubeScheduler.image.tag`.

The node was already labelled `gpu=on` by `host-setup.sh`. If you skipped that script:
`kubectl label node <gpu-node> gpu=on --overwrite`.

✅ **Check:** HAMi's pods are Running and the node advertises `nvidia.com/gpu` again, now at
HAMi's **virtual** count (physical GPUs times `deviceSplitCount`, default 10, so one card
usually shows as 10).

```bash
kubectl get pods -n kube-system | grep -i hami
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl get node "$NODE" -o jsonpath='{.status.allocatable.nvidia\.com/gpu}'; echo
kubectl get node "$NODE" -o jsonpath='{.metadata.annotations.hami\.io/node-nvidia-register}'; echo
```

The `hami.io/node-nvidia-register` annotation, not node allocatable, is where per-GPU memory
and cores are accounted. `nvidia.com/gpumem` and `nvidia.com/gpucores` never appear in
allocatable, which surprises people the first time.

### Step 5: Prove it works end to end

Run a fractional pod. This lab ships its own, sized small so it fits any card in the course:
[`manifests/fractional-pod.yaml`](./manifests/fractional-pod.yaml).

```bash
kubectl apply -f portfolio-lab/01-k8s-gpu-platform/hami/hami-gpu-operator-coexistence/manifests/fractional-pod.yaml
kubectl get pod hami-coexist-fractional -o wide
```

> 📎 **Do not apply [`../examples/`](../examples/README.md).** Those are **illustrative**
> snippets for reading alongside the Lesson 1C concepts, with `CONFIRM name/unit` markers
> rather than pinned values. The runnable, real-GPU manifests are this lab's `manifests/` and
> Part B's
> [`hami-isolation-realgpu/manifests/`](../hami-isolation-realgpu/manifests/share-two-pods.yaml).

> ⚠️ **Wait for the HAMi scheduler before creating any GPU pod.** HAMi's mutating webhook is
> what rewrites your pod's `schedulerName` to `hami-scheduler`, and it is registered
> **`failurePolicy: Ignore`**. If the webhook cannot be reached (typically because the
> scheduler is still rolling out), your pod is admitted **unmutated** rather than rejected, so
> the **default** scheduler takes it and fails with:
>
> ```
> Warning  FailedScheduling  default-scheduler  0/1 nodes are available:
>   1 Insufficient nvidia.com/gpumem.
> ```
>
> That looks like HAMi is broken. It is not. `gpumem` and `gpucores` are **never** in node
> allocatable, so any pod reaching the default scheduler fails exactly this way, naming
> whichever of them it asked for. **The giveaway is `From: default-scheduler`** rather than the
> HAMi scheduler.
>
> ```bash
> kubectl -n kube-system rollout status deploy/hami-scheduler --timeout=180s
> kubectl get pod hami-coexist-fractional -o jsonpath='{.spec.schedulerName}'; echo
> # want: hami-scheduler   |   got default-scheduler? the webhook missed it
> ```
>
> The webhook only fires on **CREATE**, so waiting does not repair an existing pod. **Delete
> and re-apply it.** `capture-evidence.sh` gates on this and fails loudly rather than leaving
> you a mysterious Pending pod.

✅ **Gate (the whole point of this part):** a pod requesting a *fraction* of the card is
Running, HAMi scheduled it, and the Operator's DCGM Exporter is still reporting real counters
for the same physical GPU.

```bash
kubectl -n gpu-operator port-forward svc/nvidia-dcgm-exporter 9400:9400 &
curl -s localhost:9400/metrics | grep DCGM_FI_DEV_FB_USED
```

DCGM reports **physical** GPU counters and is unaffected by HAMi's virtual accounting. So a
node showing `nvidia.com/gpu: 10` still has exactly one real card in DCGM, and that is correct,
not a bug.

---

## The reboot gotcha

This one costs people an afternoon, and it only bites when the **Operator manages the driver**
(`driver.enabled=true`, the common production setup, not this course's VM).

On reboot the Operator reinstalls or reloads the driver. Anything needing the GPU that starts
before the driver is ready can CrashLoopBackOff, including HAMi's device-plugin pod. It is
reported upstream against HAMi under the Operator
([#136](https://github.com/Project-HAMi/HAMi/issues/136),
[#157](https://github.com/Project-HAMi/HAMi/issues/157)).

The shape of the fix is ordering: GPU pods must wait for the driver.

- Let the Operator's driver-ready gating do its job. The validator and the node feature labels
  exist so scheduling waits for the driver to finish.
- If HAMi's device-plugin pod CrashLoopBackOffs right after a reboot, check the driver
  daemonset is Ready before treating it as a real failure. It usually clears on its own once
  the driver finishes loading.

```bash
kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset
kubectl get pods -n kube-system | grep -i hami-device-plugin
```

This is the part most worth validating carefully on hardware. Capture the actual reboot
behaviour and note whichever readiness gate makes it deterministic in your setup.

## 📸 Capture the evidence

Steps 1 to 5 are the run. This is the deliverable. One script snapshots everything into a
tarball you scp back before teardown:

```bash
# from the repo root on the VM, after Steps 1-4
bash portfolio-lab/01-k8s-gpu-platform/hami/hami-gpu-operator-coexistence/scripts/capture-evidence.sh
```

It applies the fractional pod itself and captures six artifacts:

| # | Artifact | What it backs |
|---|---|---|
| 1 | `1-operator-pods.txt` | Operator components Running, and **no** device-plugin pod |
| 2 | `2-operator-helm-values.txt` | `devicePlugin.enabled=false` in the released values (the disabling was deliberate, not an accident) |
| 3 | `3-hami-pods.txt`, `3-node-allocatable.txt` | HAMi owns the plugin: virtual `nvidia.com/gpu` count + the register annotation |
| 4 | `4-default-runtime.txt` | `default_runtime_name = "nvidia"` |
| 5 | `5-fractional-pod.txt`, `5-fractional-in-pod-smi.txt`, `5-fractional-hami-core.txt` | a fractional pod placed by the HAMi scheduler, with the slice enforced in-pod |
| 6 | `6-dcgm-metrics.txt` | DCGM still reporting physical counters beside HAMi |

Then record the results in
[`hami-gpu-operator-coexistence-validation.md`](../../../06-validation-reports/hami-gpu-operator-coexistence-validation.md).
**That filled report is what flips this part from run-ready to validated**, and it is the
deliverable, not the VM.

Some artifacts read host files (`/etc/rancher/k3s/...`), so run the script as a user with
passwordless sudo or capture Artifact 4 by hand. The script tells you which.

Also worth capturing if you test it: the reboot sequence below.

## What this proves, and what it does not

Proves a clean single-node coexistence: the Operator owns the base stack, HAMi owns fractional
device management, and the two do not fight over `nvidia.com/gpu`. It does not prove multi-node
rollout, MIG mode, or behaviour under sustained load.

## Related

- The isolation half: [Part B - HAMi isolation on a real GPU](../hami-isolation-realgpu/README.md)
- Runbook: [device plugin not advertising GPUs](../../../../runbooks/device-plugin-not-advertising-gpus.md)
- Runbook: [k3s default runtime and containerd config](../../../../runbooks/k3s-default-runtime-containerd-config.md)
- Upstream discussion: [HAMi #1708](https://github.com/Project-HAMi/HAMi/issues/1708)
- Confirm all values against the official [HAMi](https://project-hami.io/) and
  [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html)
  docs before running.

➡️ **Next:** [Part D - Real inference benchmark](../../../04-inference-serving/inference-realgpu/README.md).

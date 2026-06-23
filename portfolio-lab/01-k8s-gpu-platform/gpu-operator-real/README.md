# Lesson 6 (Part A) - Real GPU runtime path + evidence

> Part of [Lesson 6 - Real GPU](../../real-gpu-session/README.md) · Course home:
> [AI Factory Operations Lab](../../../README.md)
>
> Start at the [Lesson 6 hub](../../real-gpu-session/README.md) for the full session order
> (host setup → **this runtime path** → HAMi sharing → inference → Slurm GRES → teardown).

This is the **real-hardware foundation** of the course. In Lesson 1 you deliberately could
not prove anything below the kubelet. Here you prove the whole thing - the complete GPU
path to a running pod - on actual silicon, and capture the evidence.

> ✅ **Validated.** Captured on a **Hyperstack RTX A6000** (driver 535.183.06, k3s v1.35,
> GPU Operator) on 2026-06-22:
> [`real-gpu-validation-report.md`](../../06-validation-reports/real-gpu-validation-report.md)
> · evidence in
> [`evidence/gpu-evidence-20260622-071518/`](../../06-validation-reports/evidence/).
> The steps below reproduce it on a fresh VM.

🎯 **After this part you can:**

1. Stand up the full GPU path link by link: driver → container toolkit → runtime class →
   device plugin (GPU Operator) → kubelet → scheduler → CUDA container.
2. Confirm the node advertises *real* `nvidia.com/gpu` and *discovered* GFD labels, and
   contrast them with the script-written labels from Lesson 1.
3. Run a CUDA pod that executes `nvidia-smi` on a real GPU - the single most important
   artifact in the course.
4. Pull real DCGM telemetry, the foundation [Lesson 3](../../03-observability/README.md)
   builds on.

🧭 **Mode:** 🟥 Real GPU. One machine with an NVIDIA card - a **bare GPU VM you get root
on** (Hyperstack, Lambda, hyperscaler) or a local GPU box. An L4 (24 GB) or RTX A6000
(48 GB) is plenty; never an A100/H100. Marketplace *containers* (Vast.ai/RunPod pods)
don't work - they can't install the toolkit + k3s.

📋 **Prerequisites:** [Lesson 1](../README.md) done (you know what the simulation did and
didn't prove), and a budget of a few dollars for the VM.

> **The iron rule: tear the VM down the moment evidence is captured.** The evidence
> directory is the deliverable; the VM has no residual value. Delete the boot/storage
> volume too if it's billed separately.

---

## What this validates (that simulation cannot)

The full GPU path to a pod, link by link, plus real telemetry:

```
NVIDIA driver → NVIDIA Container Toolkit → containerd runtime class
→ NVIDIA device plugin (GPU Operator) → kubelet → scheduler → CUDA container → DCGM
```

There are **two ways to run it**: the scripted path (what produced the validated evidence
above) or the manual steps (do it by hand to understand each link). Both end at the same
evidence.

---

## Option 1 - Scripted path (fast)

> ℹ️ **Already did the [Lesson 6 setup](../../real-gpu-session/scripts/README.md)?** Those
> scripts already do host setup → kubeconfig → `install-gpu-operator.sh`, so the cluster
> and GPU Operator are **already up**. Don't repeat the install block below - skip straight
> to [Capture evidence](#capture-evidence).

If you haven't set the host up yet, the
[`real-gpu-session/scripts/`](../../real-gpu-session/scripts/README.md) directory automates
it (read [`scripts/README.md`](../../real-gpu-session/scripts/README.md) first):

```bash
# same commands as the Lesson 6 setup - SKIP if you already ran them
scp -i <key> -r portfolio-lab/real-gpu-session/scripts <user>@<vm-ip>:~/lesson6-scripts
sudo PUBLIC_IP=<vm-ip> bash host-setup.sh      # on the VM: NVIDIA toolkit + k3s + API cert
./fetch-kubeconfig.sh <ssh-user>@<vm-ip> --key <ssh-key>   # on your laptop (open TCP 6443 first)
export KUBECONFIG=$PWD/kubeconfig-gpuvm
./install-gpu-operator.sh                       # GPU Operator + DCGM + a CUDA smoke pod
```

### Capture evidence

Whether the operator went up just now or during setup, this is all Part A still needs.
Run on the VM - it writes a tarball you scp back:

```bash
./capture-evidence.sh
# from your laptop:
scp -i <key> <user>@<vm-ip>:~/gpu-evidence-*.tgz \
  ./portfolio-lab/06-validation-reports/evidence/
```

`capture-evidence.sh` snapshots host + in-pod `nvidia-smi`, `nvidia.com/gpu` allocatable,
GFD labels, the GPU Operator pods, and real DCGM metrics - the full Part A evidence set.

✅ **Gate:** `nvidia-smi` from inside a scheduled pod, and real `DCGM_FI_*` metrics whose
values match `nvidia-smi`.

---

## Option 2 - Manual steps (understand each link)

Same result, by hand. Each step has a **Pass criteria** - its checkpoint.

> ℹ️ **Operator already up** (from the Lesson 6 setup)? Then **don't reinstall** -
> reinstalling on top of a working operator only risks breaking it. Use the steps below
> purely to *inspect* each link (the `kubectl` / `nvidia-smi` checks), then
> [capture evidence](#capture-evidence).

> **VERSION WARNING:** package names, image tags, and Helm chart versions drift with
> driver/CUDA/Kubernetes releases. Treat each command as a validated *pattern* and
> cross-check the linked official docs before running.

### Step 1 - Driver

Most "deep learning / GPU" images ship the driver. Otherwise install per the
[NVIDIA driver guide](https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/).

```bash
nvidia-smi              # driver/CUDA version, GPU model
nvidia-smi -L           # GPU inventory with UUIDs
nvidia-smi topo -m      # topology (single GPU: trivial, capture anyway)
```

**Pass:** `nvidia-smi` lists the GPU without errors.

### Step 2 - NVIDIA Container Toolkit

Install + configure the runtime (`nvidia-ctk runtime configure`) per the
[toolkit install guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html).
On a Docker host you can prove the runtime injection independent of Kubernetes:

```bash
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
```

**Pass:** in-container `nvidia-smi` matches the host. (k3s uses containerd, not Docker, so
this Docker check is optional - the CUDA pod in Step 5 proves the same path.)

### Step 3 - Single-node Kubernetes

[k3s](https://docs.k3s.io/quick-start) is fastest (it bundles containerd; the GPU Operator
supports it). `host-setup.sh` uses k3s with `--tls-san <public-ip>` so you can drive it
from your laptop.

**Pass:** `kubectl get nodes` is Ready.

### Step 4 - NVIDIA GPU Operator

Use the [official getting-started docs](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html)
for the current chart version. Pattern (driver pre-installed on the host):

```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia && helm repo update
helm install gpu-operator nvidia/gpu-operator \
  -n gpu-operator --create-namespace \
  --set driver.enabled=false        # host driver already present
```

```bash
kubectl get pods -n gpu-operator                                   # all Running/Completed
kubectl get node -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}'; echo
kubectl describe node | grep nvidia.com/gpu                        # GFD labels, now REAL
```

**Pass:** node advertises `nvidia.com/gpu` ≥ 1 and GFD labels match the real GPU - same
label *names* as the simulation, now with real provenance.

### Step 5 - CUDA test pod

```bash
kubectl run cuda-test --rm -it --restart=Never \
  --image=nvidia/cuda:12.4.1-base-ubuntu22.04 \
  --overrides='{"spec":{"runtimeClassName":"nvidia"}}' \
  --limits=nvidia.com/gpu=1 -- nvidia-smi
```

**Pass:** `nvidia-smi` from inside a scheduled pod. The complete path, proven.

### Step 6 - DCGM Exporter

The GPU Operator deploys it. The exporter container usually has no curl, so scrape via
port-forward from the host:

```bash
kubectl -n gpu-operator port-forward <dcgm-exporter-pod> 9400:9400 &
curl -s localhost:9400/metrics | grep -E 'DCGM_FI_DEV_(GPU_UTIL|FB_USED|GPU_TEMP|POWER_USAGE)'
```

**Pass:** real `DCGM_FI_*` values that match `nvidia-smi` (temp, power, FB used).

📸 Then capture everything with
[`capture-evidence.sh`](../../real-gpu-session/scripts/capture-evidence.sh) and record the
versions into
[`real-gpu-validation-report.md`](../../06-validation-reports/real-gpu-validation-report.md).

---

## Next parts (same rental)

Stay on this GPU and continue the [Lesson 6 session](../../real-gpu-session/README.md):

- **Part B - [HAMi GPU sharing](../hami/hami-isolation-realgpu/README.md):** turn this one
  card into enforced slices and prove multi-pod co-residency - the highest-value add-on.
- **Part C - [inference benchmark (vLLM)](../../04-inference-serving/README.md):** real
  TTFT / latency / tokens-per-second on one mid-range GPU.
- **Part D - [Slurm real `--gres=gpu`](../../02-slurm-gpu-platform/slurm-realgpu/README.md):**
  the real counterpart to the fake-GRES [Slurm lesson](../../02-slurm-gpu-platform/README.md).

---

## 🔬 What this part proves - and does NOT

**Proves:** the real, end-to-end GPU runtime path on one node, plus real DCGM telemetry -
exactly what Lesson 1's simulation could not.

**Does NOT prove:** single-node by design - no NCCL collective performance, no
NVLink/NVSwitch topology, no GPUDirect RDMA, no multi-node training, nothing about
production-scale fleet ops. It proves the *path and telemetry*, not scale. Full ledger:
[`fake-vs-real-limitations.md`](../../06-validation-reports/fake-vs-real-limitations.md).

➡️ **Next:** back to the [Lesson 6 hub](../../real-gpu-session/README.md) for
[Part B - HAMi sharing](../hami/hami-isolation-realgpu/README.md) on this same GPU.

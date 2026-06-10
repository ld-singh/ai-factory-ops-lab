# gpu-operator-real/ — Real GPU Validation Guide (Phase 2)

This is the **real hardware** half of Module 01. Everything here requires one
machine with an NVIDIA GPU: a rented cloud GPU VM (a single L4/T4/A10G-class
instance is enough) or a local NVIDIA GPU machine.

> **VERSION WARNING:** exact package names, image tags, and Helm chart versions
> change with driver/CUDA/Kubernetes releases. Treat every command below as a
> validated *pattern*; cross-check flags against the official docs linked at
> each step before running. Do not copy-paste blindly onto a machine you care
> about.

## What this validates (that simulation cannot)

The full GPU path to a pod, link by link:

```
NVIDIA driver → NVIDIA Container Toolkit → containerd runtime class
→ NVIDIA device plugin (via GPU Operator) → kubelet → scheduler → CUDA container
```

Plus real DCGM telemetry. Each step below produces evidence; capture it with
`scripts/collect-gpu-evidence.sh` from the repo root.

---

## Step 1 — Driver validation

Install the NVIDIA driver per your distro / cloud image (many GPU VM images
ship with it). Official docs: https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/

Evidence commands:

```bash
nvidia-smi              # driver version, CUDA version, GPU model, utilization
nvidia-smi -L           # GPU inventory with UUIDs
nvidia-smi topo -m      # topology matrix (single GPU: trivial, but capture it)
```

**Pass criteria:** `nvidia-smi` lists the GPU without errors.

## Step 2 — NVIDIA Container Toolkit validation

Install per: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
(includes configuring the container runtime, e.g. `nvidia-ctk runtime configure`).

Evidence command (adjust CUDA image tag to be ≤ your driver's supported CUDA):

```bash
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
```

**Pass criteria:** `nvidia-smi` output from *inside* the container matches the
host GPU. This proves the runtime injection path independent of Kubernetes.

## Step 3 — Kubernetes install

Either works; k3s is fastest for a single node:

- k3s: https://docs.k3s.io/quick-start (single-node server is sufficient)
- kubeadm: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/

**Note for k3s:** k3s bundles its own containerd; the GPU Operator supports
this, but check the GPU Operator platform-support docs for any k3s-specific
configuration before installing.

## Step 4 — NVIDIA GPU Operator

Official install docs (use these for current chart version and values):
https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html

Pattern:

```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
# If the driver is already installed on the host (common on cloud GPU images),
# tell the operator not to manage the driver:
helm install gpu-operator nvidia/gpu-operator \
  -n gpu-operator --create-namespace \
  --set driver.enabled=false        # only when host driver pre-installed
```

Evidence commands:

```bash
kubectl get pods -n gpu-operator                # all components Running/Completed
kubectl describe node <node>                    # nvidia.com/gpu in Allocatable
kubectl get node <node> -o jsonpath='{.status.allocatable.nvidia\.com/gpu}'
kubectl get nodes --show-labels | tr ',' '\n' | grep nvidia   # GFD labels, now REAL
```

**Pass criteria:** node advertises `nvidia.com/gpu` ≥ 1 and GFD labels match
the actual GPU. Compare these discovered labels against the script-written ones
in the simulation — same names, now with real provenance.

## Step 5 — CUDA test pod

```bash
kubectl run cuda-test --rm -it --restart=Never \
  --image=nvidia/cuda:12.4.1-base-ubuntu22.04 \
  --limits=nvidia.com/gpu=1 \
  -- nvidia-smi
```

(If `kubectl run` flags differ on your kubectl version, apply an equivalent Pod
manifest instead — `../workloads/gpu-pod-schedulable.yaml` works unchanged here
once the `kwok` toleration is removed/ignored and the nodeSelector is dropped.)

**Pass criteria:** `nvidia-smi` output from inside a scheduled pod. This is the
single most important artifact in the whole lab: the complete path proven.

## Step 6 — DCGM Exporter

The GPU Operator deploys DCGM Exporter by default. Verify:

```bash
kubectl get pods -n gpu-operator | grep dcgm
kubectl port-forward -n gpu-operator <dcgm-exporter-pod> 9400:9400 &
curl -s localhost:9400/metrics | grep -E 'DCGM_FI_DEV_(GPU_UTIL|FB_USED|GPU_TEMP)' | head
```

**Pass criteria:** real `DCGM_FI_*` metrics with non-placeholder values.
Capture the curl output — this is the telemetry evidence Phase 4 builds on.

## Step 7 — Optional extensions

- **Slurm `--gres=gpu` on the same machine:** see Module 02 once Phase 3 lands.
- **Inference workload (Triton/vLLM):** see Module 04 once Phase 5 lands.
  A small model on a single mid-range GPU is sufficient for meaningful
  TTFT/latency/tokens-per-second benchmarking.

## Recording the results

Fill in `../../06-validation-reports/real-gpu-validation-report.md` with:
instance type, GPU model, driver version, CUDA version, Kubernetes distro and
version, GPU Operator chart version, and the evidence directory produced by
`scripts/collect-gpu-evidence.sh`. Until that report contains captured output,
this module's status is "guide complete, evidence pending hardware run" — and
the project status table states exactly that.

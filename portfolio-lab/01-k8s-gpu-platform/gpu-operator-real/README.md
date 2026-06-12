# Lesson 2 — Real GPU Validation

> Course home: [AI Factory Operations Lab](../../../README.md) · Previous:
> [Lesson 1C — GPU sharing with HAMi](../hami/README.md) · Next:
> [Lesson 3 — Slurm GPU Platform](../../02-slurm-gpu-platform/README.md)

This is the **real hardware** half of Module 01. In Lesson 1 you deliberately could
not prove anything below the kubelet. Here you prove all of it — the complete GPU
path to a running pod — on actual silicon.

🎯 **Learning objectives** — after this lesson you can:

1. Validate each link of the GPU path independently: driver → container toolkit →
   runtime class → device plugin → kubelet → scheduler → CUDA container.
2. Confirm the GPU Operator advertises *real* `nvidia.com/gpu` and *discovered* GFD
   labels, and compare them to the script-written labels from Lesson 1.
3. Run a CUDA pod that executes `nvidia-smi` on a real GPU — the single most
   important artifact in the course.
4. Pull real DCGM telemetry, the foundation [Lesson 4](../../03-observability/README.md)
   builds on.

🧭 **Mode:** 🟥 Real GPU. Everything here requires one machine with an NVIDIA GPU: a
rented cloud GPU VM (a single L4/T4/A10G-class instance is enough) or a local NVIDIA
GPU machine.

📋 **Prerequisites:** [Lesson 1](../README.md) complete (you understand what the
simulation did and didn't prove). A budget of a few dollars if renting a GPU VM.

### Renting the GPU cheaply

This lesson — plus [Lesson 1C Part 3 (HAMi sharing)](../hami/README.md) and later
[Lesson 5 (inference)](../../04-inference-serving/README.md) — needs only **one**
entry-level NVIDIA GPU for a few hours. To keep it to a few dollars:

- **Pick the cheapest tier that has an NVIDIA GPU.** T4, L4, or A10G-class on a
  hyperscaler; or an RTX-class card on a GPU marketplace (RunPod, Vast.ai,
  Lambda-style providers). Everything in this lesson works the same on any of them.
  You never need an A100/H100 for this course. Check current pricing — entry GPUs
  commonly run well under $1/hour, and spot/interruptible pricing is lower still.
- **Spot/preemptible is fine here.** The lesson is a sequence of short validations
  with evidence captured at each step; an interruption costs you minutes, not work.
- **Prefer images with the NVIDIA driver pre-installed** (most "deep learning" or
  "GPU" images). That removes the slowest, most error-prone step and means you start
  at Step 1's *evidence* rather than its install.
- **Plan the session before you boot.** Read this whole page first, have the
  commands ready, run Lesson 1C Part 3 in the same session, capture evidence with
  `scripts/collect-gpu-evidence.sh` as you go — then **terminate the VM**. The
  evidence directory is the deliverable; the VM has no residual value, and a
  forgotten one is the only way this course gets expensive. Watch for storage:
  delete the boot volume too if your provider bills it separately.

Each step below has a **Pass criteria** line — treat it as the step's checkpoint.

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

## Step 7 — Optional extensions (same rental session)

- **GPU sharing with HAMi ([Lesson 1C Part 3](../hami/README.md)):** ~30 extra
  minutes turns this one GPU into several enforced slices and proves multi-pod
  co-residency — the highest-value add-on to this session.
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

---

## 🔬 What this lesson proves — and did NOT

**Proves:** the real, end-to-end GPU runtime path on one node, plus real DCGM
telemetry. This is what Lesson 1's simulation explicitly could not.

**Does NOT prove:** because it's single-node by design — no NCCL collective
performance, no NVLink/NVSwitch topology, no GPUDirect RDMA, no multi-node
distributed training, and nothing about production-scale fleet operations. It proves
the *path and telemetry*, not scale. Full ledger:
[`fake-vs-real-limitations.md`](../../06-validation-reports/fake-vs-real-limitations.md).

➡️ **Next:** [Lesson 3 — Slurm GPU Platform](../../02-slurm-gpu-platform/README.md).
You've now seen GPU scheduling under Kubernetes both ways; next you schedule GPU
*jobs* under Slurm, the other dominant AI/HPC scheduler.

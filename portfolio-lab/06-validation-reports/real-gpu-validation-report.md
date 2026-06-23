# Real GPU Validation Report - Module 01 (Lesson 2 / Phase 2)

> STATUS: ✅ VALIDATED - captured on a real NVIDIA RTX A6000 (Hyperstack), 2026-06-22.
> Evidence: real command output captured during the run (artifact files cited in the table below).

## Environment

| Item | Value |
|---|---|
| Date | 2026-06-22 |
| Machine | Hyperstack GPU VM (`OpenStack-Nova`), Ubuntu 22.04.5 LTS, kernel 6.8.0-40-generic |
| GPU model | **NVIDIA RTX A6000**, 48 GB (49140 MiB), UUID `GPU-f4591c93-8109-e804-f47f-35acdb86acae` |
| GPU architecture | Ampere (`nvidia.com/gpu.family=ampere`, compute capability **8.6**); **MIG: N/A** (not MIG-capable - software sharing is the only option, the Lesson 1C premise) |
| Driver version | 535.183.06 |
| CUDA version (driver-reported) | 12.2 (host `nvidia-smi`); a CUDA 12.4 base image ran fine in-pod |
| Kubernetes distro/version | k3s **v1.35.5+k3s1**, runtime `containerd://2.2.3-k3s1` (single control-plane node, schedulable) |
| GPU Operator | full stack deployed via the `nvidia/gpu-operator` Helm chart (chart version not captured - `helm` was absent on the VM at evidence time; operand pods enumerated below) |
| Evidence directory | `evidence/gpu-evidence-20260622-071518/` |

## Validation checklist

| Step | Pass criteria | Result | Evidence file |
|---|---|---|---|
| Driver | `nvidia-smi` lists the GPU | ✅ RTX A6000, driver 535.183.06 | `nvidia-smi.txt`, `nvidia-smi-L.txt` |
| Container runtime path | in-container `nvidia-smi` matches host | ✅ via a CUDA pod (k3s uses containerd, not Docker, so no `docker-cuda-smi`) | `cuda-pod-nvidia-smi.txt` |
| GPU Operator | all components Running/Completed | ✅ device-plugin, GFD, dcgm-exporter, NFD, operator-validator Running; `nvidia-cuda-validator` Completed | `gpu-operator-pods.txt` |
| Device plugin | node `nvidia.com/gpu` Capacity & Allocatable >= 1 | ✅ both = **1** | `node-describe.txt`, `gpu-allocatable.txt` |
| GFD labels | real *discovered* labels present | ✅ `gpu.product=NVIDIA-RTX-A6000`, `gpu.family=ampere`, `gpu.memory=49140`, `gpu.count=1`, `cuda.driver-version.full=535.183.06`, `gpu.compute.major/minor=8/6` | `node-describe.txt` |
| CUDA test pod | `nvidia-smi` from inside a scheduled pod | ✅ pod on `runtimeClassName: nvidia`, `nvidia.com/gpu: 1`, ran `nvidia-smi` on the A6000 | `cuda-pod-nvidia-smi.txt` |
| DCGM Exporter | real `DCGM_FI_*` metrics via curl | ✅ scraped real metrics, tagged with the GPU UUID + `modelName="NVIDIA RTX A6000"`: `GPU_TEMP=41`, `POWER_USAGE=29.6W`, `FB_USED=1MiB`, `FB_FREE=48675`, `SM_CLOCK=210` - all matching `nvidia-smi` | `dcgm-metrics.txt` |

## Comparison against the simulation (Lesson 1)

- **GFD labels now have real provenance.** Lesson 1's fake fleet had *script-written* labels; here the identical label *names* (`nvidia.com/gpu.product`, `.family`, `.memory`, `cuda.driver-version.*`) are **discovered** by GFD from the actual A6000 - same shape, real source.
- **The full operator stack is present** (driver-validation, container-toolkit, device-plugin, GFD, DCGM, validators) and the operator's own `nvidia-cuda-validator` ran to **Completed** - none of which exists on the fake fleet.
- **Allocation is real**: `nvidia.com/gpu` Capacity = Allocatable = 1, and a pod actually executed `nvidia-smi` on the device.
- **Telemetry is real**: the DCGM exporter's `DCGM_FI_DEV_*` values (temp 41 °C, power 29.6 W, FB used 1 MiB) match `nvidia-smi` and carry the real GPU UUID - the genuine version of the *fabricated* `DCGM_FI_*` stream the fake-DCGM exporter produces in Lessons 3/4.

## What this run proves

The complete GPU path on real silicon: **driver → NVIDIA Container Toolkit → k3s containerd
(`nvidia` RuntimeClass) → GPU Operator device plugin → kubelet → scheduler → CUDA
container**, with discovered GFD labels and **real DCGM telemetry** (values matching
`nvidia-smi`, tagged with the GPU UUID). This is exactly what Lesson 1's simulation
explicitly could not prove.

## Scope limits

Single node by design. Proves the runtime *path*, not scale: no NCCL/collective
performance, no NVLink/NVSwitch topology, no GPUDirect RDMA, no multi-node training. It
also does **not** prove GPU *sharing* or memory-cap isolation - that's Lesson 1C Part B
([`../01-k8s-gpu-platform/hami/hami-isolation-realgpu/`](../01-k8s-gpu-platform/hami/hami-isolation-realgpu/README.md)),
run next on this same A6000. Full ledger:
[`fake-vs-real-limitations.md`](./fake-vs-real-limitations.md).

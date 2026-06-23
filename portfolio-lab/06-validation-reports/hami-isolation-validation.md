# HAMi GPU Isolation Validation - Lesson 1C Part B / Lesson 6 Part B

> STATUS: ✅ VALIDATED - captured on a real NVIDIA RTX A6000 (Hyperstack), 2026-06-23.
> Evidence: real command output captured during the run (artifact files cited in the table below).
> This is the **runtime-enforcement** half the
> [HAMi scheduling sim](../01-k8s-gpu-platform/hami/hami-scheduling-sim/README.md)
> deliberately cannot prove. Lab: [`hami-isolation-realgpu/`](../01-k8s-gpu-platform/hami/hami-isolation-realgpu/README.md).

## Environment

| Item | Value |
|---|---|
| Date | 2026-06-23 |
| Machine | Hyperstack GPU VM (`optimistic-fermi`), Ubuntu 22.04 |
| GPU | **NVIDIA RTX A6000**, 48 GB (49140 MiB), UUID `GPU-d3d0a942-4b02-e4bc-b07e-485c8d2c8552`; Ampere, **no MIG** - software sharing is the only option (the HAMi premise) |
| Driver | 535.183.06 (CUDA 12.4) |
| Kubernetes | k3s, containerd config **v3**, **`default-runtime: nvidia`** (k3s `--default-runtime` flag, not a containerd template) |
| GPU stack | **HAMi 2.9.0**, scheduler image tag matched to the k8s server version. **No GPU Operator** (HAMi ships its own device plugin; the two must not coexist) |
| HAMi pods | `hami-device-plugin` 2/2 Running, `hami-scheduler` 2/2 Running (`hami-pods.txt`) |
| Registration | node allocatable `nvidia.com/gpu = 10` (1 card × deviceSplitCount); `hami.io/node-nvidia-register` → `devmem:49140, devcore:100, type:"NVIDIA RTX A6000", mode:"hami-core"` (`node-allocatable.txt`) |

> HAMi advertises only `nvidia.com/gpu` in node allocatable; `gpumem`/`gpucores` are
> accounted by the HAMi scheduler from the register annotation and enforced per-pod by
> HAMi-core - they are intentionally **not** node-allocatable resources.

## Validation checklist (5 exercises)

| # | Exercise | Pass criteria | Result | Evidence |
|---|---|---|---|---|
| 1 | Co-residency | two pods on one physical GPU | ✅ `hami-share-a` + `hami-share-b` both **Running** on `optimistic-fermi` | `1-co-residency.txt` |
| 2 | Virtualized device view | in-pod `nvidia-smi` shows the slice | ✅ both pods report **`0MiB / 8000MiB`**, not the real 49140 MiB | `2-3-probe-memory-a.txt`, `-b.txt` |
| 3 | Memory-cap enforcement | allocation refused at the slice, by HAMi-core | ✅ `cudaMalloc refused after 7680 MiB`; **`[HAMI-core ERROR] ... Device 0 OOM 8594128896 / 8388608000`** (8388608000 B = exactly 8000 MiB), while the card had ~40 GB free | `2-3-probe-memory-a.txt`, `-b.txt` |
| 4 | Per-device budget (scheduler) | a pod that fits an empty card stays Pending beside the slices | ✅ `hami-oversubscribe` (45000 MiB) **Pending** - `FilteringFailed ... CardInsufficientMemory` | `4-oversubscribe-status.txt`, `4-oversubscribe-events.txt` |
| 5 | The mechanism | the HAMi-core injection that enforces the cap | ✅ env `CUDA_DEVICE_MEMORY_LIMIT_0=8000m`, `CUDA_DEVICE_SM_LIMIT=0`; library `/usr/local/vgpu/libvgpu.so`; `NVIDIA_VISIBLE_DEVICES=GPU-d3d0a942-…` | `5-probe-mechanism-a.txt` |

## What this proves (that the simulation cannot)

- **Two tenants share one physical GPU** (Exercise 1) - stock Kubernetes treats a GPU as
  indivisible and cannot do this.
- **The slice is real, two ways:** the container is *shown* an 8 GB card (Exercise 2), and a
  CUDA allocation is *refused* at 8 GB while ~40 GB physically remained (Exercise 3). The
  refusal comes from **HAMi-core**, not the hardware - the contradiction that only a
  user-space CUDA-interception cap can produce.
- **The card is one shared, accounted budget** (Exercise 4): the HAMi scheduler refuses a 45
  GB pod beside two 8 GB slices (`CardInsufficientMemory`) even though 45 GB < the 48 GB
  card - the real-hardware counterpart of the simulation's per-device exhaustion test.
- **The mechanism is concrete** (Exercise 5): HAMi-core is injected as `libvgpu.so` and reads
  **`CUDA_DEVICE_MEMORY_LIMIT_0=8000m`** - the same `CUDA_DEVICE_MEMORY_LIMIT` mechanism that
  NVIDIA's KAI Scheduler [adopted in June 2026](https://github.com/NVIDIA/KAI-Scheduler/pull/60)
  for its own fractional-GPU memory isolation.

## Scope limits

This is **software** isolation (user-space CUDA interception), **not** MIG hardware fault
isolation - treat it as a scheduling-and-accounting guarantee with runtime enforcement, not
a security boundary. It proves the **memory cap and the virtualized device view**; it does
**not** measure compute-throttling accuracy or noisy-neighbour interference under sustained
load. Single node, so nothing about NCCL/NVLink/MIG/multi-node scale. Full ledger:
[`fake-vs-real-limitations.md`](./fake-vs-real-limitations.md).

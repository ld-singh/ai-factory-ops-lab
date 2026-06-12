# Real GPU Validation Report - Module 01 (Phase 2)

> STATUS: TEMPLATE - no real-GPU run has been recorded yet. This file becomes a
> report only when filled with captured output from an actual NVIDIA GPU machine.

## Environment

| Item | Value |
|---|---|
| Date | _TODO_ |
| Machine | _TODO (cloud instance type or local hardware)_ |
| GPU model | _TODO (`nvidia-smi -L`)_ |
| Driver version | _TODO_ |
| CUDA version (driver-reported) | _TODO_ |
| Kubernetes distro/version | _TODO (k3s / kubeadm)_ |
| GPU Operator chart version | _TODO_ |
| Evidence directory | `evidence/gpu-YYYYMMDD-HHMMSS/` _TODO_ |

## Validation checklist

| Step | Pass criteria | Result | Evidence file |
|---|---|---|---|
| Driver | `nvidia-smi` lists GPU | _TODO_ | `nvidia-smi.txt` |
| Container Toolkit | in-container `nvidia-smi` matches host | _TODO_ | `docker-cuda-smi.txt` |
| GPU Operator | all pods Running/Completed | _TODO_ | `k8s-gpu-operator.txt` |
| Device plugin | node allocatable `nvidia.com/gpu` >= 1 | _TODO_ | `k8s-gpu-allocatable.txt` |
| GFD labels | real discovered labels present | _TODO_ | `k8s-nodes-describe.txt` |
| CUDA test pod | `nvidia-smi` from inside a pod | _TODO_ | _capture manually_ |
| DCGM Exporter | real `DCGM_FI_*` metrics via curl | _TODO_ | _capture manually_ |

## Comparison against simulation

_TODO: note where real behaviour differed from the simulated fleet (e.g. GFD
label set richness, allocation latency, operator components present)._

## What this run proves

The complete GPU path: driver -> container toolkit -> device plugin -> kubelet
-> scheduler -> CUDA container, plus real GPU telemetry.

## Scope limits

Single node by design. Proves the runtime path, not scale, not multi-GPU
topology behaviour (NVLink/NVSwitch), not multi-node networking (NCCL, RDMA).

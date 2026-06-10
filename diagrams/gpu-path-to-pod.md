# The GPU Path to a Kubernetes Pod

The single most useful mental model in this lab. Every link is a distinct
failure domain with its own runbook.

```mermaid
flowchart TD
    HW[NVIDIA GPU hardware] --> DRV[NVIDIA kernel driver\nnvidia-smi works on host]
    DRV --> CTK[NVIDIA Container Toolkit\nruntime injects GPU into containers]
    CTK --> RT[containerd / CRI runtime\nnvidia runtime class configured]
    RT --> DP[NVIDIA device plugin\ndeployed by GPU Operator]
    DP --> KUBELET[kubelet\nadvertises nvidia.com/gpu allocatable]
    KUBELET --> API[Kubernetes API\nnode.status.allocatable]
    API --> SCHED[kube-scheduler\nmatches pod requests to allocatable]
    SCHED --> POD[Pod with nvidia.com/gpu limit\nCUDA visible inside container]

    style HW fill:#76b900,color:#000
    style POD fill:#76b900,color:#000
```

## Simulation boundary

```mermaid
flowchart LR
    subgraph REAL_ONLY["Real GPU mode only (Phase 2)"]
        HW2[GPU] --> DRV2[Driver] --> CTK2[Container Toolkit] --> DP2[Device plugin]
    end
    subgraph SIMULATED["Simulated by KWOK fake nodes (Phase 1)"]
        ALLOC[allocatable: nvidia.com/gpu] --> SCHED2[Scheduler decision] --> PLACE[Pod placement]
    end
    DP2 --> ALLOC
```

KWOK injects `allocatable` directly via the Node object, so everything to the
right of the device plugin is exercised faithfully; everything to the left is
not exercised at all.

## Failure-domain to runbook mapping

| Broken link | Symptom | Runbook |
|---|---|---|
| Driver | `nvidia-smi` fails on host | `runbooks/gpu-node-not-ready.md` |
| Container Toolkit | `docker run --gpus all` fails | `runbooks/gpu-operator-driver-pod-failing.md` |
| Device plugin | node shows 0 `nvidia.com/gpu` | `runbooks/device-plugin-not-advertising-gpus.md` |
| Scheduler fit | pod Pending, Insufficient nvidia.com/gpu | `runbooks/gpu-capacity-planning.md` |
| DCGM | no GPU metrics | `runbooks/dcgm-exporter-no-metrics.md` |

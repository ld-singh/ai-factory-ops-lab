# Runbooks

Operational playbooks for the GPU/Slurm/Kubernetes failure modes this course
teaches you to diagnose. Each lesson's alerts and drills link here, and several are
exercised directly by the labs (for example the observability break-it drill and the
Slurm drain drill).

## Kubernetes / GPU stack

- [Device plugin not advertising GPUs](device-plugin-not-advertising-gpus.md)
- [k3s default runtime / containerd config](k3s-default-runtime-containerd-config.md)
- [GPU node not ready](gpu-node-not-ready.md)
- [GPU Operator driver pod failing](gpu-operator-driver-pod-failing.md)
- [CUDA_VISIBLE_DEVICES debugging](cuda-visible-devices-debugging.md)
- [GPU memory pressure](gpu-memory-pressure.md)
- [GPU capacity planning](gpu-capacity-planning.md)

## Observability

- [DCGM exporter has no metrics](dcgm-exporter-no-metrics.md)

## Scheduling

- [KAI Scheduler queue starvation](kai-scheduler-queue-starvation.md)
- [Slurm job pending on a GRES reason](slurm-job-pending-reason-gres.md)
- [Slurm node drained](slurm-node-drained.md)

Each runbook follows the same shape: symptom, layered triage, verification, and
prevention, plus a lab drill where one applies.

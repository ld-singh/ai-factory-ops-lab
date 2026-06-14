# About

## The author

**Lovedeep Singh** - cloud and AI infrastructure engineer. I built this course to
teach the operational discipline behind AI/HPC GPU platforms in a way you can run end
to end, mostly for free, without overclaiming what a laptop can prove.

- LinkedIn: [lovedeep-singh-cloud-infra](https://www.linkedin.com/in/lovedeep-singh-cloud-infra/)
- GitHub: [ld-singh](https://github.com/ld-singh)

## What this project is

A guided, learn-by-doing course in NVIDIA GPU infrastructure operations: Kubernetes
GPU scheduling, queue-based scheduling with KAI, GPU sharing with HAMi, Slurm GPU
workload management, GPU observability, inference serving, and BCM-style cluster
lifecycle. Each lesson is runnable and declares whether it is a no-GPU simulation or a
real-GPU validation.

## What it proves, and what it does not

The course is deliberate about the line between simulation and real hardware:

- **Simulation** proves control-plane behaviour: scheduling, queueing, quota, GPU
  sharing decisions, capacity accounting, triage workflow, observability design.
- **Real GPU** (one cheap card) proves the runtime path: the driver-to-pod chain,
  enforced GPU memory isolation, real DCGM telemetry, real inference benchmarks.
- **Neither** claims CUDA kernel performance, NCCL/NVLink behaviour, MIG isolation,
  GPUDirect RDMA, or production-scale fleet operations.

The full ledger is in
[Fake vs real limitations](portfolio-lab/06-validation-reports/fake-vs-real-limitations.md).

## Credits

All third-party tools (kind, KWOK, run.ai fake-gpu-operator, NVIDIA GPU Operator, KAI
Scheduler, HAMi, Slurm, Triton, vLLM, Prometheus, Grafana) belong to their respective
projects. This repository contains only the configuration, automation, and
documentation written for the course.

This site is built with [MkDocs](https://www.mkdocs.org/) and
[Material for MkDocs](https://squidfunk.github.io/mkdocs-material/).

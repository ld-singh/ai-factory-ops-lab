# Lesson 3 — Slurm GPU Workload Management

> Course home: [AI Factory Operations Lab](../../README.md) · Previous:
> [Lesson 2 — Real GPU validation](../01-k8s-gpu-platform/gpu-operator-real/README.md) ·
> Next: [Lesson 4 — Observability](../03-observability/README.md)

> 🚧 **STATUS: PLANNED (Phase 3).** This page teaches the concepts and learning
> objectives now; the runnable steps land when Phase 3 is implemented. The directory
> structure exists so the course map is complete — nothing here claims to be
> implemented yet.

Kubernetes isn't the only scheduler in AI/HPC. Slurm runs most of the world's GPU
training clusters. This lesson is the Slurm counterpart to Lesson 1: same goal
(schedule GPU work, diagnose why it's stuck), different scheduler.

🎯 **Learning objectives** — when this lesson is runnable you'll be able to:

1. Stand up a Slurm-in-Docker cluster and schedule GPU jobs with **fake GRES** (no
   GPU needed), keeping fake vs real `--gres=gpu` strictly separated.
2. Read and reason about `slurm.conf`, `gres.conf`, `cgroup.conf`, and
   `slurmdbd.conf`.
3. Write GPU job scripts (small, large, array, cuda-check) and submit them.
4. Apply QoS limits and fair-share, and read accounting data (`sacct`/`sreport`).
5. Run drain/resume drills and triage pending reasons (the Slurm analogue of
   Lesson 1's Pending-pod triage).

🧭 **Mode:** 🟦 Simulation (fake GRES, no GPU) for scheduling logic; optional 🟥 real
`--gres=gpu` validation on the Lesson 2 hardware.

💡 **Why fake GRES is legitimate (same idea as Lesson 1):** `slurmctld` scheduling
does not require the device to exist — GRES scheduling is control-plane logic. So
fake GRES proves Slurm's *scheduling* behaviour, and nothing about CUDA. The same
sim-vs-real boundary you learned in Lesson 1 applies here.

📋 **Will cover:** Slurm-in-Docker cluster, fake GRES vs real `--gres=gpu` (strictly
separated), the four config files above, GPU job scripts, QoS limits, fair-share,
accounting, drain/resume drills, and pending-reason triage.

📎 **Related runbooks:**
[slurm-job-pending-reason-gres.md](../../runbooks/slurm-job-pending-reason-gres.md),
[slurm-node-drained.md](../../runbooks/slurm-node-drained.md).

✅ **Evidence (when implemented):** lands in
[`../06-validation-reports/slurm-gres-validation.md`](../06-validation-reports/slurm-gres-validation.md).
This lesson is only "Complete" once that report holds captured output.

➡️ **Next:** [Lesson 4 — Observability](../03-observability/README.md).

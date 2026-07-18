# Slurm real GRES on a real GPU (Lesson 6, Part E)

> Part of [Lesson 6 - Real GPU](../../real-gpu-session/README.md) · The simulation
> counterpart is [Lesson 2 - Slurm (fake GRES)](../README.md) · Course home:
> [AI Factory Operations Lab](../../../README.md)

> 🚧 **STATUS: PLANNED — coming in a future update (optional).** The *scheduling* half
> of Slurm GRES is fully validated in [Lesson 2 (fake GRES)](../README.md); this
> real-hardware *enforcement* half is an optional add-on planned for a later update. The
> guide below is already run-ready for when it lands: it's
> ordered notes with pointers to the official Slurm docs rather than a copy-paste script,
> because the directives depend on your Slurm version and host. Confirm every directive
> against https://slurm.schedmd.com/gres.html before running, and record your output as
> evidence.

## The boundary (read first)

The [fake-GRES Slurm lesson](../README.md) proved the **scheduling decision**:
`slurmctld` counts `gpu` GRES, places jobs, rejects impossible requests, and applies
QoS - none of which needs a real device. This page proves the part it cannot: **real
`--gres=gpu` enforcement** - that a job step is actually *confined* to the GPU(s) Slurm
allocated it, via the cgroup device controller, so a process cannot touch a GPU it
wasn't given.

| Claim | Where it's proven |
|---|---|
| GRES counting, placement, `QOSMaxGRESPerUser`, pending reasons | ✅ Fake GRES ([Lesson 2](../README.md)) - control-plane logic |
| `CUDA_VISIBLE_DEVICES` set to the *allocated* devices, and the job confined to them | 🟥 Here - cgroup device enforcement on a real GPU |

It does **not** prove multi-node GRES, NVLink/topology-aware allocation, or
GPU-sharding - single node by design, same as the rest of Lesson 6.

## Prerequisites

The same rented host as the rest of [Lesson 6](../../real-gpu-session/README.md), after
**Phase 0** (driver + a working `nvidia-smi`). You do **not** need Kubernetes for this
phase - Slurm talks to the GPU through the driver and cgroups directly. You need root
to install Slurm and configure cgroups.

## What you build

A single-node Slurm install on the GPU host where `gres.conf` points at the **real**
GPU device files and `cgroup.conf` enables device confinement, then a one-GPU job that
proves it only sees its allocation.

> The lab's [Docker-based fake-GRES cluster](../docker/) is **not** the vehicle here -
> it deliberately uses fake char-devices and `task/none`. For real enforcement you want
> Slurm on the host with the real driver and the cgroup device plugin. Treat the lab's
> [`config/`](../config/) files as the *shape* to adapt, not drop-in files.

## The steps (confirm each against the Slurm docs)

1. **Install Slurm on the host** (your distro's package or a build). Reference:
   https://slurm.schedmd.com/quickstart_admin.html
2. **Declare the real GPU as GRES.** In `gres.conf`, point `File=` at the real device
   node(s) (e.g. `/dev/nvidia0`), not the fake char-devices the sim lesson `mknod`s.
   In `slurm.conf`, set `GresTypes=gpu` and the node's `Gres=gpu:<count>`. Reference:
   https://slurm.schedmd.com/gres.html
3. **Enable cgroup device confinement.** Configure `cgroup.conf` with the device
   constraint enabled (e.g. `ConstrainDevices=yes`) and the matching
   `ProctrackType`/`TaskPlugin` for your Slurm version - this is the piece that turns
   the GRES count into actual isolation. Reference:
   https://slurm.schedmd.com/cgroup.conf.html
4. **Restart slurmctld/slurmd** and confirm the node registers the GPU:
   `sinfo -o "%n %G"` should show `gpu:<count>`.
5. **Submit a one-GPU job** that prints what it can see:

   ```bash
   # ILLUSTRATIVE - confirm flags against the Slurm docs for your version.
   srun --gres=gpu:1 bash -c 'echo "CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"; nvidia-smi -L'
   ```

## What to observe, and how to state it

1. **Allocation visibility.** `CUDA_VISIBLE_DEVICES` inside the job is set to the
   device(s) Slurm allocated - and on a multi-GPU host, a `--gres=gpu:1` job sees
   exactly one, not all. (On a single-GPU rental, the strong form of this is the
   confinement in point 2.)
2. **Enforcement.** With `ConstrainDevices=yes`, a process in the job cannot access a
   GPU outside its allocation - the cgroup device controller blocks it. Demonstrate the
   behavior; the precise error depends on driver/runtime. The claim is "the job is
   confined to its allocated device," not a specific errno.

Record both - the in-job `CUDA_VISIBLE_DEVICES`/`nvidia-smi -L`, and your `gres.conf`
+ `cgroup.conf` - into the **real-enforcement section** of
[`slurm-gres-validation.md`](../../06-validation-reports/slurm-gres-validation.md),
kept separate from the fake-GRES scheduling evidence (they back different claims).

📎 **Related runbook:** [slurm-job-pending-reason-gres.md](../../../runbooks/slurm-job-pending-reason-gres.md).

## Relationship to the simulation lesson

[Lesson 2 (fake GRES)](../README.md) proved Slurm *schedules* GPU jobs correctly, for
free, with no GPU. This phase proves Slurm *confines* a placed job to its allocation,
on one real GPU. Together they cover both halves of Slurm GRES; neither covers the
other's, which is the whole point of keeping them apart - the same decision-vs-enforcement
line HAMi draws in [Lesson 1C](../../01-k8s-gpu-platform/hami/README.md).

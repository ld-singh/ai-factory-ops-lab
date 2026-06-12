# Lesson 3 — Slurm GPU Workload Management

> Course home: [AI Factory Operations Lab](../../README.md) · Previous:
> [Lesson 2 — Real GPU validation](../01-k8s-gpu-platform/gpu-operator-real/README.md) ·
> Next: [Lesson 4 — Observability](../03-observability/README.md)

> 🚧 **STATUS: PLANNED (Phase 3).** The concept sections below are teachable now and
> worth reading; the **runnable** Slurm-in-Docker steps land when Phase 3 is
> implemented. Config fragments are marked **ILLUSTRATIVE** — exact directives are
> confirmed against the Slurm docs (https://slurm.schedmd.com/) when the phase lands.
> Nothing here claims to be implemented yet.

Kubernetes isn't the only scheduler in AI/HPC. Slurm runs most of the world's GPU
training clusters. This lesson is the Slurm counterpart to Lesson 1: same goal
(schedule GPU work, diagnose why it's stuck), different scheduler — and the same
cheap-learning trick applies, because **fake GRES is to Slurm what KWOK fake nodes
are to Kubernetes**.

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

---

## Concept 1 — The moving parts

```
            ┌────────────┐   accounting    ┌────────────┐      ┌─────────┐
 sbatch ───▶│  slurmctld │────────────────▶│  slurmdbd  │─────▶│  MySQL/ │
 squeue     │ (controller│                 │ (accounting│      │ MariaDB │
 scontrol   │  = the     │                 │  daemon)   │      └─────────┘
            │  scheduler)│                 └────────────┘
            └─────┬──────┘
                  │ dispatches job steps
        ┌─────────┼─────────┐
        ▼         ▼         ▼
   ┌────────┐┌────────┐┌────────┐
   │ slurmd ││ slurmd ││ slurmd │   one per compute node — launches and
   │ node 1 ││ node 2 ││ node 3 │   supervises the actual processes
   └────────┘└────────┘└────────┘
```

The mapping to what you already know from Lessons 1–2:

| Kubernetes concept | Slurm counterpart | Note |
|---|---|---|
| kube-scheduler + API server | `slurmctld` | One brain, not separate components |
| kubelet | `slurmd` | Per-node agent |
| Pod / Job | Job (with job *steps* inside) | Slurm jobs are batch-first |
| `nvidia.com/gpu` resource | **GRES** `gpu` (`--gres=gpu:2`) | Both are scheduler-side counts |
| ResourceQuota / KAI queue quota | **QoS** + associations + **TRES** limits | Richer, account-hierarchy-based |
| KAI fair-share between queues | Fair-share (usage-decay priority) | Built into Slurm's priority plugin |
| Gang scheduling (KAI) | Native — a job's allocation is all-or-nothing | Slurm allocates the whole job atomically |
| Pod Pending + Events | Job `PD` + **Reason** column | Same triage skill, different spelling |
| `kubectl describe pod` | `scontrol show job <id>` | Your main triage tool |
| Prometheus metrics | `sacct` / `sreport` accounting | Slurm's history lives in slurmdbd |

💡 Notice what Slurm gives you *for free* that Lesson 1B needed KAI for: atomic
whole-job allocation (gang), fair-share, and per-account quotas. This is why
training shops love Slurm — and why learning both schedulers makes each one's design
choices legible.

## Concept 2 — GRES vs TRES (the two acronyms that matter)

- **GRES** (Generic RESource): a per-node consumable device — `gpu` is the canonical
  one. Declared on nodes, requested by jobs (`--gres=gpu:2`,
  or per-task forms like `--gpus-per-task`).
- **TRES** (Trackable RESource): the *accounting and limits* view — CPU, memory,
  nodes, and GRES all become TRES so that QoS limits and fair-share can say things
  like "this account may hold at most 16 GPUs at once."

The pair is the Slurm version of Lesson 1's request/allocatable arithmetic plus
Lesson 1B's quota policy, unified in one system.

The fake-GRES idea, in config shape:

```ini
# ILLUSTRATIVE slurm.conf fragment — exact directives confirmed when Phase 3 lands.
GresTypes=gpu
NodeName=node[1-2] Gres=gpu:8 CPUs=8 RealMemory=16000   # 8 "GPUs" per fake node
```

The controller schedules against that declaration. Whether `/dev/nvidia0` exists
only matters to enforcement on the compute node (cgroup device constraint), which is
exactly the part fake GRES does **not** prove — same decision/enforcement split as
[Lesson 1C](../01-k8s-gpu-platform/hami/README.md).

## Concept 3 — The job script you'll write

```bash
# ILLUSTRATIVE job script shape
#!/bin/bash
#SBATCH --job-name=train-small
#SBATCH --partition=gpu
#SBATCH --gres=gpu:2
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=00:10:00

echo "Allocated GPUs: ${CUDA_VISIBLE_DEVICES:-<none>}"
srun ./work.sh
```

💡 On a real GPU node, Slurm sets `CUDA_VISIBLE_DEVICES` to the allocated devices —
the same environment-variable contract the
[cuda-visible-devices runbook](../../runbooks/cuda-visible-devices-debugging.md)
debugs. On the fake-GRES cluster the variable is the tell-tale: scheduling succeeded,
but there's no real device behind it. That contrast will be captured explicitly in
the validation report.

## Concept 4 — Pending-reason triage (the skill, previewed)

Lesson 1 taught you that "Pending" has distinguishable root causes. Slurm prints the
cause directly in the queue — the `REASON` column of `squeue` / `scontrol show job`:

| Reason (examples) | Meaning | Lesson 1 analogue |
|---|---|---|
| `Resources` | Nothing free that satisfies the request right now | Queue pressure (scenario 4) |
| `Priority` | Resources exist but higher-priority jobs go first | KAI priority ordering (1B) |
| `ReqNodeNotAvail` | A required node is down/drained/reserved | Node NotReady / cordoned |
| `Dependency` | Waits on another job (`--dependency`) | initContainer-ish ordering |
| `QOS…Limit` family | A QoS/association TRES limit (e.g. max GPUs per user) is hit | KAI quota enforcement (1B) |
| `JobHeldUser` / `JobHeldAdmin` | Explicitly held | `kubectl cordon`-style human action |

The triage loop you'll drill: `squeue` → read the reason → `scontrol show job <id>`
for the request → `sinfo` / `scontrol show node` for the supply side → fix or
escalate. Identical *shape* to the kubectl loop in Lesson 1, Step 3.

## Concept 5 — Drain/resume, the operational drill

`scontrol update nodename=<n> state=drain reason="lab drill"` takes a node out of
scheduling without killing running work; `state=resume` brings it back. The drill —
drain, observe jobs route around it, resume, observe backfill — is the Slurm
counterpart of cordon/uncordon, and feeds the
[slurm-node-drained runbook](../../runbooks/slurm-node-drained.md).

---

## What Phase 3 will ship

- Slurm-in-Docker compose/cluster definition (controller, slurmdbd, N compute
  containers) with **fake GRES** declared as above.
- The four config files, annotated line-by-line like
  [the KWOK node template](../01-k8s-gpu-platform/kwok/fake-gpu-node-template.yaml).
- Job scripts: small, multi-GPU (forces `Resources` pending), array, and a
  cuda-check that *documents* the fake/real divide.
- QoS + fair-share exercises mirroring Lesson 1B's quota/starvation exercises.
- Drain/resume and pending-reason drills, with evidence captured via
  [`collect-slurm-evidence.sh`](../../scripts/collect-slurm-evidence.sh).
- Optional 🟥 extension: real `--gres=gpu:1` + `nvidia-smi` job on the Lesson 2
  machine, closing the loop the way Lesson 2 did for Kubernetes.

📎 **Related runbooks:**
[slurm-job-pending-reason-gres.md](../../runbooks/slurm-job-pending-reason-gres.md),
[slurm-node-drained.md](../../runbooks/slurm-node-drained.md).

✅ **Evidence (when implemented):** lands in
[`../06-validation-reports/slurm-gres-validation.md`](../06-validation-reports/slurm-gres-validation.md).
This lesson is only "Complete" once that report holds captured output.

🔬 **What the sim will and won't prove:** fake GRES proves slurmctld's scheduling,
QoS/TRES limit enforcement (an accounting decision), fair-share ordering, and the
triage workflow. It proves nothing about device binding, cgroup device isolation,
`CUDA_VISIBLE_DEVICES` correctness against real devices, or CUDA execution — those
require the 🟥 extension. Ledger:
[`fake-vs-real-limitations.md`](../06-validation-reports/fake-vs-real-limitations.md).

➡️ **Next:** [Lesson 4 — Observability](../03-observability/README.md).

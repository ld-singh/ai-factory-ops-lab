# Slurm GRES Validation Report

> Phase 3 — fake-GRES scheduling simulation (Slurm-in-Docker). This report records
> the control-plane scheduling validation. Real `--gres=gpu` enforcement on hardware
> (the optional Lesson 2 extension) is tracked separately and kept strictly apart.

## Environment

| Field | Value |
|---|---|
| Mode | 🟦 Simulation — fake GRES (8 char-device nodes per compute node, no driver) |
| Slurm version | slurm-wlm 21.08.5 (Ubuntu package) |
| Topology | `slurmctld` + `slurmdbd` + MariaDB + 2× `slurmd` (c1, c2) + login, via docker compose |
| Fleet | 2 nodes × `gpu:8` = **16 fake GPUs**; CPUs=16, RealMem=2000M per node |
| Scheduler | `sched/backfill`, `select/cons_tres` (CR_Core), `GresTypes=gpu` |
| Accounting | slurmdbd → MariaDB; `AccountingStorageEnforce=associations,limits,qos` |

## What was validated (captured output)

Captured by `make phase3-evidence` into
`portfolio-lab/06-validation-reports/evidence/slurm-<timestamp>/`.

### Fleet registered with fake GRES

```
NODELIST   NODES PARTITION   STATE   CPUS  MEMORY  ...
c1             1      gpu*    idle    16    2000
c2             1      gpu*    idle    16    2000
# scontrol show node c1 → CfgTRES=cpu=16,mem=2000M,gres/gpu=8
```

slurmd registered `gpu:8` per node from `gres.conf` (File=/dev/nvidia[0-7], fake
char devices created by the entrypoint via `mknod`). No driver, no CUDA.

### The four scenarios behaved as designed

| Scenario | Submit | Outcome | Evidence |
|---|---|---|---|
| 1 — schedulable (`--gres=gpu:1`) | accepted | **RUNNING** on c1 | `squeue.txt` |
| 2 — impossible (`--gres=gpu:16`) | **rejected at submit** | "Requested node configuration is not available" | demo output |
| 3 — QoS cap (`--qos=capped`, gpu:6) | accepted | **PENDING `QOSMaxGRESPerUser`** | `pending.txt` |
| 4 — queue pressure (array 1–24 × gpu:1) | accepted | **16 RUNNING, rest PENDING `Resources`** | `squeue.txt` |

Both nodes fully allocated under queue pressure: `AllocTRES=cpu=8,gres/gpu=8` each —
the fleet's 16 GPUs are the binding constraint, exactly as intended.

### Drain/resume drill

```
c2  →  state=drain  →  STATE=drng  (running jobs continue, no new work lands)
c2  →  state=resume →  STATE=mix   (back in service)
```

## 🔬 What this proved — and did NOT

**Proved (control-plane):** GRES registration; `--gres=gpu` scheduling; the
Slurm-vs-Kubernetes difference on impossible requests (submit-time rejection vs
perpetual Pending); QoS/TRES limit enforcement (`QOSMaxGRESPerUser`); queue-pressure
contention bounded by GPU count; fair-share/accounting plumbing; drain/resume.

**Did NOT prove:** no device binding, no cgroup device isolation, no
`CUDA_VISIBLE_DEVICES` against real devices, no CUDA execution. The GPUs are empty
char devices. Full ledger:
[`fake-vs-real-limitations.md`](./fake-vs-real-limitations.md).

## Reproduce

```bash
make phase3-up        # build + start the cluster, bootstrap accounting
make phase3-demo      # submit the four scenarios
make phase3-drain     # drain/resume drill
make phase3-evidence  # capture sinfo/squeue/sacct/qos
make phase3-down      # tear down
```

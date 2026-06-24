# Runbook - Slurm Job Pending with a GRES/QOS Reason

**Severity:** Medium - GPU work isn't running; could be a healthy queue wait or an
unsatisfiable request that will *never* run. The first triage step is telling them apart.
**Applies to:** Slurm GPU clusters. Exercised in the Lesson 2 simulation
([fake-GRES Slurm lab](../portfolio-lab/02-slurm-gpu-platform/README.md)); the *scheduling*
reasons are identical on real hardware.

## Symptom

- A GPU job sits `PD` (Pending) in `squeue`, or is **rejected at submit**.
- The `REASON` column (or `scontrol show job`) names a GRES/QOS-related cause.

## Triage order

Slurm prints the cause directly - read it first, then confirm against the supply side.

### 1. Read the reason

```bash
squeue -l                          # STATE + REASON for every job
squeue -j <JOBID> -o '%i %T %r'    # one job: id, state, reason
scontrol show job <JOBID>          # full request: ReqTRES, gres, QOS, partition
```

Get `<JOBID>` from the first column of `squeue`. Map the reason:

| Reason | Meaning | Will it ever run? |
|---|---|---|
| `Resources` | nothing free satisfies it **right now** | ✅ yes, when capacity frees |
| `Priority` | resources exist but higher-priority jobs go first | ✅ yes, eventually |
| `QOSMaxGRESPerUser` / `AssocGrpGRES…` | a QoS/association GPU (TRES) limit is hit | ⚠️ only if the limit/usage changes |
| `ReqNodeNotAvail` | a required node is down/drained/reserved | ⚠️ when the node returns - see [node-drained runbook](slurm-node-drained.md) |
| **Rejected at submit:** `Requested node configuration is not available` | the request can't fit **any** node (e.g. `--gres=gpu:16` on 8-GPU nodes) | ❌ never - fix the request |

> The submit-time rejection is the Slurm-vs-Kubernetes contrast: Slurm refuses an
> impossible request up front; K8s would accept it and leave the pod Pending forever.

### 2. Check the supply side (for `Resources` / `Priority`)

```bash
sinfo -N -l                                                          # nodes: state, idle vs allocated
scontrol show node <node> | grep -E 'Gres|CfgTRES|AllocTRES|State'  # GPUs configured vs allocated
```

If every GPU node is fully allocated (`gres/gpu` exhausted), the job is a legitimate
queue wait, not a misconfiguration.

### 3. Check the limit (for a `QOS…`/`Assoc…` reason)

```bash
sacctmgr show qos format=Name,MaxTRESPU%20,GrpTRES%20             # per-QoS GPU caps
sacctmgr show assoc user=<user> format=User,Account,QOS,GrpTRES   # the user's limits
```

A `QOSMaxGRESPerUser` means quota enforcement is working as designed (the Lesson 1B
analogue) - the fix is a smaller request, a different QoS, or a raised limit, not a bug.

## Resolution verification

```bash
squeue -j <JOBID> -o '%i %T %r'   # → RUNNING, or a reason you've explained/accepted
```

A "fixed" job either transitions to `R`, or you can state precisely *why* it waits
(capacity / priority / an intentional quota).

## Prevention

- Right-size `--gres=gpu:N` to the largest node; reject impossible requests in review.
- Document QoS/association GPU limits so `QOSMax…` reasons are expected, not surprises.
- Alert on jobs Pending longer than a threshold with a terminal reason (`ReqNodeNotAvail`,
  a `Dependency` that can't clear).

## Drill in this lab

[Lesson 2](../portfolio-lab/02-slurm-gpu-platform/README.md) `make phase3-demo` reproduces
three of these on purpose: scenario 2 (rejected at submit), scenario 3
(`QOSMaxGRESPerUser`), scenario 4 (`Resources` under queue pressure). Walk this runbook
against that queue.

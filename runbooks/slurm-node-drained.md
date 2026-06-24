# Runbook - Slurm Node Drained / Down

**Severity:** Medium-High - a drained/down node removes GPU capacity from the fleet; jobs
needing it pile up `Pending` (`ReqNodeNotAvail` / `Resources`). Sometimes intentional
(maintenance), sometimes a health trigger - tell them apart before resuming.
**Applies to:** Slurm GPU clusters. Drill exercised in the Lesson 2 simulation
([fake-GRES Slurm lab](../portfolio-lab/02-slurm-gpu-platform/README.md), `make phase3-drain`).

## Symptom

- `sinfo` shows a node in `drain`, `drained`, `draining`, or `down*`.
- GPU jobs stay Pending with `ReqNodeNotAvail`, or the fleet is short on capacity.

## Triage order

### 1. Find which nodes, and *why*

```bash
sinfo -R                                          # nodes in a down/drain state + the REASON string
sinfo -N -l                                       # full node list with states
scontrol show node <node> | grep -E 'State|Reason|Gres|AllocTRES'
```

The `Reason` is the key signal. Distinguish:

| Reason pattern | Likely cause | Action |
|---|---|---|
| `lab drill`, `maintenance`, an operator name/ticket | **intentional** drain | resume when the work is done (step 3) |
| `Kill task failed`, `Prolog/Epilog error`, `Low RealMemory`, `gres count too low` | a **health/config** trigger | fix the underlying issue **first**, then resume |
| `Not responding` / `down*` | slurmd unreachable on the node | check the node + slurmd before anything else (step 2) |

### 2. If the node is `down`/`Not responding`

```bash
scontrol ping                                     # is slurmctld healthy?
# on the node: is slurmd up and can it reach the controller?
systemctl status slurmd
journalctl -u slurmd --since "30 min ago" | tail -30
```

A `gres count` mismatch (node advertises fewer GPUs than `gres.conf` declares) keeps a node
`drained` - see [device-plugin / GRES registration](device-plugin-not-advertising-gpus.md)
for the equivalent "node not advertising GPUs" triage.

### 3. Resume the node (only once it's actually healthy)

```bash
scontrol update nodename=<node> state=resume
sinfo -N -l | grep <node>                         # → idle/mixed, REASON cleared
```

To take a node out for maintenance the same way the drill does:

```bash
scontrol update nodename=<node> state=drain reason="maintenance: <ticket>"
```

`drain` lets running jobs finish but accepts no new ones; `resume` returns it to service.

## Resolution verification

```bash
sinfo -R                          # → empty (no drained/down nodes), or only the ones you intend
squeue -l                         # jobs that were ReqNodeNotAvail now schedule
```

## Prevention

- Always set a meaningful `reason=` when draining, so the next operator can tell intentional
  from health-triggered at a glance.
- Alert on **unexpected** drains (a `Reason` that isn't a known maintenance string).
- Track drained-node count as lost GPU capacity; reconcile `gres.conf` with real device
  inventory so health drains aren't config drift.

## Drill in this lab

[Lesson 2](../portfolio-lab/02-slurm-gpu-platform/README.md) `make phase3-drain` drains a
compute node, shows work routing to the other node, then resumes it - run this runbook
alongside it to practice the drain → diagnose → resume loop.

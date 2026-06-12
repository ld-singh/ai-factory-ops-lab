# KAI Scheduler - example manifests

> **ILLUSTRATIVE, not copy-paste.** These show the *shape* of the objects Lesson 1B
> walks through. KAI Scheduler's CRD `apiVersion`s, field names, and the queue/
> priority **label keys** change between releases. Before applying anything, confirm
> the exact names against the version you installed:
> https://github.com/NVIDIA/KAI-Scheduler
>
> When you run the lesson for real, **replace these with the manifests you actually
> applied** (version-stamped) and capture their output into
> [`../../../06-validation-reports/`](../../../06-validation-reports/). That captured
> set - not these scaffolds - is what makes a claim like "I demonstrated reclaim"
> real.

## Files

| File | Lesson 1B exercise | Demonstrates |
|---|---|---|
| [`queues.yaml`](./queues.yaml) | A (quota) | Two queues summing to the fake fleet (16+16 of 32) |
| [`team-pods.yaml`](./team-pods.yaml) | A–C | Per-team GPU pods pointed at KAI with a queue label |
| [`gang-job.yaml`](./gang-job.yaml) | D (gang) | An all-or-nothing pod group (min-member) |

## How to use them

1. Install KAI per its official docs (the chart/values drift - don't trust a pinned
   command here).
2. Open each file, and fix every value tagged `# CONFIRM` against the KAI version
   you installed: the `apiVersion`, the queue label **key**, and `schedulerName`.
3. Apply, then drive the exercises in [the lesson](../README.md).

Check whether KAI looks installed before you start:

```bash
kubectl get crds | grep -i kai          # do KAI CRDs exist?
kubectl get pods -A | grep -i kai       # are the controllers Running?
```

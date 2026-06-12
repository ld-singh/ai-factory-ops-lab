# HAMi - example manifests

> **ILLUSTRATIVE, not copy-paste.** HAMi's resource names (`nvidia.com/gpumem`,
> `nvidia.com/gpucores`, …), units, and defaults can change between releases.
> Confirm against the version you installed: https://project-hami.io/ and
> https://github.com/Project-HAMi/HAMi
>
> These run in [Lesson 1C Part 3](../README.md#part-3----share-one-real-gpu-between-pods-do-this-during-your-lesson-2-rental),
> on the **real GPU** from Lesson 2 - that's where the memory-cap enforcement is
> actually proven. Capture the in-pod `nvidia-smi` and any allocation-failure
> output into [`../../../06-validation-reports/`](../../../06-validation-reports/).

## Files

| File | Demonstrates |
|---|---|
| [`shared-pods.yaml`](./shared-pods.yaml) | Two pods each requesting a ~2 GiB slice of ONE physical GPU, co-resident |

## Use

1. Install HAMi on the Lesson 2 machine (confirm chart/values in the docs).
2. Confirm the resource names in `shared-pods.yaml` match your HAMi version.
3. Apply, then verify co-residency and the per-pod memory cap:

```bash
kubectl get pods -o wide                 # both Running on the single GPU node
kubectl exec share-a -- nvidia-smi       # reports the ~2 GiB slice, not the full card
```

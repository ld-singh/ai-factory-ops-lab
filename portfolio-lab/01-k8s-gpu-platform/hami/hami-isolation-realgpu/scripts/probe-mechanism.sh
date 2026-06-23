#!/usr/bin/env bash
# probe-mechanism.sh - show HOW HAMi enforces the slice from inside a Running pod.
# Read-only. Run AFTER share-two-pods.yaml is Running on the real-GPU host. This is
# supporting evidence for the isolation claim: it surfaces the mechanism (HAMi-core
# injected via the NVIDIA container runtime) that makes the memory cap real.
#
# It DISCOVERS the artifacts rather than asserting exact names, because the env-var
# keys, the library filename, and the mount path are HAMi-version dependent.
#   TODO: confirm the exact names for your HAMi version against
#   https://github.com/Project-HAMi/HAMi and record them in your evidence.
#
# What this does NOT do: measure compute-throttling accuracy or noisy-neighbour
# interference. Per the project's limitations ledger, sharing-performance under
# sustained load is out of scope for this lab - the isolation claim here is the
# memory cap and the virtualized device view, not throughput fairness.
set -euo pipefail

POD="${1:-hami-share-a}"

echo "== [$POD] HAMi-injected environment (memory-limit / device vars) =="
# HAMi-core reads its caps from env the container runtime injects. Names vary by
# release (e.g. CUDA_DEVICE_MEMORY_LIMIT*, CUDA_VISIBLE_DEVICES, NVIDIA_VISIBLE_DEVICES,
# LD_PRELOAD). Show whatever is present rather than assume a fixed set.
kubectl exec "$POD" -- bash -c 'env | grep -iE "CUDA|NVIDIA|VGPU|HAMI|LD_PRELOAD" | sort' \
  || echo "  (no matching env vars found - confirm against your HAMi version)"

echo
echo "== [$POD] HAMi-core library injected into the container =="
# HAMi-core is a user-space CUDA-interception library (historically libvgpu.so) the
# runtime mounts/preloads. Locate it without hardcoding the path.
kubectl exec "$POD" -- bash -c '
  echo "LD_PRELOAD=${LD_PRELOAD:-<unset>}"
  for lib in libvgpu.so libcuda.so; do
    found=$(find / -name "$lib*" 2>/dev/null | head -3)
    [ -n "$found" ] && echo "$lib:" && echo "$found"
  done
' || echo "  (library search inconclusive - confirm the HAMi-core path for your version)"

echo
echo "== [$POD] device view (CUDA_VISIBLE_DEVICES vs nvidia-smi) =="
kubectl exec "$POD" -- bash -c 'echo "CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-<unset>}"; nvidia-smi -L'

echo
echo "Interpretation: the injected env + library are how HAMi-core intercepts CUDA"
echo "driver calls to enforce the slice. This is SOFTWARE isolation (user-space"
echo "interception), not MIG hardware partitioning. Record the actual names you see;"
echo "they are version-dependent. Related runbook: cuda-visible-devices-debugging.md."

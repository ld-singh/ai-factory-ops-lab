#!/usr/bin/env bash
# verify-resources.sh - show what HAMi's scheduler sees on each GPU node:
#   1) nvidia.com/gpu in allocatable (advertised by fake-gpu-operator),
#   2) the hami.io/node-nvidia-register annotation (what HAMi schedules against,
#      including per-GPU devmem/devcore that enable fractional placement).
# Read-only.
set -euo pipefail
POOL="run.ai/simulated-gpu-node-pool=default"

echo "== nvidia.com/gpu in node allocatable (fake-gpu-operator) =="
kubectl get nodes -l "$POOL" \
  -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\\.com/gpu --no-headers

echo
echo "== HAMi scheduler registration (hami.io/node-nvidia-register) =="
echo "   each entry: id, count(split), devmem(MiB), devcore(%), type"
kubectl get nodes -l "$POOL" -o json | jq -r '
  .items[] | "\(.metadata.name): " +
  ( (.metadata.annotations["hami.io/node-nvidia-register"] // "<none>")
    | if . == "<none>" then . else (fromjson | length | tostring) + " GPUs registered" end )'

echo
echo "== handshake freshness (HAMi drops nodes stale > ~60s) =="
kubectl get nodes -l "$POOL" -o json | jq -r '
  .items[] | "\(.metadata.name): " + (.metadata.annotations["hami.io/node-handshake"] // "<none>")'

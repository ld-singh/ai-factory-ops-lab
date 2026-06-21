#!/usr/bin/env bash
# verify-resources.sh - show what each GPU node advertises after setup. With the mock
# device plugin on, the schedulable resources are:
#   nvidia.com/gpu                 (count, from fake-gpu-operator)
#   nvidia.com/gpumem-percentage   (percent, from the mock plugin - USE THIS on fakes)
#   nvidia.com/gpucores            (percent, from the mock plugin)
# Absolute nvidia.com/gpumem will read 0 here on purpose (its per-MiB device count exceeds
# the kubelet limit) - that's why demos slice memory by percentage. Read-only.
set -euo pipefail
POOL="run.ai/simulated-gpu-node-pool=default"

echo "== allocatable per pool node =="
kubectl get nodes -l "$POOL" -o json | jq -r '
  .items[] | "\(.metadata.name): " +
  "gpu=\(.status.allocatable["nvidia.com/gpu"] // "-") " +
  "gpumem-percentage=\(.status.allocatable["nvidia.com/gpumem-percentage"] // "-") " +
  "gpucores=\(.status.allocatable["nvidia.com/gpucores"] // "-") " +
  "gpumem=\(.status.allocatable["nvidia.com/gpumem"] // "-")  (gpumem 0/absent is expected)"'

echo
echo "== HAMi mock-device-plugin pods =="
kubectl -n kube-system get pods | grep -iE "mock|hami" || echo "  (none found)"

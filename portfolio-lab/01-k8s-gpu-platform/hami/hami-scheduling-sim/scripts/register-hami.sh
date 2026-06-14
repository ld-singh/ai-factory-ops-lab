#!/usr/bin/env bash
# register-hami.sh - register the fake GPUs with HAMi's SCHEDULER.
#
# fake-gpu-operator makes nodes advertise nvidia.com/gpu, but HAMi's scheduler builds
# its device cache from a node annotation, not from allocatable. With HAMi's own
# device plugin disabled (it crashes with no GPU) and the bundled mock plugin broken
# at this chart version, nothing writes that annotation - so we write it ourselves:
#
#   hami.io/node-nvidia-register : the per-GPU list, including devmem + devcore, which
#                                  is exactly what lets HAMi place FRACTIONAL requests
#                                  (gpumem/gpucores), not just whole GPUs.
#   hami.io/node-handshake       : a timestamp HAMi treats as a liveness signal; it
#                                  drops a node whose handshake is stale (~60s). On a
#                                  real node the device plugin refreshes it every ~30s;
#                                  here we refresh it before each demo.
#
# Usage: register-hami.sh [register|refresh]
#   register : write the device list + a fresh handshake (run once at setup)
#   refresh  : update only the handshake (run before scheduling new pods)
set -euo pipefail

MODE="${1:-register}"
POOL="run.ai/simulated-gpu-node-pool=default"
GPU_COUNT="${GPU_COUNT:-8}"
DEVMEM="${GPU_MEMORY:-81920}"        # MiB per fake GPU
GPU_PRODUCT="${GPU_PRODUCT:-NVIDIA-H100-80GB-HBM3}"

nodes=$(kubectl get nodes -l "$POOL" -o jsonpath='{.items[*].metadata.name}')
[[ -z "$nodes" ]] && { echo "No pool nodes found (label $POOL). Run 'make labels fleet' first."; exit 1; }

for n in $nodes; do
  if [[ "$MODE" == "register" ]]; then
    reg='['
    for i in $(seq 0 $((GPU_COUNT - 1))); do
      [[ $i -gt 0 ]] && reg="$reg,"
      reg="$reg{\"id\":\"GPU-${n}-${i}\",\"count\":10,\"devmem\":${DEVMEM},\"devcore\":100,\"type\":\"${GPU_PRODUCT}\",\"mode\":\"hami-core\",\"health\":true}"
    done
    reg="$reg]"
    kubectl annotate node "$n" "hami.io/node-nvidia-register=${reg}" --overwrite >/dev/null
  fi
  kubectl annotate node "$n" "hami.io/node-handshake=Requesting_$(date '+%Y.%m.%d %H:%M:%S')" --overwrite >/dev/null
done

echo "${MODE}: $(echo "$nodes" | wc -w) node(s) (${GPU_COUNT} fake GPUs each, ${DEVMEM} MiB)."
if [[ "$MODE" == "register" ]]; then
  echo "NOTE: handshake goes stale after ~60s; 'make demo-*' refreshes it automatically."
fi

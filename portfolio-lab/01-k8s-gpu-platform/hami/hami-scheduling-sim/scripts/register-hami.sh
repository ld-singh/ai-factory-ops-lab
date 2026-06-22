#!/usr/bin/env bash
# register-hami.sh - tell HAMi's SCHEDULER what GPUs each node has.
#
# Both HAMi device plugins are off on this fake fleet (the real one needs NVML; the mock one
# isn't used - see the README), so nothing writes the annotation HAMi's SCHEDULER reads to
# know a node has GPUs. Without it the scheduler reports "node unregistered" and pods stay
# Pending. So we write it ourselves:
#
#   hami.io/node-nvidia-register : the per-GPU list (id, split count, devmem, devcore) the
#                                  scheduler scores fractional requests against.
#   hami.io/node-handshake       : a liveness timestamp; HAMi drops a node whose handshake
#                                  is stale beyond ~60s.
#
# Run it ONCE at setup (`make up` does). If nodes go stale after long inactivity, run again.
#
# Usage: register-hami.sh [register|refresh]
#   register : write the device list + a fresh handshake (setup)
#   refresh  : update only the handshake (if nodes have gone stale)
set -euo pipefail

MODE="${1:-register}"
POOL="run.ai/simulated-gpu-node-pool=default"
GPU_COUNT="${GPU_COUNT:-8}"
DEVMEM="${GPU_MEMORY:-81920}"        # MiB per fake GPU; percentages resolve against this
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
[[ "$MODE" == "register" ]] && echo "NOTE: run demos soon; if nodes go stale (~60s), 'make register' refreshes the handshake."

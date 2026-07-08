#!/usr/bin/env bash
set -euo pipefail

TOPOLOGY="${TOPOLOGY:-${1:-topology/small.json}}"
OUT="${OUT:-generated/fake-gpu-operator-values.yaml}"

if [[ ! -f "$TOPOLOGY" ]]; then
  echo "Topology file not found: $TOPOLOGY" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"

{
  echo "# Generated from $TOPOLOGY. Do not edit by hand."
  echo "topology:"
  echo "  nodePools:"
  jq -r '
    .pools
    | to_entries[]
    | [
        .key,
        (.value.gpusPerNode | tostring),
        (.value.gpuMemoryMiB | tostring),
        .value.product
      ]
    | @tsv
  ' "$TOPOLOGY" | while IFS=$'\t' read -r pool gpus memory product; do
    cat <<YAML
    ${pool}:
      gpuCount: ${gpus}
      gpuMemory: ${memory}
      gpuProduct: ${product}
YAML
  done
} > "$OUT"

echo "Rendered fake-gpu-operator values: $OUT"

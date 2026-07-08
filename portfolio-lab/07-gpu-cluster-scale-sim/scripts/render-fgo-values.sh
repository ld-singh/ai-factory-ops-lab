#!/usr/bin/env bash
set -euo pipefail

TOPOLOGY="${TOPOLOGY:-${1:-topology/small.json}}"
OUT="${OUT:-generated/fake-gpu-operator-values.yaml}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LESSON_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

if [[ "$TOPOLOGY" != /* && ! -f "$TOPOLOGY" && -f "${LESSON_DIR}/${TOPOLOGY}" ]]; then
  TOPOLOGY="${LESSON_DIR}/${TOPOLOGY}"
fi

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

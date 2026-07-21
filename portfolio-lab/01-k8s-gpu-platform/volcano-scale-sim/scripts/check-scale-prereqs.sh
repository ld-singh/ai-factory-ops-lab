#!/usr/bin/env bash
set -euo pipefail

missing=0
for bin in docker kind kubectl helm kwok jq; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "MISSING: $bin"
    missing=1
  else
    echo "OK: $bin -> $(command -v "$bin")"
  fi
done

if [[ "$missing" -ne 0 ]]; then
  echo
  echo "Install the missing tools, then re-run this target."
  exit 1
fi

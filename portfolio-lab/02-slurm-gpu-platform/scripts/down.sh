#!/usr/bin/env bash
# down.sh — tear down the Slurm-in-Docker cluster. Removes containers and the
# named volumes (munge key + accounting DB). Evidence on the host is untouched.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE="${SCRIPT_DIR}/../docker/docker-compose.yml"

echo "This will stop the Slurm cluster and delete its containers + volumes"
echo "(munge key, accounting database). Captured evidence is NOT touched."
read -r -p "Proceed? [y/N] " answer
if [[ "${answer:-n}" != "y" && "${answer:-n}" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

docker compose -f "$COMPOSE" down -v
echo "Slurm cluster removed."

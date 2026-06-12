#!/usr/bin/env bash
# setup-qos.sh — create the 'capped' QoS used by scenario 3, and grant it to the
# lab account. Idempotent. The cap (4 GPUs/user) is an accounting decision, which
# is exactly why it's fully demonstrable on fake GRES.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE="${SCRIPT_DIR}/../docker/docker-compose.yml"
in_login() { docker compose -f "$COMPOSE" exec -T login "$@"; }

echo "==> Creating 'capped' QoS (MaxTRESPerUser=gres/gpu=4)..."
in_login sacctmgr -i add qos capped Description="GPU-capped QoS" \
  MaxTRESPerUser=gres/gpu=4 >/dev/null 2>&1 || true
# Ensure the limit is set even if the QoS already existed from a prior run.
in_login sacctmgr -i modify qos capped set MaxTRESPerUser=gres/gpu=4 >/dev/null 2>&1 || true

echo "==> Granting the lab account access to both 'normal' and 'capped' QoS..."
in_login sacctmgr -i modify account lab set QOS=normal,capped >/dev/null 2>&1 || true

echo "==> QoS state:"
in_login sacctmgr show qos format=Name,MaxTRESPU%20 || true
echo
echo "Now scenario 3 will be blocked by the cap:"
echo "  sbatch --qos=capped /jobs/03-qos-blocked.sbatch"

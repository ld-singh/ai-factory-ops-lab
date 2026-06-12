#!/usr/bin/env bash
# up.sh — build and start the Slurm-in-Docker cluster, then bootstrap accounting
# associations so jobs can be submitted. Idempotent-ish: safe to re-run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE="${SCRIPT_DIR}/../docker/docker-compose.yml"

dc()       { docker compose -f "$COMPOSE" "$@"; }
in_login() { dc exec -T login "$@"; }

echo "==> Building images and starting the cluster..."
dc up -d --build

echo "==> Waiting for compute nodes to register with slurmctld..."
# Poll sinfo until both nodes are visible and not DOWN/DRAINED. slurmd needs a
# few seconds after slurmctld to register.
ok=0
for _ in $(seq 1 60); do
  if in_login sinfo -h -o '%n %t' 2>/dev/null | grep -Eq '^c1 (idle|mix|alloc)'; then
    ok=1; break
  fi
  sleep 2
done
if [[ "$ok" -ne 1 ]]; then
  echo "WARN: nodes did not reach an idle state in time. Current state:"
  in_login sinfo -N -l || true
  echo "Inspect logs with: docker compose -f $COMPOSE logs slurmctld c1 c2"
fi

echo "==> Bootstrapping accounting (cluster/account/user associations)..."
# The cluster auto-registers in slurmdbd when slurmctld starts; retry briefly in
# case we got here first. AccountingStorageEnforce=associations means a user with
# no association cannot submit — so this step is what makes the demo work.
for _ in $(seq 1 15); do
  if in_login sacctmgr -i add account lab Description="lab account" Organization=lab >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
in_login sacctmgr -i add account lab Description="lab account" Organization=lab >/dev/null 2>&1 || true
in_login sacctmgr -i add user root DefaultAccount=lab Account=lab >/dev/null 2>&1 || true

echo
echo "==> Cluster is up. Fleet:"
in_login sinfo -N -l || true
echo
echo "Next:"
echo "  make phase3-demo       # submit the four scenarios and watch the queue"
echo "  docker compose -f $COMPOSE exec login bash   # poke around by hand"

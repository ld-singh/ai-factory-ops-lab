#!/usr/bin/env bash
# entrypoint.sh — one image, many Slurm roles, selected by $SLURM_ROLE.
#
# Roles: slurmdbd | slurmctld | slurmd | login
# Shared state across containers:
#   - /etc/munge/munge.key   (named volume) — the auth key, created once by the
#                              first container to reach the munge step.
#   - /etc/slurm/*           (bind mount, read-only) — the four config files.
set -euo pipefail

ROLE="${SLURM_ROLE:?set SLURM_ROLE to slurmdbd|slurmctld|slurmd|login}"

log() { echo "[entrypoint:${ROLE}] $*"; }

# ---------------------------------------------------------------------------
# 0. config — copy the read-only bind-mounted /config into /etc/slurm with the
#    perms/ownership Slurm insists on. slurmdbd.conf MUST be 0600 owned by the
#    SlurmUser or slurmdbd refuses to start; the host bind mount can't provide
#    that, so we stage a copy instead. slurm.conf expects gres.conf/cgroup.conf
#    in the same dir, which this satisfies.
# ---------------------------------------------------------------------------
setup_config() {
  mkdir -p /etc/slurm
  # Deploy only the configs this lab actually activates. cgroup.conf is shipped
  # as a READING artifact (mounted at /config) but deliberately NOT activated:
  # with TaskPlugin=task/none + ProctrackType=proctrack/linuxproc there is no
  # cgroup plugin, and the Slurm 21.08 that Ubuntu ships rejects newer
  # cgroup.conf syntax. The file's lesson value is the concept, not running it.
  cp -f /config/slurm.conf    /etc/slurm/ 2>/dev/null || true
  cp -f /config/gres.conf     /etc/slurm/ 2>/dev/null || true
  cp -f /config/slurmdbd.conf /etc/slurm/ 2>/dev/null || true
  if [[ -f /etc/slurm/slurmdbd.conf ]]; then
    chown slurm:slurm /etc/slurm/slurmdbd.conf
    chmod 600 /etc/slurm/slurmdbd.conf
  fi
}

# ---------------------------------------------------------------------------
# 1. munge — shared-key authentication for the whole cluster
# ---------------------------------------------------------------------------
setup_munge() {
  # The munge.key lives on a shared named volume so every container trusts the
  # same key. The first container to get here creates it; the rest wait for it.
  if [[ ! -s /etc/munge/munge.key ]]; then
    if [[ "${MUNGE_CREATOR:-0}" == "1" ]]; then
      log "creating shared munge.key (this container is the creator)"
      # /dev/urandom keygen is the documented fallback when mungekey/haveged
      # are unavailable; fine for a throwaway lab cluster.
      dd if=/dev/urandom bs=1 count=1024 of=/etc/munge/munge.key 2>/dev/null
    else
      log "waiting for shared munge.key to appear..."
      for _ in $(seq 1 60); do
        [[ -s /etc/munge/munge.key ]] && break
        sleep 1
      done
      [[ -s /etc/munge/munge.key ]] || { log "ERROR: munge.key never appeared"; exit 1; }
    fi
  fi
  chown munge:munge /etc/munge/munge.key
  chmod 400 /etc/munge/munge.key
  mkdir -p /run/munge && chown munge:munge /run/munge
  log "starting munged"
  gosu munge /usr/sbin/munged --force
}

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
wait_for_tcp() {
  local host="$1" port="$2" name="$3"
  log "waiting for ${name} (${host}:${port})..."
  for _ in $(seq 1 90); do
    if (echo > "/dev/tcp/${host}/${port}") >/dev/null 2>&1; then
      log "${name} is up"; return 0
    fi
    sleep 1
  done
  log "ERROR: timed out waiting for ${name}"; return 1
}

setup_config
setup_munge

case "$ROLE" in
  slurmdbd)
    wait_for_tcp "${DB_HOST:-mysql}" 3306 "MariaDB"
    log "starting slurmdbd (foreground)"
    exec gosu slurm /usr/sbin/slurmdbd -D
    ;;

  slurmctld)
    wait_for_tcp "${DBD_HOST:-slurmdbd}" 6819 "slurmdbd"
    log "starting slurmctld (foreground)"
    exec gosu slurm /usr/sbin/slurmctld -D -f /etc/slurm/slurm.conf
    ;;

  slurmd)
    wait_for_tcp "${CTLD_HOST:-slurmctld}" 6817 "slurmctld"
    # Create 8 FAKE GPU device nodes so slurmd registers gpu:8 (gres.conf points
    # File= here). major 195 = NVIDIA's real major; these are empty char devices
    # with no driver behind them — the fake/real boundary, made of mknod calls.
    log "creating 8 fake GPU device nodes (/dev/nvidia0..7)"
    for i in 0 1 2 3 4 5 6 7; do
      [[ -e "/dev/nvidia${i}" ]] || mknod "/dev/nvidia${i}" c 195 "${i}" || \
        log "WARN: mknod /dev/nvidia${i} failed (need CAP_MKNOD)"
    done
    # slurmd runs as root (it would launch/constrain job processes on a real node).
    log "starting slurmd (foreground) as $(hostname)"
    exec /usr/sbin/slurmd -D -N "$(hostname)" -f /etc/slurm/slurm.conf
    ;;

  login)
    # An interactive submit host: just keep munge running and idle so users can
    # `docker compose exec login bash` and run sbatch/squeue/sacct.
    wait_for_tcp "${CTLD_HOST:-slurmctld}" 6817 "slurmctld"
    log "login/submit host ready — exec into me with: docker compose exec login bash"
    exec sleep infinity
    ;;

  *)
    log "ERROR: unknown SLURM_ROLE='$ROLE'"; exit 1
    ;;
esac

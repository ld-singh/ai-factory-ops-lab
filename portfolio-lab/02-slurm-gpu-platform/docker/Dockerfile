# Slurm-in-Docker image for the AI Factory Operations Lab (Phase 3).
#
# One image, multiple roles (slurmctld / slurmdbd / slurmd / login) selected at
# runtime by the SLURM_ROLE env var in docker-compose.yml. We install Slurm from
# the Ubuntu archive (slurm-wlm) rather than building from source: it's a real,
# supported package set and keeps the lab fast to stand up.
#
# SIMULATION HONESTY: the compute nodes declare GPU GRES with NO backing device
# (see ../config/gres.conf). That makes this a *scheduling* simulation — slurmctld
# does real GRES/TRES/QoS math, but nothing below it touches a GPU. Same fake/real
# boundary as the KWOK Kubernetes lab.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# munge   = Slurm's auth daemon (shared key across all nodes)
# slurm-wlm = slurmctld + slurmd + client tools (sbatch/squeue/sinfo/scontrol/sacct)
# slurmdbd  = accounting daemon (talks to MariaDB)
# mariadb-client = used by the entrypoint to wait for / probe the DB
RUN apt-get update && apt-get install -y --no-install-recommends \
        munge \
        slurm-wlm \
        slurmdbd \
        mariadb-client \
        gosu \
        iproute2 \
        less \
        vim-tiny \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Slurm expects these dirs with the right ownership for the SlurmUser ('slurm',
# created by the package). spool + log dirs must be writable by that user.
RUN mkdir -p /var/spool/slurmctld /var/spool/slurmd /var/log/slurm /run/munge \
    && chown -R slurm:slurm /var/spool/slurmctld /var/log/slurm \
    && chown -R munge:munge /run/munge

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

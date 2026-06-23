#!/usr/bin/env bash
# set-default-runtime.sh - make 'nvidia' the DEFAULT containerd runtime on a k3s node,
# using k3s's own --default-runtime flag via /etc/rancher/k3s/config.yaml. This is the
# clean, containerd-version-agnostic way: it does NOT edit containerd's config.toml, whose
# schema differs between v2 and v3 (the v3 schema uses [plugins.'io.containerd.cri.v1.runtime']
# and a config-v3.toml.tmpl template) and breaks k3s easily if you redeclare a table.
#
# Run ON THE VM as root, AFTER host-setup.sh, BEFORE installing HAMi.
#
# Why: HAMi pods don't set runtimeClassName, so HAMi-core only gets injected if the DEFAULT
# runtime is nvidia. See https://project-hami.io/docs/v2.4.1/installation/prerequisites
# k3s flag reference (--default-runtime): https://docs.k3s.io/advanced
#
# Usage (on the VM):  sudo bash set-default-runtime.sh
set -euo pipefail

CONFIG=/etc/rancher/k3s/config.yaml
GEN=/var/lib/rancher/k3s/agent/etc/containerd/config.toml
log() { printf '\n=== %s ===\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run as root (or via sudo): sudo bash set-default-runtime.sh"
command -v k3s >/dev/null || die "k3s not found - run host-setup.sh first."

# This k3s build must support the flag. (Older builds lack it; then use a
# config-v3.toml.tmpl template per the k3s docs above instead.)
k3s server --help 2>/dev/null | grep -q -- '--default-runtime' \
  || die "this k3s build has no --default-runtime flag; set the default runtime via a
          config-v3.toml.tmpl template per https://docs.k3s.io/advanced"

log "Setting 'default-runtime: nvidia' in $CONFIG"
mkdir -p "$(dirname "$CONFIG")"; touch "$CONFIG"
if grep -qE '^[[:space:]]*default-runtime[[:space:]]*:' "$CONFIG"; then
  sed -i 's/^[[:space:]]*default-runtime[[:space:]]*:.*/default-runtime: nvidia/' "$CONFIG"
else
  echo 'default-runtime: nvidia' >> "$CONFIG"
fi
grep -n 'default-runtime' "$CONFIG"

log "Restarting k3s"
systemctl restart k3s
sleep 5
systemctl is-active k3s >/dev/null || die "k3s did not come back active - check: systemctl status k3s"

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
log "Waiting for the node to be Ready again"
for _ in $(seq 1 30); do
  kubectl get nodes 2>/dev/null | grep -q ' Ready ' && break
  sleep 4
done
kubectl get nodes -o wide || true

log "Verifying the default runtime is now nvidia"
if grep -q 'default_runtime_name = "nvidia"' "$GEN" 2>/dev/null; then
  echo "OK: $GEN has default_runtime_name = \"nvidia\""
else
  echo "WARNING: could not confirm in $GEN. Inspect:"
  echo "  sudo grep default_runtime_name $GEN"
fi

cat <<'EOF'

=== default runtime set ===
Next (from your laptop, where helm + KUBECONFIG are set up, or here with helm installed):
    ./install-hami.sh
EOF

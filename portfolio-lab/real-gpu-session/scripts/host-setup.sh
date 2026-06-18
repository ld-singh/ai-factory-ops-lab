#!/usr/bin/env bash
# host-setup.sh - bring a fresh TensorDock (or any Ubuntu/Debian) GPU VM up to a
# single-node k3s cluster that can schedule GPU pods. Run this ON THE VM as root
# (or with sudo), once, at the start of your Lesson 6 rental session.
#
# What it does, in order:
#   1. confirm the NVIDIA driver works (nvidia-smi)
#   2. install the NVIDIA Container Toolkit (so containers can use the GPU)
#   3. install k3s, with the VM's public IP in the API cert (--tls-san) so you can
#      drive kubectl from your laptop after fetching the kubeconfig
#   4. confirm k3s picked up the nvidia container runtime, and label the node gpu=on
#
# It does NOT install the GPU layer (device plugin / GPU Operator / HAMi) - that is
# Lesson 6's content; run install-gpu-operator.sh (or the lesson's steps) afterwards.
#
# IMPORTANT - version-sensitive, confirm against the official docs before trusting:
#   NVIDIA Container Toolkit: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
#   k3s + NVIDIA runtime:     https://docs.k3s.io/advanced#nvidia-container-runtime-support
# This script uses the documented commands as of this writing; package URLs and flags
# drift. Read it before you run it - do not pipe a script you haven't read onto a host.
#
# Usage (on the VM):
#   sudo PUBLIC_IP=<vm-public-ip> bash host-setup.sh
#   # PUBLIC_IP is optional; if unset it is auto-detected via api.ipify.org.
set -euo pipefail

PUBLIC_IP="${PUBLIC_IP:-}"
K3S_KUBECONFIG_MODE="${K3S_KUBECONFIG_MODE:-644}"   # 644 so a non-root SSH user can read it

log() { printf '\n=== %s ===\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run as root (or via sudo): sudo bash host-setup.sh"
command -v apt-get >/dev/null || die "this script assumes an apt-based distro (Ubuntu/Debian). Adapt per your host."

# --- 1. driver ---------------------------------------------------------------
log "1/4 NVIDIA driver check"
if ! command -v nvidia-smi >/dev/null || ! nvidia-smi >/dev/null 2>&1; then
  die "nvidia-smi not working. TensorDock GPU images usually ship the driver; if not,
       install it per https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/
       and re-run. Nothing below works without a healthy host driver."
fi
nvidia-smi -L

# --- 2. NVIDIA Container Toolkit ---------------------------------------------
log "2/4 NVIDIA Container Toolkit"
if ! command -v nvidia-ctk >/dev/null; then
  install -m 0755 -d /usr/share/keyrings
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    > /etc/apt/sources.list.d/nvidia-container-toolkit.list
  apt-get update -y
  apt-get install -y nvidia-container-toolkit
else
  echo "nvidia-ctk already present, skipping install."
fi
# Install the toolkit BEFORE k3s so k3s auto-detects the nvidia container runtime.

# --- 3. k3s ------------------------------------------------------------------
log "3/4 k3s install"
if [[ -z "$PUBLIC_IP" ]]; then
  PUBLIC_IP="$(curl -fsS https://api.ipify.org || true)"
  [[ -n "$PUBLIC_IP" ]] || die "could not auto-detect public IP; re-run with PUBLIC_IP=<ip>"
  echo "auto-detected PUBLIC_IP=$PUBLIC_IP"
fi
if ! command -v k3s >/dev/null; then
  curl -sfL https://get.k3s.io \
    | INSTALL_K3S_EXEC="--tls-san ${PUBLIC_IP} --write-kubeconfig-mode ${K3S_KUBECONFIG_MODE}" sh -
else
  echo "k3s already installed, skipping. (To change --tls-san, reinstall.)"
fi

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
log "waiting for the node to be Ready"
for _ in $(seq 1 30); do
  kubectl get nodes 2>/dev/null | grep -q ' Ready ' && break
  sleep 4
done
kubectl get nodes -o wide

# --- 4. nvidia runtime + node label -----------------------------------------
log "4/4 nvidia runtime + node label"
# k3s writes a 'nvidia' RuntimeClass into its containerd config when the toolkit is
# present at install time. Confirm it exists (the GPU layer references it).
if kubectl get runtimeclass nvidia >/dev/null 2>&1; then
  echo "RuntimeClass 'nvidia' present."
else
  echo "WARNING: RuntimeClass 'nvidia' not found. On k3s this is usually auto-created"
  echo "when the toolkit is installed before k3s. See"
  echo "https://docs.k3s.io/advanced#nvidia-container-runtime-support - you may need to"
  echo "restart k3s ('systemctl restart k3s') or add the runtime manually."
fi
# Label for HAMi (Lesson 6 Part B), which schedules onto nodes labelled gpu=on.
node="$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')"
kubectl label node "$node" gpu=on --overwrite

cat <<EOF

=== host setup done ===
Cluster is up on this VM. Public IP for remote access: ${PUBLIC_IP}

Next, from your LAPTOP:
  1. Make sure TCP 6443 is reachable on this VM (open it in TensorDock's networking /
     port settings if it isn't).
  2. Fetch the kubeconfig and rewrite it to the public IP:
       ./fetch-kubeconfig.sh <ssh-user>@${PUBLIC_IP}
  3. Install the GPU layer (Lesson 6 Part A):
       KUBECONFIG=./kubeconfig-tensordock ./install-gpu-operator.sh
Then work through Lesson 6's phases. Tear the VM down when evidence is captured.
EOF

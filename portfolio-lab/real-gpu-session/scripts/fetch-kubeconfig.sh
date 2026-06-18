#!/usr/bin/env bash
# fetch-kubeconfig.sh - pull the k3s kubeconfig off the GPU VM to your LAPTOP and
# rewrite its server address so kubectl works remotely. Run this LOCALLY after
# host-setup.sh has finished on the VM.
#
# k3s writes /etc/rancher/k3s/k3s.yaml with server: https://127.0.0.1:6443. For remote
# use we (a) read it over SSH (via sudo, so it works regardless of file mode) and
# (b) replace 127.0.0.1 with the VM's public IP. host-setup.sh already added that IP to
# the API certificate (--tls-san), so TLS validates.
#
# Usage:
#   ./fetch-kubeconfig.sh <ssh-user>@<vm-ip> [--port N] [--key path] [--ip PUBLIC_IP] [--out FILE]
# Examples:
#   ./fetch-kubeconfig.sh root@203.0.113.10
#   ./fetch-kubeconfig.sh user@203.0.113.10 --port 2222 --key ~/.ssh/tensordock
#
# Requires: ssh, sed locally; kubectl is used only to verify (skipped if absent).
set -euo pipefail

[[ $# -ge 1 ]] || { echo "usage: $0 <ssh-user>@<vm-ip> [--port N] [--key path] [--ip PUBLIC_IP] [--out FILE]"; exit 2; }

TARGET="$1"; shift
SSH_PORT=22
SSH_KEY=""
PUBLIC_IP="${TARGET##*@}"   # default the API IP to the SSH host
OUT="./kubeconfig-tensordock"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) SSH_PORT="$2"; shift 2;;
    --key)  SSH_KEY="$2";  shift 2;;
    --ip)   PUBLIC_IP="$2"; shift 2;;
    --out)  OUT="$2"; shift 2;;
    *) echo "unknown arg: $1"; exit 2;;
  esac
done

ssh_opts=(-p "$SSH_PORT" -o StrictHostKeyChecking=accept-new)
[[ -n "$SSH_KEY" ]] && ssh_opts+=(-i "$SSH_KEY")

echo "Reading /etc/rancher/k3s/k3s.yaml from ${TARGET} (via sudo)..."
raw="$(ssh "${ssh_opts[@]}" "$TARGET" 'sudo cat /etc/rancher/k3s/k3s.yaml')" \
  || { echo "ERROR: could not read the kubeconfig. Check SSH access and that k3s is installed."; exit 1; }

# Rewrite the loopback server address to the public IP.
echo "$raw" | sed -E "s#server: https://127\.0\.0\.1:6443#server: https://${PUBLIC_IP}:6443#" > "$OUT"
chmod 600 "$OUT"
echo "Wrote $OUT (server -> https://${PUBLIC_IP}:6443)"

if command -v kubectl >/dev/null; then
  echo "Verifying with kubectl..."
  if KUBECONFIG="$OUT" kubectl get nodes -o wide; then
    echo
    echo "Success. Use it from your laptop with:"
    echo "  export KUBECONFIG=$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
  else
    cat >&2 <<EOF

kubectl could not reach the cluster. Most common causes:
  - TCP 6443 is not open to your laptop. Open it in TensorDock's networking/port
    settings for this VM (the k3s API listens on 6443).
  - The public IP is wrong. Re-run with --ip <correct-public-ip>.
  - host-setup.sh ran without that IP in --tls-san (TLS name mismatch). Re-run
    host-setup with PUBLIC_IP=<ip>, or add the IP and reinstall k3s.
EOF
    exit 1
  fi
else
  echo "kubectl not found locally - skipped verification. Install kubectl, then:"
  echo "  KUBECONFIG=$OUT kubectl get nodes"
fi

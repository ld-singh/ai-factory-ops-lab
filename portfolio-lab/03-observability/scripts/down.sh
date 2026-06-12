#!/usr/bin/env bash
# down.sh - remove the observability stack. Leaves the kind cluster and any
# captured evidence intact.
set -euo pipefail

NS_MON="monitoring"
echo "==> Uninstalling kube-prometheus-stack..."
helm uninstall kube-prometheus-stack -n "$NS_MON" >/dev/null 2>&1 || true

echo "==> Removing exporter + dashboards..."
kubectl delete namespace gpu-observability --ignore-not-found
kubectl -n "$NS_MON" delete configmap -l grafana_dashboard=1 --ignore-not-found >/dev/null 2>&1 || true
kubectl delete namespace "$NS_MON" --ignore-not-found

echo "Observability stack removed. The kind cluster and evidence are untouched."

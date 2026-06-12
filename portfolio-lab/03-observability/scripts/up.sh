#!/usr/bin/env bash
# up.sh - deploy the observability stack onto the existing Phase 1 kind cluster:
#   - kube-prometheus-stack (Prometheus + Grafana + Alertmanager + kube-state-metrics)
#   - the fake-dcgm-exporter (SYNTHETIC GPU metrics, no GPU)
#   - ServiceMonitor, alert rules, and two Grafana dashboards
# No GPU required. Idempotent (helm upgrade --install, kubectl apply).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB="${SCRIPT_DIR}/.."
CTX="kind-${CLUSTER_NAME:-ai-factory-lab}"
NS_MON="monitoring"

if ! kubectl config get-contexts -o name 2>/dev/null | grep -qx "$CTX"; then
  echo "kind context '$CTX' not found. Bring up the Phase 1 cluster first:"
  echo "  make phase1-up"
  exit 1
fi
kubectl config use-context "$CTX" >/dev/null

echo "==> Installing kube-prometheus-stack (this pulls a few images on first run)..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n "$NS_MON" --create-namespace \
  --set grafana.adminPassword=admin \
  --set grafana.sidecar.dashboards.enabled=true \
  --set prometheus.prometheusSpec.retention=2h \
  --set alertmanager.alertmanagerSpec.resources.requests.memory=64Mi \
  --wait --timeout 8m

echo "==> Deploying the fake-DCGM exporter (synthetic metrics)..."
# Deliver the Python app as a ConfigMap so no image build/registry is needed.
kubectl create namespace gpu-observability --dry-run=client -o yaml | kubectl apply -f -
kubectl -n gpu-observability create configmap fake-dcgm-app \
  --from-file=app.py="${LAB}/fake-dcgm-exporter/app.py" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "${LAB}/manifests/exporter.yaml"
kubectl apply -f "${LAB}/manifests/servicemonitor.yaml"
kubectl apply -f "${LAB}/manifests/alerts.yaml"
kubectl -n gpu-observability rollout status deployment/fake-dcgm-exporter --timeout=120s

echo "==> Loading Grafana dashboards (sidecar auto-imports labelled ConfigMaps)..."
for dash in "${LAB}"/dashboards/*.json; do
  name="dash-$(basename "$dash" .json)"
  kubectl -n "$NS_MON" create configmap "$name" --from-file="$(basename "$dash")=$dash" \
    --dry-run=client -o yaml | kubectl label --local -f - grafana_dashboard=1 -o yaml | kubectl apply -f -
done

echo
echo "==> Done. Access the UIs with port-forwards:"
echo "  # Grafana (admin / admin):"
echo "  kubectl -n $NS_MON port-forward svc/kube-prometheus-stack-grafana 3000:80"
echo "  # Prometheus:"
echo "  kubectl -n $NS_MON port-forward svc/kube-prometheus-stack-prometheus 9090:9090"
echo
echo "Dashboards: '[DESIGN] GPU Fleet Overview' and '[DESIGN] Idle-GPU / Money-Fire'."
echo "Now trip the alerts on purpose:  make phase4-break"

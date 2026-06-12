#!/usr/bin/env bash
# break-it.sh — trip the control-plane + DCGM alerts on purpose, so you watch the
# alert->runbook wiring fire end to end. This is the Phase 4 drill: an alert you've
# never seen fire is an alert you don't trust.
set -euo pipefail

NS_MON="monitoring"
NS_GPU="gpu-observability"

# Query Prometheus for currently-firing alert names via a temporary port-forward.
firing_alerts() {
  kubectl -n "$NS_MON" port-forward svc/kube-prometheus-stack-prometheus 9090:9090 >/dev/null 2>&1 &
  local pf=$!
  sleep 3
  curl -s "http://localhost:9090/api/v1/alerts" \
    | jq -r '.data.alerts[] | select(.state=="firing") | .labels.alertname' 2>/dev/null | sort -u || true
  kill "$pf" >/dev/null 2>&1 || true
}

scenario() {
  # POST a scenario to the exporter to change its synthetic numbers.
  kubectl -n "$NS_GPU" exec deploy/fake-dcgm-exporter -- \
    python -c "import urllib.request; urllib.request.urlopen(urllib.request.Request('http://localhost:9400/scenario?name=$1', method='POST')).read()" \
    >/dev/null 2>&1 || true
  echo "   exporter scenario set to: $1"
}

echo "=== Drill 1: DCGMExporterAbsent (delete the exporter) ==="
kubectl -n "$NS_GPU" scale deployment/fake-dcgm-exporter --replicas=0
echo "   waiting ~60s for 'absent()' to trip..."
sleep 70
echo "   firing alerts now:"; firing_alerts | sed 's/^/     - /'
echo "   restoring exporter..."
kubectl -n "$NS_GPU" scale deployment/fake-dcgm-exporter --replicas=1
kubectl -n "$NS_GPU" rollout status deployment/fake-dcgm-exporter --timeout=120s

echo
echo "=== Drill 2: GPUMemoryPressure (push a GPU to 98% framebuffer) ==="
scenario mem-pressure
echo "   waiting ~45s for the threshold window..."
sleep 50
echo "   firing alerts now:"; firing_alerts | sed 's/^/     - /'

echo
echo "=== Drill 3: GPUXidErrors (inject an XID driver error) ==="
scenario xid
sleep 20
echo "   firing alerts now:"; firing_alerts | sed 's/^/     - /'

echo
echo "Resetting exporter to normal..."
scenario normal
echo
echo "Each alert above carries a 'runbook' annotation pointing into runbooks/."
echo "Capture the firing state as evidence:  make phase4-evidence"

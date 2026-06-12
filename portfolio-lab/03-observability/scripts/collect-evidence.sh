#!/usr/bin/env bash
# collect-evidence.sh - snapshot Prometheus targets, rules, and alert state into
# the validation-reports evidence tree. Read-only. Uses a temporary port-forward.
set -euo pipefail

NS_MON="monitoring"
OUT_DIR="portfolio-lab/06-validation-reports/evidence/observability-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT_DIR"
echo "Collecting observability evidence into $OUT_DIR"

kubectl -n "$NS_MON" port-forward svc/kube-prometheus-stack-prometheus 9090:9090 >/dev/null 2>&1 &
PF=$!
trap 'kill "$PF" >/dev/null 2>&1 || true' EXIT
sleep 3

save() {
  local file="$1" url="$2"
  curl -s "http://localhost:9090${url}" > "$OUT_DIR/$file" 2>&1 && echo "  wrote $file" \
    || echo "  [WARN] failed: $url"
}

save targets.json     "/api/v1/targets"
save rules.json       "/api/v1/rules"
save alerts.json      "/api/v1/alerts"
# A couple of representative metric snapshots proving the scrape works.
save sm_active.json   "/api/v1/query?query=DCGM_FI_PROF_SM_ACTIVE"
save fb_used_pct.json "/api/v1/query?query=DCGM_FI_DEV_FB_USED%20/%20(DCGM_FI_DEV_FB_USED%20%2B%20DCGM_FI_DEV_FB_FREE)"

# Human-readable firing-alert summary.
curl -s "http://localhost:9090/api/v1/alerts" \
  | jq -r '.data.alerts[] | "\(.state)\t\(.labels.alertname)\t\(.labels.severity // "-")\t\(.annotations.runbook // "-")"' \
  > "$OUT_DIR/firing-summary.tsv" 2>/dev/null || true
echo "  wrote firing-summary.tsv"

echo
echo "Done. Reference from the observability section of your lab notebook."

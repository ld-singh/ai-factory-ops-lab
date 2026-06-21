#!/usr/bin/env bash
# await-running.sh <app-label> <want-running> [loops] - wait for pods to reach Running,
# clearing HAMi's stuck node bind-lock as we go. Echoes the final Running count.
#
# WHY: HAMi locks a node (annotation hami.io/mutex.lock) while binding a GPU pod and
# releases it after the device plugin's Allocate. On the fake fleet that release is flaky,
# so a second pod targeting the same node stays Pending with "node ... has been locked
# within 5m0s" - a KNOWN HAMi behaviour, not unique to fakes (HAMi issues #1130, #1548).
# We clear the stale lock - the same release HAMi normally does - so binds proceed.
#
# This is OURS, not official: on a real cluster HAMi manages this lock itself and you never
# touch the annotation. It does NOT fake the sharing (the mock plugin genuinely answers
# Allocate); it only releases a stuck bind mutex.
set -euo pipefail

LABEL="${1:?usage: await-running.sh <app-label> <want-running> [loops]}"
WANT="${2:?want-running required}"
LOOPS="${3:-30}"
POOL="run.ai/simulated-gpu-node-pool=default"

r=0
for _ in $(seq 1 "$LOOPS"); do
  for n in $(kubectl get nodes -l "$POOL" -o name 2>/dev/null); do
    kubectl annotate "$n" hami.io/mutex.lock- >/dev/null 2>&1 || true
  done
  r="$(kubectl get pods -l "app=$LABEL" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  [ "${r:-0}" -ge "$WANT" ] && break
  sleep 3
done
echo "${r:-0}"

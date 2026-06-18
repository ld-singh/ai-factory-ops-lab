#!/usr/bin/env bash
# Exercise 5 - per-device memory exhaustion. Pin one 8-GPU node, submit 17 pods that
# each want 30000 MiB. A GPU fits two (60000) but not three (90000), so 16 fit and the
# 17th stays Pending with CardInsufficientMemory - whole GPUs by count are free, but no
# device has 30000 MiB left. Proves HAMi accounts memory PER DEVICE.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

"$(dirname "${BASH_SOURCE[0]}")/register-hami.sh" refresh
node="$("$(dirname "${BASH_SOURCE[0]}")/pin-node.sh")"
echo "Target node: $node (8 fake GPUs x 81920 MiB)"

kubectl delete -f manifests/05-mem-exhaustion.yaml --ignore-not-found >/dev/null 2>&1 || true
kubectl apply -f manifests/05-mem-exhaustion.yaml
sleep 18

running="$(kubectl get pods -l app=hami-mem-exhaustion --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')"
pending="$(kubectl get pods -l app=hami-mem-exhaustion --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l | tr -d ' ')"
echo
echo "hami-mem-exhaustion: $running Running / $pending Pending (of 17)"
echo "Pending pod scheduling reason:"
pod="$(kubectl get pods -l app=hami-mem-exhaustion --field-selector=status.phase=Pending -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
[[ -n "$pod" ]] && kubectl describe pod "$pod" | sed -n '/Events:/,$p' | head -8
echo
echo "Expected (run to confirm): 16 Running, 1 Pending with CardInsufficientMemory."
echo "Per-device memory is the binding constraint, not GPU count. 'make evidence' to capture."

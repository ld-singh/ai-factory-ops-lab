#!/usr/bin/env bash
# ensure-cluster.sh - bring up the exact Lesson 1 fake-GPU fleet (kind + KWOK +
# fake-gpu-operator + node pools), reusing the Lesson 1 scripts rather than
# duplicating them. KAI then schedules on that shared fleet: queue/quota/gang
# decisions are pure control-plane logic over the integer nvidia.com/gpu the operator
# advertises onto the KWOK nodes. This is the same fleet `make phase1-up` builds.
set -euo pipefail

CLUSTER="${CLUSTER:-ai-factory-lab}"
LAB1_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" && pwd)"

"$LAB1_SCRIPTS/setup-kind.sh" "$CLUSTER"
"$LAB1_SCRIPTS/install-kwok.sh"
"$LAB1_SCRIPTS/install-fake-gpu-operator.sh"
"$LAB1_SCRIPTS/create-fake-gpu-nodes.sh"
echo "Shared Lesson 1 fake GPU fleet ready (a100/h100/l40s, 32 GPUs)."

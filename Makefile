# AI Factory Operations Lab — Makefile
# Simple, idempotent-where-possible targets. Each target prints what it does.
# Phases map to portfolio-lab/ modules. Targets for later phases are stubs that
# explain what is coming, so `make help` is always an honest project map.

SHELL := /bin/bash
CLUSTER_NAME ?= ai-factory-lab
LAB1 := portfolio-lab/01-k8s-gpu-platform

.DEFAULT_GOAL := help

# ---------------------------------------------------------------------------
# Meta
# ---------------------------------------------------------------------------
.PHONY: help check
help: ## Show all targets
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

check: ## Verify local prerequisites (docker, kind, kubectl, helm, kwok, jq)
	./scripts/check-prereqs.sh

# ---------------------------------------------------------------------------
# Phase 1 — Kubernetes fake-GPU control-plane simulation (no GPU required)
# ---------------------------------------------------------------------------
.PHONY: phase1-up phase1-demo phase1-evidence phase1-down
phase1-up: ## Create kind cluster, install KWOK, create fake GPU node pools
	$(LAB1)/scripts/setup-kind.sh $(CLUSTER_NAME)
	$(LAB1)/scripts/install-kwok.sh
	$(LAB1)/scripts/create-fake-gpu-nodes.sh

phase1-demo: ## Deploy schedulable + intentionally-pending GPU workloads
	$(LAB1)/scripts/run-scheduling-demo.sh

phase1-evidence: ## Capture kubectl evidence into portfolio-lab/06-validation-reports/
	./scripts/collect-k8s-evidence.sh

phase1-down: ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER_NAME)

# ---------------------------------------------------------------------------
# Phase 2 — Real GPU validation (requires one NVIDIA GPU machine)
# ---------------------------------------------------------------------------
.PHONY: phase2-guide
phase2-guide: ## Print the real-GPU validation guide location
	@echo "Real GPU validation is a guided manual process by design."
	@echo "Follow: $(LAB1)/gpu-operator-real/README.md"
	@echo "Then capture evidence with: ./scripts/collect-gpu-evidence.sh"

# ---------------------------------------------------------------------------
# Phase 3+ — stubs (honest project map; implemented in later phases)
# ---------------------------------------------------------------------------
.PHONY: phase3-up phase4-up phase5-up
phase3-up: ## [PLANNED] Slurm-in-Docker cluster with fake GRES
	@echo "Phase 3 (Slurm) not implemented yet. See portfolio-lab/02-slurm-gpu-platform/README.md"

phase4-up: ## [PLANNED] Prometheus/Grafana observability stack
	@echo "Phase 4 (Observability) not implemented yet. See portfolio-lab/03-observability/README.md"

phase5-up: ## [PLANNED] Inference serving (Triton/vLLM)
	@echo "Phase 5 (Inference) not implemented yet. See portfolio-lab/04-inference-serving/README.md"

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
.PHONY: clean
clean: ## Remove lab clusters and generated artifacts (asks for confirmation)
	./scripts/cleanup.sh

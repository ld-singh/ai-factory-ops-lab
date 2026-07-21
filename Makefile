# AI Factory Operations Lab - Makefile
# Simple, idempotent-where-possible targets. Each target prints what it does.
# Phases map to portfolio-lab/ modules. Targets for later phases are stubs that
# explain what is coming, so `make help` is always an accurate project map.

SHELL := /bin/bash
CLUSTER_NAME ?= ai-factory-lab
LAB1 := portfolio-lab/01-k8s-gpu-platform
LAB1D := $(LAB1)/volcano-scale-sim
LAB2 := portfolio-lab/02-slurm-gpu-platform
LAB3 := portfolio-lab/03-observability
LAB4 := portfolio-lab/04-inference-serving
LAB5 := portfolio-lab/05-bcm-style-cluster-lifecycle

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
# Phase 1 - Kubernetes fake-GPU control-plane simulation (no GPU required)
# ---------------------------------------------------------------------------
.PHONY: phase1-up phase1-demo phase1-evidence phase1-down
phase1-up: ## Create kind cluster, install KWOK + fake-gpu-operator, create fake GPU node pools
	$(LAB1)/scripts/setup-kind.sh $(CLUSTER_NAME)
	$(LAB1)/scripts/install-kwok.sh
	$(LAB1)/scripts/install-fake-gpu-operator.sh
	$(LAB1)/scripts/create-fake-gpu-nodes.sh

phase1-demo: ## Deploy schedulable + intentionally-pending GPU workloads
	$(LAB1)/scripts/run-scheduling-demo.sh

phase1-evidence: ## Capture kubectl evidence into portfolio-lab/06-validation-reports/
	./scripts/collect-k8s-evidence.sh

phase1-down: ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER_NAME)

# ---------------------------------------------------------------------------
# Real GPU validation - Lesson 6 Part A (requires one NVIDIA GPU machine)
# ---------------------------------------------------------------------------
.PHONY: phase2-guide
phase2-guide: ## Print the real-GPU validation guide location
	@echo "Real GPU validation is a guided manual process by design."
	@echo "Follow: $(LAB1)/gpu-operator-real/README.md"
	@echo "Then capture evidence with: ./scripts/collect-gpu-evidence.sh"

# ---------------------------------------------------------------------------
# Lessons 1B / 1C - guided (install drifts; we ship example manifests, not an
# automated install, to respect the no-invented-commands rule).
# ---------------------------------------------------------------------------
.PHONY: kai-guide hami-guide
kai-guide: ## Lesson 1B (KAI Scheduler): runnable lesson with its own Makefile
	@echo "Lesson 1B - Queue-based scheduling with KAI Scheduler (runnable, no GPU)."
	@echo "It has its own Makefile (own GPU fleet via the fake-gpu-operator):"
	@echo "  cd $(LAB1)/kai-scheduler && make up && make demo-quota"
	@echo "Guide: $(LAB1)/kai-scheduler/README.md"
	@echo "Is KAI installed?"
	@kubectl get crds 2>/dev/null | grep -i kai || echo "  (not yet - run 'make up' in the lesson dir)"

hami-guide: ## Lesson 1C (HAMi): print example manifests + install check
	@echo "Lesson 1C - GPU sharing / fractional GPUs with HAMi."
	@echo "Guide:    $(LAB1)/hami/README.md"
	@echo "Examples: $(LAB1)/hami/examples/ (ILLUSTRATIVE - run on the Lesson 6 GPU)"
	@echo "Is HAMi installed?"
	@kubectl get pods -A 2>/dev/null | grep -i hami || echo "  (no HAMi pods found - install per the official docs on the GPU machine)"

# ---------------------------------------------------------------------------
# Phase 3 - Slurm GPU workload management (Slurm-in-Docker, fake GRES, no GPU)
# ---------------------------------------------------------------------------
.PHONY: phase3-up phase3-demo phase3-drain phase3-evidence phase3-down
phase3-up: ## Build + start the Slurm-in-Docker cluster and bootstrap accounting
	$(LAB2)/scripts/up.sh

phase3-demo: ## Submit the four GPU scheduling scenarios; show the queue + reasons
	$(LAB2)/scripts/demo.sh

phase3-drain: ## Run the drain/resume node-maintenance drill
	$(LAB2)/scripts/drain-drill.sh

phase3-evidence: ## Capture sinfo/squeue/sacct/qos evidence into 06-validation-reports/
	./scripts/collect-slurm-evidence.sh

phase3-down: ## Stop and remove the Slurm cluster (containers + volumes)
	$(LAB2)/scripts/down.sh

# ---------------------------------------------------------------------------
# Phase 4 - GPU observability (Prometheus/Grafana over synthetic DCGM metrics)
# Runs against the Phase 1 kind cluster. No GPU required.
# ---------------------------------------------------------------------------
.PHONY: phase4-up phase4-break phase4-evidence phase4-down
phase4-up: ## Deploy fake-DCGM exporter + kube-prometheus-stack into the kind cluster
	$(LAB3)/scripts/up.sh

phase4-break: ## Break-it drills: trip the control-plane alerts on purpose
	$(LAB3)/scripts/break-it.sh

phase4-evidence: ## Capture Prometheus targets, rules, and alert state
	$(LAB3)/scripts/collect-evidence.sh

phase4-down: ## Remove the observability stack (keeps the kind cluster)
	$(LAB3)/scripts/down.sh

# ---------------------------------------------------------------------------
# Phase 5 - Inference serving / benchmarking
# $0 harness tier runs against a CPU-served model; numbers are NOT a benchmark.
# Real benchmark numbers require the Lesson 6 GPU machine.
# ---------------------------------------------------------------------------
.PHONY: phase5-serve-cpu phase5-serve-gpu phase5-bench phase5-batching phase5-prefill phase5-decode phase5-overload phase5-capacity phase5-down
phase5-serve-cpu: ## [$0] Serve a tiny model on CPU to study serving behaviour
	$(LAB4)/scripts/serve-cpu.sh

phase5-serve-gpu: ## [Lesson 6 GPU VM] Deploy vLLM on the k3s GPU cluster (OpenAI API on :8000)
	$(LAB4)/scripts/serve-gpu.sh

phase5-bench: ## Run the concurrency sweep against $ENDPOINT (default: local CPU server)
	$(LAB4)/harness/run-bench.sh

phase5-batching: ## [$0 drill] Make continuous batching visible (short requests behind long ones)
	$(LAB4)/harness/drills.sh batching

phase5-prefill: ## [$0 drill] Input-length sweep -> TTFT (prefill cost)
	$(LAB4)/harness/drills.sh prefill

phase5-decode: ## [$0 drill] Output-length sweep -> e2e/TPOT (decode cost)
	$(LAB4)/harness/drills.sh decode

phase5-overload: ## [$0 drill] Push past the knee -> goodput collapses, errors climb
	$(LAB4)/harness/drills.sh overload

phase5-capacity: ## [$0] Capacity-planning exercise (Little's Law + $/1M tokens); pass ARGS="--..."
	python3 $(LAB4)/harness/capacity-plan.py $(ARGS)

phase5-down: ## Stop the local CPU model server
	$(LAB4)/scripts/down.sh

# ---------------------------------------------------------------------------
# Phase 6 - BCM-style cluster lifecycle drill (runs on the Phase 1 kind cluster)
# ---------------------------------------------------------------------------
.PHONY: phase6-drill
phase6-drill: ## Run the node provision -> health-gate -> patch -> retire lifecycle drill
	$(LAB5)/scripts/lifecycle-drill.sh


# ---------------------------------------------------------------------------
# Lesson 1D - GPU fleet scale simulation with Volcano (no GPU required).
# Named for the lesson, not a phase number: this lesson belongs to the Lesson 1
# scheduling family and reuses the Lesson 1 fake fleet.
# ---------------------------------------------------------------------------
.PHONY: phase1d-up phase1d-volcano phase1d-demo phase1d-status phase1d-evidence phase1d-down
phase1d-up: ## Lesson 1D: create a topology-driven KWOK fake GPU fleet; pass TOPOLOGY=...
	$(LAB1D)/scripts/check-scale-prereqs.sh
	CLUSTER_NAME=$(CLUSTER_NAME) TOPOLOGY=$${TOPOLOGY:-$(LAB1D)/topology/small.json} $(LAB1D)/scripts/up.sh

phase1d-volcano: ## Lesson 1D: install Volcano scheduler for queue/gang scheduling drills
	VOLCANO_VERSION=$${VOLCANO_VERSION:-v1.10.0} $(LAB1D)/scripts/install-volcano.sh

phase1d-demo: ## Lesson 1D: run Volcano Queue/PodGroup GPU scale scheduling scenarios
	TOPOLOGY=$${TOPOLOGY:-$(LAB1D)/topology/small.json} $(LAB1D)/scripts/run-volcano-demo.sh

phase1d-status: ## Lesson 1D: show fake fleet and Volcano scheduling state
	$(LAB1D)/scripts/status.sh

phase1d-evidence: ## Lesson 1D: capture scheduling evidence
	$(LAB1D)/scripts/collect-scale-evidence.sh

phase1d-down: ## Lesson 1D: remove workloads and fake scale nodes
	REMOVE_VOLCANO=$${REMOVE_VOLCANO:-0} $(LAB1D)/scripts/down.sh

# ---------------------------------------------------------------------------
# Docs site (MkDocs Material) -> https://ld-singh.github.io/ai-factory-ops-lab/
# Needs: pip install -r requirements-docs.txt   (use a venv if your Python is managed)
# NO_MKDOCS_2_WARNING silences Material's advocacy banner about a future MkDocs 2.0.
# ---------------------------------------------------------------------------
export NO_MKDOCS_2_WARNING := true

.PHONY: docs-serve docs-build
# Port 8001 (not mkdocs' default 8000) so the docs preview can run alongside the
# Lesson 4 inference server, which serves on the conventional OpenAI/vLLM port 8000.
docs-serve: ## Sync lesson markdown and serve the docs site locally at http://localhost:8001
	./scripts/sync-docs.sh
	mkdocs serve --dev-addr 127.0.0.1:8001

docs-build: ## Sync lesson markdown and build the static site into site/
	./scripts/sync-docs.sh
	mkdocs build

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
.PHONY: clean
clean: ## Remove lab clusters and generated artifacts (asks for confirmation)
	./scripts/cleanup.sh

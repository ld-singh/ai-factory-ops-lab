# Lesson 1D - GPU Fleet Scale Simulation with Volcano

SHELL := /bin/bash
TOPOLOGY ?= topology/small.json
CLUSTER_NAME ?= ai-factory-lab
VOLCANO_VERSION ?= v1.10.0

.PHONY: help check up volcano-up demo status evidence down

help: ## Show lesson targets
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

check: ## Verify local prerequisites
	./scripts/check-scale-prereqs.sh

up: check ## Create kind+KWOK cluster, install fake-gpu-operator, and create the scale fake GPU fleet
	CLUSTER_NAME=$(CLUSTER_NAME) TOPOLOGY=$(TOPOLOGY) ./scripts/up.sh

volcano-up: ## Install Volcano scheduler into the current cluster
	VOLCANO_VERSION=$(VOLCANO_VERSION) ./scripts/install-volcano.sh

demo: ## Create Volcano queues, PodGroups, and GPU-like queue pressure workloads
	TOPOLOGY=$(TOPOLOGY) ./scripts/run-volcano-demo.sh

status: ## Show fake GPU fleet and Volcano scheduling state
	./scripts/status.sh

evidence: ## Capture nodes, queues, PodGroups, Pods, and events into the validation report area
	./scripts/collect-scale-evidence.sh

down: ## Remove Lesson 1D workloads and fake nodes; pass REMOVE_VOLCANO=1 to uninstall Volcano too
	REMOVE_VOLCANO=$(REMOVE_VOLCANO) ./scripts/down.sh

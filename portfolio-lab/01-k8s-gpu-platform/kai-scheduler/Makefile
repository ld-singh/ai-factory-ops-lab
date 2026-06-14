# KAI Scheduler lesson (1B) - queue/quota/borrow/reclaim/gang on the KWOK fake fleet.
# Control plane only: pods are pause containers on fake GPU nodes. No GPU, no CUDA.
# KAI works here because queue and gang decisions are pure scheduling logic over the
# integer nvidia.com/gpu that KWOK nodes advertise. See README.md.

SHELL := /bin/bash

# Pinned versions. Override on the command line if needed.
KAI_VERSION ?= v0.15.2
CLUSTER     ?= ai-factory-lab

SCRIPTS := scripts
export KAI_VERSION CLUSTER

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show targets
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

.PHONY: up
up: cluster kai ## Full setup: shared Lesson 1 fleet + KAI (queues are a separate step)
	@echo "Ready. Next: make queues, then make demo-quota / demo-borrow / demo-reclaim / demo-gang"

.PHONY: cluster
cluster: ## Ensure the shared Lesson 1 fleet exists (kind + KWOK + fake-gpu-operator + nodes)
	$(SCRIPTS)/ensure-cluster.sh

.PHONY: kai
kai: ## Install KAI Scheduler from its OCI Helm chart at KAI_VERSION
	$(SCRIPTS)/install-kai.sh

.PHONY: queues
queues: ## Create the demo namespace + the parent/leaf queues (research, prod, gang)
	kubectl apply -f manifests/namespace.yaml
	kubectl apply -f manifests/queues.yaml
	kubectl get queues.scheduling.run.ai

.PHONY: demo-quota
demo-quota: ## Exercise A: two teams each fill their 8-GPU quota
	$(SCRIPTS)/demo-quota.sh

.PHONY: demo-borrow
demo-borrow: ## Exercise B: prod borrows research's idle GPUs (runs beyond its quota)
	$(SCRIPTS)/demo-borrow.sh

.PHONY: demo-reclaim
demo-reclaim: ## Exercise C: research returns; KAI reclaims borrowed GPUs (run after demo-borrow)
	$(SCRIPTS)/demo-reclaim.sh

.PHONY: demo-gang
demo-gang: ## Exercise D: a 10-GPU gang binds all-or-none (anti-deadlock)
	$(SCRIPTS)/demo-gang.sh

.PHONY: evidence
evidence: ## Capture queues, pods, and events into evidence/<timestamp>/
	$(SCRIPTS)/collect-evidence.sh

.PHONY: clean
clean: ## Delete the demo workloads and queues (keep the cluster, KAI, and fleet)
	-kubectl delete deploy -n kai-demo --all --ignore-not-found
	-kubectl delete -f manifests/queues.yaml --ignore-not-found

.PHONY: uninstall
uninstall: ## Tear everything down: delete the whole kind cluster (KAI + the shared fleet)
	kind delete cluster --name $(CLUSTER)
	@echo "Deleted cluster '$(CLUSTER)' (KAI, the fake-gpu-operator fleet, and all workloads are gone)."

# HAMi scheduling simulation - control plane only, no GPU.
# Self-contained: its own kind cluster and pinned versions. See README.md for the
# boundary: this validates HAMi's fractional SCHEDULING DECISIONS, NOT GPU sharing or
# runtime isolation. Anything where pods must actually SHARE a device lives in the
# real-GPU lesson (../hami-isolation-realgpu/) - the fake fleet cannot do it without
# forcing, so we don't.
#
# Setup mirrors the official HAMi local-fake-gpu tutorial
# (https://project-hami.io/tutorials/labs/local-fake-gpu), plus the per-node
# hami.io/node-nvidia-register annotation so HAMi's scheduler can score gpumem/gpucores.

SHELL := /bin/bash

# Pinned versions. K8S_VERSION feeds BOTH the kind node image AND HAMi's
# scheduler.kubeScheduler.imageTag, so the two cannot drift (a top HAMi failure mode).
# Override on the command line, e.g. make up K8S_VERSION=v1.30.4
K8S_VERSION  ?= v1.31.0
HAMI_VERSION ?= 2.9.0
FGO_VERSION  ?= 0.0.59

CLUSTER    ?= hami-sim
KIND_IMAGE := kindest/node:$(K8S_VERSION)
HAMI_REPO  := https://project-hami.github.io/HAMi
SCRIPTS    := scripts
export K8S_VERSION HAMI_VERSION FGO_VERSION CLUSTER

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show targets
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

.PHONY: up
up: cluster labels fleet hami register verify ## Full setup in the required order
	@echo "Setup complete. Next: make demo-fractional / demo-pending / demo-placement"

.PHONY: cluster
cluster: ## Create the kind cluster (1 control-plane + 3 workers) at K8S_VERSION
	kind create cluster --name $(CLUSTER) --image $(KIND_IMAGE) --config kind/cluster.yaml
	kubectl cluster-info --context kind-$(CLUSTER)

.PHONY: labels
labels: ## Label workers gpu=on AND run.ai/simulated-gpu-node-pool=default
	@for n in $$(kubectl get nodes -o name | grep -v control-plane); do \
	  kubectl label "$$n" gpu=on run.ai/simulated-gpu-node-pool=default --overwrite ; \
	done
	kubectl get nodes -L gpu,run.ai/simulated-gpu-node-pool

.PHONY: fleet
fleet: ## Install run.ai fake-gpu-operator so nodes advertise nvidia.com/gpu (no hardware)
	$(SCRIPTS)/setup-fleet.sh

.PHONY: hami
hami: ## Install HAMi: device plugin OFF (it needs NVML); scheduler tag pinned to K8S_VERSION
	helm repo add hami-charts $(HAMI_REPO)
	helm repo update hami-charts
	helm upgrade --install hami hami-charts/hami \
	  --version $(HAMI_VERSION) \
	  -n kube-system \
	  --set devicePlugin.enabled=false \
	  --set mockDevicePlugin.enabled=false \
	  --set scheduler.kubeScheduler.imageTag=$(K8S_VERSION) \
	  --wait --timeout 5m
	kubectl -n kube-system get pods | grep -i hami

.PHONY: register
register: ## Tell HAMi's scheduler what GPUs each node has (run once; 'make up' does it)
	$(SCRIPTS)/register-hami.sh register

# SCOPE: this fake fleet proves HAMi's control-plane SCHEDULING DECISIONS only - a single
# fractional pod placing, and a request that can't fit being rejected (Pending + reason).
# It does NOT do GPU sharing (multiple pods on one device, both Running): that needs a real
# device plugin to complete and release each bind, which only real hardware provides.
# Sharing + isolation live in ../hami-isolation-realgpu/. `make up` runs `register` once to
# write the scheduler's node-GPU annotation (both device plugins are off, so nothing else
# writes it); if nodes go stale (~60s), `make register` refreshes the handshake.

.PHONY: verify
verify: ## Show nvidia.com/gpu and the HAMi registration annotation per node
	$(SCRIPTS)/verify-resources.sh

.PHONY: demo-fractional
demo-fractional: ## Scenario 1: a single fractional pod (gpu:1, gpumem, gpucores) schedules
	kubectl apply -f manifests/01-fractional-pod.yaml
	@sleep 12
	kubectl get pod hami-fractional -o wide
	@echo "Verify:  kubectl get pod hami-fractional -o wide"

.PHONY: demo-pending
demo-pending: ## Scenario 2: a gpumem request bigger than any GPU stays Pending
	kubectl apply -f manifests/02-overrequest-pending.yaml
	@sleep 10
	kubectl get pod hami-overrequest -o wide
	@kubectl describe pod hami-overrequest | sed -n '/Events:/,$$p' | head -8
	@echo "Verify:  kubectl get pod hami-overrequest -o wide   (Pending: CardInsufficientMemory)"

.PHONY: demo-placement
demo-placement: ## Scenario 3: show HAMi's per-pod placement DECISION (FilteringSucceed)
	$(SCRIPTS)/demo-placement.sh

.PHONY: evidence
evidence: ## Capture control-plane evidence into evidence/<timestamp>/
	$(SCRIPTS)/collect-evidence.sh

.PHONY: clean
clean: ## Delete the demo workloads (keep the cluster)
	-kubectl delete -f manifests/03-placement-spread.yaml --ignore-not-found
	-kubectl delete -f manifests/02-overrequest-pending.yaml --ignore-not-found
	-kubectl delete -f manifests/01-fractional-pod.yaml --ignore-not-found

.PHONY: down
down: ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER)

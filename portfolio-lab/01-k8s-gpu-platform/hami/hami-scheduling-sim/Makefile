# HAMi scheduling simulation - control plane only, no GPU.
# Self-contained: its own kind cluster and pinned versions. See README.md for the
# boundary (this validates fractional SCHEDULING, NOT runtime isolation).
#
# Setup mirrors the official HAMi local-fake-gpu tutorial
# (https://project-hami.io/tutorials/labs/local-fake-gpu), with one addition that
# makes FRACTIONAL scheduling work: the per-node hami.io/node-nvidia-register
# annotation (with devmem/devcore) so HAMi's scheduler can place gpumem/gpucores.

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
hami: ## Install HAMi: real device-plugin OFF (it crashes with no GPU), scheduler tag pinned
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
register: ## Register the fake GPUs with HAMi's scheduler (node annotation + handshake)
	$(SCRIPTS)/register-hami.sh register

.PHONY: verify
verify: ## Show nvidia.com/gpu and the HAMi registration annotation per node
	$(SCRIPTS)/verify-resources.sh

.PHONY: demo-fractional
demo-fractional: ## Scenario 1: a fractional pod (gpu:1, gpumem:3000, gpucores:30) binds
	@$(SCRIPTS)/register-hami.sh refresh
	kubectl apply -f manifests/01-fractional-pod.yaml
	@sleep 12
	kubectl get pod hami-fractional -o wide
	@echo "Bound to node: $$(kubectl get pod hami-fractional -o jsonpath='{.spec.nodeName}')"

.PHONY: demo-pending
demo-pending: ## Scenario 2: a gpumem request bigger than any GPU stays Pending
	@$(SCRIPTS)/register-hami.sh refresh
	kubectl apply -f manifests/02-overrequest-pending.yaml
	@sleep 10
	kubectl get pod hami-overrequest -o wide
	@kubectl describe pod hami-overrequest | sed -n '/Events:/,$$p' | head -8

.PHONY: demo-placement
demo-placement: ## Scenario 3: small slices; show HAMi's per-pod placement DECISIONS
	@$(SCRIPTS)/register-hami.sh refresh
	kubectl apply -f manifests/03-placement-spread.yaml
	@sleep 15
	@echo "HAMi placement decisions (node chosen + fractional score per pod):"
	@kubectl get events --field-selector reason=FilteringSucceed 2>/dev/null \
	  | grep -i "find fit node" | tail -3 || echo "  (re-run; events may still be arriving)"
	@echo "Pods (binding onto fake nodes is slow/serialized; see the manifest note):"
	kubectl get pods -l app=hami-placement -o wide

.PHONY: demo-binpack
demo-binpack: ## Scenario 4: 12 pods share one 8-GPU node (multiple pods per device)
	$(SCRIPTS)/demo-binpack.sh

.PHONY: demo-mem-exhaustion
demo-mem-exhaustion: ## Scenario 5: per-device gpumem budget exhausts; last pod Pending
	$(SCRIPTS)/demo-mem-exhaustion.sh

.PHONY: demo-gpucores
demo-gpucores: ## Scenario 6: gpucores (compute %) exhausts independently of memory
	$(SCRIPTS)/demo-gpucores.sh

.PHONY: demo-gpumem-percentage
demo-gpumem-percentage: ## Scenario 7: percentage memory form (gpumem-percentage) binds
	$(SCRIPTS)/demo-gpumem-percentage.sh

.PHONY: evidence
evidence: ## Capture control-plane evidence into evidence/<timestamp>/
	$(SCRIPTS)/collect-evidence.sh

.PHONY: clean
clean: ## Delete the demo workloads (keep the cluster)
	-kubectl delete -f manifests/07-gpumem-percentage.yaml --ignore-not-found
	-kubectl delete -f manifests/06-gpucores.yaml --ignore-not-found
	-kubectl delete -f manifests/05-mem-exhaustion.yaml --ignore-not-found
	-kubectl delete -f manifests/04-binpack.yaml --ignore-not-found
	-kubectl delete -f manifests/03-placement-spread.yaml --ignore-not-found
	-kubectl delete -f manifests/02-overrequest-pending.yaml --ignore-not-found
	-kubectl delete -f manifests/01-fractional-pod.yaml --ignore-not-found
	-$(SCRIPTS)/pin-node.sh --clear

.PHONY: down
down: ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER)

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
#
# HAMI_VERSION is 2.8.x ON PURPOSE: it's the version whose hami-scheduler-device ConfigMap
# the mock device plugin (image 1.0.1) can parse. HAMi 2.9.0's Ascend user-space
# partitioning reshaped that config to a map, which the mock plugin rejects
# ("cannot unmarshal map into []ascend.VNPUConfig"). The mock plugin is what answers the
# kubelet's Allocate so SHARED pods actually run on fakes - so we pin 2.8.x to keep it.
K8S_VERSION  ?= v1.31.0
HAMI_VERSION ?= 2.8.0
MOCK_TAG     ?= 1.0.1
FGO_VERSION  ?= 0.0.59

CLUSTER    ?= hami-sim
KIND_IMAGE := kindest/node:$(K8S_VERSION)
HAMI_REPO  := https://project-hami.github.io/HAMi
SCRIPTS    := scripts
export K8S_VERSION HAMI_VERSION MOCK_TAG FGO_VERSION CLUSTER

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show targets
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

.PHONY: up
up: cluster labels fleet hami register verify ## Full setup in the required order
	@echo "Setup complete. Next: make demo-share (the headline) / demo-fractional / demo-pending / demo-placement / demo-binpack"

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
hami: ## Install HAMi with the MOCK device plugin ON (it answers Allocate, so shared pods run)
	helm repo add hami-charts $(HAMI_REPO)
	helm repo update hami-charts
	helm upgrade --install hami hami-charts/hami \
	  --version $(HAMI_VERSION) \
	  -n kube-system \
	  --set devicePlugin.enabled=false \
	  --set mockDevicePlugin.enabled=true \
	  --set mockDevicePlugin.image.tag=$(MOCK_TAG) \
	  --set scheduler.kubeScheduler.imageTag=$(K8S_VERSION) \
	  --wait --timeout 6m
	kubectl -n kube-system get pods | grep -iE "hami|mock"

.PHONY: register
register: ## Tell HAMi's scheduler what GPUs each node has (run once; 'make up' does it)
	$(SCRIPTS)/register-hami.sh register

# SCOPE: this fake fleet proves HAMi's control-plane scheduling AND, thanks to HAMi's mock
# device plugin (which answers the kubelet's Allocate with no hardware), multiple pods
# SHARING a GPU actually reach Running. `make up` runs `register` ONCE to write the
# scheduler's node-GPU annotation (the mock plugin registers devices with the kubelet but
# NOT that annotation). Demos do NOT re-register - doing so before each demo tangles HAMi's
# per-node bind lock and leaves the second pod Pending ("node ... has been locked"). If
# nodes go stale (~60s of inactivity), `make register` refreshes them. Two hard rules:
#   * request GPU memory as a PERCENTAGE (nvidia.com/gpumem-percentage), not absolute MiB:
#     the mock plugin registers one device per MiB, so 8x81920 MiB blows past the kubelet's
#     ~120 GiB device limit and absolute gpumem capacity comes back 0. Percentage is a
#     small count (8x100) and allocates fine.
#   * runtime ISOLATION (the slice actually enforced inside the container), CUDA, and MIG
#     still need a real GPU - that's ../hami-isolation-realgpu/.

.PHONY: verify
verify: ## Show what each node advertises (nvidia.com/gpu + gpumem-percentage/gpucores)
	$(SCRIPTS)/verify-resources.sh

.PHONY: demo-share
demo-share: ## THE HEADLINE: two pods SHARE one GPU - both Running (default scheduler can't)
	$(SCRIPTS)/demo-share.sh

.PHONY: demo-fractional
demo-fractional: ## Scenario 1: a single fractional pod (gpu:1 + a memory %) reaches Running
	kubectl apply -f manifests/01-fractional-pod.yaml
	@sleep 12
	kubectl get pod hami-fractional -o wide
	@echo "Verify:  kubectl get pod hami-fractional -o wide   (Running)"

.PHONY: demo-pending
demo-pending: ## Scenario 2: a memory request bigger than a GPU stays Pending
	kubectl apply -f manifests/02-overrequest-pending.yaml
	@sleep 10
	kubectl get pod hami-overrequest -o wide
	@kubectl describe pod hami-overrequest | sed -n '/Events:/,$$p' | head -8
	@echo "Verify:  kubectl get pod hami-overrequest -o wide   (Pending: CardInsufficientMemory)"

.PHONY: demo-placement
demo-placement: ## Scenario 3: show HAMi's per-pod placement DECISION (FilteringSucceed)
	$(SCRIPTS)/demo-placement.sh

.PHONY: demo-binpack
demo-binpack: ## Scenario 4: many fractional pods pack onto few GPUs (sharing at scale)
	$(SCRIPTS)/demo-binpack.sh

.PHONY: evidence
evidence: ## Capture control-plane evidence into evidence/<timestamp>/
	$(SCRIPTS)/collect-evidence.sh

.PHONY: clean
clean: ## Delete the demo workloads (keep the cluster)
	-kubectl delete -f manifests/04-binpack.yaml --ignore-not-found
	-kubectl delete -f manifests/03-placement-spread.yaml --ignore-not-found
	-kubectl delete -f manifests/02-overrequest-pending.yaml --ignore-not-found
	-kubectl delete -f manifests/00-share.yaml --ignore-not-found
	-kubectl delete -f manifests/01-fractional-pod.yaml --ignore-not-found

.PHONY: down
down: ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER)

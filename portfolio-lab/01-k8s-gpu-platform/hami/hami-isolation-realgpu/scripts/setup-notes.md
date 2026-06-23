# Host setup notes (real GPU)

Ordered steps from a fresh rented instance to two pods sharing one GPU. These are
notes, not a one-command script, because the host-level steps depend on the provider
image and the installed driver and are not safe to run blindly. Read each step, adjust
for your host, then run it. Defer to the upstream docs linked below for exact commands.

## 0. Requirements

- One NVIDIA GPU visible to the host (a consumer 24 GB card such as RTX 4090 or
  RTX 3090 is the intended target: no MIG, which is HAMi's core use case).
- root on the host, and the ability to install packages and configure the container
  runtime. A locked marketplace container you cannot reconfigure will not work.

## 1. Confirm the host sees the GPU

```bash
nvidia-smi
```

You should see the card and a driver version. If this fails, stop: nothing below will
work until the host driver is healthy.

## 2. Install the NVIDIA Container Toolkit and set the containerd runtime

Install the toolkit and configure it as a containerd runtime. Do this BEFORE
installing k3s, so k3s detects the NVIDIA runtime when it starts.

- NVIDIA Container Toolkit install guide:
  https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
- The configure step is, in outline, `nvidia-ctk runtime configure --runtime=containerd`
  followed by restarting containerd. Confirm the exact invocation for your host in the
  guide above.

## 3. Install single-node k3s

```bash
curl -sfL https://get.k3s.io | sh -
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes
```

k3s bundles its own containerd. With the toolkit installed first (step 2), k3s should
detect the NVIDIA container runtime. Confirm against the k3s advanced/GPU docs if the
runtime is not picked up: https://docs.k3s.io/

## 4. Capture the Kubernetes server version

```bash
kubectl version
```

Note the **server** version (for example v1.31.x). You will pass it to HAMi as the
scheduler image tag in the next step. A mismatch here is the most common HAMi failure.

## 5. Label the node

```bash
kubectl label node "$(kubectl get nodes -o name | head -1 | cut -d/ -f2)" gpu=on --overwrite
```

## 6. Install HAMi with the scheduler image tag matched to the server version

Replace `vX.Y.Z` with the server version from step 4.

```bash
helm repo add hami-charts https://project-hami.github.io/HAMi
helm repo update hami-charts
helm upgrade --install hami hami-charts/hami \
  --version 2.9.0 \
  -n kube-system \
  --set scheduler.kubeScheduler.imageTag=vX.Y.Z \
  --wait
kubectl -n kube-system get pods | grep -i hami
```

The hami-device-plugin and hami-scheduler pods should reach Running. The device
plugin will register the real GPU into the node's `nvidia.com/*` resources and the
`hami.io/node-nvidia-register` annotation.

## 7. Deploy the two sharing pods and probe

```bash
kubectl apply -f manifests/share-two-pods.yaml
kubectl get pods -o wide          # both should land on the single GPU node
kubectl wait --for=condition=Ready pod/hami-share-a pod/hami-share-b --timeout=300s
./scripts/probe-memory.sh hami-share-a
./scripts/probe-memory.sh hami-share-b

# Exercise 4: a third pod that fits an empty card but not beside the two slices.
# Size its gpumem first (see the manifest comment), then apply and watch it stay Pending.
kubectl apply -f manifests/oversubscribe-pending.yaml
sleep 15
kubectl get pod hami-oversubscribe -o wide
kubectl describe pod hami-oversubscribe | sed -n '/Events:/,$p' | head -8   # CardInsufficientMemory

# Exercise 5: show HOW the cap is enforced (HAMi-core injection + device view)
./scripts/probe-mechanism.sh hami-share-a
```

The first probe shows the virtualized `nvidia-smi` (the slice, not the full card).
The second shows a CUDA allocation refused near the slice limit. Exercise 4 shows the
card's memory is one shared, accounted budget on real hardware; Exercise 5 surfaces the
HAMi-core mechanism behind the cap. Record all of them as the isolation evidence. Then
tear the instance down.

## Notes

- Consumer-card marketplaces vary in reliability (driver versions, host config,
  uptime). Expect to occasionally discard an instance and reprovision.
- TODO: `nvidia.com/gpumem` unit. HAMi docs phrase it as "MB"; this lesson treats it
  as MiB. Confirm against the chart version you installed if exact sizing matters.

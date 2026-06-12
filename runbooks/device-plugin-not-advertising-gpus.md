# Runbook - Node Not Advertising nvidia.com/gpu

**Severity:** High - GPU capacity silently missing from the fleet; workloads Pending.
**Applies to:** real GPU clusters with NVIDIA GPU Operator. (In the simulation,
the analogue is a fake node missing its `status.allocatable` entry.)

## Symptom

- GPU pods Pending with `Insufficient nvidia.com/gpu` despite a GPU node existing
- `kubectl describe node <node>` shows `nvidia.com/gpu: 0` or no entry at all

## Triage order (walk the GPU path bottom-up)

The fastest diagnosis follows `diagrams/gpu-path-to-pod.md` from hardware up.
Each step isolates one failure domain.

### 1. Driver layer (on the node)

```bash
nvidia-smi
```

- Fails / no devices → driver problem. Check `dmesg | grep -i nvidia`, driver
  package state, secure boot / kernel module signing, recent kernel upgrades
  that orphaned the DKMS module. Stop here and fix the driver first.

### 2. Container runtime layer (on the node)

```bash
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
# or for containerd-only nodes, check the runtime config:
grep -A3 nvidia /etc/containerd/config.toml
```

- Fails while host `nvidia-smi` works → Container Toolkit / runtime config
  problem. Re-run `nvidia-ctk runtime configure` per official docs and restart
  the runtime.

### 3. GPU Operator components

```bash
kubectl get pods -n gpu-operator -o wide | grep -E 'device-plugin|driver|toolkit|validator'
kubectl logs -n gpu-operator <device-plugin-pod>
kubectl describe pod -n gpu-operator <failing-pod>
```

Common findings:
- Driver daemonset pod CrashLoopBackOff → see `gpu-operator-driver-pod-failing.md`
- Device plugin running but logging "no devices found" → step 1 or 2 actually
  failed; re-verify
- Validator pods failing → read their logs; they name the broken layer

### 4. Node labels / selectors

```bash
kubectl get node <node> --show-labels | tr ',' '\n' | grep -i nvidia
```

- GPU Operator daemonsets target nodes via feature labels; a node that lost its
  labels (e.g. after re-provisioning) gets no device plugin pod at all.

### 5. kubelet registration

```bash
kubectl get node <node> -o jsonpath='{.status.allocatable}' | jq .
journalctl -u kubelet --since "1 hour ago" | grep -i 'device plugin'
```

- Device plugin healthy but allocatable still 0 → kubelet may need a restart to
  re-register the plugin socket; check for stale sockets under
  `/var/lib/kubelet/device-plugins/`.

## Resolution verification

```bash
kubectl get node <node> -o jsonpath='{.status.allocatable.nvidia\.com/gpu}'
kubectl run cuda-verify --rm -it --restart=Never \
  --image=nvidia/cuda:12.4.1-base-ubuntu22.04 \
  --limits=nvidia.com/gpu=1 -- nvidia-smi
```

## Prevention

- Alert on `sum(node allocatable nvidia.com/gpu)` dropping below expected fleet
  size (Phase 4 alert rule)
- Pin GPU Operator and driver versions; treat upgrades as change-managed events
- Run the validator checks after every node provision/reboot

## Drill in this lab

Simulation: delete the `nvidia.com/gpu` allocatable from one fake node and
watch scheduling behaviour change; practice the triage narrative.
Real mode: after Phase 2 setup, stop the device plugin daemonset and walk this
runbook end to end, capturing output for the validation report.

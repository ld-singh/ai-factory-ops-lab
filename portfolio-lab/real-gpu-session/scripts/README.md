# Lesson 6 setup scripts - TensorDock GPU VM → k3s → kubeconfig

> Part of [Lesson 6 - Real GPU](../README.md). These automate **Phase 0 (host setup)**
> and the **Phase A install**, for a rented GPU VM (written against
> [TensorDock](https://www.tensordock.com/), but any Ubuntu/Debian GPU VM with root
> works). The lab itself (Parts A–D) is still driven by the Lesson 6 pages.

> ⚠️ **Read each script before running it.** They use the documented NVIDIA / k3s
> commands as of this writing, but package URLs, chart names, and flags drift - the
> scripts flag the version-sensitive bits and link the official docs. Never pipe a
> setup script you haven't read onto a host you're paying for.

## The flow

```
┌─ on the GPU VM (SSH in, as root) ─────────────────────────────────────────┐
│  sudo PUBLIC_IP=<vm-ip> bash host-setup.sh                                 │
│    → driver check → NVIDIA Container Toolkit → k3s (--tls-san <vm-ip>)     │
│      → labels node gpu=on. Cluster is up; API on :6443.                    │
└───────────────────────────────────────────────────────────────────────────┘
                              │  (open TCP 6443 to your laptop)
┌─ on your LAPTOP ──────────────────────────────────────────────────────────┐
│  ./fetch-kubeconfig.sh <ssh-user>@<vm-ip>                                  │
│    → writes ./kubeconfig-tensordock with server → https://<vm-ip>:6443     │
│    → verifies `kubectl get nodes`                                          │
│                                                                            │
│  export KUBECONFIG=$PWD/kubeconfig-tensordock                              │
│  ./install-gpu-operator.sh        # GPU Operator (DCGM incl.) + CUDA smoke │
│    # or: MODE=device-plugin ./install-gpu-operator.sh   (lighter on k3s)   │
└───────────────────────────────────────────────────────────────────────────┘
```

After that you have a real GPU cluster you drive from your laptop. Work the
[Lesson 6 phases](../README.md): Part A evidence is already produced by the smoke test;
then [Part B - HAMi](../../01-k8s-gpu-platform/hami/hami-isolation-realgpu/README.md),
[Part C - Slurm GRES](../../02-slurm-gpu-platform/slurm-realgpu/README.md), and the
[Part D inference benchmark](../../04-inference-serving/README.md). **Tear the VM down
the moment your evidence is captured.**

## The scripts

| Script | Runs on | Does |
|---|---|---|
| [`host-setup.sh`](host-setup.sh) | the VM (root) | NVIDIA Container Toolkit + k3s with the public IP in the API cert; labels the node `gpu=on` |
| [`fetch-kubeconfig.sh`](fetch-kubeconfig.sh) | your laptop | reads k3s.yaml over SSH, rewrites the server to the VM's public IP, verifies `kubectl` |
| [`install-gpu-operator.sh`](install-gpu-operator.sh) | laptop or VM | installs the GPU layer (Operator, or `MODE=device-plugin`) and runs a CUDA smoke-test pod |

## TensorDock specifics (and gotchas)

- **You need a VM you fully control** (root + your own runtime), not a fixed container.
  TensorDock's GPU **VMs** fit; pick an Ubuntu image - ideally one with the NVIDIA
  driver pre-installed (`nvidia-smi` already works), which skips the slowest step.
- **Open TCP 6443.** k3s serves its API on 6443; `fetch-kubeconfig.sh` and your laptop
  `kubectl` need it reachable. If TensorDock filters ports, open 6443 (and your SSH
  port) in the VM's networking settings. If you'd rather not expose the API, run
  `install-gpu-operator.sh` *on the VM* instead (`export KUBECONFIG=/etc/rancher/k3s/k3s.yaml`).
- **SSH details vary.** Pass a non-default port/key to `fetch-kubeconfig.sh` with
  `--port` / `--key`. It reads the kubeconfig via `sudo cat`, so a sudo-capable user is enough.
- **The driver is the host's.** These scripts never install/manage the GPU driver -
  that's TensorDock's image. If `nvidia-smi` fails on the VM, fix that first (or pick a
  different image); nothing downstream works without it.
- **Cost discipline.** The VM has no value once your evidence is on your laptop. Destroy
  it (and any separately-billed storage) in the TensorDock dashboard as soon as you're done.

## What these prove (and don't)

They are **setup tooling**, not a validation. A green smoke test is real evidence for
Lesson 6 Phase A (the runtime path) once you capture it; everything else still has to be
run and captured per its lesson. Same fake-vs-real boundary as the rest of the course:
see [`fake-vs-real-limitations.md`](../../06-validation-reports/fake-vs-real-limitations.md).

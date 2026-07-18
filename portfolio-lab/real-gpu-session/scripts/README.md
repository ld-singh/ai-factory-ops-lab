# Lesson 6 setup scripts - bare GPU VM → k3s → kubeconfig

> Part of [Lesson 6 - Real GPU](../README.md). These automate **Part 0 (host setup)**
> and the **Part A install** on any **bare GPU VM you get root on** - e.g. Hyperstack,
> Lambda, or a hyperscaler GPU VM. Ubuntu/Debian assumed. They do **not** work on a
> marketplace *container* (Vast.ai / RunPod pods, managed notebooks): those don't let you
> install the container toolkit + k3s. The lab itself (Parts A–D) is driven by the Lesson 6
> pages.

> ⚠️ **Read each script before running it.** They use the documented NVIDIA / k3s
> commands as of this writing, but package URLs, chart names, and flags drift - the
> scripts flag the version-sensitive bits and link the official docs. Never pipe a
> setup script you haven't read onto a host you're paying for.

## Get the lab onto the VM

Clone the repo on the VM and run from the repo root:

```bash
git clone https://github.com/ld-singh/ai-factory-ops-lab.git
cd ai-factory-ops-lab
```

The setup scripts live in `portfolio-lab/real-gpu-session/scripts/` and are self-contained;
run them by path from the repo root (e.g.
`sudo PUBLIC_IP=<vm-ip> bash portfolio-lab/real-gpu-session/scripts/host-setup.sh`).

(Evidence capture is `capture-evidence.sh` here - self-contained, writes a tarball - so you
don't need the repo-root `scripts/collect-gpu-evidence.sh`.)

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
│    → writes ./kubeconfig-gpuvm with server → https://<vm-ip>:6443          │
│    → verifies `kubectl get nodes`                                          │
│                                                                            │
│  export KUBECONFIG=$PWD/kubeconfig-gpuvm                                   │
│  ./install-gpu-operator.sh        # GPU Operator (DCGM incl.) + CUDA smoke │
│    # or: MODE=device-plugin ./install-gpu-operator.sh   (lighter on k3s)   │
└───────────────────────────────────────────────────────────────────────────┘
```

Each script verifies itself, but you can re-check by hand. Three steps:

**1. On the VM** - set up the host, then confirm the node and runtime:

```bash
sudo PUBLIC_IP=<vm-ip> bash host-setup.sh
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes -o wide                 # node Ready
kubectl get runtimeclass nvidia           # the nvidia container runtime exists
```

**2. On your laptop** - fetch the kubeconfig and confirm you can reach the cluster
(open TCP 6443 to the VM first):

```bash
./fetch-kubeconfig.sh <ssh-user>@<vm-ip> --key <ssh-key>   # --port N too if non-22
export KUBECONFIG=$PWD/kubeconfig-gpuvm
kubectl get nodes -o wide                 # reachable from your laptop, node Ready
```

**3. GPU layer + smoke test** - install the operator, then confirm the GPU is
allocatable and runs CUDA:

```bash
./install-gpu-operator.sh
kubectl get nodes -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}'; echo   # >= 1
kubectl logs cuda-smoke                    # nvidia-smi ran on the real GPU
```

After that you have a real GPU cluster you drive from your laptop. Work the
[Lesson 6 parts](../README.md): Part A evidence is already produced by the smoke test;
then [Part B - HAMi](../../01-k8s-gpu-platform/hami/hami-isolation-realgpu/README.md),
[Part D - inference benchmark](../../04-inference-serving/README.md), and
[Part E - Slurm GRES](../../02-slurm-gpu-platform/slurm-realgpu/README.md). **Tear the VM
down the moment your evidence is captured.**

## The scripts

| Script | Runs on | Does |
|---|---|---|
| [`host-setup.sh`](host-setup.sh) | the VM (root) | NVIDIA Container Toolkit + k3s with the public IP in the API cert; labels the node `gpu=on` |
| [`fetch-kubeconfig.sh`](fetch-kubeconfig.sh) | your laptop | reads k3s.yaml over SSH, rewrites the server to the VM's public IP, verifies `kubectl` |
| [`install-gpu-operator.sh`](install-gpu-operator.sh) | laptop or VM | installs the GPU layer (Operator, or `MODE=device-plugin`) and runs a CUDA smoke-test pod |
| [`capture-evidence.sh`](capture-evidence.sh) | the VM | snapshots Part A evidence (host + in-pod `nvidia-smi`, allocatable, DCGM) into a tarball to scp back |

## GPU VM requirements (any provider) and gotchas

- **A VM you fully control** (root + your own runtime), not a fixed container. A bare GPU
  VM fits (Hyperstack, Lambda, hyperscaler); a marketplace *container* (Vast.ai/RunPod
  pods, managed notebooks) does **not** - it can't install the toolkit + k3s. Pick an
  Ubuntu image, ideally with the NVIDIA driver pre-installed (`nvidia-smi` already works),
  to skip the slowest step. An L4 (24 GB) or RTX A6000 (48 GB) on Ubuntu 22.04 is plenty -
  and neither supports MIG, which is exactly HAMi's use case.
- **Open TCP 6443.** k3s serves its API on 6443; `fetch-kubeconfig.sh` and your laptop
  `kubectl` need it reachable - open it (and your SSH port) in the provider's
  networking/firewall settings. If you'd rather not expose the API, run
  `install-gpu-operator.sh` *on the VM* instead (`export KUBECONFIG=/etc/rancher/k3s/k3s.yaml`).
- **SSH details vary.** Pass a non-default port/key to `fetch-kubeconfig.sh` with
  `--port` / `--key`. It reads the kubeconfig via `sudo cat`, so a sudo-capable user is enough.
- **The driver is the host's.** These scripts never install/manage the GPU driver - that's
  the provider image's. If `nvidia-smi` fails on the VM, fix that first (or pick a
  different image); nothing downstream works without it.
- **Cost discipline.** The VM has no value once your evidence is on your laptop. Destroy it
  (and any separately-billed storage) in the provider's dashboard as soon as you're done.

## What these prove (and don't)

They are **setup tooling**, not a validation. A green smoke test is real evidence for
Lesson 6 Part A (the runtime path) once you capture it; everything else still has to be
run and captured per its lesson. Same fake-vs-real boundary as the rest of the course:
see [`fake-vs-real-limitations.md`](../../06-validation-reports/fake-vs-real-limitations.md).

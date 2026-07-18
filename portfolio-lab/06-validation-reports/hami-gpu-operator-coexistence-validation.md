# HAMi + NVIDIA GPU Operator Coexistence Validation - Lesson 6 Part C

> 🟡 STATUS: **PENDING HARDWARE RUN.** The lab is run-ready and the capture script exists, but
> this report holds **no captured output yet**, so the part is not Complete. Run
> [`capture-evidence.sh`](../01-k8s-gpu-platform/hami/hami-gpu-operator-coexistence/scripts/capture-evidence.sh)
> on the GPU VM, then fill the tables below from the artifacts. Lab:
> [`hami-gpu-operator-coexistence/`](../01-k8s-gpu-platform/hami/hami-gpu-operator-coexistence/README.md).

The claim this report is meant to back: **HAMi and the NVIDIA GPU Operator run on one node
without fighting over `nvidia.com/gpu`, with the Operator owning the base stack and HAMi owning
the device plugin.** Nothing below is proven until the Result column holds real output.

## Environment

Fill from `0-versions.txt` and `2-operator-helm-values.txt`.

| Item | Value |
|---|---|
| Date | *(pending)* |
| Machine | *(pending)* |
| GPU | *(pending - any non-MIG card: RTX A6000, L4, L40/L40S)* |
| Driver | *(pending - and note whether it came from the VM image or the Operator)* |
| Kubernetes | *(pending - k3s version, containerd config schema)* |
| Default runtime | *(pending - expect `nvidia`)* |
| GPU Operator | *(pending - chart version; note the driver/toolkit/devicePlugin flags used)* |
| HAMi | *(pending - chart version, deviceSplitCount)* |

> **Record which component installed the driver.** This lab's VM gets the driver from the
> deep-learning image and the toolkit from `host-setup.sh`, so the Operator runs with
> `driver.enabled=false` and `toolkit.enabled=false`. A production cluster where the Operator
> owns the driver is a **different configuration**, and the reboot behaviour below is the part
> that differs. Say which one you ran.

## Validation checklist (6 artifacts)

| # | Claim | Pass criteria | Result | Evidence |
|---|---|---|---|---|
| 1 | Operator components run, its device plugin does not | Operator pods Running; **no** device-plugin pod in the namespace | *(pending)* | `1-operator-pods.txt` |
| 2 | The device plugin is disabled deliberately | `devicePlugin.enabled=false` in the released helm values / ClusterPolicy | *(pending)* | `2-operator-helm-values.txt` |
| 3 | HAMi owns the device-plugin role | HAMi pods Running; `nvidia.com/gpu` allocatable at HAMi's **virtual** count; `hami.io/node-nvidia-register` present | *(pending)* | `3-hami-pods.txt`, `3-node-allocatable.txt` |
| 4 | nvidia is the **default** containerd runtime | `default_runtime_name = "nvidia"` in the generated containerd config | *(pending)* | `4-default-runtime.txt` |
| 5 | A fractional pod is placed and enforced | pod Running; scheduled by the **HAMi scheduler**; in-pod `nvidia-smi` shows the **slice**, not the full card | *(pending)* | `5-fractional-pod.txt`, `5-fractional-in-pod-smi.txt`, `5-fractional-hami-core.txt` |
| 6 | DCGM is unaffected by HAMi | DCGM Exporter still reports **physical** `DCGM_FI_*` counters alongside HAMi | *(pending)* | `6-dcgm-metrics.txt` |

### The two results that matter most

- **Artifact 3** is the coexistence proof. If `nvidia.com/gpu` shows HAMi's virtual count (one
  card reported as `deviceSplitCount`, default 10) rather than `1`, then HAMi's device plugin
  won the role and the Operator's is genuinely out of the way. A value of `1` means the
  Operator's plugin is still running and the setup is wrong.
- **Artifact 5** is the proof it is not merely cosmetic. A fractional pod Running is the
  scheduler half; the in-pod `nvidia-smi` showing the slice instead of the full card is the
  enforcement half, and it only happens if the default runtime is `nvidia` so HAMi-core was
  injected.

## The reboot behaviour

> ⚠️ Only reproducible where the **Operator owns the driver** (`driver.enabled=true`). On a VM
> whose driver comes from the image, the Operator does not reinstall it on boot, so this is
> expected **not** to reproduce. Record which case you tested, including "not applicable".

| Question | Result |
|---|---|
| Configuration tested (Operator-managed driver, or driver from image?) | *(pending)* |
| Did HAMi's device-plugin pod CrashLoopBackOff after a reboot? | *(pending)* |
| If yes, did it clear on its own once the driver daemonset was Ready? | *(pending)* |
| Time from boot to a working fractional pod | *(pending)* |
| Any readiness gate needed to make it deterministic | *(pending)* |

Upstream context: [HAMi #136](https://github.com/Project-HAMi/HAMi/issues/136),
[#157](https://github.com/Project-HAMi/HAMi/issues/157),
[#1708](https://github.com/Project-HAMi/HAMi/issues/1708).

## What this would prove (once filled)

A clean single-node coexistence: the Operator managing the base stack and telemetry, HAMi
managing fractional device allocation, one device plugin owning `nvidia.com/gpu`, and the
fractional slice still enforced by HAMi-core. That is the configuration most clusters actually
need, since the Operator is how the GPU stack normally gets installed.

## Scope limits

Single node. Proves the two components coexist and that fractional allocation still works and
is enforced; does **not** prove multi-node rollout, upgrade behaviour of either chart, MIG mode
(the cards here have none), or sharing performance under sustained load. The isolation
mechanism itself is proven separately in
[`hami-isolation-validation.md`](./hami-isolation-validation.md). Full ledger:
[`fake-vs-real-limitations.md`](./fake-vs-real-limitations.md).

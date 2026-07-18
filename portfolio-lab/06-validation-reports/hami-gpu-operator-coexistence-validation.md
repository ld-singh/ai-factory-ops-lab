# HAMi + NVIDIA GPU Operator Coexistence Validation - Lesson 6 Part C

> ✅ STATUS: **VALIDATED** - captured on a real NVIDIA L40 (48 GB), 2026-07-18. The NVIDIA GPU
> Operator (device plugin disabled) and HAMi ran on one k3s node without fighting over
> `nvidia.com/gpu`: the Operator owned the base stack and telemetry, HAMi owned the device
> plugin, and two pods shared the one card with the slice enforced by HAMi-core. Evidence:
> real command output from
> [`capture-evidence.sh`](../01-k8s-gpu-platform/hami/hami-gpu-operator-coexistence/scripts/capture-evidence.sh)
> (artifact files cited per row). Lab:
> [`hami-gpu-operator-coexistence/`](../01-k8s-gpu-platform/hami/hami-gpu-operator-coexistence/README.md).

The claim this report backs: **HAMi and the NVIDIA GPU Operator run on one node without fighting
over `nvidia.com/gpu`, with the Operator owning the base stack and HAMi owning the device
plugin.**

## Environment

| Item | Value |
|---|---|
| Date | 2026-07-18 |
| Machine | GPU VM (`keen-galileo`), Ubuntu 22.04.5 LTS, kernel 6.8.0-40-generic |
| GPU | **NVIDIA L40**, 48 GB (49140 MiB), UUID `GPU-d109b6c4-8e03-c41e-faa1-822812575879`; Ada Lovelace, **no MIG** - software sharing is the only option (the HAMi premise) |
| Driver | 535.183.06 (CUDA 12.4), from the VM image (**not** the Operator: `driver.enabled=false`) |
| Kubernetes | k3s **v1.36.2+k3s1**, containerd 2.3.2-k3s2, **`default-runtime: nvidia`** (k3s `--default-runtime` flag) |
| GPU Operator | **v26.3.3**, installed with `driver.enabled=false`, `toolkit.enabled=false`, **`devicePlugin.enabled=false`** (the base stack + DCGM/NFD/validator, minus the device plugin) |
| HAMi | **2.9.0**, kube-scheduler sidecar pointed at `registry.k8s.io` (chart default is an Aliyun mirror that times out outside China); deviceSplitCount 10 (default) |

> **The driver came from the VM image**, so the Operator ran with `driver.enabled=false` and
> `toolkit.enabled=false`. A production cluster where the Operator owns the driver is a
> **different configuration**, and the reboot behaviour below is the part that would differ.

## Validation checklist (6 artifacts)

| # | Claim | Pass criteria | Result | Evidence |
|---|---|---|---|---|
| 1 | Operator components run, its device plugin does not | Operator pods Running; **no** device-plugin pod in the namespace | ✅ GFD, NFD (master/worker/gc), operator, **DCGM Exporter**, operator-validator all **Running**; cuda-validator **Completed**; device-plugin grep returned **none** | `1-operator-pods.txt` |
| 2 | The device plugin is disabled deliberately | `devicePlugin.enabled=false` in the released helm values / ClusterPolicy | ✅ helm user-supplied values show `devicePlugin.enabled=false` (also `driver`/`toolkit` false); ClusterPolicy `devicePlugin.enabled=false` | `2-operator-helm-values.txt` |
| 3 | HAMi owns the device-plugin role | HAMi pods Running; `nvidia.com/gpu` allocatable at HAMi's **virtual** count; `hami.io/node-nvidia-register` present | ✅ `hami-device-plugin` 2/2 + `hami-scheduler` 2/2 **Running**; `nvidia.com/gpu = 10` (1 card × split 10); register annotation `devmem:49140, devcore:100, type:"NVIDIA L40", mode:"hami-core"` | `3-hami-pods.txt`, `3-node-allocatable.txt` |
| 4 | nvidia is the **default** containerd runtime | `default_runtime_name = "nvidia"` in the generated containerd config | ✅ `config.yaml: default-runtime: nvidia`, and generated `config.toml` has `default_runtime_name = "nvidia"` | `4-default-runtime.txt` |
| 5 | Two pods share one GPU, enforced | both pods Running on the **same** card; scheduled by the **HAMi scheduler**; each pod's in-pod `nvidia-smi` shows its **slice**, not the full card | ✅ `hami-coexist-a` + `-b` both **Running** on `keen-galileo`, both allocated **the same** `GPU-d109b6c4-…`; scheduled by **`hami-scheduler`** (`FilteringSucceed`, `BindingSucceed`); each in-pod `nvidia-smi` reports **`0MiB / 4000MiB`**, not the 49140 MiB card; HAMi-core injected: `CUDA_DEVICE_MEMORY_LIMIT_0=4000m`, `libvgpu.so` present | `5-share-pods.txt`, `5-in-pod-smi-hami-coexist-a.txt`, `-b.txt`, `5-hami-core.txt` |
| 6 | DCGM is unaffected by HAMi | DCGM Exporter still reports **physical** `DCGM_FI_*` counters alongside HAMi | ✅ DCGM reports the **physical** card for `GPU-d109b6c4-…`: `DCGM_FI_DEV_FB_FREE = 48439` MiB (the full ~48 GB), while the pods each see a 4000 MiB slice | `6-dcgm-metrics.txt` |

### The two results that matter most

- **Artifact 3 is the coexistence proof.** `nvidia.com/gpu` came back as **`10`**, HAMi's
  virtual count (one card × `deviceSplitCount` 10), not `1`. That means HAMi's device plugin
  won the role and the Operator's is genuinely out of the way. A value of `1` would have meant
  the Operator's plugin was still running and the setup was wrong.
- **Artifact 5 proves it is not merely cosmetic.** Two pods co-resident on one card is the
  sharing half (stock Kubernetes hands the whole device to the first pod); each pod's in-pod
  `nvidia-smi` reporting `0MiB / 4000MiB` instead of the 49140 MiB card is the enforcement
  half. Both pods carry the **same GPU UUID** in their allocation annotation, so they really
  are on one physical device, and `CUDA_DEVICE_MEMORY_LIMIT_0=4000m` shows HAMi-core enforcing
  the cap (it is injected because `nvidia` is the default runtime, Artifact 4).

> **Cross-check across artifacts:** the same UUID `GPU-d109b6c4-…` appears in the HAMi register
> annotation (Artifact 3), both pods' allocation annotations and in-pod views (Artifact 5), and
> DCGM's physical counters (Artifact 6). One physical L40, seen three ways: as ten schedulable
> HAMi slices, as two 4000 MiB in-pod caps, and as one ~48 GB card in DCGM. That is coexistence.

## The reboot behaviour

> ⚠️ Only reproducible where the **Operator owns the driver** (`driver.enabled=true`). On this
> VM the driver came from the image (`driver.enabled=false`), so the Operator does not reinstall
> it on boot.

| Question | Result |
|---|---|
| Configuration tested | Driver from the VM image (`driver.enabled=false`), not Operator-managed |
| Did HAMi's device-plugin pod CrashLoopBackOff after a reboot? | **Not applicable to this configuration** - reboot not exercised; the Operator does not reload the driver here, so the race cannot occur |
| Time from install to the share pods Running | Both pods `Running` within seconds of apply (`AGE 4s` in `5-share-pods.txt`) |

> **Still to validate:** the Operator-managed-driver case (`driver.enabled=true`), where the
> reboot race in [HAMi #136](https://github.com/Project-HAMi/HAMi/issues/136) /
> [#157](https://github.com/Project-HAMi/HAMi/issues/157) can occur. This run does not cover it.
> Upstream discussion: [#1708](https://github.com/Project-HAMi/HAMi/issues/1708).

## What this proves

A clean single-node coexistence: the Operator managing the base stack and telemetry (driver
off, but DCGM/GFD/NFD/validator all Running), HAMi managing fractional device allocation, one
device plugin (HAMi's) owning `nvidia.com/gpu`, two pods sharing the card, and the slice
enforced by HAMi-core. That is the configuration most clusters need, since the Operator is how
the GPU stack normally gets installed.

## Scope limits

Single node, driver from the VM image. Proves the two components coexist and that fractional
allocation still works and is enforced; does **not** prove the Operator-managed-driver reboot
case, multi-node rollout, upgrade behaviour of either chart, MIG mode (the L40 has none), or
sharing performance under sustained load. The isolation mechanism itself is proven separately in
[`hami-isolation-validation.md`](./hami-isolation-validation.md). Full ledger:
[`fake-vs-real-limitations.md`](./fake-vs-real-limitations.md).

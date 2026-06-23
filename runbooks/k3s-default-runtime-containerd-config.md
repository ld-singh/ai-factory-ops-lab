# Runbook - k3s Fails to Start After a containerd Config Change (and setting the nvidia default runtime)

**Severity:** High - k3s (the whole node's control plane + kubelet) is down, or GPU pods
run under `runc` and never see the GPU.
**Applies to:** k3s nodes where you need `nvidia` as the **default** containerd runtime
(e.g. for HAMi, whose pods don't set `runtimeClassName`).

## Symptom

One of:

- After writing `…/containerd/config.toml.tmpl` and restarting, k3s won't come up:
  ```
  systemctl status k3s   → Active: activating (auto-restart) (Result: protocol)
  Job for k3s.service failed because the service did not take the steps required…
  ```
- GPU pods schedule but the GPU isn't visible inside them (they ran under the default
  `runc`, not `nvidia`).

## Root cause

k3s **generates** its containerd config (`/var/lib/rancher/k3s/agent/etc/containerd/config.toml`)
on every start. Hand-editing that file doesn't stick, and a bad `config.toml.tmpl` produces
invalid TOML that crashes the embedded containerd. The two traps:

1. **Redeclaring an existing table.** `{{ template "base" . }}` already emits the CRI
   `containerd` table; appending another `[plugins.…containerd]` to set `default_runtime_name`
   is a **duplicate table** - invalid TOML - and k3s won't start.
2. **Wrong schema version.** Newer k3s ships **containerd config `version = 3`**, where the
   runtime table is `[plugins.'io.containerd.cri.v1.runtime']` and the template file must be
   `config-v3.toml.tmpl`. A v2-style snippet (`[plugins."io.containerd.grpc.v1.cri".containerd]`)
   in a v3 config is wrong.

## Resolution

### 1. Recover a crash-looping k3s

```bash
sudo rm -f /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl
sudo rm -f /var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.tmpl
sudo systemctl restart k3s && sleep 5 && systemctl is-active k3s   # → active
```
k3s regenerates a clean config from scratch, so you're back to a working node.

### 2. Set the default runtime the clean way (no TOML editing)

k3s has a first-class flag - use it via `/etc/rancher/k3s/config.yaml`:

```bash
k3s server --help | grep -i default-runtime          # confirm the flag exists
echo 'default-runtime: nvidia' | sudo tee -a /etc/rancher/k3s/config.yaml
sudo systemctl restart k3s && sleep 5 && systemctl is-active k3s
```

(The `nvidia` runtime must already be defined - it is when the NVIDIA Container Toolkit was
installed **before** k3s, which auto-creates it.)

### 3. Verify

```bash
sudo grep default_runtime_name /var/lib/rancher/k3s/agent/etc/containerd/config.toml
# expect: default_runtime_name = "nvidia"
```

> If your k3s build lacks `--default-runtime`, the supported fallback is a **template that
> matches your config schema** - `config-v3.toml.tmpl` for `version = 3` - and you set the
> key inside the existing runtime table rather than redeclaring it. See the
> [k3s advanced docs](https://docs.k3s.io/advanced#configuring-containerd).

## Prevention

- **Never hand-edit the generated `config.toml`** - k3s overwrites it on restart.
- Prefer the `--default-runtime` flag over a template; it's schema-agnostic.
- If you must template, first check the schema: `head -1 …/containerd/config.toml`
  (`version = 2` vs `3`) and use the matching `config*.toml.tmpl`; never redeclare an
  existing table.
- After any change, gate on `systemctl is-active k3s` **and** a GPU smoke pod before moving on.

## Drill in this lab

[Lesson 6 Part B - HAMi isolation](../portfolio-lab/01-k8s-gpu-platform/hami/hami-isolation-realgpu/README.md)
needs `nvidia` as the default runtime; [`set-default-runtime.sh`](../portfolio-lab/01-k8s-gpu-platform/hami/hami-isolation-realgpu/scripts/set-default-runtime.sh)
applies step 2 idempotently and verifies step 3.

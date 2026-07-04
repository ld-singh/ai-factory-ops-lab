# Lesson 7 - Security for GPU/AI Infrastructure

> Course home: [AI Factory Operations Lab](../../README.md) · Tracked as
> [issue #10](https://github.com/ld-singh/ai-factory-ops-lab/issues/10) on the
> [roadmap](https://github.com/users/ld-singh/projects/1)

> 🚧 **STATUS: PLANNED - coming in a future update.** This page is the outline. The
> simulation-first lesson is on the roadmap; the shape below is what it will cover.

Every other lesson gets a GPU platform *working*. This one asks the next question a real
operator has to answer: **is it safe to run more than one tenant on it?** GPU platforms are
expensive, so they get shared, and sharing is where the security work lives.

🧭 **Mode:** 🟦 Simulation-first (on the same fake GPU fleet as Lessons 1-3). The controls
here are control-plane controls, so most of it is provable without hardware.

## What it will cover

### 1. Multi-tenant isolation
- Namespace-per-tenant boundaries, and what a namespace does and does not isolate on a
  shared GPU node.
- The gap between *scheduling* isolation (Lesson 1) and *runtime* isolation (HAMi, Lesson 1C/6B),
  seen through a security lens: a memory cap is also a blast-radius control.

### 2. RBAC and quotas as security controls
- Least-privilege RBAC for who can request GPUs, edit workloads, and read telemetry.
- ResourceQuota / LimitRange on `nvidia.com/gpu` as a denial-of-service guardrail, not just
  a capacity one.

### 3. Network boundaries
- NetworkPolicy around inference endpoints (who can call the model server).
- Locking down the metrics surface: DCGM exporter and Prometheus expose fleet detail that
  shouldn't be world-readable.

### 4. Secrets and supply chain
- Handling model-registry and cloud credentials the workloads need.
- Model-artifact provenance: where the weights came from, and why "pull any HF model" is a
  supply-chain decision.

### 5. The break-it drill
- In the spirit of the observability lesson: misconfigure one control on purpose (an
  over-broad RBAC role, a missing NetworkPolicy) and show the exposure, then close it.

## What it will prove (and not)

Provable for free: the control-plane security posture - RBAC, quotas, network policy,
namespace boundaries, and the drills that verify them. It will **not** prove hardware-level
tenant isolation (side channels, firmware, confidential computing), which is out of scope for
this course's single-node, entry-GPU focus and is called out explicitly.

> 💡 **Want to help shape or build this?** Comment on
> [issue #10](https://github.com/ld-singh/ai-factory-ops-lab/issues/10).

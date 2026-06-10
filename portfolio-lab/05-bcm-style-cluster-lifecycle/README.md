# Lesson 6 — BCM-Style Cluster Lifecycle (Conceptual)

> Course home: [AI Factory Operations Lab](../../README.md) · Previous:
> [Lesson 5 — Inference Serving](../04-inference-serving/README.md) · Next:
> [★ Your lab notebook](../06-validation-reports/)

> 🚧 **STATUS: PLANNED (Phase 6).**
>
> **HONESTY MARKER:** unless an actual NVIDIA Base Command Manager evaluation install
> is performed and evidenced, this lesson is explicitly a *BCM-style conceptual lab*.
> It maps BCM concepts to equivalents the author has operated in production (image
> pipelines, node pools, lifecycle hooks). **No invented BCM commands.**

The final lesson zooms out from "schedule and observe workloads" to "operate the
cluster itself over its lifetime" — the layer a tool like NVIDIA Base Command Manager
(BCM) manages.

🎯 **Learning objectives** — this lesson teaches you to reason about, and map to
tools you know:

1. Head node / compute node architecture.
2. Software images and node categories.
3. Provisioning, health checks, and workload-manager integration.
4. Patching lifecycle and user/role management.

🧭 **Mode:** 🟨 Conceptual — documented as concepts and mapped to production
equivalents, not run. If a real BCM evaluation is ever performed, its evidence (and
only then) upgrades this from conceptual to validated.

💡 **Why conceptual is still useful:** the course's whole discipline is not
overclaiming. Rather than fake BCM output, this lesson connects BCM's lifecycle
model to image pipelines, node pools, and lifecycle hooks you *have* operated — which
is a transferable, defensible understanding without pretending to hands-on BCM
experience.

➡️ **Next:** [★ Your lab notebook](../06-validation-reports/) — close the loop by
making sure every lesson you ran has captured evidence.

# Lesson 6 - BCM-Style Cluster Lifecycle (Conceptual)

> Course home: [AI Factory Operations Lab](../../README.md) · Previous:
> [Lesson 5 - Inference Serving](../04-inference-serving/README.md) · Next:
> [★ Your lab notebook](../06-validation-reports/)

> 🟡 **STATUS: RUNNABLE DRILL (Phase 6), conceptual mapping.**
>
> **HONESTY MARKER:** this lesson does **not** use NVIDIA Base Command Manager and
> invents **no BCM commands**. Instead it ships a runnable drill that implements the
> *generic* node lifecycle BCM automates - provision → health-gate → in-service →
> patch → retire - as real Kubernetes state transitions on the KWOK fake fleet, then
> maps each stage back to its BCM concept. If a real BCM evaluation is ever performed,
> its evidence (and only then) upgrades the BCM-specific claims from conceptual to
> validated. BCM reference: https://docs.nvidia.com/base-command-manager/

The final lesson zooms out from "schedule and observe workloads" to "operate the
cluster itself over its lifetime" - the layer a tool like NVIDIA Base Command Manager
(BCM) manages. Everything in Lessons 1–5 assumed nodes exist, run an OS, have
drivers, and joined a scheduler. This lesson is about the machinery that makes that
true for hundreds of nodes at once, repeatably.

🎯 **Learning objectives** - this lesson teaches you to reason about, and map to
tools you know:

1. Head node / compute node architecture, and why the head node is the cluster's
   single source of truth.
2. Software images and node categories - image-based fleet management vs per-node
   configuration drift.
3. Provisioning, health checks, and workload-manager integration.
4. Patching lifecycle and user/role management.

🧭 **Mode:** 🟨 Conceptual - documented as concepts and mapped to production
equivalents, not run. If a real BCM evaluation is ever performed, its evidence (and
only then) upgrades this from conceptual to validated.

---

## The concept map (the lesson's core artifact)

Each BCM-domain concept, mapped to the generic mechanism it implements and to where
this course (or common production practice) already touches it:

| Lifecycle concern | The generic mechanism | Where you've seen the idea |
|---|---|---|
| Head node | A management plane holding cluster state and serving provisioning | The kind control-plane node in Lesson 1; `slurmctld` in Lesson 3 |
| Software image | A golden OS image nodes boot from; change the image, not the node | Cloud machine images / immutable infrastructure |
| Node category | A group of nodes sharing one image + config (e.g. "gpu-compute") | Lesson 1's node pools (`gpu-pool=a100`) - same idea, lower in the stack |
| Provisioning | Network boot → image → node-specific finalization | Cloud-init / PXE pipelines |
| Health checks | Scripted checks gating whether a node accepts work | K8s readiness + the drain drills of Lessons 1/3 |
| WLM integration | The lifecycle layer installs/configures Slurm or K8s on nodes | Lesson 3's config files - here, generated rather than handwritten |
| Patching lifecycle | Update the image, roll node-by-node, drain → reimage → resume | Rolling updates; cordon/drain (Lesson 1), `scontrol drain` (Lesson 3) |
| Users & roles | Central identity + per-team access to partitions/queues | Lesson 1B's queues and quotas, one layer down |

💡 **The transferable insight:** cluster managers are *fleet-level immutability
engines*. The unit of change is the image plus its category, never the individual
node - the same shift containers made for applications, applied to the OS/driver
layer. If you can defend that sentence and walk this table, you understand what BCM
is *for* without pretending hands-on experience.

## Why conceptual is still useful

The course's whole discipline is not overclaiming. Rather than fake BCM output,
this lesson connects BCM's lifecycle model to image pipelines, node pools, and
lifecycle hooks you *have* operated - which is a transferable, defensible
understanding without pretending to hands-on BCM experience. In an interview, "I've
mapped BCM's concepts onto systems I've run, and here's the mapping" is a stronger
position than recited command names.

## The drill (run this)

Needs the Phase 1 kind cluster up (`make phase1-up`). No GPU. It steps through the
full lifecycle interactively (press enter between stages):

```bash
make phase6-drill
```

It will:

1. **Provision** a new KWOK node at `image-version=v1`, `lifecycle=provisioning`,
   health-gated with a `NoSchedule` taint so nothing lands prematurely.
2. **Health-gate** it: run a scripted check (does it advertise GPUs?), and on pass
   flip `lifecycle=in-service` and remove the gate taint.
3. **In-service:** a workload pod (selector `lifecycle=in-service`) schedules onto it.
4. **Patch:** cordon + drain, recreate the node at `image-version=v2`, re-gate,
   re-check, reopen - the workload is evicted then reschedules (a rolling reimage).
5. **Retire:** drain and delete the node from the cluster.

✅ **Checkpoint:** you watch a node move provisioning → in-service → (v1→v2) → retired
as real `kubectl` state, with a workload correctly evicted and rescheduled across the
patch. Each stage maps to a BCM concept in the table above.

💡 **Why this is honest:** it never claims to be BCM. It demonstrates the *mechanism*
BCM automates (image-based, health-gated, drain-before-reimage lifecycle) using tools
you can actually run, which is a defensible "I understand what BCM does" - stronger
than reciting commands you've never executed.

See also: [bcm-style-cluster-lifecycle.md](../../diagrams/bcm-style-cluster-lifecycle.md).

➡️ **Next:** [★ Your lab notebook](../06-validation-reports/) - close the loop by
making sure every lesson you ran has captured evidence.

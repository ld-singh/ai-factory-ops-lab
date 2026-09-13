# Learner Experience & Polish Plan (BACKUP - do not merge)

> This file is a **backup of a planning spec**, kept on the dedicated branch
> `notes/learner-experience-plan` only. It must never be merged into `main` or added to any
> lesson/feature branch. It is here purely so the spec is recoverable if the local copy is lost.
> The tracked execution source remains the GitHub Project board. Not yet executed.
>
> Owner: Lovedeep Singh. Recorded verbatim below.

---

## The improvement task (as provided)

You are working in the repository:

`ld-singh/ai-factory-ops-lab`

The live site is:

`https://ld-singh.github.io/ai-factory-ops-lab/`

Your task is to improve this project from a strong engineering repository into a polished, attractive, easy-to-follow hands-on learning experience for GPU / AI infrastructure engineers.

Do not turn it into a generic marketing website. Preserve its technical credibility, engineering depth, evidence-driven approach, and strict simulation-vs-real-GPU boundary.

Before modifying anything, read:

`CLAUDE.md`
`README.md`
`ROADMAP.md`
`mkdocs.yml`
`docs/index.md`
`docs/stylesheets/extra.css`
`Makefile`
`portfolio-lab/real-gpu-session/README.md`
`portfolio-lab/06-validation-reports/README.md`
`portfolio-lab/06-validation-reports/fake-vs-real-limitations.md`

Also inspect the lesson READMEs, diagrams, runbooks, scripts, and existing MkDocs overrides where relevant.

Important project rules:

Never touch, stage, inspect, expose, or commit anything under `private/`.

Do not weaken the simulation-vs-real-GPU distinction.

Never imply that fake GPUs prove CUDA execution, GPU memory enforcement, MIG, NCCL, NVLink, GPUDirect RDMA, InfiniBand behaviour, or other hardware behaviour.

Do not invent benchmark results, validation results, commands, tool support, flags, screenshots, completion claims, or hardware tests.

A feature or lesson must not be described as validated unless captured evidence already exists.

Do not remove existing technical depth merely to make pages shorter.

Do not perform a wholesale redesign of the repository.

Prefer incremental, maintainable changes using the existing MkDocs Material stack.

Do not add heavy JavaScript frameworks or unnecessary dependencies.

Do not stage or commit changes unless explicitly requested.

Do not use em dashes in user-facing prose.

The central product proposition should become clearer:

**Learn GPU infrastructure without owning a GPU.**

The learning philosophy should become a visible recurring concept:

**Build -> Break -> Diagnose -> Prove**

The site should make it immediately clear that most of the course runs for free on a laptop and that the real-GPU portion is an optional capstone used to validate what simulation cannot prove.

Implement the following in priority order:

1. Audit and fix consistency before redesigning anything.
   Compare the homepage, README, MkDocs navigation, ROADMAP, Lesson 6 overview, validation notebook, and individual lessons.
   Fix inconsistent lesson numbering and status.
   The current homepage lesson cards do not match the current learning path. The canonical sequence should be derived from the actual current course content, not guessed.
   Lesson 6 Part D, real inference benchmarking, is already shown as validated in the capstone and validation notebook. ROADMAP.md currently appears to understate this. Reconcile it.
   Part E, real Slurm GRES, must remain planned unless evidence proves otherwise.
   Establish one canonical lesson numbering and naming scheme and use it across: README.md, docs/index.md, mkdocs.yml, ROADMAP.md, lesson navigation text where necessary.

2. Improve the homepage hero.
   The first screen should answer four questions within seconds: What is this? Why is it different? What does it cost? How do I start?
   Position it around: `Learn GPU Infrastructure Without Owning a GPU`
   Supporting copy: `Build, break, troubleshoot and operate production-style AI infrastructure on your laptop. Then validate the hardware-specific parts on one real GPU.`
   Make `$0 to start`, `No GPU required`, and the optional real-GPU capstone visually obvious.
   Keep the AI Factory Operations Lab name. Add a subtitle such as: `Hands-on GPU Infrastructure Engineering`.
   Two strong CTAs: `Start Learning`, `View Learning Path`. The first CTA should not dump a new learner directly into an advanced lesson without orientation.

3. Create a proper Start Here experience.
   Improve the existing overview/setup page or create a dedicated Start Here page.
   It should explain: prerequisites, who the course is for, simulation vs real mode, expected total effort, how evidence works, the recommended lesson sequence, what the learner should run first.
   Make this the main destination of the homepage Start Learning button.
   A learner with Kubernetes basics but no previous GPU infrastructure experience should know exactly what to do next.

4. Make the course feel like a learning product rather than repository documentation.
   Add consistent metadata to lesson cards and, where practical, lesson introductions: estimated time, difficulty, mode, GPU requirement, outcome.
   Example: `35 min | Intermediate | Simulation | No GPU` followed by `Diagnose why a GPU workload remains Pending.`
   Do not fabricate timings with false precision. Use reasonable ranges and mark them as estimates where necessary.

5. Make Build -> Break -> Diagnose -> Prove a visible teaching methodology.
   Introduce this concept near the top of the site.
   Where existing lessons already contain break/fix/evidence workflows, make the structure easier to recognise without unnecessarily rewriting technically correct content.
   Build: stand up the system or capability. Break: introduce a realistic failure/capacity/queue/operational problem. Diagnose: use the same signals and tools an operator would use in production. Prove: capture evidence.
   Preserve existing terminology where it is already clearer.

6. Add learner tracks.
   A simple section allowing learners to choose a route through the existing material.
   Include at least: `Kubernetes / Platform Engineer`, `HPC / Slurm Engineer`, `AI Infrastructure Engineer`.
   Do not duplicate lesson content. These are curated routes through the same lessons. Make the full AI Infrastructure path the most comprehensive track.

7. Add an architecture learning map.
   Use Mermaid if practical (already supported). Show how the course technologies relate: workloads/inference, Kubernetes or Slurm, queueing and scheduling, KAI/Volcano, GPU sharing and allocation, HAMi, GPU runtime, NVIDIA GPU Operator/device plugin, observability, DCGM/Prometheus/Grafana, inference serving, vLLM, physical GPU.
   Map lessons onto the relevant layers. Keep it technically defensible; avoid suggesting tools are interchangeable where they are not.

8. Turn Lesson 6 into a visibly branded capstone.
   Keep its technical structure and source-of-truth pages. Present it as: `AI Factory Operator Capstone`.
   The scenario should feel like a realistic platform engineering assignment: a team has received GPU capacity and must make it usable, observable, shareable where appropriate, benchmarked, and operationally defensible.
   Show the existing Parts A to E and their current validation status. Do not mark Part E complete.
   Emphasise that the output is evidence the learner can retain in their lab notebook or portfolio.

9. Improve learner-friendly Make targets without breaking existing automation.
   Current internal-looking targets: `phase1-up`, `phase1-demo`, `phase3-up`, `phase4-break`. Do not remove or rename these.
   Investigate friendly aliases where useful, e.g. `lesson1-start`, `lesson1-demo`, `lesson1-check`, `lesson1-clean`. Only where they map cleanly to existing verified commands. Do not invent functionality. Keep existing targets working. Improve `make help` grouping/descriptions if clean.

10. Introduce automated lesson verification where evidence already makes this feasible.
    Investigate `make lesson1-check`. A check should validate observable state, not simply print success.
    Example output: `[PASS] cluster reachable`, `[PASS] fake GPU nodes discovered`, `[PASS] GPU resource advertised`, `[PASS] workload scheduled`.
    Do not attempt automated grading for things that cannot be verified reliably. Start with one lesson as the reference implementation. Design it so the pattern can be reused.

11. Improve evidence as a learner feature.
    Make the validation-report model more visible. Explain that course completion is based on evidence, not merely running commands.
    Consider a reusable `Lab Evidence` template learners can copy: lesson, environment, what was built, failure introduced, diagnosis, fix, evidence, what this proves, what this does not prove.
    Do not create fake certificates. The goal is a technically credible portfolio artifact.

12. Improve visual proof of the labs.
    ROADMAP issue #16 proposes an asciinema/GIF demo. Treat as an important learner-experience task.
    Add a location and integration point in the README/homepage for a short demo showing a lab running.
    If no real recording asset exists locally, do not fabricate one. Prepare the markup/documentation/script/workflow needed to add the recording later, and clearly identify the missing asset.
    Ideal demo: a fake GPU fleet appearing, an intentionally Pending workload, diagnosis, workload scheduling, or an inference concurrency sweep.

13. Improve the homepage lesson cards.
    Cards should prioritise learner outcomes rather than tool names alone. Tool names still visible for discoverability.
    Instead of only `Queue scheduling (KAI)`, prefer: `Control GPU access between teams` / `KAI Scheduler - Queue quotas - Gang scheduling`. Keep titles concise. Add visual distinction for simulation, concept/drill, real GPU.

14. Improve search/discoverability without SEO spam.
    Review: MkDocs site_name, site_description, page titles, homepage heading hierarchy, README introduction, repository description alignment, social preview wording.
    Search concepts should naturally include: GPU infrastructure, AI infrastructure, Kubernetes GPU scheduling, NVIDIA GPU Operator, GPU sharing, HAMi, KAI Scheduler, Slurm, DCGM, GPU observability, vLLM, inference serving. Keep writing natural.

15. Update the social preview positioning.
    Keep the existing visual identity unless compelling reason. Update messaging so the dominant idea is closer to: `Learn GPU Infrastructure Operations`, `No GPU Required to Start`. Supporting labels: Kubernetes, HAMi, Slurm, DCGM, vLLM. Avoid wording that suggests simulation is real hardware.

16. Update the roadmap itself.
    Keep existing planned work: Security, Cost/autoscaling, multi-node concepts, MIG vs HAMi, real Slurm GRES, CI, terminal demo.
    Add a new top-level roadmap theme: `Learner Experience & Adoption`. Capture the major improvements from this task.
    Reorder priority so learner-experience work occurs before continuously adding more technical breadth. Do not delete existing GitHub issue references. ROADMAP.md stays human-readable; GitHub Project board is the tracked execution source.

17. Preserve and strengthen credibility.
    Keep distinguishing: simulated control-plane behaviour, real runtime behaviour, hardware-specific behaviour, scale/topology behaviour. Never sacrifice precision for cleaner copy.
    Prefer `simulate GPU scheduling` over `run GPUs locally` where no GPU exists. Prefer `validate hardware-specific behaviour on one real GPU` over implying one GPU proves distributed AI/HPC behaviour.

18. Validate the implementation.
    Run applicable static checks locally: `make docs-build`, verify MkDocs navigation, check broken internal links with existing tooling, check `make help`, inspect `git diff`, confirm `git status` does not expose anything from `private/`. Do not claim lab runtime validation unless those labs were actually run.

Implementation approach: inspect first, produce a concise plan from the actual current structure, then implement the P0 learner-experience changes. Prefer a coherent high-quality first pass over touching every file superficially. If a feature needs assets that do not exist (e.g. a real terminal recording), build the surrounding support and leave the asset as a documented follow-up. Do not ask to approve every individual file change; use engineering judgement, preserve existing behaviour, continue until the coherent first pass is complete.

At the end provide: changed files and why; inconsistencies found and how resolved; anything intentionally deferred; validation commands run and results; recommended next three improvements.

---

## Notes captured at save time (current repo state, for the eventual execution)

- Canonical numbering as of save: 1, 1B, 1C (Overview + scheduling sim), 1D (Volcano), 2, 3,
  3B (inference observability, PR pending), 4 group -> 4A (Inference benchmarks) + 4B (KV cache),
  5, 6 capstone (Part A runtime, B HAMi isolation, C HAMi+GPU-Operator coexistence, D inference
  benchmark, E Slurm GRES planned, F teardown), 7 Security (planned).
- Validated on real hardware: Part A, B (A6000), C (L40), D (A6000). Part E (Slurm GRES) is
  PLANNED, no evidence. ROADMAP "Shipped and validated" line says only "A, B and C" -> understates
  Part D; reconcile to A/B/C/D validated, E planned.
- Homepage cards and ROADMAP lag the current content (missing 1D, 3B, 4A/4B split) -> item 1.

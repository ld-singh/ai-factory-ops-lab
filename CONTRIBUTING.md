# Contributing

Thanks for your interest in improving **AI Factory Operations Lab**. This is a
learn-by-doing course, and contributions that make the labs clearer, more correct, or
more complete are very welcome.

## Ways to help

- **Try a lab and report friction.** If a step is unclear or an expected output is wrong,
  open an issue. That feedback is gold.
- **Pick up a roadmap item.** See the [roadmap board](https://github.com/users/ld-singh/projects/1)
  and the [issues](https://github.com/ld-singh/ai-factory-ops-lab/issues), especially those
  tagged `good first issue` and `help wanted`.
- **Add or extend a lesson.** Lessons tagged `lesson` on the roadmap are open for authoring.

## Running the labs locally

Most of the course needs **no GPU**:

```bash
make check          # verify docker, kind, kubectl, helm, kwok, jq
make phase1-up      # a fake GPU fleet on kind + KWOK
make phase1-demo    # schedulable + intentionally-Pending GPU workloads
make phase1-down    # tear it down
```

Serve the docs site while editing:

```bash
pip install -r requirements-docs.txt
make docs-serve     # http://localhost:8001
```

## House rules (what keeps this course trustworthy)

These are the principles the whole project is built on. Please keep to them:

1. **Simulation vs real GPU is always explicit.** Never let a README or report imply that a
   fake-GPU simulation proves real hardware behaviour (CUDA, NCCL, NVLink, MIG, GPUDirect
   RDMA, or real GPU memory). Each lesson states its **mode** and what it does and does not
   prove. See [`fake-vs-real-limitations.md`](./portfolio-lab/06-validation-reports/fake-vs-real-limitations.md).
2. **A module is only "Complete" when its validation report holds real captured output.**
   Claims are backed by evidence, not prose.
3. **No invented commands or flags.** For NVIDIA / KAI / BCM / Slurm specifics, defer to the
   official docs and link them.
4. **Teach the concept, keep it readable.** Every command pairs with the *why*, and steps
   have an expected output and a checkpoint.

## Pull request flow

1. Fork and branch (`feat/...`, `docs/...`, or `lesson/...`).
2. Make your change. If you touched docs, confirm the site builds:
   ```bash
   ./scripts/sync-docs.sh && mkdocs build
   ```
3. Keep the existing style: short paragraphs, expected outputs, and the per-lesson rhythm.
4. Open the PR with a clear description of what it changes and why.

## Reporting issues

Use the [issue tracker](https://github.com/ld-singh/ai-factory-ops-lab/issues). For a lab
problem, include the lesson, the command you ran, and the output you got versus what you
expected.

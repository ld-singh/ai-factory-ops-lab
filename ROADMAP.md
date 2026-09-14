# Roadmap

The live, tracked roadmap is the GitHub project board:
**[AI Factory Ops Lab - Roadmap](https://github.com/users/ld-singh/projects/1)**.
This file is the human-readable overview; the board is where work is tracked.

## Where the course stands

The bar for "validated" is a report with real captured output in the
[lab notebook](./portfolio-lab/06-validation-reports/README.md) (house rule 2). Lessons are
grouped by that bar, not by whether they run.

**Validated with captured evidence:**

- Simulation (no GPU): Lesson 1 Kubernetes GPU scheduling (local simulation report), 1D Volcano
  gang scheduling at fleet scale (GPU scale-sim report), and 2 Slurm with fake GRES (Slurm GRES
  report).
- Lesson 6 real-GPU capstone: Parts A, B, C and D validated on real hardware (runtime path +
  real DCGM, HAMi sharing/isolation, HAMi with the GPU Operator, and the inference benchmark).
  Part E (Slurm real GRES) is planned.

**Shipped and runnable, evidence report still to capture:**

- 1B KAI queueing, 1C HAMi fractional scheduling (sim), 3 DCGM observability, 3B inference
  observability, 4A inference benchmarks (the $0 CPU tier), 4B the KV cache (calculator tier),
  and 5 the BCM-style lifecycle drill. Each runs end to end today; none is marked Complete until
  its captured-output report lands in the notebook.

## Planned

Tracked as issues on the board. Themes:

| Theme | Item | Issue |
|---|---|---|
| Learner experience | Learner Experience & Adoption: homepage, Start Here, tracks, methodology, cards, demo (first pass shipped; prioritised ahead of new technical breadth) | [#52](https://github.com/ld-singh/ai-factory-ops-lab/issues/52) |
| Security | Lesson 7: Security for GPU/AI infrastructure | [#10](https://github.com/ld-singh/ai-factory-ops-lab/issues/10) |
| Cost | Lesson 8: Cost & autoscaling for GPU platforms | [#11](https://github.com/ld-singh/ai-factory-ops-lab/issues/11) |
| Scale | Concepts: the multi-node boundary (NCCL, NVLink, GPUDirect RDMA, InfiniBand) | [#12](https://github.com/ld-singh/ai-factory-ops-lab/issues/12) |
| Real GPU | Lesson 6 Part E: Slurm real GRES enforcement on hardware | [#13](https://github.com/ld-singh/ai-factory-ops-lab/issues/13) |
| Concepts | MIG (hardware partitioning) vs HAMi (software sharing) | [#14](https://github.com/ld-singh/ai-factory-ops-lab/issues/14) |
| Project | CI: mkdocs build + markdown lint on PRs | [#15](https://github.com/ld-singh/ai-factory-ops-lab/issues/15) |
| Docs | asciinema / GIF of a lab running in the README | [#16](https://github.com/ld-singh/ai-factory-ops-lab/issues/16) |

## Contributing

Items tagged `help wanted` and `good first issue` are the best places to start. See
[CONTRIBUTING.md](./CONTRIBUTING.md).

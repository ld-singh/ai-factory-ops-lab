# Roadmap

The live, tracked roadmap is the GitHub project board:
**[AI Factory Ops Lab - Roadmap](https://github.com/users/ld-singh/projects/1)**.
This file is the human-readable overview; the board is where work is tracked.

## Where the course stands

**Shipped and validated:**

- Lessons 1-5 (simulation): Kubernetes GPU scheduling, KAI queueing, HAMi fractional
  scheduling, Slurm (fake GRES), observability, inference harness, BCM-style lifecycle.
- Lesson 6 real-GPU capstone, Parts A, B and C validated on real hardware (runtime path +
  DCGM, HAMi sharing, inference benchmark).

## Planned

Tracked as issues on the board. Themes:

| Theme | Item | Issue |
|---|---|---|
| Security | Lesson 7: Security for GPU/AI infrastructure | [#10](https://github.com/ld-singh/ai-factory-ops-lab/issues/10) |
| Cost | Lesson 8: Cost & autoscaling for GPU platforms | [#11](https://github.com/ld-singh/ai-factory-ops-lab/issues/11) |
| Scale | Concepts: the multi-node boundary (NCCL, NVLink, GPUDirect RDMA, InfiniBand) | [#12](https://github.com/ld-singh/ai-factory-ops-lab/issues/12) |
| Real GPU | Lesson 6 Part D: Slurm real GRES enforcement on hardware | [#13](https://github.com/ld-singh/ai-factory-ops-lab/issues/13) |
| Concepts | MIG (hardware partitioning) vs HAMi (software sharing) | [#14](https://github.com/ld-singh/ai-factory-ops-lab/issues/14) |
| Project | CI: mkdocs build + markdown lint on PRs | [#15](https://github.com/ld-singh/ai-factory-ops-lab/issues/15) |
| Docs | asciinema / GIF of a lab running in the README | [#16](https://github.com/ld-singh/ai-factory-ops-lab/issues/16) |

## Contributing

Items tagged `help wanted` and `good first issue` are the best places to start. See
[CONTRIBUTING.md](./CONTRIBUTING.md).

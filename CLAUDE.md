# Project rules for Claude Code

- NEVER stage, commit, or read aloud anything under private/ — it is the personal
  career toolkit and is gitignored. Verify `git status` excludes it before any commit.
- Maintain the simulation vs real-GPU honesty boundary. Do not let any README or
  report imply fake-GPU simulation proves CUDA, NCCL, NVLink, MIG, GPUDirect RDMA,
  or real GPU memory behaviour. See portfolio-lab/06-validation-reports/fake-vs-real-limitations.md.
- A module is only "Complete" when its validation report contains real captured output.
- No invented commands or flags. For NVIDIA/KAI/BCM specifics, defer to official docs.

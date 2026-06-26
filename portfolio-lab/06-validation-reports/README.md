# ★ Your Lab Notebook - Validation Reports

> Course home: [AI Factory Operations Lab](../../README.md)

This directory is where claims become concrete. **A lesson is only "Complete" when
its report here holds real, captured output.** No evidence directory, no completion -
that rule is what separates "I read about it" from "I ran it and watched it happen."

## How to use it

Each time you finish a runnable lesson:

1. Run the lesson's `make ...-evidence` (or `collect-*-evidence.sh`) step. Snapshots
   land in [`evidence/`](./evidence/) as timestamped directories.
2. Open the matching report below and fill in your environment details plus a
   reference to that evidence directory.
3. Only then mark the lesson done.

## The reports

| Report | Lesson | Mode | Fill in after… |
|---|---|---|---|
| [local-simulation-report.md](./local-simulation-report.md) | [1 - K8s GPU scheduling](../01-k8s-gpu-platform/README.md) | 🟦 Sim | `make phase1-up/-demo/-evidence` |
| [slurm-gres-validation.md](./slurm-gres-validation.md) | [2 - Slurm](../02-slurm-gpu-platform/README.md) | 🟦 Sim (+ real GRES in Lesson 6) | *Phase 3* |
| [real-gpu-validation-report.md](./real-gpu-validation-report.md) | [6 - Real GPU](../real-gpu-session/README.md) (Part A) | 🟥 Real | The Lesson 6 hardware run ✅ |
| [hami-isolation-validation.md](./hami-isolation-validation.md) | [6 - Real GPU](../real-gpu-session/README.md) (Part B - HAMi) | 🟥 Real | The Lesson 6 Part B run ✅ |
| [inference-benchmark-report.md](./inference-benchmark-report.md) | [6 - Real GPU](../real-gpu-session/README.md) (Part C - inference) | 🟥 Real | 🟡 Runnable — serve vLLM, run the drills, capture the numbers |

## The limitations ledger - read this to grade your own claims

[**fake-vs-real-limitations.md**](./fake-vs-real-limitations.md) is the single source
of truth for what each lab *mode* can and cannot prove. Before you write any claim in
a report, check it against that ledger.

➡️ **Back to:** [the Learning Path](../../README.md#the-learning-path).

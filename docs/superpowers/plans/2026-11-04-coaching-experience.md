# Coaching Experience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the benchmark detect observed tutoring weaknesses, then improve the local coach against that frozen evaluation.

**Architecture:** Reuse native snapshots, deterministic request generation, the existing qualified judge, candidate runner, budget meter, and grade checkpoints. Add a small independently versioned experience suite and bounded comparison entry point; keep historical evidence immutable.

**Tech Stack:** Swift/XCTest, Python unittest, existing OpenAI Responses client.

**Spec:** `docs/superpowers/specs/2026-11-04-coaching-experience-design.md`

## Global Constraints

- Existing isolated PR #23; no main changes, merge, auto-merge, or destructive cleanup.
- $10 conservative combined API cap; no paid CI, silent retries, holdout exposure, or case-specific advice in prompts.
- Freeze grader briefs and controls before candidate iteration; three repetitions, all results retained.
- Exact model configuration must reach the local development launcher if selected.

## Review Focus

- Sensitivity controls must bind to the correct board and interaction, not just a case name.
- Negative examples must fail for the intended dimension, while good direct staged feedback and requested Hint pass.
- Case briefs and expected responses must never reach candidate prompts.
- Slow/failed calls must remain visible; fresh versus conversation follow-up measurements must not be conflated.
- Selection must reflect unseen transfer cases, not only tuned development probes.

### Task 1: Freeze a sensitive experience suite

**Files:** Add `ChessTutorTests/Coaching/ModelEvaluation/CoachingExperienceBenchmarkTests.swift`; update `project.yml` and generated Xcode project; add `Tools/CoachingEval/benchmark/judge-experience-v1.json`.

**Interfaces:** Produces the existing eight-case regression export using `COACHING_EXPERIENCE_BENCHMARK_OUTPUT_DIR`; controls consumed by `JudgeSensitivity.run`.

- [ ] Add native tests for deterministic export, source-snapshot equivalence, no brief leakage, and independently checked knight/bishop/mate facts.
- [ ] Implement eight cases with explicit score ceilings for ignored answers, premature exact moves, and vague goals; preserve existing corpora.
- [ ] Build/export, validate all controls through the real response contract, run existing Python/native tests. Expected: zero failures/skips.
- [ ] Commit the frozen evaluation before changing the tutor.

### Task 2: Bounded comparison and experience metrics

**Files:** Add `Tools/CoachingEval/benchmark/experience.py`, `Tools/CoachingEval/tests/test_experience_evaluation.py`; update evaluator README.

**Interfaces:** Consumes exported corpus, pinned candidate paths and sensitivity controls; reuses `BudgetedClient`, `JudgeQualification`, `run_candidates`, `grade_run`, `write_report`. Produces immutable manifest, candidate/grade artifacts, quality summary, timing and repetitive-ending metrics.

- [ ] Write failing tests for rejected controls preventing generation, shared spending cap, immutable output, latency separation, failure visibility, and confirmation-ending counting.
- [ ] Implement the smallest CLI/workflow satisfying the tests; no alternate HTTP or grading implementation.
- [ ] Run full evaluator/server suites. Expected: zero failures/skips. Commit.

### Task 3: Measure, improve, verify, and deliver

**Files:** Add a versioned tutor prompt and pinned model/candidate configs; update `scripts/run_hosted_coaching_dev.sh` only if evidence supports selection; add `docs/reports/2026-11-04-coaching-experience.md`.

**Interfaces:** Uses frozen Task 1 criteria and Task 2 workflow, unchanged current coach as baseline, shared $10 budget journal for all paid work.

- [ ] Run positive/negative sensitivity controls and baseline; inspect actual failures before editing prompt.
- [ ] Revise general tutoring instructions, run three repetitions, keep all intermediate results. Expected: improved strong rate and no severe errors; otherwise iterate within budget or report honestly.
- [ ] Verify finalist on unchanged playthrough/later-game suites and original development sequences; retain initial/follow-up latency and cost separately. Do not claim independent holdout success.
- [ ] Run native/evaluator/server tests; independent review of code and outputs; address important findings with tests.
- [ ] Record results, exact reproduction commands, shortcomings, cost and selected configuration. Update PR #23, leave open.

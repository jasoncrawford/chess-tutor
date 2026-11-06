# Repeatable Coaching Regressions Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline, then one fresh final reviewer.

**Goal:** Make recent coaching improvements measurable by repeatable, automatically graded evaluations.

**Architecture:** Mechanically export a separate eight-position regression corpus; reuse candidate generation, grading, and reports. A bounded workflow verifies judge sensitivity before evaluating the exact local app candidate.

**Tech Stack:** Swift/XCTest, Python unittest, existing hosted Responses client, Bash.

**Spec:** `docs/superpowers/specs/2026-11-04-repeatable-coaching-regressions-design.md`

## Global Constraints

- Preserve frozen v1 corpus, previous prompts, and broad judge qualification.
- Eight regression positions, all development; three repetitions; no promotion claim.
- Candidate must match the local launcher; no model/prompt changes this task.
- $10 conservative ceiling; keep all attempts and cost reservations. Holdout excluded for this execution.
- Continue isolated PR #23; no A16 changes, merge, deployment, or automatic paid CI.

## Review Focus

- A changed prompt/compiler must affect real model input and provenance, not merely a label.
- An incomplete or tuned regression matrix must never be promoted as held-out success.
- A judge that praises a retained bad answer must stop the workflow; positive controls detect blanket rejection.
- Budget/HTTP/interruption failures preserve evidence and never silently become free calls or passing cells.
- Exported facts stay out of candidate prompts; the new request builder uses real legal move history.

### Task 1: Versioned regression corpus and current candidate

**Files:** new `ChessTutorTests/Coaching/ModelEvaluation/CoachingPlaythroughBenchmarkTests.swift`; existing `CoachingQualityBenchmarkCorpus.swift`; `Tools/CoachingEval/benchmark/corpus.py`; configuration and launcher tests; new `configs/astra-discovery-v2-low.json`.

**Interfaces:** `CoachingQualityBenchmarkExporter.artifacts/write(..., corpus: ..., regression: Bool)` defaults preserve v1. Regression manifest schema `coaching-quality-playthrough-regression-manifest.v1`, eight independent development turns. `BenchmarkCorpus.is_regression` is true only for that validated schema.

- [x] Add failing corpus-loader and native tests: exact eight cases, deterministic export, no grader leakage, one-way defense, defended e5, Bxf7 king recapture, Bxe6 pawn recapture, actual wrong-piece/changed-move context.
- [x] Implement fixtures and exporter using existing production rules/builder; retain old export bytes and inventory. Add pinned current candidate; integration-test dev launch selection against its loaded model config.
- [x] Run focused Python/native tests, export both corpora, commit.

### Task 2: Repeated regression evidence through existing runner/report

**Files:** runner.py, report.py, cli.py, corresponding tests; new `judge-sensitivity-v1.json` and `regression.py`.

**Interfaces:** `run_candidates(mode="regression")` performs three repetitions, permits one candidate, never eligible for promotion. Regression corpus only runs in regression mode. Public grader payload helper used by both grading and sensitivity checks. Workflow invokes existing `grade_run` checkpoints and `write_report`.

- [x] Add failing tests for single-candidate three-repetition runs, original v1 guards, complete/incomplete regression reporting, and sensitivity rejection/positive controls using actual production payload construction.
- [x] Add strict retained-answer cases and sensitivity evaluation; no expectations or reference labels enter judge prompts. Preserve negative outputs and require all three repetitions to satisfy bounded dimension expectations.
- [x] Add budget wrapper tests (pre-call refusal, failed-call reservation, cumulative context, no secrets) and implement retained accounting.
- [x] Run evaluator suite; commit.

### Task 3: One-command workflow, real evaluation, documentation

**Files:** new `scripts/run_coaching_regressions.sh`; regression workflow tests; README; new results report.

**Interfaces:** script exports standard/regression corpora on Coaching Smoke (overridable simulator); `python -m ...regression` loads candidate/judge/prices, reuses qualification, sensitivity-checks, runs both suites, writes separate reports and top-level manifest. Default candidate pins the dev-launcher model; default ceiling $10.

- [x] Add failing workflow tests: selected config, failed sensitivity stops candidates, no overwrite, budget failure retains results, repeated suite reports and provenance, no key exposure.
- [x] Implement documented command and resume-safe grading checkpoints, retaining incomplete candidate evidence and preventing automatic replay.
- [x] Run live sensitivity first, then current candidate on both suites three times within $10. Record quality/latency/cost and failures honestly; no tuning to the results.
- [x] Run full relevant suites, fresh branch review, fix important findings with tests, update PR #23; do not merge.

Completed: sensitivity 18/18; new suite 24/24 strong and 0 severe; original development suite 143/168 strong and 3 severe. Both matrices and all grading completed after a credit top-up, using saved checkpoints without rerolls. Conservative total $9.5540495 includes three unknown-charge reservations and remains within the original $10 cap. Raw scores retained; rubric inconsistencies documented rather than tuned mid-run. See `docs/reports/2026-11-04-coaching-regression-evaluation.md`. Python CI passed; iPad CI was blocked before execution by hosted-runner capacity and requires a successful fresh attempt before merge.

# Judge Qualification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace per-run judge calibration with a reusable, repeatable, human-grounded qualification workflow.

**Architecture:** A focused reference-set module owns the reviewed fixture contract and deterministic review rendering. A qualification module runs and validates three calibration passes, publishes immutable artifacts, and selects compatible unexpired qualifications. Grading consumes a validated qualification instead of invoking calibration, while CLI and launcher orchestration ensures qualification happens before candidate inference.

**Tech Stack:** Python 3 standard library, Bash launcher, `unittest`, existing OpenAI Responses adapter.

**Spec:** `docs/superpowers/specs/2026-09-03-judge-qualification-design.md`

## Global Constraints

- Real qualification requires explicit human-review provenance; agent-authored proposals are not ground truth.
- Run three complete 20-case passes; every pass requires severe agreement >= 0.95 and dimension-within-one agreement >= 0.90.
- A passing qualification is valid for 30 days and binds judge configuration, judge prompt, schemas, and reference-set hashes.
- Qualification must run before candidate inference when no compatible unexpired artifact exists.
- Ordinary grade runs make no calibration or canary calls.
- Preserve rejected qualification diagnostics, but never persist credentials, provider bodies, exception text, reasoning traces, or candidate identities.
- Keep legacy reports readable; new grade runs require qualification v2.

---

### Task 1: Reviewed reference-set contract and review sheet

**Files:**
- Create: `Tools/CoachingEval/benchmark/reference_set.py`
- Create: `Tools/CoachingEval/benchmark/judge-reference-v2.json`
- Create: `Tools/CoachingEval/benchmark/judge-reference-v2-review.md`
- Create: `Tools/CoachingEval/tests/test_benchmark_reference_set.py`
- Modify: `Tools/CoachingEval/benchmark/configuration.py`
- Modify: `Tools/CoachingEval/tests/test_benchmark_configuration.py`

**Interfaces:**
- Produces: `JudgeReferenceSet.load(path: Path, expected_sha256: str, require_reviewed: bool = True) -> JudgeReferenceSet`.
- Produces: `JudgeReferenceSet.render_review() -> str`.
- `JudgeConfiguration` exposes `reference_set_path`, `reference_set_sha256`, `qualification_repetitions`, `minimum_severe_agreement`, `minimum_dimension_agreement`, and `qualification_valid_days`.

- [ ] **Step 1: Write failing reference-set tests**

Test exact 20-case inventory, actual grading payload keys, complete score/flag maps, deterministic Markdown rendering, hash pinning, and refusal of pending/malformed provenance when `require_reviewed=True`.

- [ ] **Step 2: Run the new test module and verify failures identify the missing module and v2 contract**

Run: `python3 -m unittest Tools.CoachingEval.tests.test_benchmark_reference_set`

- [ ] **Step 3: Implement the minimal reference-set object and deterministic renderer**

Keep parsing, provenance validation, and rendering inside the single cohesive object. Do not export loose helper functions.

- [ ] **Step 4: Replace the provisional JSONL with a proposed v2 set using real grader payloads**

Correct obvious inconsistencies, including the endangered-knight case that currently receives all 5s despite revealing the answer and skipping the expected interaction. Leave provenance pending until the product owner reviews the rendered Markdown.

- [ ] **Step 5: Update and test judge configuration v2**

Pin the reference set and exact qualification criteria in `configs/judge-v2.json`. Tests use a temporary reviewed reference fixture so production configuration cannot silently accept the pending proposal.

- [ ] **Step 6: Run reference and configuration tests**

Run: `python3 -m unittest Tools.CoachingEval.tests.test_benchmark_reference_set Tools.CoachingEval.tests.test_benchmark_configuration`

### Task 2: Repeatable immutable qualification artifacts

**Files:**
- Create: `Tools/CoachingEval/benchmark/qualification.py`
- Create: `Tools/CoachingEval/tests/test_benchmark_qualification.py`
- Modify: `Tools/CoachingEval/benchmark/grader.py`
- Modify: `Tools/CoachingEval/tests/test_benchmark_grader.py`

**Interfaces:**
- Produces: `JudgeQualification.ensure(configuration, client, price_table, artifact_root, now) -> Path`.
- Produces: `JudgeQualification.load_compatible(path, configuration, now) -> JudgeQualification`.
- Consumes the existing bounded `_judge_call` semantics through a narrow injected callable; qualification owns repetitions, thresholds, timestamps, selection, and publication.

- [ ] **Step 1: Write failing qualification tests**

Cover three passing repetitions, one borderline 90% severe pass being rejected, one below-90% dimension pass being rejected, minimum metrics, 30-day expiration, exact hash mismatch, selection of the newest compatible artifact, atomic no-overwrite publication, and preservation of rejected row diagnostics.

- [ ] **Step 2: Run qualification tests and verify they fail for missing behavior**

Run: `python3 -m unittest Tools.CoachingEval.tests.test_benchmark_qualification`

- [ ] **Step 3: Extract one-pass evaluation from the grader without changing judge payload semantics**

The internal evaluator returns the existing row-level comparisons and call metrics. Rename fixture fields to `referenceScores` and `referenceFlags`; do not retain the misleading `human*` names.

- [ ] **Step 4: Implement `JudgeQualification`**

Bind `configuration.sha256`, prompt SHA, reference SHA, `_absolute_schema()` SHA, and `_pairwise_schema()` SHA. Require every pass to clear configured thresholds. Aggregate qualification metrics separately and publish one immutable JSON artifact beneath a timestamped directory.

- [ ] **Step 5: Run qualification and grader tests**

Run: `python3 -m unittest Tools.CoachingEval.tests.test_benchmark_qualification Tools.CoachingEval.tests.test_benchmark_grader`

### Task 3: Grade with a qualified judge and report the binding

**Files:**
- Modify: `Tools/CoachingEval/benchmark/grader.py`
- Modify: `Tools/CoachingEval/benchmark/report.py`
- Modify: `Tools/CoachingEval/tests/test_benchmark_grader.py`
- Modify: `Tools/CoachingEval/tests/test_benchmark_report.py`

**Interfaces:**
- `grade_run(..., qualification_path: Path, now: datetime | None = None) -> Path` validates compatibility before loading candidate artifacts or issuing judge calls.
- New grade artifacts contain `qualification.json`; legacy report loading continues to accept `calibration.json`.

- [ ] **Step 1: Write failing tests proving grading performs zero calibration calls**

Provide one prequalified artifact and only candidate/pairwise queued outputs. Assert call count excludes 20 calibration calls. Reject missing, expired, unreviewed, rejected, and hash-mismatched qualifications before any judge call.

- [ ] **Step 2: Run grader tests and verify the old per-run calibration causes the expected failures**

Run: `python3 -m unittest Tools.CoachingEval.tests.test_benchmark_grader`

- [ ] **Step 3: Change grade publication to bind the qualification artifact**

Copy the validated qualification into the immutable grade directory, record its SHA-256 in the grade manifest, and remove new-run `calibration.json` production. Keep automatic unusable and blinded pairwise behavior unchanged.

- [ ] **Step 4: Update report validation and presentation**

For v2 grades, verify qualification hash and compatibility, show qualification creation/expiration, minimum agreements, repetitions, and separate qualification metrics. Compute current-run judge overhead only from absolute and pairwise calls. Retain the v1 calibration reader for frozen old reports.

- [ ] **Step 5: Run grader and report tests**

Run: `python3 -m unittest Tools.CoachingEval.tests.test_benchmark_grader Tools.CoachingEval.tests.test_benchmark_report`

### Task 4: Qualify before candidate inference in CLI and launcher

**Files:**
- Modify: `Tools/CoachingEval/benchmark/cli.py`
- Modify: `Tools/CoachingEval/tests/test_benchmark_cli.py`
- Modify: `scripts/run_coaching_quality_benchmark.sh`

**Interfaces:**
- Add CLI command `qualify --judge PATH --pricing PATH --artifact-root PATH --api-key-env NAME`.
- `grade` requires `--qualification PATH`.
- The launcher obtains or creates a qualification before corpus export, then passes its path to `grade`.

- [ ] **Step 1: Write failing CLI and launcher-order tests**

Assert qualification returns a bounded JSON summary, reuses a compatible artifact without provider calls, excludes credentials, and occurs before `xcodebuild` and `benchmark.cli run`. Assert failed qualification prevents both corpus export and candidate calls while preserving its diagnostic artifact.

- [ ] **Step 2: Run CLI tests and verify the missing command/order failures**

Run: `python3 -m unittest Tools.CoachingEval.tests.test_benchmark_cli`

- [ ] **Step 3: Implement the `qualify` and qualified `grade` CLI boundaries**

Keep stdout machine-readable and bounded. Return the selected qualification path; never return row evidence or secrets on stdout.

- [ ] **Step 4: Reorder the launcher**

Resolve judge and pricing paths, ensure qualification, and stop on rejection before `xcodebuild`. Preserve interrupt cleanup for session artifacts without deleting shared qualification artifacts.

- [ ] **Step 5: Run CLI and launcher tests**

Run: `python3 -m unittest Tools.CoachingEval.tests.test_benchmark_cli`

### Task 5: Human review, documentation, live qualification, and full verification

**Files:**
- Modify: `Tools/CoachingEval/benchmark/judge-reference-v2.json`
- Modify: `Tools/CoachingEval/benchmark/judge-reference-v2-review.md`
- Modify: `Tools/CoachingEval/benchmark/configs/judge-v2.json`
- Modify: `Tools/CoachingEval/README.md`
- Modify: `docs/superpowers/specs/2026-09-01-coaching-quality-benchmark-design.md`

**Interfaces:**
- Product-owner approval changes provenance from pending to reviewed and updates pinned hashes; it does not silently alter any proposed judgment.

- [ ] **Step 1: Present the generated review sheet to the product owner**

Record requested score/flag corrections. Only an explicit approval permits setting `reviewStatus` to `humanReviewed`, `reviewedBy` to the reviewer’s name, and `reviewedAt` to the review date.

- [ ] **Step 2: Update provenance, hashes, and documentation after approval**

Document qualification reuse, 30-day expiration, separate cost, the new command order, and the fact that ordinary benchmark runs no longer recalibrate.

- [ ] **Step 3: Run all provider-free tests**

Run: `python3 -m unittest discover -s Tools/CoachingEval/tests -p 'test_*.py'`

Run: `python3 -m unittest discover -s CoachingServer/tests -p 'test_*.py'`

- [ ] **Step 4: Run one live qualification only after reviewed provenance exists**

Run the Keychain-backed launcher far enough to create/reuse qualification before any candidate run. Verify three passing repetitions, useful margin, row diagnostics, bounded artifacts, qualification cost, and zero candidate calls if qualification is rejected.

- [ ] **Step 5: Run a five-turn smoke using the accepted qualification**

Verify the smoke reuses qualification, makes no 20-case calibration calls, and reports candidate-grading overhead separately.

- [ ] **Step 6: Commit, push, and open a PR against `codex/chess-coaching-comparison`**

Include `Fixes #15` only after the reference review and live repeatability checks succeed.

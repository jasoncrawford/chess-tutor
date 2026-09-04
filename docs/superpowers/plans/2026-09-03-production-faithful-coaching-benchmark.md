# Production-Faithful Coaching Benchmark Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a trustworthy production-shaped benchmark, use it to select a hosted coaching configuration, and promote that exact configuration into a verified iPad app build.

**Architecture:** A strict shared hosted-model configuration owns every model-facing runtime parameter and is consumed by both the server and benchmark. Replayable v13 reference sources drive absolute and order-balanced pairwise judge qualification. Paid runs are fully preflighted, then a separate promotion PR changes only the tracked production configuration and its coverage.

**Tech Stack:** Python 3 standard library, Flask, Swift/XCTest, Bash, OpenAI Responses API, `unittest`, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-03-production-faithful-coaching-benchmark-design.md`

## Global Constraints

- Do not make a paid call until the revised ground truth is explicitly human-reviewed.
- Derive reference `availableUI` only by compiling replayable sources through `tutor-v13`.
- Use exactly 20 absolute and 10 pairwise reference cases.
- Run three qualification passes; each must clear 0.95 severe agreement, 0.90 dimension-within-one agreement, and 0.90 pairwise agreement.
- Present each pairwise reference in both orders and count order inconsistency as disagreement.
- Conversation reuse requires stored responses.
- Initial, tactical-follow-up, and simple-follow-up reasoning settings come from one shared hosted-model configuration.
- Preflight exactly one comparison baseline and complete price coverage before provider construction or inference.
- Keep secrets, raw provider errors, response IDs outside published artifacts, and private reasoning out of all artifacts.
- Provider-backed checks are local release evidence, never pull-request CI.

---

### Task 1: Shared hosted-model configuration and production-shaped candidate execution

**Files:**
- Create: `CoachingServer/model_configuration.py`
- Create: `CoachingServer/configs/production-v1.json`
- Create: `CoachingServer/tests/test_model_configuration.py`
- Modify: `CoachingServer/service.py`
- Modify: `CoachingServer/http_app.py`
- Modify: `CoachingServer/tests/test_service.py`
- Modify: `CoachingServer/tests/test_http_app.py`
- Modify: `Tools/CoachingEval/benchmark/configuration.py`
- Modify: `Tools/CoachingEval/benchmark/configs/production-v1.json`
- Modify: `Tools/CoachingEval/benchmark/runner.py`
- Modify: `Tools/CoachingEval/tests/test_benchmark_configuration.py`
- Modify: `Tools/CoachingEval/tests/test_benchmark_runner.py`

**Interfaces:**
- Produces: `HostedModelConfiguration.load(path: Path, repository_root: Path) -> HostedModelConfiguration`.
- Produces: `HostedModelConfiguration.reasoning_effort(request: Mapping, is_follow_up: bool) -> str`.
- Produces: candidate wrappers with `modelConfigurationPath`, `modelConfigurationSHA256`, `baseline`, and `pricingVersion`.
- Consumes: the existing neutral request parser and v13 compilers.

- [ ] **Step 1: Write failing shared-configuration tests**

Assert strict schema loading, prompt hash pinning, initial/tactical/simple routing, rejection of conversation reuse without storage, and rejection of unknown fields. Assert the live service forwards model, effort, token cap, timeout, prompt version, `store`, and continuation ID from the object instead of hard-coded values.

- [ ] **Step 2: Run the focused server tests and verify RED**

Run: `.venv/bin/python -m unittest CoachingServer.tests.test_model_configuration CoachingServer.tests.test_service CoachingServer.tests.test_http_app`

Expected: failures because `HostedModelConfiguration` and configuration injection do not exist.

- [ ] **Step 3: Implement the cohesive configuration object and inject it into the service**

Keep validation, reasoning routing, raw hash, and prompt loading on `HostedModelConfiguration`. `HostedCoachingService` accepts the object and a provider; the environment application loads `CoachingServer/configs/production-v1.json` unless `CHESS_TUTOR_COACHING_MODEL_CONFIG` names another repository-contained pinned file.

- [ ] **Step 4: Run server tests and verify GREEN**

Run the command from Step 2. Expected: all selected tests pass with zero skips.

- [ ] **Step 5: Write failing benchmark wrapper and runner-fidelity tests**

Assert candidate wrappers bind an exact model configuration. A three-step sequence must call the provider with initial, tactical, and simple effort as appropriate, use `store=True`, and pass the prior response ID. Assert configuration metadata in the run manifest contains the three efforts and storage setting.

- [ ] **Step 6: Run benchmark configuration/runner tests and verify RED**

Run: `.venv/bin/python -m unittest Tools.CoachingEval.tests.test_benchmark_configuration Tools.CoachingEval.tests.test_benchmark_runner`

Expected: failures against the old flat candidate schema, uniform follow-up effort, and `store=False`.

- [ ] **Step 7: Implement the candidate wrapper and production-shaped execution**

Load `HostedModelConfiguration` through the wrapper, select effort through its method, and set `store` from the exact shared configuration. Preserve bounded candidate records without persisting provider response IDs; retain them only in memory for the next sequence step.

- [ ] **Step 8: Run focused tests, then commit**

Run both focused commands. Commit message: `Align benchmark execution with production`.

### Task 2: Replayable v13 reference sources and corrected absolute judgments

**Files:**
- Modify: `Tools/CoachingEval/benchmark/reference_set.py`
- Replace: `Tools/CoachingEval/benchmark/judge-reference-v2.json`
- Replace: `Tools/CoachingEval/benchmark/judge-reference-v2-review.md`
- Modify: `Tools/CoachingEval/tests/test_benchmark_reference_set.py`
- Modify: `Tools/CoachingEval/benchmark/configs/judge-v2.json`
- Modify: `Tools/CoachingEval/tests/test_benchmark_configuration.py`

**Interfaces:**
- Produces: a reference set with replayable `sources`, 20 `absoluteCases`, and 10 `pairwiseCases`.
- Produces: derived case payloads exposing `graderBrief`, `availableUI`, and validated candidate turns.
- Consumes: exact exported `CoachingQualityBenchmarkCaseRecord` objects and the v13 initial/follow-up compiler.

- [ ] **Step 1: Export a fresh deterministic corpus to an ignored directory**

Run the opt-in corpus export with `COACHING_QUALITY_BENCHMARK_SOURCE_SHA=$(git rev-parse HEAD)` and a fresh `.coaching-eval/benchmark/reference-source/<timestamp>` destination. Record its manifest and cases hashes in the reference source provenance.

- [ ] **Step 2: Write failing source-contract tests**

Assert exact source/case inventories, request SHA validation, source ID resolution, production-v13 compilation, derived UI, required `expects`, candidate app validation, complete expected-response coverage, positive square/move-focus coverage, positive Hint coverage, and rejection of a help-closed source as a candidate turn.

- [ ] **Step 3: Run reference tests and verify RED**

Run: `.venv/bin/python -m unittest Tools.CoachingEval.tests.test_benchmark_reference_set`

Expected: failure because the pending set stores handwritten legacy UI and has no replayable sources.

- [ ] **Step 4: Implement source loading and deterministic derivation**

Validate source records without importing Swift-only code. Recompile each source through `compile_context` or `compile_follow_up_context` according to the stored request kind. Build the judge payload from source grader brief plus derived UI; never accept handwritten UI.

- [ ] **Step 5: Author the 20 corrected absolute cases**

Use only replayable sources. Apply the independent audit corrections: make answer-revealing dead ends severe, keep chess correctness distinct from pedagogy, remove retired actions, align questions with `expects`, replace the close-help response, and include every required coverage class. Keep human provenance pending.

- [ ] **Step 6: Generate the review sheet, update the pinned hash, and verify GREEN**

Run the reference renderer and focused tests. Expected: byte-identical deterministic Markdown and all contract tests passing.

- [ ] **Step 7: Commit**

Commit message: `Ground judge references in production turns`.

### Task 3: Order-balanced pairwise judge qualification

**Files:**
- Modify: `Tools/CoachingEval/benchmark/judge_contract.py`
- Modify: `Tools/CoachingEval/benchmark/judge-v1.md`
- Modify: `Tools/CoachingEval/benchmark/qualification.py`
- Modify: `Tools/CoachingEval/benchmark/configuration.py`
- Modify: `Tools/CoachingEval/benchmark/configs/judge-v2.json`
- Modify: `Tools/CoachingEval/tests/test_benchmark_configuration.py`
- Modify: `Tools/CoachingEval/tests/test_benchmark_qualification.py`
- Modify: `Tools/CoachingEval/tests/test_benchmark_reference_set.py`

**Interfaces:**
- Adds: `minimumPairwiseAgreement` to judge v2 configuration.
- Produces: per-pass normalized pairwise rows in accepted and rejected qualification artifacts.
- Consumes: the 10 reviewed pairwise reference cases, each presented in both orders.

- [ ] **Step 1: Write failing pairwise qualification tests**

Cover exact A/B normalization, tie handling, both presentation orders, an order-biased judge, one pass below 0.90, minimum aggregation, bounded rejected diagnostics, cost/latency accounting, and compatibility/hash validation.

- [ ] **Step 2: Run qualification tests and verify RED**

Run: `.venv/bin/python -m unittest Tools.CoachingEval.tests.test_benchmark_qualification`

Expected: failure because qualification currently calls only the absolute schema.

- [ ] **Step 3: Explain expected-response controls in the judge prompt**

Add the five exact symbolic-to-visible interaction mappings from the spec. Update its pinned SHA only after prompt tests show the intended text.

- [ ] **Step 4: Implement order-balanced pairwise qualification**

For every repetition, grade each reference pair as A/B and B/A, normalize to response-one/response-two/tie, mark an order-inconsistent pair wrong in both rows, aggregate the threshold independently from absolute metrics, and retain bounded evidence.

- [ ] **Step 5: Run qualification/reference/configuration tests and verify GREEN**

Run: `.venv/bin/python -m unittest Tools.CoachingEval.tests.test_benchmark_reference_set Tools.CoachingEval.tests.test_benchmark_configuration Tools.CoachingEval.tests.test_benchmark_qualification`

- [ ] **Step 6: Commit**

Commit message: `Qualify pairwise coaching judgments`.

### Task 4: Complete paid-run preflight and recommendation gates

**Files:**
- Modify: `Tools/CoachingEval/benchmark/runner.py`
- Modify: `Tools/CoachingEval/benchmark/report.py`
- Modify: `Tools/CoachingEval/benchmark/cli.py`
- Modify: `Tools/CoachingEval/tests/test_benchmark_runner.py`
- Modify: `Tools/CoachingEval/tests/test_benchmark_report.py`
- Modify: `Tools/CoachingEval/tests/test_benchmark_cli.py`
- Modify: `scripts/run_coaching_quality_benchmark.sh`

**Interfaces:**
- Candidate preflight receives the price table and completes before `provider_factory` is invoked.
- Reports distinguish development trial evidence from holdout promotion evidence.

- [ ] **Step 1: Write failing preflight tests**

Assert two baselines, zero baselines, missing model price, pricing-version mismatch, invalid conversation/storage combination, and compilation failure all stop before provider construction. Assert exactly one baseline succeeds.

- [ ] **Step 2: Run runner/CLI tests and verify RED**

Run: `.venv/bin/python -m unittest Tools.CoachingEval.tests.test_benchmark_runner Tools.CoachingEval.tests.test_benchmark_cli`

- [ ] **Step 3: Implement complete preflight**

Pass the price table into preflight, estimate zero usage for each distinct model, require exactly one baseline for comparison, and construct provider clients only after every cell and invariant validates.

- [ ] **Step 4: Write failing recommendation-gate tests**

Assert a diagnostic subset and development-only comparison cannot promote a challenger; a complete holdout candidate must meet every concrete quality gate; keeping the baseline remains a valid report outcome.

- [ ] **Step 5: Implement report gates and manifest evidence**

Record whether the run includes holdout and the reasoning/storage policy. Report trial eligibility for development and promotion eligibility only for complete holdout evidence.

- [ ] **Step 6: Run focused tests and commit**

Run the runner, report, and CLI suites. Commit message: `Preflight and gate coaching comparisons`.

### Task 5: Human review, live judge qualification, and issue-15 PR

**Files:**
- Modify after explicit review: `Tools/CoachingEval/benchmark/judge-reference-v2.json`
- Regenerate after explicit review: `Tools/CoachingEval/benchmark/judge-reference-v2-review.md`
- Modify: `Tools/CoachingEval/benchmark/configs/judge-v2.json`
- Modify: `Tools/CoachingEval/README.md`
- Modify: `docs/superpowers/specs/2026-09-01-coaching-quality-benchmark-design.md`

**Interfaces:**
- Consumes: explicit product-owner approval or corrections to the rendered reference sheet.
- Produces: one accepted live qualification and a production-shaped five-turn diagnostic report.

- [ ] **Step 1: Present the corrected deterministic review sheet**

Open it in Codex. Apply requested corrections and regenerate until the product owner explicitly approves the absolute scores/flags and pairwise winners.

- [ ] **Step 2: Record human provenance and update all pins**

Set `reviewStatus=humanReviewed`, the human reviewer's name, and the actual review date. Recompute the reference SHA in `judge-v2.json` and regenerate the sheet without changing approved judgments.

- [ ] **Step 3: Run all provider-free tests**

Run: `.venv/bin/python -m unittest discover -s Tools/CoachingEval/tests -p 'test_*.py'`

Run: `.venv/bin/python -m unittest discover -s CoachingServer/tests -p 'test_*.py'`

Run the full iPad scheme with `xcodebuild test` on `iPad (A16)`. Require zero failures and zero skips.

- [ ] **Step 4: Run one live qualification**

Use the Keychain-backed CLI. Verify all three passes clear every absolute and pairwise threshold, artifacts are bounded, cost is reported, and no candidate call occurs if qualification rejects.

- [ ] **Step 5: Run a five-turn production-baseline smoke**

Verify qualification reuse, initial/tactical/simple routing, stored chaining, zero calibration calls during grading, and separate candidate/judge/qualification costs.

- [ ] **Step 6: Review, push, open, and merge the PR**

Run whole-branch review, push `codex/stabilize-benchmark-judge`, and open a PR against `codex/chess-coaching-comparison` with `Fixes #15`. Wait for every required check. The user has authorized merging once all checks pass; merge only after green.

### Task 6: Hosted comparison and recommendation

**Files:**
- Create: tracked shared model configurations and benchmark wrappers for justified hosted challengers.
- Create: a versioned price table covering every compared model.
- Create after the run: `docs/reports/2026-09-<date>-coaching-quality-benchmark.md`

**Interfaces:**
- Consumes: merged benchmark and accepted reusable judge qualification.
- Produces: diagnostic, development, and finalist holdout reports with a specific recommendation.

- [ ] **Step 1: Start a fresh worktree from the merged comparison branch**

Pull the merge commit, create a focused comparison/configuration branch, and copy no ignored artifact into source control.

- [ ] **Step 2: Verify current official model availability and pricing**

Use official OpenAI documentation. Add immutable model/pricing configurations only for accessible justified candidates; do not silently substitute unavailable models.

- [ ] **Step 3: Run diagnostic smoke for each challenger**

Preserve failures and remove candidates with provider, contract, or obvious severe-quality failures.

- [ ] **Step 4: Run the development comparison for survivors**

Use 56 development turns and three repetitions. Inspect aggregate evidence and worst cases without changing the frozen prompt or corpus during the run.

- [ ] **Step 5: Run holdout for finalists**

Use all 70 turns and three repetitions only for configurations still capable of meeting the quality bar. Regenerate the report offline as needed; do not rerun model responses to tune presentation.

- [ ] **Step 6: Write the evidence-backed recommendation**

Name the exact model, initial/tactical/simple reasoning efforts, output cap, timeout, storage/chaining behavior, prompt version, latency percentiles, estimated cost, severe-error rate, strong-response rate, pairwise result, and any observed limitation.

### Task 7: Promote the winner and verify the app

**Files:**
- Modify: `CoachingServer/configs/production-v1.json`
- Modify: corresponding hash-bound benchmark baseline wrapper.
- Modify: server/configuration tests that pin the production policy.
- Modify: `docs/hosted-coaching-server.md`
- Modify: `docs/reports/2026-09-<date>-coaching-quality-benchmark.md`

**Interfaces:**
- Consumes: the exact winning shared model configuration from Task 6.
- Produces: the normal development launcher running that configuration in ChessTutor.

- [ ] **Step 1: Write a failing production-policy regression test**

Assert the default environment application loads the exact recommended model, three efforts, token cap, timeout, prompt/hash, response contract, and stored continuation setting.

- [ ] **Step 2: Run the focused server test and verify RED**

Run the production configuration and service tests. Expected: failure until the promoted document is installed.

- [ ] **Step 3: Promote the exact winning document**

Change only the tracked production configuration and its hash-bound benchmark baseline. Do not retype settings in service code.

- [ ] **Step 4: Run all provider-free and iPad tests**

Require zero failures and zero skips in evaluator, server, and full iPad suites.

- [ ] **Step 5: Launch the real simulator app**

Run `./scripts/run_hosted_coaching_dev.sh 'iPad (A16)'`. Exercise initial Help, a tactical staged move, a Hint, and a simple follow-up. Verify the model/efforts in logs, valid UI controls, natural latency, and useful coaching.

- [ ] **Step 6: Review, push, open, and merge the promotion PR**

Wait for all required checks, merge under the user's standing authorization, pull the merge locally, and leave the normal launcher ready for the user.

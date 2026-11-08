# Chess Coaching Consistency Comparison Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce an immutable eight-call hosted consistency run and one immutable eight-case Qwen3 1.7B local run from the frozen tutor-v6 prompts.

**Architecture:** Add a narrow consistency layer around the existing hosted completion and artifact boundaries, and make the existing local pilot select from two fully pinned model configurations. Reuse the source loader, response schema, validator, server lifecycle, and atomic writers; do not change prompt bytes or application code.

**Tech Stack:** Python 3 standard library, OpenAI Responses API, llama.cpp b10516, unittest.

## Global Constraints

- Exact frozen `tutor-v6` system/user prompts and source hashes.
- No retry, repair, prompt mutation, hidden cases, or persisted reasoning.
- Hosted: GPT-5.6 Sol, high reasoning, 2,048 maximum output tokens, two new samples each for cases 02/05/06/07.
- Local: Qwen3 1.7B Q4_K_M, seed 1103, bounded thinking, temperature 0.2, top-p 0.95, 512 maximum output tokens.
- Fresh immutable destinations and generic redacted provider errors.

---

### Task 1: Hosted hard-case consistency runner

**Files:**
- Create: `Tools/CoachingEval/run_hosted_chess_native_consistency.py`
- Create: `Tools/CoachingEval/tests/test_run_hosted_chess_native_consistency.py`

**Interfaces:**
- Consumes: `run_hosted_chess_native_pilot._load_frozen_source`, `_complete_prompt`, canonical JSON and fsync behavior.
- Produces: `run_hosted_consistency(...) -> dict` and a CLI with source, system prompt, destination, and timeout arguments.

- [ ] **Step 1: Write failing behavioral tests**

Require exactly two samples of 02/05/06/07 in deterministic order, unique record filenames, unchanged prompt/schema/model settings, continuation after a redacted failure, atomic overwrite refusal, and environment-only credentials.

- [ ] **Step 2: Run the focused test and verify RED**

Run `python3 -B -m unittest Tools.CoachingEval.tests.test_run_hosted_chess_native_consistency -v` and confirm it fails because the runner module is absent.

- [ ] **Step 3: Implement the minimal runner**

Reuse the hosted pilot's completion boundary; add only sample identity, consistency manifest/review rendering, atomic writing, and CLI wiring.

- [ ] **Step 4: Run focused and adjacent tests**

Run the new test plus hosted pilot and Responses client tests; require zero failures/skips.

### Task 2: Pinned Qwen candidate selection

**Files:**
- Modify: `Tools/CoachingEval/run_chess_native_pilot.py`
- Modify: `Tools/CoachingEval/tests/test_run_chess_native_pilot.py`

**Interfaces:**
- Consumes: a candidate ID selected at the CLI and its explicit model/model-manifest paths.
- Produces: unchanged Smol default behavior plus pinned `qwen3-1.7b-q4_k_m` provenance and output.

- [ ] **Step 1: Write failing candidate-selection tests**

Require the Qwen ID to validate its literal manifest/hash/size/revision, appear in records and manifest provenance, reject cross-candidate artifacts, and preserve the original Smol default.

- [ ] **Step 2: Run focused tests and verify RED**

Run `python3 -B -m unittest Tools.CoachingEval.tests.test_run_chess_native_pilot -v` and confirm the new Qwen expectations fail against the Smol-only implementation.

- [ ] **Step 3: Implement the two-candidate pin table**

Thread the selected immutable candidate through provenance validation, records, review title, server setup, and CLI defaults without weakening runtime or source gates.

- [ ] **Step 4: Run focused and full evaluator tests**

Require the focused runner tests and full `Tools/CoachingEval/tests` discovery suite to pass with zero failures/skips.

### Task 3: Execute the frozen comparison

**Files:**
- Create ignored artifacts under `.coaching-eval/runs/` in the established evaluation workspace.

- [ ] **Step 1: Verify hashes before generation**

Check the source manifest, examples inventory, system prompt, model artifacts, model manifests, runtime binary, and runtime manifest against their pinned values.

- [ ] **Step 2: Run the hosted consistency calls once**

Retrieve the API key from Keychain into the child process environment without printing it. Run exactly eight calls and verify the immutable manifest before reading outputs.

- [ ] **Step 3: Run the Qwen pilot once**

Use the pinned local runtime and Qwen artifact for one eight-case run. Verify complete preflight, manifest, trace scan, and provenance.

- [ ] **Step 4: Inspect all sixteen responses**

Assess factual correctness, latest-action awareness, single-stage coaching, discovery orientation, child language, and action/focus alignment. Compare the new hosted samples with the first funded sample.

### Task 4: Report and verify

**Files:**
- Create: `docs/reports/2026-08-30-chess-coaching-consistency-comparison.md`

- [ ] **Step 1: Record exact evidence and recommendation**

Document commands, hashes, counts, latency/token summaries, every response, qualitative findings, and the bounded next recommendation.

- [ ] **Step 2: Run final verification**

Run the full evaluator suite, Python compilation, trace/credential scans, manifest hash verification, `git diff --check`, and `git status --short`.

- [ ] **Step 3: Commit scoped tracked files**

Commit code, tests, design, plan, and report on `codex/chess-coaching-comparison`; keep raw artifacts ignored.

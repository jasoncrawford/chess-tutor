# Zero-Shot Compact Coaching Evaluation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Evaluate the existing three local models with the unchanged compact Markdown chess evidence and strict structured response contract, but without the eight full few-shot examples.

**Architecture:** Add immutable `tutor-v4` prompt files and explicitly classify it as a compact-context prompt. Add a token-only audit that uses the same pinned runtime, model templates, compact inputs, and exact tokenizer as generation but never calls completion. Gate the existing 60-record pilot on that audit, then use the existing blinded review and visible/hidden advancement rules.

**Tech Stack:** Python 3 standard library, `unittest`, pinned llama.cpp `b10516`, GGUF, GBNF, JSONL, SHA-256, Swift/XCTest validator parity.

## Global Constraints

- The shipping ChessTutor app remains unchanged and model-free.
- `model-coaching-context.v1`, the compact Markdown compiler output, and all complete chess evidence remain unchanged.
- `model-coaching-turn.v1`, request-specific GBNF, alias restoration, and the complete request-aware validator remain unchanged.
- The immutable prompt bundle is `tutor-v4`; `examples-v4.json` is exactly `[]`.
- `tutor-v1`, `tutor-v2`, and `tutor-v3` remain byte-immutable.
- The exact rendered-input budget remains 4,000 tokens; no prompt, section, or evidence value is truncated.
- Preflight uses each real model's own template and tokenizer for ten fixed visible cases × two modes and never requests completion.
- Pilot inference starts only when all 60 preflight cells fit the budget.
- Hidden cases remain uninspected unless a candidate passes the full visible gates.
- Private reasoning traces, model weights, runtime builds, corpus, runs, transcripts, and review artifacts remain ignored under `.coaching-eval/`.

---

### Task 1: Add the immutable zero-shot compact prompt bundle

**Files:**
- Create: `Tools/CoachingEval/prompts/tutor-v4.md`
- Create: `Tools/CoachingEval/prompts/examples-v4.json`
- Modify: `Tools/CoachingEval/run_eval.py`
- Modify: `Tools/CoachingEval/tests/test_run_eval.py`
- Modify: `Tools/CoachingEval/README.md`

**Interfaces:**
- Consumes: `_load_prompt_bundle(version)`, `_example_messages(examples, prompt_version:)`, and `EvaluationRunner.evaluate_case`.
- Produces: `_uses_compact_context(prompt_version: str) -> bool`, immutable `PromptBundle(version="tutor-v4", examples=[])`, and a zero-shot compact prompt that retains the approved coaching invariants.

- [ ] **Step 1: Write failing compact-family and prompt-bundle tests**

Add tests proving that `tutor-v4` takes the compact evaluation path, renders the compact Markdown as its user message, supplies no example messages, records the 4,000-token compiler budget/compact transport, and leaves every older prompt file hash unchanged. Add a direct bundle test asserting:

```python
bundle = run_eval._load_prompt_bundle("tutor-v4")
self.assertEqual([], bundle.examples)
self.assertLess(len(bundle.system_prompt.encode("utf-8")), 2600)
self.assertIn("latest learner action", bundle.system_prompt.lower())
self.assertIn("one coherent", bundle.system_prompt.lower())
```

- [ ] **Step 2: Run the focused tests and record RED**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
  Tools.CoachingEval.tests.test_run_eval.CompactEvaluationRunnerTests \
  Tools.CoachingEval.tests.test_run_eval.RunEvalConfigurationTests -v
```

Expected: failures because the `tutor-v4` bundle and compact-family behavior do not exist.

- [ ] **Step 3: Add the minimal compact-family seam and zero-shot prompt**

Add one explicit version predicate used everywhere the current code checks `== "tutor-v3"` for compact behavior:

```python
COMPACT_CONTEXT_PROMPT_VERSIONS = frozenset(("tutor-v3", "tutor-v4"))

def _uses_compact_context(prompt_version):
    return prompt_version in COMPACT_CONTEXT_PROMPT_VERSIONS
```

Create `examples-v4.json` as exactly:

```json
[]
```

Create `tutor-v4.md` with only the approved invariant groups: role/age, evidence authority, latest-action continuity, one-step pedagogy, optional Safe/Take/Wake, concise field semantics, alias discipline, and exact JSON-only response. Do not restate the input schema, enumerate worked positions, or duplicate constraints already enforced by GBNF.

- [ ] **Step 4: Run focused and full evaluator tests**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
  Tools.CoachingEval.tests.test_run_eval.CompactEvaluationRunnerTests \
  Tools.CoachingEval.tests.test_run_eval.RunEvalConfigurationTests -v
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tools/CoachingEval/tests -v
python3 -m py_compile Tools/CoachingEval/*.py
git diff --check
```

Expected: all tests pass, zero skipped, and no diff-check output.

- [ ] **Step 5: Document and commit the prompt bundle**

Document `tutor-v4` as zero-shot and compact-context in `README.md`, including the unchanged 4,000-token gate. Commit:

```bash
git add Tools/CoachingEval/prompts/tutor-v4.md \
  Tools/CoachingEval/prompts/examples-v4.json \
  Tools/CoachingEval/run_eval.py \
  Tools/CoachingEval/tests/test_run_eval.py \
  Tools/CoachingEval/README.md
git commit -m "feat: add zero-shot compact coaching prompt"
```

---

### Task 2: Add a reproducible token-only prompt preflight

**Files:**
- Create: `Tools/CoachingEval/preflight_prompts.py`
- Create: `Tools/CoachingEval/tests/test_preflight_prompts.py`
- Modify: `Tools/CoachingEval/README.md`

**Interfaces:**
- Consumes: `run_eval._load_prompt_bundle`, `run_eval._load_cases`, `run_eval._select_case_list`, `run_eval._example_messages`, `llama_server.LlamaServer.render_prompt`, and `LlamaServer.token_count`.
- Produces: `preflight_prompts.preflight(...) -> dict` and a CLI that writes one immutable JSON manifest with 60 model/mode/case cells and exits nonzero when any exact rendered prompt exceeds 4,000 tokens.

- [ ] **Step 1: Write failing unit and integration tests**

Use a fake template/token client to assert that preflight:

- covers exactly ten pilot cases in declared order for each requested model and mode;
- calls `render_prompt` and `token_count` but never `complete_rendered`;
- records prompt version/hash, examples hash/count, corpus and pilot hashes, runtime/model provenance, rendered bytes/tokens/hash, and budget status per cell;
- produces deterministic JSON for deterministic clients;
- refuses hidden cases, duplicate cells, an existing output file, or an incomplete 60-cell matrix;
- exits nonzero if one cell is 4,001 tokens and zero when every cell is at most 4,000.

- [ ] **Step 2: Run the new tests and record RED**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
  Tools.CoachingEval.tests.test_preflight_prompts -v
```

Expected: import failure because `preflight_prompts` does not exist.

- [ ] **Step 3: Implement the token-only audit**

Keep model startup serial to avoid Metal contention. For each real model, start one pinned server, render/tokenize every pilot case in off and bounded mode, stop the server in `finally`, then proceed to the next model. Never call the completion endpoint. Write through a temporary sibling followed by atomic rename. The manifest top level is:

```json
{
  "schemaVersion": "coaching-prompt-preflight.v1",
  "promptVersion": "tutor-v4",
  "budgetTokens": 4000,
  "preferredTargetTokens": 3000,
  "models": [],
  "cells": [],
  "summary": {}
}
```

The summary contains `cellCount`, `overBudgetCount`, `abovePreferredTargetCount`, `minimumTokens`, `medianTokens`, `p90Tokens`, and `maximumTokens`.

- [ ] **Step 4: Run focused, full, and fake-client integration verification**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
  Tools.CoachingEval.tests.test_preflight_prompts -v
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tools/CoachingEval/tests -v
python3 -m py_compile Tools/CoachingEval/*.py
git diff --check
```

Expected: all tests pass, zero skipped, no completion calls, and no diff-check output.

- [ ] **Step 5: Document and commit the preflight**

Add the exact real-runtime command to `README.md`. Commit:

```bash
git add Tools/CoachingEval/preflight_prompts.py \
  Tools/CoachingEval/tests/test_preflight_prompts.py \
  Tools/CoachingEval/README.md
git commit -m "feat: preflight compact coaching prompts"
```

---

### Task 3: Run the real preflight and gated visible pilot

**Files:**
- Modify: `docs/reports/2026-08-29-zero-shot-compact-coaching-evaluation.md`
- Generated and ignored: `.coaching-eval/analysis/zero-shot-preflight-v1.json`
- Generated and ignored when preflight passes: `.coaching-eval/runs/<model>/<timestamp>/`
- Generated and ignored when inference runs: `.coaching-eval/reviews/zero-shot-pilot-v1/`

**Interfaces:**
- Consumes: frozen corpus v2, fixed ten-case pilot, `tutor-v4`, three verified GGUFs, pinned b10516 runtime, token preflight, existing evaluator/review/summarizer.
- Produces: a committed report with exact prompt-size distribution, pilot mechanical results, blinded scores when generated, and a gate decision.

- [ ] **Step 1: Verify frozen inputs and runtime provenance**

Run model-store verification, runtime provenance verification, schema compatibility, corpus count/hash checks, prompt/example hashes, and the existing adversarial real-runtime grammar smoke for all three models and both modes. Record exact commands and hashes in the task report.

- [ ] **Step 2: Run the 60-cell real token preflight**

Run `preflight_prompts.py` with corpus v2, `compact-markdown-v1.json`, `tutor-v4`, all three configured models, both modes, and output `.coaching-eval/analysis/zero-shot-preflight-v1.json`.

If any cell exceeds 4,000 tokens, stop before inference and write the report. Do not increase the budget or remove evidence.

- [ ] **Step 3: Run the 60-record visible pilot only when preflight passes**

Run each model serially with the fixed ten-case pilot, both supported modes, one pinned seed, corpus v2, and `tutor-v4`. Verify each immutable run contains exactly 20 unique model/mode/case/seed records, no hidden IDs, no trace markers, and no context/compiler errors.

- [ ] **Step 4: Conduct blinded pilot review and apply the fixed gate**

Render one combined packet from the three exact pilot run directories. Have an independent reviewer score all 60 rows without access to `review-key.json`. After the completed rubric returns, unblind and verify all pointers and every mechanically valid severe row against the source request.

Advance a model only when it meets all thresholds from the design. If none advances, stop. If one advances, run its full visible matrix with three pinned seeds and repeat blinded scoring before considering hidden/device work.

- [ ] **Step 5: Write the result report and commit the evaluation decision**

Create `docs/reports/2026-08-29-zero-shot-compact-coaching-evaluation.md` with exact artifact paths/hashes, token distribution, validity/repair/error counts, blinded scores, severe examples, and the advancement decision. Commit tracked prompt/tooling/report changes without adding `.coaching-eval` artifacts.

---

### Task 4: Final verification and review

**Files:**
- Modify if needed: `Tools/CoachingEval/README.md`
- Modify if needed: `docs/reports/2026-08-29-zero-shot-compact-coaching-evaluation.md`

**Interfaces:**
- Consumes: final Task 1–3 tree and evidence.
- Produces: verified clean branch and reviewed conclusion.

- [ ] **Step 1: Run final evaluator and parity gates**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tools/CoachingEval/tests -v
python3 -m py_compile Tools/CoachingEval/*.py
xcodebuild test -project ChessTutor.xcodeproj -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingTurnValidatorTests
git diff --check
git status --short
```

Expected: all tests pass with zero skipped/expected failures, compilation succeeds, diff check is silent, and status contains only intended report changes before the final commit.

- [ ] **Step 2: Independently review the complete branch diff**

Verify prompt immutability, compact-path routing, zero examples, no completion during preflight, exact 60-cell coverage, correct gate application, hidden-set non-use, trace redaction, and report/artifact consistency. Resolve every Critical or Important finding before completion.

- [ ] **Step 3: Commit any review fixes and confirm clean status**

Run the affected tests again after any fix, commit separately, and confirm `git status --short` is empty.


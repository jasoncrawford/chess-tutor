# Coaching Playthrough Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this focused change inline.

**Goal:** Improve staged-move teaching using observed playthrough failures and a small replayable comparison.

**Architecture:** Keep the existing Swift request builder, server compiler, model, and response contract. Add a versioned prompt/configuration only if live comparisons support it; preserve old benchmark artifacts.

**Tech Stack:** Swift/XCTest; Python server and evaluation transport; Markdown prompts.

**Spec:** `docs/superpowers/specs/2026-11-03-coaching-playthrough-design.md`

## Global Constraints

- No deployed-default or A16 game changes.
- No invented model-facing advice in test input; use the production request builder.
- At most $2.50 conservative API cost for this round, with all attempts retained.
- Existing frozen corpus, prompt, and model configurations remain unchanged.

## Review Focus

- Accurate one-way defense, not mutual-pawn-defense claims.
- Useful explanation without introducing false tactical claims.
- Wrong answers and losing captures still receive appropriate feedback.
- Help remains discovery-oriented; Hint may identify a move.
- Changed or removed tentative moves supersede older advice.

### Task 1: Replay evidence and prompt revision

**Files:** Extend `ChessTutorTests/Coaching/ModelEvaluation/CoachingQualityBenchmarkCorpusTests.swift` with a diagnostic exporter using actual legal move histories. Add `Tools/CoachingEval/prompts/tutor-v13-discovery-v2.md` and a corresponding pinned model configuration. Save diagnostic artifacts under ignored `.coaching-eval/playthrough/20261103/`.

**Interfaces:** Export neutral request arrays via `ModelCoachingNeutralRequestBuilder.build`; consume them with the existing compiler and OpenAI transport. Keep oracle/audit commentary out of candidate prompts.

- [x] Preserve the observed failing output and trace.
- [x] Add replay tests verifying legal histories, the d3→e4 defense and absence of its reverse, and relevant capture replies. Export deterministic requests.
- [x] Run the diagnostic cases with the old prompt, then the revised prompt; inspect every output and record the evidence, including failures.
- [x] Retain the revision only if it improves useful feedback without new factual/interaction errors in the bounded test.

### Task 2: Local trial handoff

**Files:** `scripts/run_hosted_coaching_dev.sh`, launcher tests, `docs/hosted-coaching-server.md`, and a playthrough report.

- [x] Point the local launcher at the newly pinned policy if Task 1 supports it; leave direct/deployed Sol default intact.
- [x] Run server/evaluator tests and native regression tests; verify the actual revised response in Coaching Smoke.
- [x] Obtain one fresh-context branch review; address substantive findings; create a PR with findings, limits, and reproduction instructions. Leave it open for review: [PR #23](https://github.com/jasoncrawford/chess-tutor/pull/23).

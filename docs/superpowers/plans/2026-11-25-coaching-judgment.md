# Coaching Judgment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan inline, with a fresh independent review at the end.

**Goal:** Demonstrate and improve decision-useful chess coaching through a frozen eval-first experiment.
**Architecture:** Native Swift snapshots generate normal app requests; the existing Python benchmark owns candidate calls, blinded grading, accounting and reports. Add a narrow judgment suite and, only after baseline measurement, an experimental engine-backed prompt generator.
**Tech Stack:** Swift/XCTest, Python unittest, existing Responses adapter, Stockfish UCI via an established library if the engine arm is reached.
**Spec:** `docs/superpowers/specs/2026-11-25-coaching-judgment-design.md`

**Outcome, November 26:** All three arms evaluated; results and limitations are in
[the experiment report](../../reports/2026-11-25-coaching-judgment.md). Baseline
30/36 useful, prompt-only 35/36, engine-backed 34/36. Total conservative accounting
$9.9870640. No deployment. Independent review fixes and local tests are complete.

## Global Constraints

- Work on `codex/coaching-evaluation` in the existing isolated worktree. Preserve old prompts, fixtures and production config.
- No paid calls before the corpus, criteria and controls are frozen. Shared conservative journal, originally $10; user approved $11.50 on November 26 to finish. Retain failed calls and reservations.
- Changes to runtime prompt behavior follow the unchanged-coach baseline, not vice versa.
- Keep test expectations independently derived; verify chess claims through legal replay and explicit assertions.
- No simultaneous simulator jobs. No issue #29 work or rollout.

## Review Focus

Check rubric leakage into candidate prompts; fairness to sound retreats and non-best moves; whether the rubric rewards verbosity or unsupported aggression; engine score perspective, draft application and history; whether failures disappear from metrics; budget/resume integrity; claims stronger than the measured evidence.

## Task 1: Freeze the judgment evaluation

**Files:** New `ChessTutorTests/Coaching/ModelEvaluation/CoachingJudgmentBenchmarkTests.swift`; `Tools/CoachingEval/benchmark/corpus.py`, `report.py`; new judge controls and tests; README.

**Interface:** A versioned 12-case native corpus uses the existing case schema, private brief and normal request builder. Existing runner/grade interfaces remain unchanged.

- [x] Add failing Python inventory/report tests; run them and observe rejection of the new schema.
- [x] Register the strict suite inventory without weakening old inventories; verify tests pass.
- [x] Add native scenarios, legal replay/factual checks, export and grader-isolation checks. Run the new native test class.
- [x] Add paired weak/strong judge controls bound to exported positions, plus necessary-retreat and tactical counterplay controls.
- [x] Record scoring policy and freeze source/controls before paid evaluation. Run Python suites and commit.

Expected: all tests pass; export preserves full legal history and private criteria never enter candidate requests.

## Task 2: Measure the unchanged coach

**Files:** Reuse existing runner, sensitivity, qualification, grading and budget components; add a small judgment launcher/report only where existing interfaces are insufficient.

**Interface:** Same frozen corpus and controls for every arm, one shared budget journal. `visual-v5` is the unchanged baseline.

- [x] Inspect qualification cache, validate judge sensitivity, then run the baseline with three repetitions.
- [x] Publish per-case judgment, failures, all other rubric dimensions, latency/cost and representative verbatim responses.
- [x] Inspect whether the new suite captures the reported weakness. Do not alter the frozen rubric to force a result.

Expected: evidence establishes the baseline before any candidate prompt edits; uncertainty and any judge disagreement remain visible.

## Task 3: Compare focused improvements

**Files:** New versioned tutor/config files; if justified, a small engine-evidence compiler and its unit tests; experiment report.

**Interface:** Same model/reasoning and app response contract. Prompt-only arm first, then same prompt with compact engine facts. No engine facts or grading criteria smuggled into baseline.

- [x] Based on observed baseline errors, create an evaluation-focused prompt and run on the frozen suite.
- [x] Write failing tests for engine perspective, draft root restriction, legal history, mate scores and bounded evidence; implement using library-managed UCI.
- [x] Pin/log engine settings and compare the engine arm within the remaining shared budget.
- [x] Assess budget for broader regression checks and label unrun checks: no paid historical regression suite was run; it remains a prerequisite for production promotion.

Expected: improved judgment without factual/interaction regressions, or an honest account of why an approach did not help.

## Task 4: Verify and hand off

**Files:** README, experiment findings and handoff notes.

- [x] Run complete Python suites and relevant native tests; inspect output.
- [x] Fresh independent whole-branch review; fix important findings with fail-first tests.
- [x] Checkpoint changes and provide measured results, costs, limitations and the recommended next step. No automatic deployment or merge.

Expected: reproducible artifacts and a concise evidence-backed recommendation.

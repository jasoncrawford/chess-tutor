# Resumable paid grading implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan.

**Goal:** Resume an interrupted paid grading run without paying again for completed judgments or hiding failed attempts.

**Architecture:** An optional, durable checkpoint owns per-call progress and exact run bindings. The existing grader keeps validation, blind comparison, publication, and rubric semantics. The CLI only supplies a checkpoint path.

**Tech Stack:** Existing Python standard library, unittest, benchmark modules.

**Spec:** This document's design below; scoped repair under the user's delegated benchmark-completion request.

## Design and global constraints

An actual judge renewal aborted after 95 successful calls when the provider returned an incomplete response. Inspection confirms `grade_run` similarly keeps all completed grades in memory and publishes only at the end. We must preserve expensive progress before starting the 626-call grading run. Qualification itself is unchanged in this repair.

- Add optional `checkpoint_path=None` to `grade_run` and `--checkpoint` to `grade`. Without it, existing behavior remains unchanged.
- New `JudgeCheckpoint` class in `Tools/CoachingEval/benchmark/grade_checkpoint.py` owns durable state. Grader integration must checkpoint each absolute and pairwise paid judgment only after full existing validation, including identity leakage validation. Cached judgments retain original measured latency, usage and cost, not replay timing.
- Bind checkpoint to the exact run manifest and candidate records, corpus manifest identity, complete judge configuration/prompt/schema identities, qualification bytes, and pricing identity. Reject mismatches, corruption, invalid cached output, symlinks and concurrent use before any paid request. Follow existing binding/validation patterns rather than inventing a broad storage framework.
- Write an in-flight marker atomically before each paid request. On success atomically store validated output and original call metrics. On failure preserve bounded metrics if available, otherwise one unknown-accounting attempt. On a later explicit resume, an interrupted in-flight call is an unknown-accounting failed attempt, never free.
- Combine failed-attempt metrics with the eventual successful cell's metrics using existing aggregation semantics: total call count/latency sum, unknown accounting keeps total cost null. Preserve attempt evidence in the checkpoint. A valid but low-scoring completed judgment must never be rerun or replaced.
- Existing completed output directories are never overwritten. Qualification must still be accepted, exact-bound and unexpired on each invocation. No automatic retries, altered thresholds, synthetic responses, candidate regeneration, production/app behavior changes, or hidden network calls.
- Single-writer protection is required; a crashed process must not leave an unrecoverable lock. Use standard-library advisory file locking in this macOS/Linux tool.
- No credentials, raw provider errors, or provider response IDs in checkpoints.

## Review focus

Failure after both an absolute and a pairwise success must preserve both. A process crash after send but before persistence must not appear free. Changed input/config/price/certificate must reject before calling the provider. Cached grades must be validated on read. Concurrent invocation must fail safely rather than duplicate paid calls.

### Task 1: Add durable opt-in grading checkpoints

**Files:** Create `Tools/CoachingEval/benchmark/grade_checkpoint.py`; modify `Tools/CoachingEval/benchmark/grader.py` and `cli.py`; add focused tests under `Tools/CoachingEval/tests/`; update the existing benchmark runbook under `docs/` (find the relevant current document).

**Interfaces:** `grade_run(..., checkpoint_path: Path | None = None)`; CLI `grade --checkpoint PATH`; a narrowly public `JudgeCheckpoint` class used only by the grader. Choose small internal method signatures appropriate to existing callbacks and validation; do not expose general caching or transport APIs.

- [x] Write and run failing tests for an interrupted fake-client run resumed to completion: previous successful absolute and pairwise calls are not repeated; low scores are preserved; metrics retain original latency and unsuccessful attempt cost uncertainty.
- [x] Add tests for unresolved in-flight state, mismatched bindings (including pricing and qualification), malformed cached grade, concurrent use, no-checkpoint compatibility, and output overwrite refusal before provider use.
- [x] Implement the minimal checkpoint and grader/CLI integration. Keep input/payload construction and validation in the grader; checkpoint owns persistence and single-writer invariants.
- [x] Run focused tests during iteration, then `python3 -m unittest discover -s Tools/CoachingEval/tests` and `python3 -m unittest discover -s CoachingServer/tests` once before committing. Existing dependencies are available in sibling `../stabilize-benchmark-judge/.venv/bin/python` if needed; use it without modifying that worktree.
- [x] Document starting/resuming the same grade command, never deleting checkpoints to obtain better scores, and incomplete accounting after interruption. Commit implementation, tests, runbook and this plan on this branch. No push/merge yet.

### Implementation record (2026-10-31)

Opt-in checkpointing is implemented with per-call durable in-flight markers,
validated output/attempt metrics, exact bindings, and a crash-recoverable advisory
lock. The grader still owns all judge payloads and output validation. The
qualification code, thresholds, candidates, launcher, and app are unchanged.

Verification: 29 focused grader/checkpoint/CLI tests passed; full evaluator
discovery passed 330 tests; full server discovery passed 49 tests, with no skips.
The existing sibling virtual environment was used read-only. Complete suites
required sandbox approval for their fake-provider loopback servers; the evaluator
also needed that environment's `bin` directory on `PATH` for a launcher subprocess.

Runbook ruling: the current command runbook is `Tools/CoachingEval/README.md`,
not under `docs/`. Updated it and added an operational note to the existing
`docs/reports/2026-09-06-benchmark-readiness.md`, preserving its historical claims.

## Execution ruling

This is an operational repair, not a change to the comparison or judge. The user has delegated implementation and model-selection judgment and explicitly waived further design review. The controller will review the change, run it against the frozen evidence, and merge only after all checks pass.

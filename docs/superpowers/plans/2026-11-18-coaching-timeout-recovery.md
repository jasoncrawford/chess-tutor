# Coaching timeout recovery implementation plan

> **For agentic workers:** Use superpowers:executing-plans for inline implementation and one final independent review.

**Goal:** Diagnose the family iPad's repeated provider timeouts, make failures understandable and recoverable, and retain useful diagnostics without changing coaching quality policy.

**Architecture:** Keep the existing Swift session/transport and Flask/provider boundaries. Reconstruct the logged position through the production chess rules and request builder. Add bounded metadata at the provider boundary; never log secrets, prompts, raw responses, or reasoning.

**Tech stack:** Swift/XCTest, Python/unittest, Flask, urllib, Vercel.

**Spec:** User-approved November 18 plan in this chat: reproduce the failed position, compare hosted/direct timing with a longer diagnostic deadline, fix only demonstrated causes, and preserve the game through timeout/retry.

## Global constraints

- Keep GPT-6 Astra, low reasoning, tutor-v13-experience-v6 and grounded-v4 unchanged.
- At most four paid diagnostic calls initially; no model sweep or judge run.
- No automatic retry that doubles paid requests; retry remains player-controlled.
- Do not change timeout budgets without evidence that additional time permits completion.
- No device reset, game deletion, or intervention in A16.

## Review focus

- A timeout while reading a response body must not become a generic transport failure.
- Provider metadata and exception strings must not expose response text or credentials.
- Failed follow-ups must preserve their staged move and last successful continuation.
- Cancellation or an obsolete result must not replace current coaching with an error.
- Real HTTP 504s and device network timeouts must both have useful recovery, without mislabeling other failures.

### Task 1: Incident replay and provider diagnostics

Files: `Tools/CoachingEval/openai_responses.py`, its tests, `CoachingServer/service.py`, server tests; a native incident-replay test; incident report under `docs/reports/`.

- [x] Reconstruct the logged 46-ply game through production rules and assert the resulting FEN. Export an opt-in neutral request for diagnostic replay.
- [x] Compare one hosted replay with the same direct request allowing up to 90 seconds. Retain timing/usage only; cap initial paid calls at four.
- [x] Write failing tests for header-vs-body timeout classification, safe phase/timing metadata and HTTP-status preservation in logs.
- [x] Implement minimal provider diagnostics and verify the tests pass. Do not speculate about upstream processing versus network stalls.
- [x] Run server and evaluation-tooling tests and commit the diagnostic work.

### Task 2: Recoverable client timeout

Files: hosted transport/contracts/session/projector, GameSession hosted error handling, corresponding XCTest files.

- [x] Write failing tests demonstrating HTTP 504 and URL timeout propagate distinctly to child-facing timeout copy, with retry and close controls.
- [x] Test retry after a failed staged-move follow-up preserves the move, game, and continuation; test cancellation/stale completion separately.
- [x] Implement typed timeout handling in the existing session/model layer. Keep other failures generic and do not render arbitrary server text.
- [x] Assess deadline changes: replay did not demonstrate that more time permits completion, so retain existing provider/client/platform deadlines and frozen benchmark configs.
- [x] Run native tests and Python suites, document measured results/limitations, obtain one independent review, and prepare the PR. Leave it unmerged for user review.

## Progress

- PR #25 merged with user approval; baseline `eb15f4a`.
- Existing server baseline: 65 tests passed.
- Incident: three warm-server initial requests timed out after ~30 seconds. Failing FEN `r2q2k1/ppp5/6N1/2PP1r1p/3Q4/5p2/PPP2PP1/R4RK1 w - - 0 24`.
- Four controlled probes completed; no production deadline or coaching policy changes.
- Final verification: 1,024 native, 66 server and 380 evaluation-tooling tests passed, with zero skips. All four independent-review findings fixed; the corrected URLSession fixture demonstrated the old error-body bug before the final green run.

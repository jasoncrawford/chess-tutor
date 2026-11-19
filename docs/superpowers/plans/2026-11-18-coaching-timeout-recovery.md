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
- Original investigation constraint: do not change timeout budgets without evidence that additional time permits completion. Superseded for the scoped mitigation by the user's November 19 approval to increase timeout headroom; do not claim this proves the cause of the original failures.
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

### Follow-up: isolate slow hosted processing

- [x] User approved pursuing the unresolved cause. Cap this follow-up at four additional paid requests, leaving the live deployment and quality policy unchanged.
- [x] Instrument connection, request-send, headers and completion in an opt-in diagnostic bundle, with the provider's reported processing time and safe client correlation IDs.
- [x] Run four initial-position replays in a disposable Vercel project in the same region, allowing 90 seconds for diagnosis. All four completed; the slowest provider call took 29.9 seconds, of which OpenAI reported 29.8 seconds processing. This supports provider-side variability but does not reproduce a >30-second call.
- [x] Remove temporary projects/deployments and verify production is unchanged. Document the incomplete final phase trace; make future log collection wait for terminal events before cleanup.
- [x] Verify and review the repeatable diagnostic tool; retain the evidence and limitations in PR #26. Fresh full suites: 72 server and 381 evaluation-tooling tests pass, zero skips. The single incremental review finding (failure-path log loss) was reproduced and fixed. No production deadline change or additional paid run is authorized by this checklist.

### Task 3: Coordinated timeout headroom (November 19 approval)

**Design:** The user accepted more timeout headroom. Use a 60-second provider
timeout, 70-second iPad request timeout, and 90-second Vercel function limit.
These are maximum waits, not imposed delays. Preserve one attempt, cancellation,
retry behavior, model, prompts, token limit and reasoning. More headroom may
prevent premature failures; it is not a speedup or a proven cure. Changing the
model was the alternative and is outside this change.

**Files:** Add `CoachingServer/configs/production-v2.json`, copied from the
accepted `astra-experience-v7-low-model.json` with only timeout 60. Point
`CoachingServer/deployment.json`, `vercel.json` and the development launcher to
it. Do not rewrite historical benchmark inputs or the legacy v1 configuration.
Change `HostedCoachingTransport.swift` to send timeout 70. Update deployment,
launcher and native transport tests and the incident report/runbook.

**Interfaces:** Existing configuration schema and transport API; no new API.

**Review focus:** Deployment/dev must select the same new config; the packaged
service must pass timeout 60 to the provider; client/platform must leave margins;
quality settings and historical benchmark configurations must not drift; no
automatic retry. The user subsequently explicitly authorized merging once green,
updating the connected family iPad and deploying the server change.

- [x] Write failing tests for the actual packaged provider call's 60-second budget, dev/production alignment and only-timeout difference from the accepted benchmark; update the native outgoing-request test for 70 seconds and cross-layer margins.
- [x] Run Python focused tests and the native transport test; expect failures at the old 30/35-second budgets.
- [x] Apply the coordinated configuration changes; update current runbook/status without rewriting historical experiment results.
- [x] Run complete Python and native suites; expect zero failures/skips. No paid requests or benchmark grading. Result: 1,013 native unit +11 UI +73 server +381 eval-tooling tests pass, zero skips.
- [x] Obtain one final review, address important findings with regressions, commit/push to PR #26. Review complete: stale `.env.example` override fixed after a failing regression; an extra packaged timeout/one-attempt negative test is a deferred minor (runtime attempt policy remains1).
- [ ] With the user's explicit authorization, merge only after GitHub checks pass, then update the connected family iPad and deploy the server configuration. Verify health and authentication without paid model calls. If the device is unavailable, clearly report that its old client cutoff remains until it is updated.

# Coaching Debounce and Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Combine rapid coaching input and provide useful exported client timing diagnostics.

**Architecture:** Keep scheduling in GameSession, driven by a stable SwiftUI task identity rather than restarting its network call on each tap. HostedCoachingSession retains only the selection-question context necessary for replacement answers. Injectable monotonic timing and a compact diagnostic sink make the real session behavior deterministic under tests.

**Tech Stack:** Swift 6, Observation, Swift concurrency, XCTest, existing DiagnosticsLog actor.

**Spec:** docs/superpowers/specs/2026-11-20-coaching-debounce-design.md

## Global Constraints

- Default board debounce 400 ms; opening Help and explicit controls immediate.
- One in-flight request and one latest pending request per GameSession; no automatic provider retries.
- No model/prompt/server protocol changes, paid API calls, deployment or iPad installation.
- Preserve immediate board behavior, stale-response guards, bounded diagnostic export and secret exclusions.

## Review Focus

- Rapid piece answers while thinking: final tap must replace the first, without restoring obsolete question semantics after a move.
- Input during a slow provider call: keep one in flight, discard obsolete response and its continuation, send latest state.
- Help close/reopen or cancelled resolver during a wait: no stranded request or unintended new call.
- Returning to exactly the previous board state: request identity still prevents applying stale advice.
- Export ordering and retention: event timestamps/sequences are captured at the interaction, with no arbitrary error/payload leakage.

### Task 1: Implement and verify batching with client evidence

**Files:**
- Modify: `ChessTutor/Game/GameSession.swift`, `ChessTutor/Coaching/Hosted/HostedCoachingSession.swift`
- Create: `ChessTutor/Coaching/Hosted/HostedCoachingTiming.swift`, `ChessTutor/Coaching/Hosted/HostedCoachingDiagnostics.swift`
- Modify: `ChessTutor/App/CoachingPanelAccessibilityFixture.swift` (same task identity as production)
- Test: `ChessTutorTests/Coaching/Hosted/HostedCoachingDebounceTests.swift`, existing hosted integration/session tests and diagnostics export tests
- Document: `docs/hosted-coaching-server.md` and handoff link

**Interfaces:**
- Consume existing `HostedCoachingTurning.turn`, `HostedCoachingCorrelation`, `DiagnosticsLog.append`, `GameSession.coachingRequestIdentity`.
- Produce injectable `HostedCoachingTiming` with monotonic `now`, async cancellable `sleep`, `debounceSeconds` (0.4 default); a safe `HostedCoachingDiagnostics.record(DiagnosticsEvent)` sink; existing UI request identity becomes stable across replacements in a batch.

- [x] Run baseline hosted session/integration/diagnostics tests. Expected: zero failures.
- [x] Add failing integration cases using the real GameSession and a controlled external provider. Test final piece answer replacement, staging during a pending answer, only-latest serialization, stale continuation rejection and close/cancel behavior. Assert actual outgoing request count/content and visible advice, not only scheduler flags.
- [x] Run new tests before implementation. Expected: fails on immediate calls/lost later answers or missing timing seam; observe the behavioral failure against current code first.
- [x] Implement trailing deadline and serialized resolver in GameSession; keep immutable request snapshots and all existing applicability checks. Preserve selection-question context only until superseded by another kind of learner action.
- [x] Add fake-clock boundary tests: no board call before 400 ms after final relevant interaction, immediate initial/control requests, cancelled waits, delayed flight plus latest queue, duplicate resolver entry, reopen while an old call finishes.
- [x] Add diagnostics through a fixed, compact field allowlist at input, scheduling, dispatch and result boundaries. Test real export contains matching IDs and event timing/combination counts and excludes secrets, payloads and raw errors. Verify asynchronous writer sequencing via event_sequence.
- [x] Run focused tests to green, then full native suite (unit + UI), server and eval-tooling suites with no paid provider. Expected: all pass, zero skips.
- [x] Document event meanings/export route and limitations; verify a clean diff check for the feature commit.
- [x] One independent whole-change review; fix important findings with RED→GREEN tests. Integration uses an unmerged PR.

## Verification commands

Use `xcodebuild test -project ChessTutor.xcodeproj -scheme ChessTutor -destination 'platform=iOS Simulator,id=2405386C-1815-48D7-BA99-53ED13F009A2' -derivedDataPath /tmp/chess-debounce-build -parallel-testing-enabled NO`, adding `-only-testing` for the named focused classes during development. Generate the Xcode project after adding sources. Run Python suites with the existing local Python environment: `python -m unittest discover -s CoachingServer/tests -q` and `python -m unittest discover -s Tools/CoachingEval/tests -q`.

## Review and verification notes

Final native suite: **1,028 unit + 12 UI tests passed**, zero failures/skips,
on the dedicated Coaching Smoke simulator. Server: **73 passed**. Eval tooling:
**381 passed** on the full repeat, with the intermittent interruption-test
failure noted below. The production diagnostic sink was also inspected in the
simulator's app data: correlated dispatch/application records and timings were
present, not merely captured through the test injection seam.

One independent whole-change review found cancellation and pending board-routing
gaps. Regression tests reproduced the session failures before correction:
cancelled work could be sent twice or leave newer input stranded, and the
authoritative board task lost its identification intent while thinking.
The real-board UI test separately checks that successive physical taps reach
the provider as the final piece-answer event. Ordinary physical taps already
passed before the routing correction; that UI check is integration coverage,
not proof of a reproduced gesture failure.

Opening Help, explicit controls, final-answer selection, quiet-interval
boundaries, in-flight serialization, obsolete continuation rejection,
close/reopen, cancellation, and compact diagnostic export have deterministic
tests with controlled providers. No paid calls, prompt changes, server rollout,
or family-iPad installation are included.

Decisions and limitations:

- 400 ms remains a hypothesis. Actual device traces must establish whether its
  added wait is worth the request reduction; no live cost/performance claim.
- The full Python eval suite passed 381 tests after installing the documented
  dependencies in this worktree. Its existing
  `test_interrupt_preserves_partial_corpus_export` also failed intermittently
  with `TimeoutExpired` on separate runs. The benchmark launcher is unchanged;
  this is flagged for separate investigation and can still cause CI failures.
- Deferred minor: closing Help and the eventual transport outcome can generate
  multiple outcome records for one request. Interpret cancellation reasons and
  count unique dispatched request IDs, not raw outcome lines. Separate logical
  invalidation/transport event names are deferred.

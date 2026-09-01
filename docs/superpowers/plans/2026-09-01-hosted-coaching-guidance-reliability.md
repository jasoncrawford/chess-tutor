# Hosted Coaching Guidance Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent literal formatting, answer-revealing focus, and avoidable validation 502s in hosted coaching.

**Architecture:** Add immutable `tutor-v12`, keep the response schema unchanged, and align Python and Swift semantic validation. Adopt v12 end to end while preserving v11 behavior for historical tests.

**Tech Stack:** Python 3 unittest, Swift/XCTest, XcodeGen, Flask hosted service.

## Global Constraints

- Do not edit `tutor-v11`; add `tutor-v12`.
- Keep provider output and rejected values out of logs.
- Keep 18 words as prompt guidance, not a hard validation failure.
- Enforce a 256-Unicode-code-point hard message bound.
- Discovery turns with `findEndangeredPiece` or `findSafeCapture` must have empty focus.
- Refer to visible control titles in plain text, optionally in quotation marks, never Markdown.

---

### Task 1: Prompt contract

**Files:**
- Create: `Tools/CoachingEval/prompts/tutor-v12.md`
- Create: `Tools/CoachingEval/tests/test_tutor_v12_prompt.py`

**Interfaces:**
- Produces: immutable `tutor-v12` system prompt consumed by the hosted server.

- [x] Write prompt tests that require plain or quoted control titles, forbid Markdown emphasis instructions, require empty focus for discovery response types, and retain concise-language guidance.
- [x] Run `python3 -B -m unittest Tools.CoachingEval.tests.test_tutor_v12_prompt -v` and verify RED because the prompt is absent.
- [x] Copy v11 to v12 and minimally revise the control-title, focus, and message-length guidance.
- [x] Rerun the focused test and verify GREEN.

### Task 2: Python response validation and diagnostics

**Files:**
- Modify: `Tools/CoachingEval/chess_native_response.py`
- Modify: `Tools/CoachingEval/tests/test_chess_native_response.py`
- Modify: `CoachingServer/tests/test_service.py`

**Interfaces:**
- Produces: `ChessNativeResponseContract.validation_issues(_:)` accepting 19-plus-word messages up to 256 code points and rejecting focus on discovery turns.
- Produces: safe categories `emptyMessage`, `messageTooLong`, `chessNotation`, and `discoveryFocus`.

- [x] Add failing Python tests for a 19-word valid message, a 257-code-point invalid message, both discovery response types rejecting focus, and the exact safe diagnostic categories.
- [x] Run the focused Python tests and verify the intended failures.
- [x] Replace the 18-word validator/grammar boundary with the 256-code-point validator boundary, add discovery-focus validation, and refine safe categories.
- [x] Rerun the focused Python tests and verify GREEN.

### Task 3: Swift response validation

**Files:**
- Modify: `ChessTutor/Coaching/ModelEvaluation/ModelCoachingChessNativeTurnValidator.swift`
- Modify: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingChessNativeTurnValidatorTests.swift`

**Interfaces:**
- Produces: device validation matching the Python 256-code-point and discovery-focus rules.

- [x] Add failing XCTest cases accepting 19 words, rejecting 257 Unicode code points, and rejecting focus for each discovery expected response.
- [x] Run the selected XCTest class and verify RED.
- [x] Implement the matching Swift validation rules using `unicodeScalars.count`.
- [x] Rerun the selected XCTest class and verify GREEN.

### Task 4: Adopt tutor-v12 end to end

**Files:**
- Modify: `CoachingServer/service.py`
- Modify: `CoachingServer/http_app.py`
- Modify: `CoachingServer/chess_native_compiler.py`
- Modify: `CoachingServer/tests/test_service.py`
- Modify: `CoachingServer/tests/test_http_app.py`
- Modify: `Tools/CoachingEval/tests/test_chess_native_compiler.py`
- Modify: `ChessTutor/Game/GameSession.swift`
- Modify: `ChessTutor/App/CoachingPanelAccessibilityFixture.swift`
- Modify: `ChessTutor/Coaching/ModelEvaluation/ModelCoachingChessNativeContextCompiler.swift`
- Modify: `ChessTutor/Coaching/Hosted/HostedCoachingTransport.swift`
- Modify: affected tests under `ChessTutorTests/Coaching/`.

**Interfaces:**
- Consumes: `tutor-v12` and the v11-compatible response compiler.
- Produces: requests and hosted responses labeled `tutor-v12`.

- [x] Update tests first to expect v12 server compilation, system prompt loading, app request creation, and transport acceptance; run them and verify RED.
- [x] Extend v11 compiler branches to v12 and update the production server/device version constants.
- [x] Rerun the affected Python and Swift tests and verify GREEN.

### Task 5: Verification and delivery

**Files:**
- Update: this plan's checkboxes after evidence is collected.

**Interfaces:**
- Produces: a reviewed branch and pull request for user merge.

- [x] Run all `CoachingServer` and `Tools/CoachingEval` Python tests.
- [x] Run affected Swift tests, then the full iPad scheme and standalone build.
- [x] Run `git diff --check` and scan the diff for private content.
- [x] Commit, push, open a PR without auto-merge, and monitor CI until merge-ready.

# Hosted Coaching Response Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make hosted coaching questions mechanically produce matching board interactions and response buttons, while safely diagnosing rejected provider turns.

**Architecture:** `expects` becomes the single authoritative interaction intent. The model may request only an optional Hint action; Swift derives all primary controls from `expects`, and Python/Swift compilers publish an identical tutor-v11 contract. Provider validation errors expose only bounded categories to logs.

**Tech Stack:** Swift 6, XCTest, Python 3.9, unittest, OpenAI Responses structured output, SwiftUI.

## Global Constraints

- Advice-quality changes beyond response-contract instructions are out of scope.
- Historical tutor-v6 through tutor-v10 contracts remain unchanged.
- Hosted runtime uses `tutor-v11`; response wire shape remains `hosted-coaching-turn.v3`.
- Rejected provider text and arbitrary rejected values must never enter logs.
- Every behavior change follows observed RED then GREEN.

---

### Task 1: Versioned compiler and response contract

**Files:**
- Modify: `ChessTutor/Coaching/ModelEvaluation/ModelCoachingChessNativeContracts.swift`
- Modify: `ChessTutor/Coaching/ModelEvaluation/ModelCoachingChessNativeContextCompiler.swift`
- Modify: `ChessTutor/Coaching/ModelEvaluation/ModelCoachingChessNativeTurnValidator.swift`
- Modify: `CoachingServer/chess_native_compiler.py`
- Modify: `Tools/CoachingEval/chess_native_response.py`
- Create: `Tools/CoachingEval/prompts/tutor-v11.md`
- Test: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingChessNativeContextCompilerTests.swift`
- Test: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingChessNativeTurnValidatorTests.swift`
- Test: `Tools/CoachingEval/tests/test_chess_native_compiler.py`
- Test: `Tools/CoachingEval/tests/test_chess_native_response.py`
- Create: `Tools/CoachingEval/tests/test_tutor_v11_prompt.py`

**Interfaces:**
- Produces: `ModelCoachingChessNativeExpectedResponse` cases `none`, `findEndangeredPiece`, `findSafeCapture`, `stageMove`, `judgeMoveSafety`, and `chooseWhetherToPlay`.
- Produces: tutor-v11 compilation with only optional `hint` in `Actions` and all six response types in `Expected response`.

- [x] **Step 1: Write failing Swift and Python tests** asserting the exact v11 action/response lists, legacy v10 stability, and the six response types.
- [x] **Step 2: Run the focused tests** and verify failures name missing tutor-v11 contract behavior.
- [x] **Step 3: Implement the minimal versioned compiler, enum, schema, grammar, and prompt changes.** The prompt must explain each response type using its exact visible control titles.
- [x] **Step 4: Run the focused tests** and verify all pass with zero skips.

### Task 2: Derive UI controls and record exact answers

**Files:**
- Modify: `ChessTutor/Coaching/Hosted/HostedCoachingPresentationProjector.swift`
- Modify: `ChessTutor/Coaching/Hosted/HostedCoachingSession.swift`
- Modify: `ChessTutor/Coaching/Hosted/HostedCoachingTransport.swift`
- Modify: `ChessTutor/Game/GameSession.swift`
- Test: `ChessTutorTests/Coaching/Hosted/HostedCoachingPresentationProjectorTests.swift`
- Test: `ChessTutorTests/Coaching/Hosted/HostedCoachingSessionTests.swift`
- Test: `ChessTutorTests/Coaching/Hosted/HostedCoachingTransportTests.swift`
- Test: `ChessTutorTests/Coaching/Hosted/HostedGameSessionIntegrationTests.swift`
- Test: `ChessTutorUITests/HostedCoachingContinuityUITests.swift`

**Interfaces:**
- Consumes: the tutor-v11 response types from Task 1.
- Produces: projector-derived board tasks/buttons and exact learner events for every response type.

- [x] **Step 1: Write failing projector/session/integration tests** for the four distinct button sets and the `noPieceNeedsHelp`, `noSafeCapture`, `looksSafe`, and move-decision paths.
- [x] **Step 2: Run the focused Swift tests** and verify the current generic contract fails them.
- [x] **Step 3: Implement derived controls.** Piece-finding types use `.identify`; `stageMove` uses `.move`; move judgment and move choice use no board task. Negative answers record the response-type-specific semantic action. `Try another move` keeps the existing move-removal flow.
- [x] **Step 4: Update transport/runtime pins to tutor-v11** and run focused Swift tests until green.

### Task 3: Safe 502 diagnostics

**Files:**
- Modify: `Tools/CoachingEval/chess_native_response.py`
- Modify: `CoachingServer/service.py`
- Test: `Tools/CoachingEval/tests/test_chess_native_response.py`
- Test: `CoachingServer/tests/test_service.py`

**Interfaces:**
- Produces: `ChessNativeResponseValidationError.categories`, a tuple drawn only from a fixed allowlist.
- Produces: `provider_response_failed ... reasons=<comma-separated categories>` without response content.

- [x] **Step 1: Write failing tests** that feed private malformed content and assert only fixed categories appear in captured logs.
- [x] **Step 2: Run focused Python tests** and verify the current log omits categories.
- [x] **Step 3: Implement the bounded validation exception and logging.** Map every detailed issue to a fixed category; parse/shape failures use fixed categories and never include values.
- [x] **Step 4: Run focused Python tests** and verify behavior and redaction are green.

### Task 4: Documentation and final verification

**Files:**
- Modify: `docs/hosted-coaching-server.md`
- Modify: `ChessTutor/App/CoachingPanelAccessibilityFixture.swift` only if its hosted wire fixture requires the new response enum.

**Interfaces:**
- Consumes: all completed production behavior.
- Produces: documented tutor-v11 runtime contract and final verification evidence.

- [x] **Step 1: Update hosted-server documentation** with tutor-v11 response types and safe 502 diagnostic meaning.
- [x] **Step 2: Run all CoachingServer and CoachingEval Python tests** with localhost access where required.
- [x] **Step 3: Run the full `ChessTutor` iPad (A16) test scheme** and extract exact xcresult counts.
- [x] **Step 4: Run a standalone iPad (A16) build, Python compilation, `git diff --check`, secret scan, and final status audit.**
- [ ] **Step 5: Commit, push, and open a PR** against `codex/chess-coaching-comparison`; do not auto-merge.

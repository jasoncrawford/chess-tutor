# Hosted Coaching Without Dead Ends Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent every hosted coaching turn from becoming inert by requiring a meaningful next interaction.

**Architecture:** Introduce immutable prompt version `tutor-v13`, remove `none` from its request-specific response schema in both compilers, and switch the hosted server and client to that contract. Keep legacy decoding compatibility while rejecting `none` at the live transport boundary.

**Tech Stack:** Swift, Python 3, XCTest, unittest, Flask, OpenAI Structured Outputs

## Global Constraints

- Preserve v10-v12 prompt behavior and compatibility.
- Do not remove the internal `ModelCoachingChessNativeExpectedResponse.none` case.
- Hosted v13 turns must always expose one meaningful next interaction.
- Add failing regressions before production changes; no skipped tests.

---

### Task 1: Define the v13 response contract

**Files:**
- Create: `Tools/CoachingEval/prompts/tutor-v13.md`
- Create: `Tools/CoachingEval/tests/test_tutor_v13_prompt.py`
- Modify: `CoachingServer/chess_native_compiler.py`
- Modify: `Tools/CoachingEval/tests/test_chess_native_compiler.py`
- Modify: `ChessTutor/Coaching/ModelEvaluation/ModelCoachingChessNativeContextCompiler.swift`
- Modify: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingChessNativeContextCompilerTests.swift`

**Interfaces:**
- Consumes: `compile_context(request, prompt_version)` and `ModelCoachingChessNativeContextCompiler.compile`.
- Produces: an exact five-value v13 expected-response list with no `none`.

- [ ] **Step 1: Write failing Python and Swift compiler/prompt tests**
- [ ] **Step 2: Run the focused tests and confirm they fail because v13 is unavailable or still includes `none`**
- [ ] **Step 3: Add tutor-v13 and exact Python/Swift compiler parity**
- [ ] **Step 4: Run the focused tests and confirm they pass**

### Task 2: Adopt v13 at both live boundaries

**Files:**
- Modify: `CoachingServer/service.py`
- Modify: `CoachingServer/http_app.py`
- Modify: `CoachingServer/tests/test_service.py`
- Modify: `ChessTutor/Game/GameSession.swift`
- Modify: `ChessTutor/Coaching/Hosted/HostedCoachingTransport.swift`
- Modify: `ChessTutorTests/Coaching/Hosted/HostedCoachingTransportTests.swift`
- Modify: `ChessTutor/App/CoachingPanelAccessibilityFixture.swift`

**Interfaces:**
- Consumes: tutor-v13 system prompt and v13 compiler contract.
- Produces: hosted responses labeled `tutor-v13`; live transport rejects `.none`.

- [ ] **Step 1: Write failing service and transport regressions for v13 and `none` rejection**
- [ ] **Step 2: Run them and observe the existing v12/accepted-`none` failures**
- [ ] **Step 3: Switch the server/client to v13 and add the defensive transport guard**
- [ ] **Step 4: Run focused Python and Swift tests**
- [ ] **Step 5: Run the full Python suites, full iPad tests, and standalone build**
- [ ] **Step 6: Commit, push, and open a PR against `codex/chess-coaching-comparison`**

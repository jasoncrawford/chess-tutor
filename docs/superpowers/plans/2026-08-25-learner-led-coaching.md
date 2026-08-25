# Learner-Led Coaching Reconciliation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every staged move supersede the position-level coaching question that preceded it, so coaching evaluates the learner's current move without requiring or acting on an obsolete absence answer.

**Architecture:** Preserve the existing authoritative `CoachingInteractionSnapshot`, exact advice identity, pure reconciler, session, projector, and SwiftUI boundaries. Narrow the inconsistency inside `CoachingReconciler.deriveTentativeMove`: once exact move advice exists, rejection paths derive move-specific revision, reply, or completion states and never restore Safe, Take, Wake, or check questions. `CoachingMoveOrigin` remains explanatory context, not workflow authority.

**Tech Stack:** Swift 5, SwiftUI Observation, XCTest, the existing local coaching advisor/evaluator, XcodeGen-discovered source targets, and iPad Simulator UAT.

## Global Constraints

- A non-nil tentative move permits only awaiting-advice, opponent-reply, revise-move, or complete stages.
- The previous Safe, Take, Wake, or check context may enrich copy but may not select the active stage.
- A quiet move staged from Take must receive its ordinary exact-move assessment.
- A rejected capture or unresolved safety move must remain staged while coaching gives move-specific revision feedback.
- `No safe capture` and every other position-level absence action must be absent while a move is staged.
- Removing or replacing the move must continue to invalidate exact-move advice and re-derive from the current snapshot.
- Do not add a Skip action, new prompt family, evaluator rule, workflow state, or SwiftUI chess conditional.
- Every behavior change starts with a failing test and no test may be skipped.
- Final verification must report zero failures and zero skips.

## File structure

- Modify `ChessTutor/Coaching/CoachingReconciler.swift`: stop origin-specific rejection from restoring position-level stages; distinguish an attempted capture from an unrelated quiet move; derive move-specific revision when the exact move should not be played.
- Modify `ChessTutorTests/Coaching/CoachingReconcilerTests.swift`: enforce the tentative-move stage invariant at the pure model boundary.
- Modify `ChessTutorTests/Coaching/CoachingSessionTests.swift`: cover Take-to-quiet-move, rejected capture, unresolved Safe, actions, and presentation coherence through a real `CoachingSession`.
- Modify `ChessTutorTests/Game/GameSessionCoachingTests.swift`: reproduce the user path through `GameSession` and a real `LocalCoachingAdvisor`, including preservation of the tentative board state.
- `ChessTutorTests/Coaching/CoachingGoldenTranscriptTests.swift` remains unchanged unless the focused command reports an exact golden case that stages a move yet expects a position-level question; migrate only that named case and retain all factual copy assertions.

---

### Task 1: Make tentative moves authoritative

**Files:**
- Modify: `ChessTutor/Coaching/CoachingReconciler.swift`
- Test: `ChessTutorTests/Coaching/CoachingReconcilerTests.swift`
- Test: `ChessTutorTests/Coaching/CoachingSessionTests.swift`
- Test: `ChessTutorTests/Game/GameSessionCoachingTests.swift`
- Conditional test migration: `ChessTutorTests/Coaching/CoachingGoldenTranscriptTests.swift`, limited to a named focused failure that expects a position-level question while a move is staged.

**Interfaces:**
- Consumes: `CoachingEpisodeState.interaction.tentativeMove`, exact `CoachingAdvice`, `CoachingMoveAssessment`, `CoachingMoveOrigin`, `LegalMoveGenerator.capture(for:in:)`, and existing feedback helpers.
- Produces: the existing `CoachingDerivedState`; no new public type or UI interface.
- Maintains: advice applicability still requires the exact move, origin, learner, committed state, and position revision.

- [ ] **Step 1: Run the focused baseline**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/CoachingReconcilerTests \
  -only-testing:ChessTutorTests/CoachingSessionTests \
  -only-testing:ChessTutorTests/GameSessionCoachingTests
```

Expected: exit 0 with zero failures and zero skips before new tests.

- [ ] **Step 2: Add a failing pure reconciler regression**

Add a test named `testTentativeMoveNeverReturnsToPositionLevelQuestion` to `CoachingReconcilerTests`. Build an episode with `nontrivialTakeClearAdvice`, `fallbackMove` staged, origin `.take`, and exact acceptable tentative advice. Assert the literal stage and actions-driving identity:

```swift
let result = CoachingReconciler().derive(learner: .white, episode: episode)
XCTAssertEqual(
    result.stage,
    .complete(move: CoachingTestFixtures.fallbackMove, origin: .take, concepts: [])
)
XCTAssertEqual(
    result.questionID,
    .complete(move: CoachingTestFixtures.fallbackMove, origin: .take)
)
```

Add table rows proving that an illegal move and an unresolved Safe move derive `.reviseMove(origin:)` rather than their prior position-level stages.

- [ ] **Step 3: Add failing session regressions**

In `CoachingSessionTests`, reproduce the obsolete flow:

```swift
var session = session()
session.receive(CoachingTestFixtures.nontrivialTakeClearAdvice)
XCTAssertEqual(session.stage, .takeChooseMove)

stage(CoachingTestFixtures.fallbackMove, in: &session)
session.receive(CoachingTestFixtures.adviceForTentativeMove(
    CoachingTestFixtures.fallbackMove,
    origin: .take,
    assessment: CoachingTestFixtures.acceptableAssessment(
        CoachingTestFixtures.fallbackMove
    )
))

XCTAssertEqual(
    session.stage,
    .complete(move: CoachingTestFixtures.fallbackMove, origin: .take, concepts: [])
)
XCTAssertEqual(
    session.presentation?.actions.map(\.action),
    [.done, .keepLooking, .stop]
)
XCTAssertFalse(session.presentation?.actions.map(\.action).contains(.noAnswer) == true)
```

Also update or add exact regressions for:

- a losing capture staged from Take deriving `.reviseMove(origin: .take)` with the existing concrete exchange feedback and no `.noAnswer`;
- a Safe-origin move that leaves danger unresolved deriving `.reviseMove(origin: .safe)` with the existing danger feedback;
- a noncapturing mate staged from Take completing as mate rather than returning to Take.

- [ ] **Step 4: Add a failing real `GameSession` regression**

Use `CoachingGoldenPosition.losingCapture.state` with `LocalCoachingAdvisor`. Start Help, resolve the position request, verify Take is current, stage the quiet king move `g1-h1`, and resolve its exact request. Assert user-visible behavior and board preservation:

```swift
XCTAssertFalse(
    session.coachingPresentation?.actions.map(\.action).contains(.noAnswer) == true
)
XCTAssertTrue(session.canFinishTurn)
XCTAssertEqual(session.state.board[sq("h1")]?.kind, .king)
XCTAssertNil(session.state.board[sq("g1")])
```

Use the existing public display-board and session properties; do not add a production accessor solely for this test. Compare `primaryMessage`, `instruction`, `observation`, actions, and focus with a second `GameSession` in which the same move was already staged before Help. The move-specific presentation must be equal even though the conversational history differs.

- [ ] **Step 5: Run the focused tests and record RED**

Run the Step 1 command.

Expected: failures show the current reconciler returning `.takeChooseMove` or `.safeResolve`, retaining `.noAnswer`, and/or discarding the move after the obsolete absence path. Compilation errors caused by test typos do not count; correct them until the tests fail on the intended behavior.

- [ ] **Step 6: Implement the minimal reconciler change**

In `CoachingReconciler.deriveTentativeMove`:

1. Replace the illegal-move call to `originDerivation` with a move-specific revision derivation.
2. Apply the Take-specific rejection only when the staged move is actually a capture.
3. Replace rejected-capture and unresolved-Safe calls to `originDerivation` with move-specific revision derivation.
4. Let quiet moves staged from Take continue through opponent-reply or completion using their exact assessment.

Add these private helpers, keeping all behavior inside the pure reconciler:

```swift
private func isCapture(
    _ move: Move,
    advice: CoachingAdvice
) -> Bool {
    LegalMoveGenerator.capture(
        for: move,
        in: advice.evaluation.request.committedState
    ) != nil
}

private func revisionDerivation(
    origin: CoachingMoveOrigin,
    move: Move,
    promptOverride: CoachingPrompt? = nil,
    feedback: CoachingFeedback? = nil
) -> CoachingDerivedState {
    derived(
        stage: .reviseMove(origin: origin),
        questionID: .revise(move: move, origin: origin),
        promptOverride: promptOverride,
        feedback: feedback
    )
}
```

Remove `originDerivation` if it has no remaining callers. Do not normalize or rewrite the stored origin, add state, or modify the projector to hide an incoherent result.

- [ ] **Step 7: Run focused GREEN and migrate only obsolete assertions**

Run the Step 1 command.

Expected: all selected tests pass with zero skips. If an existing assertion expects a position-level stage while a tentative move is present, update it to the move-specific stage and retain its exact factual feedback assertion. Investigate any other failure before changing it.

- [ ] **Step 8: Run the coaching acceptance slice**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/CoachingAcceptanceTests \
  -only-testing:ChessTutorTests/CoachingGoldenTranscriptTests \
  -only-testing:ChessTutorTests/CoachingPresentationProjectorTests
```

Expected: exit 0 with zero failures and zero skips. Any changed golden case must now describe the exact staged move and must not expose `.noAnswer`.

- [ ] **Step 9: Perform direct simulator UAT**

On the iPad (A16) simulator with the normal app, play and commit `1. e2-e4 e7-e6 2. f1-c4 a7-a6` through the ordinary board and Done path. White then has the legal but losing captures `Bxa6` and `Bxf7` and can instead develop the g1 knight.

1. Open Help in that exact position and confirm Take asks for a safe capture.
2. Stage `g1-f3` instead.
3. Confirm the panel switches to the assessment of `g1-f3` and `No safe capture` disappears.
4. Confirm the knight remains on f3 and Done/revision behavior matches the exact assessment.
5. Replace it with `b1-c3` and confirm coaching evaluates the replacement rather than restoring the Take question.
6. Remove the replacement and confirm coaching re-derives Take from the committed position.

Capture the move-specific state and inspect text, actions, board focus, and tentative board position. Use no permanent UAT-only product behavior.

- [ ] **Step 10: Run full verification**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
xcodebuild build -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
git diff --check
git status --short --branch
```

Read the final `.xcresult` summary and report exact passed, failed, skipped, and expected-failure counts. Expected: both Xcode commands exit 0, all tests pass, zero skips/expected failures, and the diff is limited to the reconciler and directly affected tests/docs.

- [ ] **Step 11: Commit and install the UAT build**

```bash
git add ChessTutor/Coaching/CoachingReconciler.swift \
  ChessTutorTests/Coaching/CoachingReconcilerTests.swift \
  ChessTutorTests/Coaching/CoachingSessionTests.swift \
  ChessTutorTests/Game/GameSessionCoachingTests.swift \
  ChessTutorTests/Coaching/CoachingGoldenTranscriptTests.swift
git commit -m "fix: follow the learner's staged move"
```

Omit unchanged paths from `git add`. Rebuild, install, and launch the normal app on the iPad (A16) simulator with no UAT arguments, leaving it open for product evaluation.

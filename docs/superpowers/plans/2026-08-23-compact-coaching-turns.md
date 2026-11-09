# Compact Coaching Turns Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every on-demand coaching state present one short, factually coherent turn whose message, instruction, optional observation, actions, and board focus all describe the current board.

**Architecture:** Preserve the evaluator → insight source → reconciler → projector/explainer → SwiftUI pipeline. Extend evaluator output with every legal opponent check/capture, bind purposes only to exact moves, make the reconciler decide whether an opponent scan has teaching value, and replace the independent response/headline/instruction presentation with primary/instruction/observation authored as one turn.

**Tech Stack:** Swift 6, SwiftUI, Observation, XCTest, XCUITest, xcodegen, iPadOS simulator.

## Global Constraints

- Coaching remains on-demand; the normal playable board remains the main experience.
- Child-facing language targets a child of about five.
- Render text in `primaryMessage → instruction → observation` order.
- `primaryMessage` is normally one sentence and roughly 4–12 words.
- `instruction` is one short imperative describing the next available action.
- `observation` is optional, factual, nonduplicative, and visually/accessibly last.
- No move is called safe before its exact tactical assessment completes.
- Every purpose, danger, attack, protection, and opponent relationship is bound to exact board evidence.
- Quiet positions with no legal opponent check or capture skip the opponent-response quiz.
- Tactically live positions ask for a piece that can “check your king or win one of your pieces”; a benign attack is acknowledged but not accepted as a winning reply.
- Prohibit child-facing “verified purpose,” “qualifying issue,” “immediate-response scan,” “material,” “cannot name a purpose,” “bring a new piece into the game,” and “more useful place.”
- Preserve deterministic, offline behavior. Do not add Stockfish, an LLM, settings, curriculum, or a new coaching mode.
- Every selection, drag, tentative move, replacement, removal, or undo rederives from the current snapshot.
- Run focused and full tests with zero failed, zero skipped, and zero expected failures.

---

### Task 1: Replace the three-text presentation with one compact turn contract

**Files:**

- Modify: `ChessTutor/Coaching/CoachingModels.swift`
- Modify: `ChessTutor/Coaching/LocalCoachingExplanationSource.swift`
- Modify: `ChessTutor/UI/Coaching/CoachingPanelView.swift`
- Modify: `ChessTutor/App/CoachingPanelAccessibilityFixture.swift`
- Modify: `ChessTutorTests/Coaching/LocalCoachingExplanationSourceTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingSessionTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingAcceptanceTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingGoldenTranscriptTests.swift`
- Modify: `ChessTutorTests/Game/GameSessionCoachingTests.swift`
- Modify: `ChessTutorTests/UI/CoachingPanelLayoutTests.swift`
- Modify: `ChessTutorTests/UI/CoachFocusOverlayTests.swift`
- Modify: `ChessTutorUITests/CoachingPanelAccessibilityUITests.swift`

**Interfaces:**

- Consumes: existing `CoachingPresentationContext` and `CoachingActionPresentation`.
- Produces:

```swift
struct CoachingPresentation: Equatable, Sendable {
    let primaryMessage: String
    let instruction: String?
    let observation: String?
    let hint: CoachingHint?
    let routine: [CoachingRoutineState]
    let actions: [CoachingActionPresentation]
    let boardTask: CoachingBoardTask
    let focus: CoachFocusPresentation
}
```

- [ ] **Step 1: Write failing model and accessibility-order tests**

Add a source test that constructs the new contract and a UI fixture assertion that expects the spoken labels in the new order:

```swift
func testPresentationUsesPrimaryInstructionObservationContract() {
    let presentation = CoachingPresentation(
        primaryMessage: "What could Black do next?",
        instruction: "Tap a black piece that could check your king or win one of your pieces.",
        observation: "That knight does not cause trouble here.",
        hint: nil,
        routine: [],
        actions: [],
        boardTask: .identify(allowsMoveRevision: true),
        focus: .empty
    )

    XCTAssertEqual(presentation.primaryMessage, "What could Black do next?")
    XCTAssertEqual(
        [presentation.primaryMessage, presentation.instruction, presentation.observation]
            .compactMap { $0 },
        [
            "What could Black do next?",
            "Tap a black piece that could check your king or win one of your pieces.",
            "That knight does not cause trouble here.",
        ]
    )
}
```

In `CoachingPanelAccessibilityUITests`, make the fixture use those three strings and assert:

```swift
XCTAssertEqual(
    semanticElements.map(\.label).filter(expectedLabels.contains),
    [expectedPrimary, expectedInstruction, expectedObservation,
     "Safe, current step", "Play this move", "Try another move", "Close coaching help"]
)
```

- [ ] **Step 2: Run the tests and capture RED**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/LocalCoachingExplanationSourceTests \
  -only-testing:ChessTutorTests/CoachingPanelLayoutTests \
  -only-testing:ChessTutorUITests/CoachingPanelAccessibilityUITests
```

Expected: compile failure because `primaryMessage` and `observation` do not exist.

- [ ] **Step 3: Migrate the presentation model without compatibility aliases**

Replace `response` with `observation` and `headline` with `primaryMessage` in `CoachingModels.swift`. Update the convenience initializer to accept the new names; do not leave computed `response`/`headline` aliases.

Update the explainer construction mechanically first:

```swift
return CoachingPresentation(
    primaryMessage: headline(for: context, base: base.headline),
    instruction: instruction(for: context, base: base.instruction),
    observation: responseCopy(for: context),
    hint: context.hint,
    routine: context.routine,
    actions: context.actions.map { actionPresentation(for: $0, context: context) },
    boardTask: context.boardTask,
    focus: context.focus
)
```

Task 4 will replace the temporary helper names and rewrite the content.

- [ ] **Step 4: Render and speak the fields in one fixed order**

Change `CoachingPanelView.conversation` to:

```swift
VStack(alignment: .leading, spacing: 8) {
    Text(presentation.primaryMessage)
        .font(AppTheme.coachingTitleFont)
        .foregroundStyle(AppTheme.ink)

    if let instruction = presentation.instruction {
        Text(instruction)
            .font(AppTheme.panelBodyFont)
            .foregroundStyle(AppTheme.ink.opacity(0.78))
    }

    if let observation = presentation.observation {
        Text(observation)
            .font(AppTheme.panelBodyFont)
            .foregroundStyle(AppTheme.ink.opacity(0.72))
    }
}
```

Give accessibility priorities `primary = 3`, `instruction = 2`, `observation = 1`. Update the fixture to exercise both a present and absent observation in tall and wide compositions.

- [ ] **Step 5: Migrate all coaching test call sites**

Update property assertions and `CoachingPresentation` initializers in the listed test files. Rename `CoachingGoldenTurn.response` to `observation` and `CoachingGoldenTurn.ask` to `primaryMessage` in the same mechanical migration so the golden model uses the same semantics as production:

```swift
XCTAssertEqual(presentation.primaryMessage, expected.primaryMessage)
XCTAssertEqual(presentation.instruction, expected.instruction)
XCTAssertEqual(presentation.observation, expected.observation)
```

Keep expected strings unchanged in this task; only their semantic field and visual order change.

- [ ] **Step 6: Run the contract and layout suites GREEN**

Run the command from Step 2, then:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/CoachingSessionTests \
  -only-testing:ChessTutorTests/CoachingAcceptanceTests \
  -only-testing:ChessTutorTests/GameSessionCoachingTests \
  -only-testing:ChessTutorTests/CoachingGoldenTranscriptTests
```

Expected: all selected tests pass with zero skips.

- [ ] **Step 7: Commit**

```bash
git add ChessTutor/Coaching/CoachingModels.swift ChessTutor/Coaching/LocalCoachingExplanationSource.swift ChessTutor/UI/Coaching/CoachingPanelView.swift ChessTutor/App/CoachingPanelAccessibilityFixture.swift ChessTutorTests/Coaching/LocalCoachingExplanationSourceTests.swift ChessTutorTests/Coaching/CoachingSessionTests.swift ChessTutorTests/Coaching/CoachingAcceptanceTests.swift ChessTutorTests/Coaching/CoachingGoldenTranscriptTests.swift ChessTutorTests/Game/GameSessionCoachingTests.swift ChessTutorTests/UI/CoachingPanelLayoutTests.swift ChessTutorTests/UI/CoachFocusOverlayTests.swift ChessTutorUITests/CoachingPanelAccessibilityUITests.swift
git commit -m "refactor: present one compact coaching turn"
```

---

### Task 2: Preserve every visible opponent check and capture as evidence

**Files:**

- Modify: `ChessTutor/Coaching/CoachingModels.swift`
- Modify: `ChessTutor/Coaching/MaterialTacticalEvaluator.swift`
- Modify: `ChessTutor/Coaching/LocalCoachingAdvisor.swift`
- Modify: `ChessTutorTests/Coaching/CoachingGoldenFixtures.swift`
- Modify: `ChessTutorTests/Coaching/CoachingGoldenPositionTests.swift`
- Modify: `ChessTutorTests/Coaching/MaterialTacticalEvaluatorTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingTestFixtures.swift`
- Modify: `ChessTutorTests/Coaching/CoachingReconcilerTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingSessionTests.swift`
- Modify: `ChessTutorTests/Game/GameSessionCoachingTests.swift`

**Interfaces:**

- Consumes: exact tentative `Move`, committed `GameState`, and existing capture/check generators.
- Produces:

```swift
struct CoachingOpponentActivity: Equatable, Sendable {
    let reply: Move
    let opponentPiece: Piece.Kind
    let checkingSquares: Set<Square>
    let capturedSquare: Square?
    let capturedPiece: Piece.Kind?
    let netGainForOpponent: Int?
    let immediateRecapture: Move?
    let isMate: Bool

    var isCheck: Bool { !checkingSquares.isEmpty }
    var canWinPiece: Bool { (netGainForOpponent ?? 0) >= 1 }
    var isQuestionAnswer: Bool { isCheck || canWinPiece }
}
```

Add `let opponentActivities: [CoachingOpponentActivity]` to `CoachingMoveAssessment`. Arrays use the existing rank-major `stableMoveKey` ordering. Update every memberwise initializer in production and test fixtures in the same task: the evaluator supplies the computed array, `LocalCoachingAdvisor` preserves it while adding concepts, and hand-built fixtures use an explicit empty or factual array. Do not add a default that could silently erase real activities.

- [ ] **Step 1: Add two factual teaching fixtures**

Add these positions and moves to `CoachingGoldenFixtures.swift`:

```swift
case openingBishopCanBeTaken
// rnbqkbnr/pppp1ppp/4p3/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2

case protectedPawnUnderBishopAttack
// rnbqkbnr/pppppppp/8/8/2B1P3/8/PPPP1PPP/RNBQK1NR b KQkq - 0 2

static let outsidePawn = Move(from: sq("h2"), to: sq("h4"))
static let openingKnightToF3 = Move(from: sq("g1"), to: sq("f3"))
static let bishopToA6 = Move(from: sq("f1"), to: sq("a6"))
static let blackPawnToE6 = Move(from: sq("e7"), to: sq("e6"))
static let bishopTakesE6 = Move(from: sq("c4"), to: sq("e6"))
```

In `CoachingGoldenPositionTests`, prove `b7xa6` is legal after `bishopToA6`, and `bishopTakesE6` is legal but has a negative net exchange after `blackPawnToE6`.

- [ ] **Step 2: Write failing evaluator tests**

```swift
func testQuietFirstKnightMoveHasNoOpponentActivity() throws {
    let assessment = try assessment(
        position: .starting,
        tentativeMove: CoachingGoldenMoves.openingKnightToF3
    )
    XCTAssertEqual(assessment.opponentActivities, [])
}

func testBishopOnA6RecordsWinningPawnReply() throws {
    let assessment = try assessment(
        position: .openingBishopCanBeTaken,
        tentativeMove: CoachingGoldenMoves.bishopToA6
    )
    let activity = try XCTUnwrap(assessment.opponentActivities.first {
        $0.reply == Move(from: sq("b7"), to: sq("a6"))
    })
    XCTAssertEqual(activity.opponentPiece, .pawn)
    XCTAssertEqual(activity.capturedPiece, .bishop)
    XCTAssertTrue(activity.canWinPiece)
}

func testProtectedPawnAttackIsVisibleButNotWinning() throws {
    let assessment = try assessment(
        position: .protectedPawnUnderBishopAttack,
        tentativeMove: CoachingGoldenMoves.blackPawnToE6
    )
    let activity = try XCTUnwrap(assessment.opponentActivities.first {
        $0.reply == CoachingGoldenMoves.bishopTakesE6
    })
    XCTAssertEqual(activity.capturedPiece, .pawn)
    XCTAssertLessThan(activity.netGainForOpponent ?? 0, 1)
    XCTAssertFalse(activity.isQuestionAnswer)
}
```

- [ ] **Step 3: Run RED**

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/CoachingGoldenPositionTests \
  -only-testing:ChessTutorTests/MaterialTacticalEvaluatorTests
```

Expected: compile failure because `opponentActivities` does not exist.

- [ ] **Step 4: Build activities once and derive issues from them**

In `MaterialTacticalEvaluator`, enumerate legal opponent moves after each learner move. Retain a move when it gives check or captures:

```swift
private func opponentActivities(after move: Move, in state: GameState) -> [CoachingOpponentActivity] {
    let afterMove = state.applyingUnchecked(move)
    return LegalMoveGenerator.allLegalMoves(in: afterMove)
        .compactMap { reply in
            let afterReply = afterMove.applyingUnchecked(reply)
            let postReplyCheckingSquares = LegalMoveGenerator.checkingPieceSquares(
                against: afterReply.sideToMove,
                in: afterReply.board
            )
            let estimate = captureEstimate(for: reply, in: afterMove)
            guard !postReplyCheckingSquares.isEmpty || estimate != nil,
                  let opponentPiece = afterMove.board[reply.from]?.kind else { return nil }
            return CoachingOpponentActivity(
                reply: reply,
                opponentPiece: opponentPiece,
                checkingSquares: visibleCheckingSquares(
                    for: postReplyCheckingSquares,
                    after: reply
                ),
                capturedSquare: estimate?.capturedSquare,
                capturedPiece: estimate?.capturedPiece.kind,
                netGainForOpponent: estimate?.netGainForMover,
                immediateRecapture: estimate?.immediateRecapture,
                isMate: !postReplyCheckingSquares.isEmpty
                    && LegalMoveGenerator.allLegalMoves(in: afterReply).isEmpty
            )
        }
        .sorted { stableMoveKey($0.reply) < stableMoveKey($1.reply) }
}
```

Pass the array into issue classification so existing `CoachingOpponentIssue` values remain the accepted check/winning-reply subset: `isMate` produces `.mateInOne`, a nonmate check produces `.check`, and `canWinPiece` produces `.materialLoss`. Preserve the current severity adjustments for favorable recaptures and unavoidable danger. Do not run a second, divergent legal-reply scan.

- [ ] **Step 5: Run GREEN and the evaluator regression suite**

Run the Step 3 command, then:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/LocalCoachingAdvisorTests \
  -only-testing:ChessTutorTests/CoachingReconcilerTests
```

Expected: all selected tests pass, zero skips.

- [ ] **Step 6: Commit**

```bash
git add ChessTutor/Coaching/CoachingModels.swift ChessTutor/Coaching/MaterialTacticalEvaluator.swift ChessTutor/Coaching/LocalCoachingAdvisor.swift ChessTutorTests/Coaching/CoachingGoldenFixtures.swift ChessTutorTests/Coaching/CoachingGoldenPositionTests.swift ChessTutorTests/Coaching/MaterialTacticalEvaluatorTests.swift ChessTutorTests/Coaching/CoachingTestFixtures.swift ChessTutorTests/Coaching/CoachingReconcilerTests.swift ChessTutorTests/Coaching/CoachingSessionTests.swift ChessTutorTests/Game/GameSessionCoachingTests.swift
git commit -m "feat: preserve visible opponent activity"
```

---

### Task 3: Derive tactical questions and purposes from the exact move

**Files:**

- Modify: `ChessTutor/Coaching/CoachingModels.swift`
- Modify: `ChessTutor/Coaching/CoachingState.swift`
- Modify: `ChessTutor/Coaching/LocalCoachingAdvisor.swift`
- Modify: `ChessTutor/Coaching/CoachingReconciler.swift`
- Modify: `ChessTutor/Coaching/CoachingSession.swift`
- Modify: `ChessTutor/Coaching/CoachingPresentationProjector.swift`
- Modify: `ChessTutor/Coaching/LocalCoachingExplanationSource.swift`
- Modify: `ChessTutorTests/Coaching/LocalCoachingAdvisorTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingReconcilerTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingSessionTests.swift`
- Modify: `ChessTutorTests/Coaching/LocalCoachingExplanationSourceTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingGoldenTranscriptTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingTestFixtures.swift`
- Modify: `ChessTutorTests/Game/GameSessionCoachingTests.swift`

**Interfaces:**

- Consumes: `CoachingMoveAssessment.opponentActivities`, exact concepts, and exact position Wake tasks.
- Produces:

```swift
enum CoachingCompletionIdea: Equatable, Sendable {
    // existing factual cases...
    case seemsSafe(suggestion: CoachingWakePurpose?)
}

enum CoachingFeedback: Equatable, Sendable {
    // existing factual cases...
    case benignOpponentActivity(CoachingOpponentActivity)
}

enum CoachingPrompt: Equatable, Sendable {
    // existing cases...
    case opponentReply(opponent: PieceColor, threatenedPiece: Piece.Kind?)
}
```

Replace `CoachingMoveAssessment.isAcceptable` with `isTacticallyAcceptable`. It means only: legal, required danger resolved, and no `.reviseMove` issue. Supported purpose remains a separate question answered by exact `concepts` or exact membership in a `CoachingWakeTask`.

- [ ] **Step 1: Write failing derived-state regressions**

```swift
func testQuietOpeningKnightCompletesWithoutOpponentQuiz() async throws {
    let session = try await tentativeSession(
        state: CoachingGoldenPosition.starting.state,
        move: CoachingGoldenMoves.openingKnightToF3,
        learner: .white
    )
    guard case .complete = session.stage else {
        return XCTFail("Expected direct completion, got \(session.stage)")
    }
    XCTAssertFalse(try XCTUnwrap(session.presentation).actions.map(\.action).contains(.looksSafe))
}

func testOutsidePawnDoesNotInheritCentralActivity() async throws {
    let session = try await tentativeSession(
        state: CoachingGoldenPosition.starting.state,
        move: CoachingGoldenMoves.outsidePawn,
        learner: .white
    )
    guard case let .complete(_, _, concepts) = session.stage else {
        return XCTFail("Expected completion")
    }
    XCTAssertFalse(concepts.contains(.improvesCentralActivity))
}

func testUnsafeBishopAsksForOpponentReplyBeforePurpose() async throws {
    let session = try await tentativeSession(
        state: CoachingGoldenPosition.openingBishopCanBeTaken.state,
        move: CoachingGoldenMoves.bishopToA6,
        learner: .white
    )
    XCTAssertEqual(
        session.stage,
        .opponentCheck(move: CoachingGoldenMoves.bishopToA6, origin: .fallback)
    )
}
```

Add a history test that reaches `h2–h4` after selecting a knight and asserts equality with direct `h2–h4` derivation.

- [ ] **Step 2: Write failing benign-activity tap regression**

In `CoachingGoldenTranscriptTests`, use its real-advisor `tentativeSession` helper to stage `e7–e6` for Black, enter opponent check, tap c4, and assert that the turn stays on the same question with the benign observation rather than the generic wrong-source observation:

```swift
var session = try await tentativeSession(
    state: CoachingGoldenPosition.protectedPawnUnderBishopAttack.state,
    move: CoachingGoldenMoves.blackPawnToE6,
    learner: .black
)
session.handle(.identificationTapped(sq("c4")))
XCTAssertEqual(
    session.stage,
    .opponentCheck(move: CoachingGoldenMoves.blackPawnToE6, origin: .fallback)
)
XCTAssertEqual(
    session.presentation?.observation,
    "That bishop attacks your pawn, but the pawn is protected."
)
XCTAssertEqual(session.presentation?.focus.paths, [CoachFocusPath(
    source: sq("c4"),
    destination: sq("e6"),
    role: .attacker
)])
```

- [ ] **Step 3: Run RED**

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/LocalCoachingAdvisorTests \
  -only-testing:ChessTutorTests/CoachingReconcilerTests \
  -only-testing:ChessTutorTests/CoachingSessionTests \
  -only-testing:ChessTutorTests/GameSessionCoachingTests
```

Expected: compile/assertion failures for the new assessment, feedback, and completion semantics.

- [ ] **Step 4: Separate tactical acceptability from purpose**

In `LocalCoachingAdvisor`, compute:

```swift
let isTacticallyAcceptable = assessment.isLegal
    && assessment.resolvesRequiredDanger
    && !assessment.opponentIssues.contains { $0.severity == .reviseMove }
```

Store this independently of `hasRecognizedPurpose`. Update every previous `isAcceptable` use to choose deliberately between tactical acceptability and exact-purpose membership.

- [ ] **Step 5: Gate the opponent question on visible tactical activity**

In `deriveTentativeMove`, keep legality, active Take, and unresolved Safe checks first. Remove the early Wake `noRecognizedPurpose` return. Then use:

```swift
if !assessment.opponentActivities.isEmpty {
    return deriveReply(
        move: move,
        origin: origin,
        assessment: assessment,
        advice: advice,
        positionAdvice: positionAdvice,
        answer: episode.evidence.replyAnswer,
        episode: episode
    )
}
return completionDerivation(move: move, origin: origin, assessment: assessment)
```

Within Looks-safe handling, accept only when there is no `CoachingOpponentIssue`. Benign activities do not invalidate Looks safe.

Change `.opponentReply` to carry an optional threatened piece. `CoachingPresentationProjector` may name a piece only when the accepted activities contain no checking alternative and every winning activity captures the same piece kind; otherwise it passes `nil` and the explainer uses the generic “check your king or win one of your pieces” instruction. This prevents the a6 scenario from requiring copy-layer inference while avoiding a false single-target claim in mixed positions.

- [ ] **Step 6: Remove the invented central-purpose fallback**

Delete the `?? .centralActivity` fallback in `originDerivation`. In `completionIdea`, return an exact constructive idea only when the move belongs to an exact task or concept. Otherwise return:

```swift
.seemsSafe(
    suggestion: origin == .wake
        ? initialWakePurpose(in: episode.knowledge.positionAdvice)
        : nil
)
```

The suggestion describes the tutor's still-valid task; it is not attached as the staged move's accomplishment.

- [ ] **Step 7: Recognize benign opponent taps without changing the answer**

In `CoachingSession.handleIdentificationTap`, after checking accepted issues, find an activity whose `reply.from` equals the tapped square. Record `.benignOpponentActivity(activity)` and leave `replyAnswer` unchanged. An unrelated enemy tap continues to record `.notReplyIssue`.

In `CoachingPresentationProjector`, when the current recorded feedback is `.benignOpponentActivity`, add that activity's source and destination to the current focus and render an attacker path between them. Keep the opponent question's normal candidate focus when Hint is active; the factual feedback path supplements rather than replaces it.

- [ ] **Step 8: Run GREEN and full coaching-state regression**

Run the Step 3 command. Then run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/CoachingAcceptanceTests \
  -only-testing:ChessTutorTests/CoachingGoldenTranscriptTests \
  -only-testing:ChessTutorTests/CoachingPresentationProjectorTests
```

Expected: all selected tests pass, zero skips.

- [ ] **Step 9: Commit**

```bash
git add ChessTutor/Coaching/CoachingModels.swift ChessTutor/Coaching/CoachingState.swift ChessTutor/Coaching/LocalCoachingAdvisor.swift ChessTutor/Coaching/CoachingReconciler.swift ChessTutor/Coaching/CoachingSession.swift ChessTutor/Coaching/CoachingPresentationProjector.swift ChessTutor/Coaching/LocalCoachingExplanationSource.swift ChessTutorTests/Coaching/LocalCoachingAdvisorTests.swift ChessTutorTests/Coaching/CoachingReconcilerTests.swift ChessTutorTests/Coaching/CoachingSessionTests.swift ChessTutorTests/Coaching/LocalCoachingExplanationSourceTests.swift ChessTutorTests/Coaching/CoachingGoldenTranscriptTests.swift ChessTutorTests/Coaching/CoachingTestFixtures.swift ChessTutorTests/Game/GameSessionCoachingTests.swift
git commit -m "fix: derive coaching from exact move evidence"
```

---

### Task 4: Rewrite coaching copy as compact, coherent turns

**Files:**

- Modify: `ChessTutor/Coaching/LocalCoachingExplanationSource.swift`
- Modify: `ChessTutorTests/Coaching/LocalCoachingExplanationSourceTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingSessionTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingAcceptanceTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingGoldenTranscriptTests.swift`
- Modify: `ChessTutorTests/Game/GameSessionCoachingTests.swift`

**Interfaces:**

- Consumes: one `CoachingPresentationContext` with exact prompt, feedback, actions, and focus.
- Produces: one `CoachingPresentation(primaryMessage:instruction:observation:...)` whose three strings are authored together.

- [ ] **Step 1: Write failing exact-copy tests for the reported paths**

```swift
func testCompactSafeAndOpeningCopy() {
    let safe = source.presentation(for: context(
        prompt: .complete(origin: .wake, idea: .seemsSafe(suggestion: nil))
    ))
    XCTAssertEqual(safe.primaryMessage, "That move seems safe.")
    XCTAssertEqual(safe.instruction, "Play it, or try another move.")
    XCTAssertNil(safe.observation)

    let opening = source.presentation(for: context(
        prompt: .complete(
            origin: .wake,
            idea: .seemsSafe(suggestion: .openingDevelopment(firstMove: true))
        )
    ))
    XCTAssertEqual(
        opening.primaryMessage,
        "That move seems safe, but a center pawn or knight is a simpler start."
    )
    XCTAssertEqual(opening.instruction, "Play it, or try another move.")
    XCTAssertNil(opening.observation)
}

func testBenignAttackBecomesLastObservation() {
    let activity = CoachingOpponentActivity(
        reply: Move(from: sq("c4"), to: sq("e6")),
        opponentPiece: .bishop,
        checkingSquares: [],
        capturedSquare: sq("e6"),
        capturedPiece: .pawn,
        netGainForOpponent: -2,
        immediateRecapture: Move(from: sq("d7"), to: sq("e6")),
        isMate: false
    )
    let presentation = source.presentation(for: context(
        prompt: .opponentReply(opponent: .white, threatenedPiece: nil),
        feedback: .benignOpponentActivity(activity)
    ))
    XCTAssertEqual(presentation.primaryMessage, "What could White do next?")
    XCTAssertEqual(
        presentation.instruction,
        "Tap a white piece that could check your king or win one of your pieces."
    )
    XCTAssertEqual(
        presentation.observation,
        "That bishop attacks your pawn, but the pawn is protected."
    )
}
```

Add exact tests for the a6 bishop question, found-pawn revision, a generic incorrect opponent tap, and the quiet `g1–f3` completion.

- [ ] **Step 2: Add corpus-wide compact-copy tests before implementation**

Add helpers to `CoachingGoldenTranscriptTests`:

```swift
private func normalizedClauses(_ text: String?) -> Set<String> {
    guard let text else { return [] }
    return Set(text
        .split(whereSeparator: { ".!?;".contains($0) })
        .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty })
}

private func wordCount(_ text: String) -> Int {
    text.split(whereSeparator: \.isWhitespace).count
}

private func sentenceCount(_ text: String) -> Int {
    text.filter { ".!?".contains($0) }.count
}

private func assertCompact(_ presentation: CoachingPresentation) {
    XCTAssertLessThanOrEqual(wordCount(presentation.primaryMessage), 18)
    XCTAssertLessThanOrEqual(sentenceCount(presentation.primaryMessage), 1)
    if let instruction = presentation.instruction {
        XCTAssertLessThanOrEqual(wordCount(instruction), 16)
        XCTAssertLessThanOrEqual(sentenceCount(instruction), 1)
    }
    if let observation = presentation.observation {
        XCTAssertLessThanOrEqual(wordCount(observation), 18)
        XCTAssertLessThanOrEqual(sentenceCount(observation), 1)
    }
    XCTAssertTrue(normalizedClauses(presentation.primaryMessage)
        .isDisjoint(with: normalizedClauses(presentation.instruction)))
    XCTAssertTrue(normalizedClauses(presentation.primaryMessage)
        .isDisjoint(with: normalizedClauses(presentation.observation)))
    XCTAssertTrue(normalizedClauses(presentation.instruction)
        .isDisjoint(with: normalizedClauses(presentation.observation)))
}
```

Extend the structural copy audit with all prohibited phrases from the global constraints.

- [ ] **Step 3: Run RED**

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/LocalCoachingExplanationSourceTests \
  -only-testing:ChessTutorTests/CoachingGoldenTranscriptTests
```

Expected: exact-copy, word-bound, duplication, and prohibited-language failures.

- [ ] **Step 4: Author the three fields as one turn**

Replace `baseCopy`, `headline`, `instruction`, and `responseCopy` composition with a single helper:

```swift
private struct AuthoredTurn {
    let primaryMessage: String
    let instruction: String?
    let observation: String?
}

private func authoredTurn(for context: CoachingPresentationContext) -> AuthoredTurn {
    let current = currentTaskCopy(for: context)
    return AuthoredTurn(
        primaryMessage: current.primaryMessage,
        instruction: current.instruction,
        observation: observationCopy(for: context.feedback, context: context)
    )
}
```

The current task owns primary/instruction. Feedback may supply only the observation unless the semantic state itself changes prompt—for example, a found dangerous reply uses `.opponentIssueRevise` as the current task and needs no duplicate observation.

- [ ] **Step 5: Rewrite the complete semantic copy table**

Use these mandatory forms:

```text
quiet safe completion:
  That move seems safe.
  Play it, or try another move.

opponent prompt:
  What could Black do next?
  Tap a black piece that could check your king or win one of your pieces.

unsafe bishop revision:
  Black's pawn could take your bishop.
  Try a different bishop move.

generic wrong opponent source observation:
  That piece cannot check or win a piece here.

opening entry:
  A center pawn or knight is a simple way to start.
  Tap a center pawn or knight.

selected knight:
  Moving this knight is called developing it.
  Move the knight.
```

Rewrite every remaining semantic enum output to satisfy the length and vocabulary contract. Preserve exact factual relationships for Safe, Take, check resolution, castling, protection, threats, and mobility. Do not shorten by removing the concrete source/target fact.

- [ ] **Step 6: Update the existing 47-case corpus and real-session expectations**

For every existing case, replace the expected turn with `primaryMessage`, `instruction`, and `observation` in their new roles. Remove generic strategy and implementation language rather than moving it between fields. Update session/acceptance/GameSession expectations in the same commit so the branch is green.

- [ ] **Step 7: Run GREEN**

Run the Step 3 command, then:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/CoachingSessionTests \
  -only-testing:ChessTutorTests/CoachingAcceptanceTests \
  -only-testing:ChessTutorTests/GameSessionCoachingTests
```

Expected: all selected tests pass, zero skips.

- [ ] **Step 8: Commit**

```bash
git add ChessTutor/Coaching/LocalCoachingExplanationSource.swift ChessTutorTests/Coaching/LocalCoachingExplanationSourceTests.swift ChessTutorTests/Coaching/CoachingSessionTests.swift ChessTutorTests/Coaching/CoachingAcceptanceTests.swift ChessTutorTests/Coaching/CoachingGoldenTranscriptTests.swift ChessTutorTests/Game/GameSessionCoachingTests.swift
git commit -m "fix: make coaching turns concise and coherent"
```

---

### Task 5: Lock the reported product paths and accessibility behavior

**Files:**

- Modify: `ChessTutorTests/Coaching/CoachingGoldenFixtures.swift`
- Modify: `ChessTutorTests/Coaching/CoachingGoldenTranscriptTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingAcceptanceTests.swift`
- Modify: `ChessTutorTests/Game/GameSessionCoachingTests.swift`
- Modify: `ChessTutorTests/UI/CoachingPanelLayoutTests.swift`
- Modify: `ChessTutor/App/CoachingPanelAccessibilityFixture.swift`
- Modify: `ChessTutorUITests/CoachingPanelAccessibilityUITests.swift`

**Interfaces:**

- Consumes: compact presentation, opponent activities, evidence-gated scan, and exact purpose binding from Tasks 1–4.
- Produces: an expanded named transcript corpus and permanent UI/accessibility regressions for the reported scenarios.

- [ ] **Step 1: Add the named corpus cases**

Add these ordered cases to `CoachingGoldenCase` and its exhaustive equality test:

```swift
.t1OutsidePawnMove,
.t11UnsafeBishopEntry,
.t11UnsafeBishopFound,
.t11BenignCaptureTap,
.t11BenignCaptureLooksSafe,
```

This expands the corpus from 47 to 52 cases. Drive all five through real `CoachingSession` instances; do not call the explainer directly.

- [ ] **Step 2: Write the five literal golden turns**

```swift
case .t1OutsidePawnMove:
    return turn(
        primary: "That move seems safe, but a center pawn or knight is a simpler start.",
        instruction: "Play it, or try another move.",
        observation: nil,
        actions: [.done, .keepLooking, .stop],
        boardTask: .none
    )

case .t11UnsafeBishopEntry:
    return turn(
        primary: "What could Black do next?",
        instruction: "Tap the black piece that could win your bishop.",
        observation: nil,
        actions: [.looksSafe, .hint, .stop],
        boardTask: .identify(allowsMoveRevision: true)
    )

case .t11UnsafeBishopFound:
    return turn(
        primary: "Black's pawn could take your bishop.",
        instruction: "Try a different bishop move.",
        observation: nil,
        actions: [.hint, .stop],
        boardTask: .move
    )

case .t11BenignCaptureTap:
    return turn(
        primary: "What could White do next?",
        instruction: "Tap a white piece that could check your king or win one of your pieces.",
        observation: "That bishop attacks your pawn, but the pawn is protected.",
        actions: [.looksSafe, .hint, .stop],
        boardTask: .identify(allowsMoveRevision: true)
    )

case .t11BenignCaptureLooksSafe:
    return turn(
        primary: "That move seems safe.",
        instruction: "Play it, or try another move.",
        observation: nil,
        actions: [.done, .keepLooking, .stop],
        boardTask: .none
    )
```

Assert exact emphasized squares, candidate squares, and paths for each state.

- [ ] **Step 3: Add direct-versus-history matrices**

For `h2–h4`, `Bf1–a6`, and `e7–e6`, compare direct derivation with histories containing prior knight, rook, friendly, enemy, empty-square, Hint, and replacement interactions. Compare the entire `CoachingPresentation` value.

- [ ] **Step 4: Add layout and VoiceOver tests for minimal and observed turns**

Extend the permanent fixture with:

```swift
case compactNoObservation
case compactWithObservation
```

Run each in tall, clockwise-wide, counterclockwise-wide, standard text, and Accessibility Extra Large. Assert the conversation labels are exactly primary → instruction → observation and all conversation/routine/action frames are disjoint and contained.

- [ ] **Step 5: Run the complete focused coaching slice**

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/MaterialTacticalEvaluatorTests \
  -only-testing:ChessTutorTests/LocalCoachingAdvisorTests \
  -only-testing:ChessTutorTests/CoachingReconcilerTests \
  -only-testing:ChessTutorTests/CoachingPresentationProjectorTests \
  -only-testing:ChessTutorTests/LocalCoachingExplanationSourceTests \
  -only-testing:ChessTutorTests/CoachingSessionTests \
  -only-testing:ChessTutorTests/CoachingAcceptanceTests \
  -only-testing:ChessTutorTests/CoachingGoldenPositionTests \
  -only-testing:ChessTutorTests/CoachingGoldenTranscriptTests \
  -only-testing:ChessTutorTests/GameSessionCoachingTests \
  -only-testing:ChessTutorTests/CoachingPanelLayoutTests \
  -only-testing:ChessTutorTests/CoachFocusOverlayTests \
  -only-testing:ChessTutorUITests/CoachingPanelAccessibilityUITests
```

Expected: all selected tests pass with zero skipped.

- [ ] **Step 6: Commit**

```bash
git add ChessTutorTests/Coaching/CoachingGoldenFixtures.swift ChessTutorTests/Coaching/CoachingGoldenTranscriptTests.swift ChessTutorTests/Coaching/CoachingAcceptanceTests.swift ChessTutorTests/Game/GameSessionCoachingTests.swift ChessTutorTests/UI/CoachingPanelLayoutTests.swift ChessTutor/App/CoachingPanelAccessibilityFixture.swift ChessTutorUITests/CoachingPanelAccessibilityUITests.swift
git commit -m "test: lock compact coaching transcripts"
```

---

### Task 6: Direct simulator UAT, full verification, and handoff

**Files:**

- Create: `docs/handoff/2026-08-23-compact-coaching-turns.md`
- Do not leave temporary UAT source files, launch gates, or project membership changes.

**Interfaces:**

- Consumes: final production and test behavior from Tasks 1–5.
- Produces: direct iPad evidence, final green gates, a normal installed build, and a concise durable handoff.

- [ ] **Step 1: Build and install on the dedicated iPad simulator**

```bash
xcodebuild build -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
xcrun simctl boot 'iPad (A16)'
xcrun simctl install 'iPad (A16)' DerivedData/ChessTutor/Build/Products/Debug-iphonesimulator/ChessTutor.app
xcrun simctl launch 'iPad (A16)' org.jasoncrawford.chesstutor
```

If the named simulator is already booted, treat simctl's already-booted result as informational and continue.

- [ ] **Step 2: Perform direct standard-text UAT in both compositions**

Exercise and capture:

```text
1. Help → g1 → f3: direct compact completion, no opponent quiz.
2. Help → h2 → h4: no center-purpose leak; safe/simple-start copy.
3. e4/e6 fixture → Bf1-a6 → b7 pawn: question, identification, concrete revision.
4. bishop c4 / Black e7-e6 → tap c4 → Looks safe: benign observation then compact completion.
5. Change knight → rook → h-pawn → knight and replace tentative moves: current-state equality.
```

Inspect text order, word wrapping, action labels, focus paths, selection changes, and conversation scrolling in tall and wide compositions.

- [ ] **Step 3: Repeat at Accessibility Extra Large**

Set `UICTContentSizeCategoryAccessibilityExtraLarge`, repeat all five routes in tall and wide compositions, and verify primary/instruction/observation remain readable and reachable. Restore content size to `large` afterward.

Store screenshots, exact commands, result summaries, and observations in this plan's ignored SDD workspace during execution.

- [ ] **Step 4: Run final focused, full, and build gates**

Run Task 5's exact focused command, then:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
xcodebuild build -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
git diff --check
git status --short
```

Expected: focused and full tests pass with zero failed/skipped/expected failures; build succeeds; no temporary harness is tracked.

- [ ] **Step 5: Write the durable handoff**

Create `docs/handoff/2026-08-23-compact-coaching-turns.md` containing:

```markdown
# Compact coaching turns handoff

- Presentation order: primary → instruction → optional observation.
- Opponent quiz appears only when a legal check or capture exists.
- Purposes are bound to exact pieces and moves.
- Safe-but-unclear copy is “That move seems safe.”
- Golden corpus: 52 named real-session cases.
- Verification: <record the final focused/full/build counts and simulator configuration>.
```

Replace the bracketed verification line with the actual observed counts before committing.

- [ ] **Step 6: Commit the handoff**

```bash
git add docs/handoff/2026-08-23-compact-coaching-turns.md
git commit -m "docs: hand off compact coaching turns"
```

- [ ] **Step 7: Leave the normal verified app ready for product review**

Reinstall the final standalone build, launch `org.jasoncrawford.chesstutor` without UAT arguments, visually confirm the starting board, and leave Simulator open at content size Large.

---

## Final completion gate

Before requesting integration review:

```bash
git diff --check
git status --short
git log --oneline -10
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
xcodebuild build -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Require:

- every reported path is locked through the real session pipeline;
- all 52 named transcript cases pass exact full-presentation assertions;
- primary/instruction/observation never duplicate or contradict one another;
- no tactical, safety, or strategic claim lacks exact evidence;
- both UI compositions pass standard and Accessibility Extra Large layout/VoiceOver checks;
- direct simulator UAT covers every revised path in both compositions and sizes;
- no generic or prohibited child-facing phrases remain;
- full test and build gates pass with zero skipped tests;
- tracked worktree is clean and the normal verified app is installed and open.

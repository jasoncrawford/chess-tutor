# Derived Coaching State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every coaching prompt, hint, focus, and action a fresh projection of the current board interaction plus valid pedagogical evidence, eliminating stale stage history such as the opening knight-to-rook source switch.

**Architecture:** Introduce a pure `CoachingReconciler` that receives an authoritative `CoachingInteractionSnapshot`, cached position/move advice, and minimal pedagogical evidence, then returns one `CoachingDerivedState`. Extract presentation-context construction into a pure projector, reduce `CoachingSession` to episode ownership and event reduction, and make `GameSession` synchronize coaching after every finalized selection or tentative-move mutation through one common path.

**Tech Stack:** Swift 5, SwiftUI Observation, XCTest, XcodeGen source-directory discovery, existing pure chess Core and local coaching advisor/explainer abstractions.

## Global Constraints

- Preserve all chess evaluation, piece values, candidate ranking, accepted-move policy, child-facing copy, hint ladders, board emphasis, panel layout, and source-independent advisor/explainer boundaries.
- Do not add Stockfish, online AI, new coaching routines, new prompts, new controls, or a generic workflow/rules engine.
- `GameSession` remains authoritative for selected square, tentative move, and chess-position state.
- `CoachingSession` may retain the last supplied interaction snapshot for comparison, but must never mutate a competing selected source or tentative move.
- A selection-only change must reuse committed-position advice and must not queue an advisor request.
- An advice result is applicable only to its exact committed position and, for move advice, its exact tentative move and origin.
- SwiftUI remains presentation-only; no reconciliation or chess-evaluation conditionals belong in `ChessBoardView`.
- Wake source selection must use ordinary board selection so candidate and noncandidate learner pieces are interpreted consistently.
- No routine-specific rewind table or backward-transition collection may be introduced.
- Every changed behavior begins with a failing test; no test may be disabled or skipped.
- Final verification must report zero test failures and zero skipped tests.

## File structure

- Create `ChessTutor/Coaching/CoachingState.swift`: internal value types for the interaction snapshot, cached knowledge, pedagogical evidence, question identity/progress, reconciler input, and derived result.
- Create `ChessTutor/Coaching/CoachingReconciler.swift`: pure reduction and derivation for Safe, Take, Wake, check, fallback, tentative assessment, opponent reply, revision, and completion.
- Create `ChessTutor/Coaching/CoachingPresentationProjector.swift`: pure mapping from one derived state to `CoachingPresentationContext`, including prompt, routine, actions, semantic hints, and focus.
- Modify `ChessTutor/Coaching/CoachingSession.swift`: retain only Help-episode ownership, input reduction, explainer invocation, and directive publication; remove transition-driven ownership of stage, Wake source, and tentative move.
- Modify `ChessTutor/Game/GameSession.swift`: supply authoritative snapshots, centralize synchronization after board mutations, and strengthen request applicability checks.
- Modify `ChessTutor/Coaching/CoachingModels.swift`: keep public coaching/advice/presentation contracts; move internal workflow-only declarations out when their new owner is introduced.
- Create `ChessTutorTests/Coaching/CoachingReconcilerTests.swift`: table-driven pure derivation and history-independence tests.
- Create `ChessTutorTests/Coaching/CoachingPresentationProjectorTests.swift`: coherent prompt/task/action/focus and question-progress tests.
- Modify `ChessTutorTests/Coaching/CoachingSessionTests.swift`: drive the new session with authoritative snapshots and verify minimal evidence reduction.
- Modify `ChessTutorTests/Game/GameSessionCoachingTests.swift`: cover real selection, clearing, tentative replacement, and asynchronous applicability.
- Modify `ChessTutorTests/Coaching/CoachingAcceptanceTests.swift`: update Wake taps to follow the ordinary board path and add end-to-end equivalence transcripts.
- Modify `ChessTutor.xcodeproj/project.pbxproj` via `xcodegen generate` after Tasks 1 and 2 add files. `project.yml` itself remains unchanged because both targets already include their source directories recursively.

---

### Task 1: Pure coaching state and step reconciliation

**Files:**
- Create: `ChessTutor/Coaching/CoachingState.swift`
- Create: `ChessTutor/Coaching/CoachingReconciler.swift`
- Create: `ChessTutorTests/Coaching/CoachingReconcilerTests.swift`
- Modify: `ChessTutor/Coaching/CoachingSession.swift` (move `CoachingStage`, `CoachingEvent`, and `CoachingDirective` declarations to the new state file without changing runtime behavior yet)
- Modify: `ChessTutor.xcodeproj/project.pbxproj` via `xcodegen generate`

**Interfaces:**
- Consumes: existing `CoachingAdvice`, `CoachingMoveAssessment`, `CoachingMoveOrigin`, `CoachingFeedback`, `CoachingPrompt`, `CoachingHint`, `CoachingPresentationContext`, `Move`, and `Square`.
- Produces:

```swift
struct CoachingInteractionSnapshot: Equatable, Sendable {
    let selectedSquare: Square?
    let tentativeMove: Move?
    let positionRevision: Int
}

enum CoachingQuestionID: Equatable, Sendable {
    case checkLocate
    case checkResolve(checker: Square)
    case safeLocate
    case safeAttacker(target: Square)
    case safeResolve(target: Square, attacker: Square)
    case take
    case wakeSource(purpose: CoachingWakePurpose)
    case wakeMove(source: Square, purpose: CoachingWakePurpose)
    case fallback
    case opponentReply(move: Move, origin: CoachingMoveOrigin)
    case revise(move: Move?, origin: CoachingMoveOrigin)
    case complete(move: Move, origin: CoachingMoveOrigin)
}

enum CoachingReplyAnswer: Equatable, Sendable {
    case looksSafe(move: Move)
    case issue(move: Move, issue: CoachingOpponentIssue)
}

struct CoachingPedagogicalEvidence: Equatable, Sendable {
    var checkingPiece: Square?
    var safeTarget: Square?
    var safeAttacker: Square?
    var confirmedSafeAbsence: Bool
    var confirmedTakeAbsence: Bool
    var tentativeOrigin: CoachingMoveOrigin?
    var replyAnswer: CoachingReplyAnswer?

    static let empty = CoachingPedagogicalEvidence(
        checkingPiece: nil,
        safeTarget: nil,
        safeAttacker: nil,
        confirmedSafeAbsence: false,
        confirmedTakeAbsence: false,
        tentativeOrigin: nil,
        replyAnswer: nil
    )
}

struct CoachingKnowledge: Equatable, Sendable {
    var positionAdvice: CoachingAdvice?
    var tentativeAdvice: CoachingAdvice?
    var unsupportedContext: CoachingRequest.Context?
    var pendingContext: CoachingRequest.Context?
}

struct CoachingQuestionProgress: Equatable, Sendable {
    var questionID: CoachingQuestionID?
    var hintLevel: Int
    var missesAtCurrentLevel: Int
    var feedback: CoachingFeedback?
    var feedbackAnchor: CoachingFeedbackAnchor?
    var pulseID: Int
}

enum CoachingFeedbackAnchor: Equatable, Sendable {
    case identification(square: Square)
    case selection(square: Square?)
    case tentativeMove(Move)
    case action(CoachingAction)
}

struct CoachingEpisodeState: Equatable, Sendable {
    var knowledge: CoachingKnowledge
    var evidence: CoachingPedagogicalEvidence
    var progress: CoachingQuestionProgress
    var interaction: CoachingInteractionSnapshot
}

struct CoachingDerivedState: Equatable, Sendable {
    let stage: CoachingStage
    let questionID: CoachingQuestionID?
    let promptOverride: CoachingPrompt?
    let derivedFeedback: CoachingFeedback?
    let requestedAdvice: CoachingRequest.Context?
}

struct CoachingReconciler: Sendable {
    func derive(
        learner: PieceColor,
        episode: CoachingEpisodeState
    ) -> CoachingDerivedState
}
```

- `CoachingStage` remains observable to existing tests during migration, but only `CoachingReconciler.derive` may choose it after Task 3.

- [ ] **Step 1: Add failing Wake derivation tests**

Create `CoachingReconcilerTests` with a helper that supplies `startingPositionAdvice` and varies only the snapshot:

```swift
func testWakeStepIsDerivedFromCurrentSelection() {
    let reconciler = CoachingReconciler()

    XCTAssertEqual(
        reconciler.derive(
            learner: .white,
            episode: episode(advice: CoachingTestFixtures.startingPositionAdvice)
        ).stage,
        .wakeChoosePiece(purpose: .openingDevelopment(firstMove: true))
    )

    XCTAssertEqual(
        reconciler.derive(
            learner: .white,
            episode: episode(
                advice: CoachingTestFixtures.startingPositionAdvice,
                selectedSquare: CoachingTestFixtures.openingKnight
            )
        ).stage,
        .wakeChooseMove(
            piece: CoachingTestFixtures.openingKnight,
            purpose: .openingDevelopment(firstMove: true)
        )
    )

    let blockedRook = Square(file: .a, rank: 1)
    let blocked = reconciler.derive(
        learner: .white,
        episode: episode(
            advice: CoachingTestFixtures.startingPositionAdvice,
            selectedSquare: blockedRook
        )
    )
    XCTAssertEqual(
        blocked.stage,
        .wakeChoosePiece(purpose: .openingDevelopment(firstMove: true))
    )
    XCTAssertEqual(blocked.derivedFeedback, .blockedWakePiece(piece: .rook))
}
```

Also add table rows for a different recommended source, a movable noncandidate learner piece, an opponent piece, and cleared selection. Assert `questionID` as well as `stage` and `derivedFeedback`.

- [ ] **Step 2: Add failing prerequisite-validation tests**

Use `multipleDangerAdvice` to prove that the derivation ignores invalid evidence rather than trusting history:

```swift
func testSafeEvidenceIsUsedOnlyWhileItsPrerequisitesRemainValid() {
    var episode = episode(advice: CoachingTestFixtures.multipleDangerAdvice)
    episode.evidence.safeTarget = CoachingTestFixtures.whiteQueen
    episode.evidence.safeAttacker = CoachingTestFixtures.blackBishop
    XCTAssertEqual(
        CoachingReconciler().derive(learner: .white, episode: episode).questionID,
        .safeResolve(
            target: CoachingTestFixtures.whiteQueen,
            attacker: CoachingTestFixtures.blackBishop
        )
    )

    episode.evidence.safeTarget = CoachingTestFixtures.whiteRook
    XCTAssertEqual(
        CoachingReconciler().derive(learner: .white, episode: episode).questionID,
        .safeAttacker(target: CoachingTestFixtures.whiteRook)
    )
}
```

Add cases for an invalid checker, a Safe/Take absence flag against advice that contains an answer, and reply evidence for a different tentative move.

- [ ] **Step 3: Add failing tentative-move derivation tests**

Cover no applicable advice → awaiting/request, exact assessment → opponent reply, illegal/unresolved/unpurposeful assessment → revision with concrete prompt or feedback, correct reply answer → completion, and mismatched move advice → ignored/requested:

```swift
func testTentativeAdviceMustMatchExactCurrentMoveAndOrigin() {
    let currentMove = CoachingTestFixtures.openingKnightMove
    let staleMove = CoachingTestFixtures.alternateKnightMove
    var episode = episode(
        advice: CoachingTestFixtures.startingPositionAdvice,
        selectedSquare: currentMove.to,
        tentativeMove: currentMove
    )
    episode.evidence.tentativeOrigin = .wake
    episode.knowledge.tentativeAdvice = CoachingTestFixtures.adviceForTentativeMove(
        staleMove,
        origin: .wake,
        assessment: CoachingTestFixtures.acceptableAssessment(
            staleMove,
            concepts: [.developsKnightOrBishop]
        )
    )

    let result = CoachingReconciler().derive(learner: .white, episode: episode)
    XCTAssertEqual(result.stage, .awaitingAdvice(origin: .wake))
    XCTAssertEqual(result.requestedAdvice, .tentativeMove(origin: .wake))
}
```

- [ ] **Step 4: Regenerate the Xcode project**

```bash
xcodegen generate
```

Expected: `ChessTutor.xcodeproj/project.pbxproj` includes both new app sources and `CoachingReconcilerTests.swift` in the unit-test target.

- [ ] **Step 5: Run the focused tests to record RED**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/CoachingReconcilerTests
```

Expected: compilation fails because the new state and reconciler types do not exist.

- [ ] **Step 6: Implement the value types and pure derivation**

Move the internal workflow enums from `CoachingSession.swift` into `CoachingState.swift`. Implement `CoachingReconciler.derive` in this order:

```swift
func derive(learner: PieceColor, episode: CoachingEpisodeState) -> CoachingDerivedState {
    if let move = episode.interaction.tentativeMove {
        return deriveTentativeMove(move, learner: learner, episode: episode)
    }
    guard let advice = applicablePositionAdvice(in: episode) else {
        return episode.knowledge.unsupportedContext == .start
            ? fallbackDerivation()
            : awaitingPositionAdviceDerivation(pending: episode.knowledge.pendingContext)
    }
    if !advice.checkingPieces.isEmpty {
        return deriveCheck(advice: advice, evidence: episode.evidence)
    }
    if requiresSafeScan(advice: advice, evidence: episode.evidence) {
        return deriveSafe(advice: advice, evidence: episode.evidence)
    }
    if requiresTakeScan(advice: advice, evidence: episode.evidence) {
        return takeDerivation()
    }
    return deriveWakeOrFallback(
        learner: learner,
        advice: advice,
        interaction: episode.interaction
    )
}
```

Validate every evidence field against the current applicable advice before deriving a later question. Derive Wake source and purpose from `interaction.selectedSquare`; when a tentative move exists, derive its source from `tentativeMove.from`.

- [ ] **Step 7: Run focused tests and the existing session suite**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/CoachingReconcilerTests -only-testing:ChessTutorTests/CoachingSessionTests
```

Expected: all selected tests pass with zero skips. Existing runtime behavior remains unchanged because `CoachingSession` is not yet using the reconciler.

- [ ] **Step 8: Commit Task 1**

```bash
git add ChessTutor/Coaching/CoachingState.swift ChessTutor/Coaching/CoachingReconciler.swift ChessTutor/Coaching/CoachingSession.swift ChessTutorTests/Coaching/CoachingReconcilerTests.swift ChessTutor.xcodeproj/project.pbxproj
git commit -m "refactor: derive coaching steps from current facts"
```

---

### Task 2: Pure presentation projection and question-scoped progress

**Files:**
- Create: `ChessTutor/Coaching/CoachingPresentationProjector.swift`
- Create: `ChessTutorTests/Coaching/CoachingPresentationProjectorTests.swift`
- Modify: `ChessTutor/Coaching/CoachingSession.swift`
- Test: `ChessTutorTests/Coaching/CoachingSessionTests.swift`
- Modify: `ChessTutor.xcodeproj/project.pbxproj` via `xcodegen generate`

**Interfaces:**
- Consumes: `CoachingDerivedState`, `CoachingEpisodeState`, and existing `CoachingExplaining`.
- Produces:

```swift
struct CoachingPresentationProjector: Sendable {
    func context(
        learner: PieceColor,
        derived: CoachingDerivedState,
        episode: CoachingEpisodeState
    ) -> CoachingPresentationContext?
}

extension CoachingQuestionProgress {
    mutating func enter(_ questionID: CoachingQuestionID?)
    mutating func recordMiss(
        _ feedback: CoachingFeedback,
        anchor: CoachingFeedbackAnchor
    )
    mutating func revealNextHint(available: [CoachingHint])
    mutating func discardFeedbackInvalidated(
        by interaction: CoachingInteractionSnapshot
    )
}
```

- `enter` resets hint, misses, feedback, and hint-only focus exactly when semantic question identity changes.
- Selection-anchored feedback remains only while the same selection is current; tentative-move feedback remains only for the exact staged move.
- Correct-absence feedback may be deliberately attached once to the newly derived Take or Wake question, matching existing copy, but cannot survive the next unrelated action.

- [ ] **Step 1: Add failing question-progress tests**

```swift
func testQuestionChangeResetsHintMissAndFeedbackTogether() {
    var progress = CoachingQuestionProgress(
        questionID: .wakeSource(purpose: .openingDevelopment(firstMove: true)),
        hintLevel: 1,
        missesAtCurrentLevel: 2,
        feedback: .blockedWakePiece(piece: .rook),
        feedbackAnchor: .selection(square: Square(file: .a, rank: 1)),
        pulseID: 4
    )

    progress.enter(.wakeMove(
        source: CoachingTestFixtures.openingKnight,
        purpose: .openingDevelopment(firstMove: true)
    ))

    XCTAssertEqual(progress.hintLevel, 0)
    XCTAssertEqual(progress.missesAtCurrentLevel, 0)
    XCTAssertNil(progress.feedback)
    XCTAssertNil(progress.feedbackAnchor)
}
```

Add cases proving that selection feedback disappears when selection changes or clears, identification feedback survives a presentation rebuild but is replaced by the next identification attempt, and hint progress survives an idempotent reconciliation of the same question.

- [ ] **Step 2: Add failing projection coherence tables**

For representative `checkLocate`, `safeAttacker`, `safeResolve`, `take`, `wakeSource`, `wakeMove`, `opponentReply`, `revise`, and `complete` derivations, assert in one row:

```swift
XCTAssertEqual(context.prompt, expectedPrompt)
XCTAssertEqual(context.boardTask, expectedTask)
XCTAssertEqual(context.actions, expectedActions)
XCTAssertEqual(context.routine, expectedRoutine)
XCTAssertEqual(context.hint, expectedHint)
XCTAssertEqual(context.focus, expectedFocus)
```

Require `.move` for both Wake source and Wake destination. Require `.identify` only for actual identification questions. Verify that Safe target–attacker focus is present only when both evidence values validate against current advice.

- [ ] **Step 3: Regenerate the Xcode project**

```bash
xcodegen generate
```

Expected: `ChessTutor.xcodeproj/project.pbxproj` includes the new projector app source and test file in their targets.

- [ ] **Step 4: Run the focused projector tests to record RED**

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/CoachingPresentationProjectorTests
```

Expected: compilation fails because the projector and progress operations do not exist.

- [ ] **Step 5: Extract presentation projection from `CoachingSession`**

Move the existing implementations of these responsibilities, preserving their authored behavior:

- stage-to-prompt mapping;
- routine strip state;
- board task and actions;
- finite semantic hint ladders;
- persistent and hint-only focus;
- candidate source, destination, and path calculation;
- opponent-issue paths;
- completion idea calculation.

The projector must consume only its parameters. It must not read mutable `CoachingSession` fields or invoke the explainer.

- [ ] **Step 6: Implement semantic question progress**

Implement `enter`, miss recording, hint advancement, and feedback-anchor invalidation. Do not use stage names as ad hoc reset call sites; all resets flow through `questionID` comparison.

- [ ] **Step 7: Temporarily delegate existing session presentation building to the projector**

Keep the current transition engine for this task, but construct an equivalent `CoachingEpisodeState` view and call:

```swift
let derived = CoachingDerivedState(
    stage: stage,
    questionID: projectorQuestionID,
    promptOverride: promptOverride,
    derivedFeedback: nil,
    requestedAdvice: nil
)
let context = projector.context(learner: learner, derived: derived, episode: episodeView)
presentation = context.map { explainer.presentation(for: $0) }
```

Keep this migration adapter private to `CoachingSession`; Task 3 deletes it when the reconciler becomes authoritative.

- [ ] **Step 8: Run projection, explanation, session, and focus suites**

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/CoachingPresentationProjectorTests -only-testing:ChessTutorTests/LocalCoachingExplanationSourceTests -only-testing:ChessTutorTests/CoachingSessionTests -only-testing:ChessTutorTests/CoachFocusOverlayTests
```

Expected: all selected tests pass with zero skips and no copy changes.

- [ ] **Step 9: Commit Task 2**

```bash
git add ChessTutor/Coaching/CoachingPresentationProjector.swift ChessTutor/Coaching/CoachingSession.swift ChessTutorTests/Coaching/CoachingPresentationProjectorTests.swift ChessTutorTests/Coaching/CoachingSessionTests.swift ChessTutor.xcodeproj/project.pbxproj
git commit -m "refactor: project coaching presentation from one state"
```

---

### Task 3: Reduce `CoachingSession` to snapshots and pedagogical evidence

**Files:**
- Modify: `ChessTutor/Coaching/CoachingState.swift`
- Modify: `ChessTutor/Coaching/CoachingReconciler.swift`
- Modify: `ChessTutor/Coaching/CoachingSession.swift`
- Modify: `ChessTutorTests/Coaching/CoachingSessionTests.swift`
- Test: `ChessTutorTests/Coaching/CoachingReconcilerTests.swift`

**Interfaces:**
- Replaces the old transition-oriented event surface with:

```swift
enum CoachingEvent: Equatable, Sendable {
    case identificationTapped(Square)
    case interactionChanged(CoachingInteractionSnapshot)
    case actionChosen(CoachingAction)
}

struct CoachingSession: Sendable {
    init(
        learner: PieceColor,
        interaction: CoachingInteractionSnapshot,
        initialContext: CoachingRequest.Context,
        explainer: any CoachingExplaining = LocalCoachingExplanationSource()
    )

    mutating func receive(
        _ advice: CoachingAdvice,
        interaction: CoachingInteractionSnapshot
    ) -> [CoachingDirective]

    mutating func receiveUnsupportedPosition(
        for context: CoachingRequest.Context,
        interaction: CoachingInteractionSnapshot
    ) -> [CoachingDirective]

    mutating func handle(_ event: CoachingEvent) -> [CoachingDirective]
}
```

- `CoachingDirective` retains only `.requestAdvice(context:)`, `.stop(preservingTentativeMove:)`, and `.commitWithExistingDonePath`; remove `.selectSquare` after callers migrate in Task 4.
- `stage`, `presentation`, `hintLevel`, and `missesAtCurrentLevel` remain read-only projections for tests and UI consumers.

- [ ] **Step 1: Add the reported history-independence regression at session level**

```swift
func testWakeRookAfterKnightMatchesRookAsFirstSelection() {
    let rook = Square(file: .a, rank: 1)
    var direct = openingSession()
    direct.handle(.interactionChanged(snapshot(selected: rook)))

    var switched = openingSession()
    switched.handle(.interactionChanged(snapshot(
        selected: CoachingTestFixtures.openingKnight
    )))
    switched.handle(.interactionChanged(snapshot(selected: rook)))

    XCTAssertEqual(switched.stage, direct.stage)
    XCTAssertEqual(switched.presentation, direct.presentation)
    XCTAssertEqual(
        switched.presentation?.headline,
        "That rook can’t come out yet because other pieces are in the way."
    )
}
```

Add equivalent direct-versus-switched tests for two recommended opening sources and for clearing the selection after a candidate source.

- [ ] **Step 2: Add Safe prerequisite-change regressions**

Cover these sequences with full presentation and focus assertions:

1. target queen → attacker question → tap urgent rook: result equals choosing the rook directly, and the queen-attacker context is absent;
2. target queen → attacker bishop → Safe resolution → select a possible saving piece through `interactionChanged`: target/attacker focus remains;
3. target queen → attacker bishop → new start advice: all old evidence and focus disappear.

- [ ] **Step 3: Add action and tentative-lifecycle reducer tests**

Replace direct `.moveStaged` and `.positionChanged` calls in the focused cases with authoritative snapshots. Assert:

- a new tentative move captures the origin from the previously derived question and emits one request;
- an idempotent repeat of the same snapshot emits no second request;
- removing the move drops reply/completion evidence and rederives from retained position advice;
- replacing the move retains the original coaching origin but requires new exact move advice;
- `I don't see one`, Hint, Looks safe, Stop, Keep looking, and Done remain valid only for the derived question that exposes them.

- [ ] **Step 4: Run the focused session tests to record RED**

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/CoachingSessionTests
```

Expected: the new event API and history-independent expectations fail before the reducer migration.

- [ ] **Step 5: Replace transition mutation with one reconciliation pipeline**

`CoachingSession` should follow this shape:

```swift
@discardableResult
private mutating func reconcile() -> [CoachingDirective] {
    var derived = reconciler.derive(learner: learner, episode: episode)
    episode.progress.enter(derived.questionID)
    episode.progress.discardFeedbackInvalidated(by: episode.interaction)
    derived = reconciler.derive(learner: learner, episode: episode)
    stage = derived.stage
    let context = projector.context(
        learner: learner,
        derived: derived,
        episode: episode
    )
    presentation = context.map { explainer.presentation(for: $0) }
    return directiveForUnqueuedRequest(derived.requestedAdvice)
}
```

Input reduction may update only `episode.knowledge`, `episode.evidence`, `episode.progress`, or replace `episode.interaction` with the supplied snapshot. Delete `transition`, `returnToOrigin`, `invalidateTentativeMoveIfNeeded`, and direct assignments that use `stage` as conversation history.

- [ ] **Step 6: Implement semantic identification reduction**

- Check taps set `checkingPiece` only when the tapped square is a current checker.
- Safe learner-piece taps are always interpreted as target attempts while the derived task is identification. Set or replace `safeTarget`; clear `safeAttacker` whenever the target attempt changes.
- Opponent-piece taps during `safeAttacker` set `safeAttacker` only when the current target's current problem includes that source.
- Opponent-reply taps set `replyAnswer` only for the exact current assessed move.
- Miss feedback records the factual existing `CoachingFeedback` with an identification anchor; no tap directly assigns a later stage.

- [ ] **Step 7: Implement interaction reduction**

On `.interactionChanged`:

- replace the stored snapshot as one value;
- when a tentative move first appears, derive and record its `tentativeOrigin` from the prior derived state;
- when a move is replaced, retain that origin but clear move advice, reply answer, move-bound feedback, and pending move context;
- when a move is removed, clear move-specific evidence and advice but retain valid position advice and Safe target–attacker evidence;
- never copy `selectedSquare` into Wake evidence;
- never emit advice for a selection-only delta.

- [ ] **Step 8: Migrate existing session tests to snapshot helpers**

Add test-only helpers:

```swift
private func snapshot(
    selected: Square? = nil,
    tentativeMove: Move? = nil,
    revision: Int = 0
) -> CoachingInteractionSnapshot {
    CoachingInteractionSnapshot(
        selectedSquare: selected,
        tentativeMove: tentativeMove,
        positionRevision: revision
    )
}

private func stage(
    _ move: Move,
    in session: inout CoachingSession,
    revision: Int = 1
) -> [CoachingDirective] {
    session.handle(.interactionChanged(snapshot(
        selected: move.to,
        tentativeMove: move,
        revision: revision
    )))
}
```

Replace Wake `.squareTapped(source)` setup with an interaction snapshot selecting that source. Keep `.identificationTapped` only for check, Safe, and opponent-reply questions.

- [ ] **Step 9: Run all coaching model and explanation suites**

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/CoachingReconcilerTests -only-testing:ChessTutorTests/CoachingPresentationProjectorTests -only-testing:ChessTutorTests/CoachingSessionTests -only-testing:ChessTutorTests/LocalCoachingExplanationSourceTests
```

Expected: all selected tests pass with zero skips. Search confirms `CoachingSession` has no `selectedWakePiece`, stored tentative move, `transition`, or `returnToOrigin`.

- [ ] **Step 10: Commit Task 3**

```bash
git add ChessTutor/Coaching/CoachingState.swift ChessTutor/Coaching/CoachingReconciler.swift ChessTutor/Coaching/CoachingSession.swift ChessTutorTests/Coaching/CoachingReconcilerTests.swift ChessTutorTests/Coaching/CoachingSessionTests.swift
git commit -m "refactor: reconcile coaching from episode facts"
```

---

### Task 4: Authoritative `GameSession` synchronization and opening-source UX

**Files:**
- Modify: `ChessTutor/Game/GameSession.swift`
- Modify: `ChessTutorTests/Game/GameSessionCoachingTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingAcceptanceTests.swift`
- Test: `ChessTutor/UI/Board/ChessBoardView.swift` (verify existing fallback path; no expected edit)

**Interfaces:**
- Consumes: Task 3's `CoachingInteractionSnapshot` and event API.
- Produces inside `GameSession`:

```swift
private var coachingInteractionSnapshot: CoachingInteractionSnapshot {
    CoachingInteractionSnapshot(
        selectedSquare: selectedSquare,
        tentativeMove: tentativeMove,
        positionRevision: analysisRevision
    )
}

@discardableResult
private func synchronizeCoachingInteraction() -> Move? {
    guard coachingSession != nil else { return nil }
    let directives = coachingSession?.handle(
        .interactionChanged(coachingInteractionSnapshot)
    ) ?? []
    return applyCoachingDirectives(directives)
}
```

- `handleCoachingSquareInteraction` forwards `.identificationTapped` only when the derived board task is `.identify`; Wake source now uses `.move` and naturally falls through to the existing ordinary tap/drag handling in `ChessBoardView`.

- [ ] **Step 1: Add failing end-to-end source-switch regressions**

```swift
func testOpeningCoachRecalculatesWhenSelectionChangesFromKnightToBlockedRook() async {
    let session = GameSession(
        coachingAdvisor: ImmediateCoachingAdvisor(
            advice: CoachingTestFixtures.startingPositionAdvice
        )
    )
    session.startCoaching()
    await session.resolvePendingCoachingAdvice()

    session.select(CoachingTestFixtures.openingKnight)
    XCTAssertEqual(session.coachingPresentation?.instruction, "Move it on the board.")

    let blockedRook = Square(file: .a, rank: 1)
    session.select(blockedRook)

    XCTAssertEqual(session.selectedSquare, blockedRook)
    XCTAssertEqual(
        session.coachingPresentation?.headline,
        "That rook can’t come out yet because other pieces are in the way."
    )
    XCTAssertEqual(session.coachingPresentation?.instruction, "Tap the piece you want to move.")
    XCTAssertNil(session.pendingCoachingRequestID)
}
```

Add direct-rook versus knight-then-rook full-presentation equality, candidate-to-candidate switching, candidate-to-empty clearing, and tap-versus-drag source selection.

- [ ] **Step 2: Add failing common-path mutation tests**

Exercise `select`, `tapEmptySquare`, `prepareDrag`, `moveSelectedPiece`, `promote`, tentative replacement, and tentative restoration. For each operation, assert the coaching result corresponds to the final `selectedSquare` and `tentativeMove`, never an intermediate state. Add a request-count assertion so a selection-only path queues zero requests and one newly staged move queues exactly one.

- [ ] **Step 3: Run GameSession coaching tests to record RED**

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/GameSessionCoachingTests
```

Expected: source-switch and common-synchronization tests fail under the old stage-specific notification paths.

- [ ] **Step 4: Initialize coaching with the authoritative snapshot**

In `startCoaching`, construct `CoachingSession` with `coachingInteractionSnapshot` and `.start` or `.tentativeMove(origin: .preexisting)`. Queue that exact initial context once.

- [ ] **Step 5: Replace stage-specific notifications with the common synchronization point**

Remove `notifyCoachingMoveStaged` and `notifyCoachingPositionChanged`. Ensure each public board interaction synchronizes once after its final mutation:

- `select` after tentative restoration and final selection;
- `tapEmptySquare` after replacement, restoration, or clearing;
- `prepareDrag` after its final restored/source selection;
- `moveSelectedPiece` after staging or restoring;
- `promote` after the concrete promotion move is staged.

Use private no-sync primitives where these methods call one another so nested operations do not expose intermediate snapshots or queue duplicate advice.

- [ ] **Step 6: Remove coach-driven selection**

Delete `.selectSquare` from `CoachingDirective` and `applyCoachingDirectives`. Change Wake source projection to `.move`. Confirm `ChessBoardView.handleTap` already calls ordinary selection when `handleCoachingSquareTap` returns `false`; do not add view logic.

- [ ] **Step 7: Update acceptance transcripts to use the real board path**

Replace assertions that opening Wake consumes a coaching tap:

```swift
XCTAssertFalse(session.handleCoachingSquareTap(move.from))
session.select(move.from)
XCTAssertEqual(session.selectedSquare, move.from)
```

Keep check, Safe, and opponent-reply identification taps consumed. Update deterministic transcript expectations only where the public `consumed` result intentionally changes for Wake.

- [ ] **Step 8: Run GameSession, acceptance, board, and UI focus suites**

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/GameSessionCoachingTests -only-testing:ChessTutorTests/CoachingAcceptanceTests -only-testing:ChessTutorTests/GameSessionTests -only-testing:ChessTutorTests/CoachFocusOverlayTests
```

Expected: all selected tests pass with zero skips.

- [ ] **Step 9: Commit Task 4**

```bash
git add ChessTutor/Game/GameSession.swift ChessTutor/Coaching/CoachingState.swift ChessTutorTests/Game/GameSessionCoachingTests.swift ChessTutorTests/Coaching/CoachingAcceptanceTests.swift
git commit -m "fix: keep coaching aligned with board interaction"
```

---

### Task 5: Exact advice lifecycle, equivalence matrix, and UAT

**Files:**
- Modify: `ChessTutor/Game/GameSession.swift`
- Modify: `ChessTutor/Coaching/CoachingSession.swift`
- Modify: `ChessTutor/Coaching/CoachingReconciler.swift`
- Modify: `ChessTutorTests/Coaching/CoachingTestFixtures.swift`
- Modify: `ChessTutorTests/Game/GameSessionCoachingTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingAcceptanceTests.swift`

**Interfaces:**
- Consumes: Task 4's common synchronization path and exact `CoachingInteractionSnapshot`.
- Produces no new public UI API. It tightens request applicability and proves that equivalent current facts yield equivalent coaching output.

- [ ] **Step 1: Add failing exact-request tests**

Extend `ControllableCoachingAdvisor` with exact-request overloads while preserving its revision-based helpers:

```swift
private var continuations: [(
    request: CoachingRequest,
    continuation: CheckedContinuation<CoachingAdvice, any Error>
)] = []

func resolve(request: CoachingRequest, with advice: CoachingAdvice) {
    guard let index = continuations.firstIndex(where: { $0.request == request }) else {
        return
    }
    continuations.remove(at: index).continuation.resume(returning: advice)
}

func hasPending(request: CoachingRequest) -> Bool {
    continuations.contains(where: { $0.request == request })
}
```

Retain `resolve(revision:with:)`, `fail(revision:with:)`, and `hasPending(revision:)` by having them select the first queued request with that revision. Then add tests for:

1. coached move A pending → replace with move B → A succeeds late: B's pending request and current presentation are unchanged;
2. coached move reaches completion → remove it: completion/actions disappear immediately and retained position advice rederives the origin question;
3. Help begins on a preexisting tentative move → remove it: because no position advice is cached, exactly one `.start` request is queued;
4. move advice contains the current move but a different origin: it is ignored;
5. repeated identical snapshots while advice is pending do not create duplicate requests.

Use exact assertions on `pendingCoachingRequestID`, current selected square, tentative board, prompt, actions, and focus.

- [ ] **Step 2: Add failing history-equivalence matrices**

In `CoachingAcceptanceTests`, compare full `CoachingPresentation` values for paths ending in the same facts:

```swift
func testOpeningSelectionProjectionIsIndependentOfSelectionHistory() async {
    let direct = await openingPresentation(afterSelecting: [Square(file: .a, rank: 1)])
    let switched = await openingPresentation(afterSelecting: [
        CoachingTestFixtures.openingKnight,
        CoachingTestFixtures.alternateKnight,
        Square(file: .a, rank: 1),
    ])
    XCTAssertEqual(switched, direct)
}
```

Add a Safe matrix where direct urgent-rook identification equals queen-then-rook identification, plus a Safe resolution matrix proving that changing possible move sources does not erase valid target–attacker evidence.

- [ ] **Step 3: Run the exact-lifecycle and acceptance tests to record RED**

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/GameSessionCoachingTests -only-testing:ChessTutorTests/CoachingAcceptanceTests
```

Expected: at least the new exact-origin/stale-response or equivalence assertions fail before hardening.

- [ ] **Step 4: Harden pending-request applicability**

Before applying success or failure in `resolvePendingCoachingAdvice`, require all of:

```swift
pendingCoachingRequest?.id == pending.id
pending.request.committedState == committedState
pending.request.tentativeMove == tentativeMove
coachingSession != nil
```

Pass the current authoritative snapshot into `receive`/`receiveUnsupportedPosition`. `CoachingSession` must also verify that the advice's context, move, origin, and committed state match its current knowledge requirement before caching it.

- [ ] **Step 5: Preserve position advice separately from move advice**

Receiving `.tentativeMove` advice must never overwrite `.start` advice. Removing/replacing a move clears only move advice and reply evidence. If position advice is absent after removing a preexisting move, reconciliation requests `.start`; otherwise it immediately derives the valid current Safe/Take/Wake question.

- [ ] **Step 6: Remove migration adapters and audit invariants**

Delete the temporary Task 2 adapter and all obsolete mutable workflow fields or helpers. These searches must return no matches in production coaching code:

```bash
rg -n "selectedWakePiece|selectedWakePurpose|private var tentativeMove|func transition\(|func returnToOrigin|notifyCoachingMoveStaged|notifyCoachingPositionChanged|case selectSquare" ChessTutor/Coaching ChessTutor/Game/GameSession.swift
```

Review every assignment to `selectedSquare` or `tentativeMove` in `GameSession.swift`; each active-Help path must either stop coaching or reach `synchronizeCoachingInteraction` after its final state.

- [ ] **Step 7: Run the complete focused coaching slice**

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/CoachingReconcilerTests -only-testing:ChessTutorTests/CoachingPresentationProjectorTests -only-testing:ChessTutorTests/LocalCoachingExplanationSourceTests -only-testing:ChessTutorTests/CoachingSessionTests -only-testing:ChessTutorTests/GameSessionCoachingTests -only-testing:ChessTutorTests/CoachingAcceptanceTests -only-testing:ChessTutorTests/CoachingPanelLayoutTests -only-testing:ChessTutorTests/CoachFocusOverlayTests
```

Expected: all selected tests pass with zero failures and zero skips.

- [ ] **Step 8: Run the full suite and simulator build**

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
xcodebuild build -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Expected: full suite passes with zero failures and zero skips; build succeeds.

- [ ] **Step 9: Perform direct simulator UAT**

On the dedicated iPad simulator:

1. Starting position → Help → knight → blocked rook. Confirm the panel changes to the same blocked-rook response shown when the rook is tapped first.
2. Starting position → Help → knight → other knight → center pawn → clear selection. Confirm the prompt and board emphasis follow each final selection and return to source choice when cleared.
3. Threat fixture → Help → urgent target → its attacker → select two different possible saving sources. Confirm target–attacker focus persists while ordinary move selection changes.
4. Stage a coached move → revise/remove it before advice completes. Confirm no old reply, hint, focus, or completion appears.
5. Repeat with accessibility-extra-large text and restore the simulator to the standard content-size category afterward.

Capture screenshots for the direct-rook and knight-then-rook states and compare conversation, selection, focus, and actions.

- [ ] **Step 10: Commit Task 5**

```bash
git add ChessTutor/Coaching ChessTutor/Game/GameSession.swift ChessTutorTests/Coaching ChessTutorTests/Game/GameSessionCoachingTests.swift
git commit -m "test: cover derived coaching state invariants"
```

- [ ] **Step 11: Final branch review**

```bash
git diff --check HEAD~5 HEAD
git status --short
git log --oneline -6
```

Expected: no whitespace errors, no uncommitted files, five implementation commits following the design/plan commits, and no unrelated changes.

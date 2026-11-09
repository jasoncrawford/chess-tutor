# Coaching Scaffolding Revision Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make On-Demand Coaching V1 concrete, answerable, progressively helpful, and unclipped for a young child without changing its chess evaluator or accepted-move policy.

**Architecture:** Keep the existing `CoachingAdvisor → CoachingSession → CoachingPresentation → SwiftUI` dependency direction. Enrich the semantic prompt, feedback, and hint values owned by the coaching session; map them to authored language in `LocalCoachingExplanationSource`; and make `CoachingPanelView` use the physical panel axis to reserve a compact routine strip and arrange conversation/actions correctly. The existing `CoachFocusOverlay`, evaluator, insights, and move-commit path remain authoritative and unchanged.

**Tech Stack:** Swift 6, SwiftUI, Observation, XCTest, Xcode/iOS Simulator.

## Global Constraints

- Use the approved design in `docs/superpowers/specs/2026-08-15-coaching-scaffolding-revision-design.md`.
- Do not change piece values, urgent-loss thresholds, exchange evaluation, candidate ranking, or move acceptance.
- Do not add an engine, language model, network dependency, generated copy, or proactive coaching.
- Keep chess facts and coaching state out of SwiftUI.
- Keep all move staging and committing on the existing `GameSession` paths; only **Done** commits.
- Opening candidates remain unhighlighted until the child explicitly chooses **Hint**.
- A miss promotes **Hint** but never advances or reveals it automatically.
- Child-facing coaching copy must not contain “job,” “part of this problem,” “big danger,” or “Tap the problem.”
- Use the existing `CoachFocusPresentation` and `CoachFocusOverlay`; do not create a second board-overlay grammar.
- Preserve Stop, Keep looking, tentative-move, promotion, remote-lock, and stale-advice behavior.
- Run relevant tests before every commit and the complete suite before handoff.

---

## File responsibility map

- `ChessTutor/Coaching/CoachingModels.swift`: source-independent semantic prompt, Wake purpose, feedback, and hint values.
- `ChessTutor/Coaching/CoachingSession.swift`: stage transitions, selected target/attacker context, factual answer classification, semantic hint ladders, and focus lifecycle.
- `ChessTutor/Coaching/LocalCoachingExplanationSource.swift`: canonical child-facing questions, instructions, feedback, hint language, and action prominence.
- `ChessTutor/UI/Coaching/CoachingPanelView.swift`: compact routine strip, tall/wide composition, scrolling, action layout, and accessibility ordering.
- `ChessTutor/UI/Theme/AppTheme.swift`: coaching-specific title font only.
- `ChessTutorTests/Coaching/LocalCoachingExplanationSourceTests.swift`: exact authored-language contract and prohibited-copy coverage.
- `ChessTutorTests/Coaching/CoachingSessionTests.swift`: stage, feedback, hint, focus, routine, and action-state behavior.
- `ChessTutorTests/Coaching/CoachingAcceptanceTests.swift`: end-to-end transcripts through `GameSession`.
- `ChessTutorTests/UI/CoachingPanelLayoutTests.swift`: physical composition and accessibility contract.

---

### Task 1: Make coaching prompts purpose-aware and concrete

**Files:**
- Modify: `ChessTutor/Coaching/CoachingModels.swift`
- Modify: `ChessTutor/Coaching/CoachingSession.swift`
- Modify: `ChessTutor/Coaching/LocalCoachingExplanationSource.swift`
- Test: `ChessTutorTests/Coaching/LocalCoachingExplanationSourceTests.swift`
- Test: `ChessTutorTests/Coaching/CoachingSessionTests.swift`
- Test: `ChessTutorTests/Coaching/CoachingAcceptanceTests.swift`

**Interfaces:**
- Produces: `CoachingWakePurpose`, purpose-aware Wake stages/prompts, attacker-aware Safe resolution prompts, and revised canonical base copy.
- Preserves: `CoachingAdvising`, `CoachingAdvice`, `CoachingPresentation`, `CoachingBoardTask`, and all `GameSession` APIs.

- [ ] **Step 1: Replace the old prompt-copy assertions with the approved concrete contract**

In `LocalCoachingExplanationSourceTests.swift`, change the canonical cases to use these semantic values and exact strings:

```swift
func testEveryQuestionPromptUsesConcreteAnswerInstructions() {
    let cases: [(CoachingPrompt, String, String?)] = [
        (
            .safeLocate,
            "Which of your pieces needs help most?",
            "Tap your piece, or choose I don’t see one."
        ),
        (
            .safeIdentifyAttacker(piece: .knight),
            "You found the knight. What black piece is attacking it?",
            "Tap the black piece."
        ),
        (
            .safeResolve(target: .knight, attacker: .pawn),
            "Yes—that pawn is attacking your knight. How could you help your knight?",
            "Make a move that gets it safe."
        ),
        (
            .takeChooseMove,
            "Can one of your pieces make a useful capture?",
            "Make the capture, or choose I don’t see one."
        ),
        (
            .wakeChoosePiece(purpose: .openingDevelopment(firstMove: true)),
            "A good first step is to move a center pawn or bring out a knight. Which would you like to try?",
            "Tap the piece you want to move."
        ),
        (
            .wakeChooseMove(piece: .knight, purpose: .openingDevelopment(firstMove: true)),
            "This knight can come into the game.",
            "Move it on the board."
        ),
        (
            .opponentReply(opponent: .black),
            "Could Black check your king or win one of your pieces?",
            "Tap the black checking piece, or tap your piece Black could take. Otherwise choose Looks safe."
        ),
    ]

    for (prompt, headline, instruction) in cases {
        let presentation = explainer.presentation(for: context(prompt: prompt))
        XCTAssertEqual(presentation.headline, headline, "Unexpected headline for \(prompt)")
        XCTAssertEqual(presentation.instruction, instruction, "Unexpected instruction for \(prompt)")
    }
}
```

Add general Wake cases for `.addsDefender`, `.createsThreat`, `.centralActivity`, and `.castle` using the exact copy in the design spec. Update the development completion assertion to:

```swift
XCTAssertEqual(
    presentation.headline,
    "That works. Your knight came into the game. Chess players call that developing a piece."
)
```

- [ ] **Step 2: Add transcript assertions for the opening and Safe transitions**

In `CoachingSessionTests.swift`, update the starting-position expectation and add attacker-aware Safe assertions:

```swift
func testStartingPositionSkipsEmptyScansAndAsksConcreteOpeningQuestion() {
    var session = CoachingSession(learner: .white)

    session.receive(CoachingTestFixtures.startingPositionAdvice)

    XCTAssertEqual(session.stage, .wakeChoosePiece(purpose: .openingDevelopment(firstMove: true)))
    XCTAssertEqual(session.presentation?.routine, [
        .safeCleared, .takeCleared, .wakeCurrent,
    ])
    XCTAssertEqual(
        session.presentation?.headline,
        "A good first step is to move a center pawn or bring out a knight. Which would you like to try?"
    )
    XCTAssertTrue(session.presentation?.focus.candidateSquares.isEmpty == true)
}
```

Extend the Safe transcript:

```swift
session.handle(.squareTapped(chosenTarget))
XCTAssertEqual(
    session.presentation?.headline,
    "You found the rook. What black piece is attacking it?"
)

session.handle(.squareTapped(attacker))
XCTAssertEqual(
    session.presentation?.headline,
    "Yes—that rook is attacking your rook. How could you help your rook?"
)
XCTAssertEqual(session.presentation?.instruction, "Make a move that gets it safe.")
```

- [ ] **Step 3: Run the focused tests and verify the new API/copy contract fails**

Run:

```bash
xcodebuild test -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/LocalCoachingExplanationSourceTests \
  -only-testing:ChessTutorTests/CoachingSessionTests
```

Expected: FAIL to compile because `CoachingWakePurpose` and the revised prompt signatures do not exist, or FAIL on the old copy.

- [ ] **Step 4: Add purpose-aware prompt models**

In `CoachingModels.swift`, add:

```swift
enum CoachingWakePurpose: Equatable, Sendable {
    case openingDevelopment(firstMove: Bool)
    case addsDefender
    case createsThreat
    case centralActivity
    case castle
}
```

Replace the three affected prompt cases:

```swift
enum CoachingPrompt: Equatable, Sendable {
    // existing check and Safe cases...
    case safeIdentifyAttacker(piece: Piece.Kind)
    case safeResolve(target: Piece.Kind, attacker: Piece.Kind)
    case takeChooseMove
    case wakeChoosePiece(purpose: CoachingWakePurpose)
    case wakeChooseMove(piece: Piece.Kind, purpose: CoachingWakePurpose)
    case opponentReply(opponent: PieceColor)
    // remaining cases unchanged...
}
```

- [ ] **Step 5: Carry Wake purpose and the selected attacker through `CoachingSession`**

Replace the Wake stage payloads and add selected-attacker state:

```swift
enum CoachingStage: Equatable, Sendable {
    // existing cases...
    case wakeChoosePiece(purpose: CoachingWakePurpose)
    case wakeChooseMove(piece: Square, purpose: CoachingWakePurpose)
    // existing cases...
}

private var selectedSafeAttacker: Square?
private var selectedWakePurpose: CoachingWakePurpose?
```

Reset both values in `.start` and `receiveUnsupportedPosition()`. When a valid Safe attacker is tapped, store it before entering `.safeResolve`. When a Wake source is accepted, derive the purpose for that source and preserve it for returns from tentative-move evaluation.

Add these helpers; keep them private to `CoachingSession`:

```swift
private func wakePurpose(
    for concept: CoachingConcept?,
    in advice: CoachingAdvice
) -> CoachingWakePurpose {
    switch concept {
    case .developsKnightOrBishop, .advancesCenterPawn:
        return .openingDevelopment(
            firstMove: advice.evaluation.request.committedState == GameState.startingPosition()
        )
    case .addsUsefulDefender: return .addsDefender
    case .createsSafeImmediateThreat: return .createsThreat
    case .castlesForKingSafety: return .castle
    default: return .centralActivity
    }
}

private func wakePurpose(for source: Square, in advice: CoachingAdvice) -> CoachingWakePurpose {
    let concept = advice.wakeOpportunities.first {
        $0.moves.contains { $0.from == source }
    }?.concept
    return wakePurpose(for: concept, in: advice)
}

private func initialWakePurpose(in advice: CoachingAdvice) -> CoachingWakePurpose {
    guard let source = advice.wakeOpportunities.first?.moves.first?.from else {
        return .centralActivity
    }
    return wakePurpose(for: source, in: advice)
}
```

If `wakeSources(in:)` is empty, enter `.fallbackChooseMove` rather than presenting an unanswerable Wake question. Update `prompt(for:)`, `returnToOrigin`, `routine(for:)`, `boardTask(for:)`, `candidateMoves(for:)`, and affected test helpers for the new payloads.

Build the Safe resolution prompt from `selectedSafeAttacker`:

```swift
case let .safeResolve(target):
    return .safeResolve(
        target: pieceKind(at: target) ?? .pawn,
        attacker: selectedSafeAttacker.flatMap { pieceKind(at: $0) } ?? .pawn
    )
```

- [ ] **Step 6: Replace the base copy and Wake-purpose copy**

In `LocalCoachingExplanationSource.swift`, replace the affected `baseCopy` cases with the exact copy from Step 1 and add a private Wake-purpose mapper:

```swift
private func wakePieceCopy(
    for purpose: CoachingWakePurpose
) -> (headline: String, instruction: String) {
    switch purpose {
    case .openingDevelopment(firstMove: true):
        return (
            "A good first step is to move a center pawn or bring out a knight. Which would you like to try?",
            "Tap the piece you want to move."
        )
    case .openingDevelopment(firstMove: false):
        return (
            "Could you bring out a knight or bishop, move a center pawn, or castle?",
            "Tap the piece you want to move."
        )
    case .addsDefender:
        return ("Which piece could help protect another piece?", "Tap the piece you want to move.")
    case .createsThreat:
        return ("Which piece could safely attack something?", "Tap the piece you want to move.")
    case .centralActivity:
        return ("Which piece could move closer to the center?", "Tap the piece you want to move.")
    case .castle:
        return ("Which piece would you move to castle?", "Tap your king.")
    }
}
```

For `wakeChooseMove`, use the piece and purpose to say “This knight can come into the game,” “This pawn can help in the center,” or the corresponding verified general-Wake purpose. For `.castle`, instruct “Move it two squares toward a rook.”

- [ ] **Step 7: Run the prompt and transcript tests**

Run the same focused `xcodebuild test` command from Step 3.

Expected: PASS for `LocalCoachingExplanationSourceTests` and `CoachingSessionTests`.

- [ ] **Step 8: Run the end-to-end opening and Safe acceptance tests**

Run:

```bash
xcodebuild test -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/CoachingAcceptanceTests/testStartingPositionHelpDevelopsKnightAndWaitsForDone \
  -only-testing:ChessTutorTests/CoachingAcceptanceTests/testUrgentThreatTranscriptIdentifiesTargetAttackerAndResolvesDanger
```

Expected: PASS with the revised headlines and unchanged move/Done behavior.

- [ ] **Step 9: Commit the purpose-aware prompt slice**

```bash
git add ChessTutor/Coaching/CoachingModels.swift \
  ChessTutor/Coaching/CoachingSession.swift \
  ChessTutor/Coaching/LocalCoachingExplanationSource.swift \
  ChessTutorTests/Coaching/LocalCoachingExplanationSourceTests.swift \
  ChessTutorTests/Coaching/CoachingSessionTests.swift \
  ChessTutorTests/Coaching/CoachingAcceptanceTests.swift
git commit -m "fix: make coaching prompts concrete"
```

---

### Task 2: Replace generic answer labels with factual feedback

**Files:**
- Modify: `ChessTutor/Coaching/CoachingModels.swift`
- Modify: `ChessTutor/Coaching/CoachingSession.swift`
- Modify: `ChessTutor/Coaching/LocalCoachingExplanationSource.swift`
- Test: `ChessTutorTests/Coaching/LocalCoachingExplanationSourceTests.swift`
- Test: `ChessTutorTests/Coaching/CoachingSessionTests.swift`
- Test: `ChessTutorTests/Coaching/CoachingAcceptanceTests.swift`

**Interfaces:**
- Consumes: `CoachingWakePurpose` and attacker-aware prompts from Task 1.
- Produces: structured `CoachingFeedback` facts and first-miss Hint prominence.

- [ ] **Step 1: Write exact feedback-copy tests**

Replace the generic feedback table in `LocalCoachingExplanationSourceTests.swift` with:

```swift
func testFeedbackStatesAVisibleChessFact() {
    let cases: [(CoachingPrompt, CoachingFeedback, String)] = [
        (.safeLocate, .safePiece(piece: .bishop), "That bishop is safe right now."),
        (
            .safeLocate,
            .lowerPriorityThreat(piece: .pawn, urgentPiece: .knight),
            "Yes, that pawn is threatened. Your knight is worth more, so help the knight first."
        ),
        (
            .safeLocate,
            .nonurgentThreat(piece: .pawn),
            "Yes, that pawn is threatened. We’re looking for a knight, bishop, rook, or queen Black could win."
        ),
        (.safeLocate, .expectedLearnerPiece, "Tap one of your pieces."),
        (
            .safeIdentifyAttacker(piece: .knight),
            .notAttacker(piece: .bishop, target: .knight),
            "That bishop isn’t attacking your knight."
        ),
        (
            .safeIdentifyAttacker(piece: .knight),
            .expectedAttacker(target: .knight),
            "Tap a black piece attacking your knight."
        ),
        (
            .wakeChoosePiece(purpose: .openingDevelopment(firstMove: true)),
            .blockedWakePiece(piece: .rook),
            "That rook can’t come out yet because other pieces are in the way."
        ),
        (
            .opponentReply(opponent: .black),
            .notReplyIssue,
            "That piece doesn’t show a check or capture after this move."
        ),
        (
            .safeResolve(target: .knight, attacker: .pawn),
            .dangerStillPresent(attacker: .pawn, target: .knight),
            "The pawn could still take your knight after that move."
        ),
    ]

    for (prompt, feedback, headline) in cases {
        let result = explainer.presentation(for: context(prompt: prompt, feedback: feedback))
        XCTAssertEqual(result.headline, headline)
    }
}

func testCorrectAbsenceAcknowledgesAndAsksTheNextQuestion() {
    let presentation = explainer.presentation(for: context(
        prompt: .takeChooseMove,
        feedback: .correctAbsence
    ))

    XCTAssertEqual(
        presentation.headline,
        "Right—there isn’t one. Can one of your pieces make a useful capture?"
    )
    XCTAssertEqual(
        presentation.instruction,
        "Make the capture, or choose I don’t see one."
    )
}
```

Change the Hint-prominence test to one miss:

```swift
func testFirstMissEmphasizesHintWithoutChangingInstruction() {
    let presentation = explainer.presentation(for: context(
        prompt: .safeLocate,
        missesAtCurrentLevel: 1,
        actions: [.noAnswer, .hint, .stop]
    ))

    XCTAssertEqual(presentation.instruction, "Tap your piece, or choose I don’t see one.")
    XCTAssertEqual(
        presentation.actions.first { $0.action == .hint }?.prominence,
        .primary
    )
}
```

- [ ] **Step 2: Add session classification tests**

Add tests that distinguish a safe own piece, lower-priority threatened piece, wrong-color tap, nonattacking opponent piece, blocked opening source, and irrelevant opponent-reply tap. Include this first-miss assertion:

```swift
session.handle(.squareTapped(unrelated))

XCTAssertEqual(session.hintLevel, 0)
XCTAssertEqual(session.missesAtCurrentLevel, 1)
XCTAssertEqual(
    session.presentation?.actions.first { $0.action == .hint }?.prominence,
    .primary
)
```

For the lower-priority fixture, assert the feedback compares the tapped pawn with `advice.urgentProblems.first!.piece.kind`; do not hard-code a second evaluation threshold in the session.

- [ ] **Step 3: Run the focused tests and verify they fail**

Run:

```bash
xcodebuild test -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/LocalCoachingExplanationSourceTests \
  -only-testing:ChessTutorTests/CoachingSessionTests
```

Expected: FAIL because the factual feedback cases do not exist and Hint still becomes primary after two misses.

- [ ] **Step 4: Replace generic feedback cases with structured facts**

In `CoachingModels.swift`, replace `.correct`, `.correctAlternative`, `.relevantButNonurgent`, `.unrelatedTap`, `.dangerStillPresent(piece:)`, and `.noRecognizedPurpose` with:

```swift
enum CoachingFeedback: Equatable, Sendable {
    case safePiece(piece: Piece.Kind)
    case lowerPriorityThreat(piece: Piece.Kind, urgentPiece: Piece.Kind)
    case nonurgentThreat(piece: Piece.Kind)
    case expectedLearnerPiece
    case notCheckingPiece(piece: Piece.Kind?)
    case notAttacker(piece: Piece.Kind, target: Piece.Kind)
    case expectedAttacker(target: Piece.Kind)
    case blockedWakePiece(piece: Piece.Kind)
    case notWakeCandidate(piece: Piece.Kind, purpose: CoachingWakePurpose)
    case notReplyIssue
    case correctAbsence
    case missedExistingAnswer
    case concreteFlaw(kind: CoachingOpponentIssueKind, affectedPiece: Piece.Kind?)
    case dangerStillPresent(attacker: Piece.Kind?, target: Piece.Kind)
    case noRecognizedPurpose(purpose: CoachingWakePurpose?)
    case harmlessCheckFound
    case checkFoundOtherDangerRemains
}
```

- [ ] **Step 5: Classify taps using existing advice and Core movement facts**

Refactor `handleSquareTap` into small private helpers for Check, Safe locate, Safe attacker, Wake source, and opponent reply. Use the committed board from `advice.evaluation.request.committedState`.

For Safe locate, follow this order:

```swift
if let urgent = advice.urgentProblems.first(where: { $0.target == square }) {
    selectedSafeTarget = square
    selectedSafeAttacker = nil
    transition(to: .safeIdentifyAttacker(target: square))
} else if let piece = board[square], piece.color == learner {
    let isThreatened = advice.evaluation.opponentCaptureEstimates.contains {
        $0.capturedSquare == square
    }
    if isThreatened {
        if let urgent = advice.urgentProblems.first {
            recordMiss(.lowerPriorityThreat(
                piece: piece.kind,
                urgentPiece: urgent.piece.kind
            ))
        } else {
            recordMiss(.nonurgentThreat(piece: piece.kind))
        }
    } else {
        recordMiss(.safePiece(piece: piece.kind))
    }
} else {
    recordMiss(.expectedLearnerPiece)
}
```

For attacker identification, use `.notAttacker(piece:target:)` only for an opponent piece; use `.expectedAttacker(target:)` for an empty square or learner piece.

For Wake, classify an own piece with no allowed move as blocked:

```swift
let allowed = LegalMoveGenerator.allowedMoves(
    for: square,
    by: learner,
    in: advice.evaluation.request.committedState
)
let feedback: CoachingFeedback = allowed.isEmpty
    ? .blockedWakePiece(piece: piece.kind)
    : .notWakeCandidate(piece: piece.kind, purpose: purpose)
recordMiss(feedback)
```

Do not add new Core rules or duplicate candidate evaluation.

- [ ] **Step 6: Produce concrete unresolved-danger feedback**

Replace `unresolvedPieceKind` with a helper that uses the selected target plus a remaining `CoachingOpponentIssue` when one is available:

```swift
private func unresolvedDangerFeedback(
    for assessment: CoachingMoveAssessment,
    advice: CoachingAdvice
) -> CoachingFeedback {
    let target = selectedSafeTarget.flatMap(pieceKind(at:))
        ?? advice.urgentProblems.first?.piece.kind
        ?? .king
    let attacker = assessment.opponentIssues.first {
        if case .materialLoss = $0.kind { return true }
        return false
    }.flatMap { advice.evaluation.request.committedState.board[$0.reply.from]?.kind }
        ?? selectedSafeAttacker.flatMap { pieceKind(at: $0) }
    return .dangerStillPresent(attacker: attacker, target: target)
}
```

If no attacker is supported, the explanation must fall back to “Your {target} would still need help after that move,” not guess.

- [ ] **Step 7: Map every feedback case to factual authored language**

Update `feedbackHeadline` in `LocalCoachingExplanationSource.swift`. When `.correctAbsence` is carried into the next stage, prefix the new base question instead of replacing it:

```swift
if context.feedback == .correctAbsence {
    return "Right—there isn’t one. \(base)"
}
```

Make `missedExistingAnswer` prompt-sensitive:

```swift
private func missedAnswerHeadline(for prompt: CoachingPrompt) -> String {
    switch prompt {
    case .safeLocate: return "One of your pieces does need help."
    case .takeChooseMove: return "There is a useful capture to find."
    case let .opponentReply(opponent):
        return "\(colorName(opponent)) has a reply to notice."
    default: return "There is something to find."
    }
}
```

Set Hint prominence with `context.missesAtCurrentLevel >= 1`. Remove the appended “Want a hint?” sentence; the factual headline plus primary Hint button supplies the escalation. Map `.checkFoundOtherDangerRemains` to “You found the check. There is still another danger after this move,” and use it for the existing opponent-reply branch that finds a harmless check while a separate revise-level issue remains. Map `.harmlessCheckFound` to “You found it. {Opponent} could check your king, but your move still works.”

- [ ] **Step 8: Add a prohibited-copy regression test**

In `LocalCoachingExplanationSourceTests.swift`, collect canonical prompt, feedback, hint, and completion presentations and assert:

```swift
let prohibited = [
    "job",
    "part of this problem",
    "big danger",
    "tap the problem",
]
for phrase in prohibited {
    XCTAssertFalse(copy.lowercased().contains(phrase), "Found prohibited copy: \(phrase)")
}
XCTAssertNotEqual(copy.trimmingCharacters(in: .whitespacesAndNewlines), "Yes.")
```

Do not grep source files for the phrases because the tests and design documentation legitimately name them; test generated child-facing presentations.

- [ ] **Step 9: Run focused tests**

Run the command from Step 3.

Expected: PASS.

- [ ] **Step 10: Run coaching acceptance tests**

Run:

```bash
xcodebuild test -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/CoachingAcceptanceTests
```

Expected: PASS with all transcript expectations updated to factual language.

- [ ] **Step 11: Commit the factual-feedback slice**

```bash
git add ChessTutor/Coaching/CoachingModels.swift \
  ChessTutor/Coaching/CoachingSession.swift \
  ChessTutor/Coaching/LocalCoachingExplanationSource.swift \
  ChessTutorTests/Coaching/LocalCoachingExplanationSourceTests.swift \
  ChessTutorTests/Coaching/CoachingSessionTests.swift \
  ChessTutorTests/Coaching/CoachingAcceptanceTests.swift
git commit -m "fix: make coaching feedback factual"
```

---

### Task 3: Tie progressive hints to truthful board focus

**Files:**
- Modify: `ChessTutor/Coaching/CoachingModels.swift`
- Modify: `ChessTutor/Coaching/CoachingSession.swift`
- Modify: `ChessTutor/Coaching/LocalCoachingExplanationSource.swift`
- Test: `ChessTutorTests/Coaching/LocalCoachingExplanationSourceTests.swift`
- Test: `ChessTutorTests/Coaching/CoachingSessionTests.swift`
- Test: `ChessTutorTests/Coaching/CoachingAcceptanceTests.swift`

**Interfaces:**
- Consumes: concrete prompts and feedback from Tasks 1–2.
- Produces: `CoachingHint`, prompt-specific hint ladders, source/destination focus, and persistent Safe relationship focus.

- [ ] **Step 1: Write semantic-hint language tests**

Change the explanation-test context helper to accept `hint: CoachingHint? = nil`. Add:

```swift
func testHintLanguageNamesOnlyItsSemanticClue() {
    let cases: [(CoachingPrompt, CoachingHint, String)] = [
        (.safeLocate, .dangerMarker, "Look for the red danger marker, then tap your piece."),
        (
            .wakeChoosePiece(purpose: .openingDevelopment(firstMove: true)),
            .candidatePieces,
            "Try one of the highlighted knights or center pawns."
        ),
        (
            .safeIdentifyAttacker(piece: .knight),
            .attackerRelationship,
            "Follow the highlighted line to the piece attacking your knight."
        ),
        (
            .safeResolve(target: .knight, attacker: .pawn),
            .safeResponseIdeas,
            "Try moving your knight, protecting it, or taking the attacker."
        ),
        (
            .wakeChooseMove(piece: .knight, purpose: .openingDevelopment(firstMove: true)),
            .movementMarkers,
            "Use the movement markers to choose where your knight should go."
        ),
        (
            .opponentReply(opponent: .black),
            .replyMarkers,
            "Look for a red danger marker or a check marker."
        ),
    ]

    for (prompt, hint, instruction) in cases {
        let result = explainer.presentation(for: context(prompt: prompt, hint: hint))
        XCTAssertEqual(result.instruction, instruction)
    }
}
```

- [ ] **Step 2: Write hint/focus consistency tests in `CoachingSessionTests`**

Cover these contracts:

```swift
func testOpeningStartsWithoutCandidatesAndFirstHintRevealsSourcePieces() {
    var session = CoachingSession(learner: .white)
    session.receive(CoachingTestFixtures.startingPositionAdvice)

    XCTAssertNil(session.presentation?.hint)
    XCTAssertTrue(session.presentation?.focus.candidateSquares.isEmpty == true)

    session.handle(.actionChosen(.hint))

    XCTAssertEqual(session.presentation?.hint, .candidatePieces)
    XCTAssertEqual(
        session.presentation?.focus.candidateSquares,
        Set(CoachingTestFixtures.startingPositionAdvice.wakeOpportunities
            .flatMap(\.moves).map(\.from))
    )
}
```

```swift
func testSafeContextPersistsWithoutARequestedHint() {
    var session = CoachingSession(learner: .white)
    session.receive(CoachingTestFixtures.multipleDangerAdvice)
    session.handle(.squareTapped(CoachingTestFixtures.whiteQueen))

    XCTAssertEqual(
        session.presentation?.focus.emphasizedSquares,
        [CoachingTestFixtures.whiteQueen]
    )

    session.handle(.squareTapped(CoachingTestFixtures.blackBishop))

    XCTAssertEqual(
        session.presentation?.focus.emphasizedSquares,
        [CoachingTestFixtures.whiteQueen, CoachingTestFixtures.blackBishop]
    )
    XCTAssertEqual(session.presentation?.focus.paths, [CoachFocusPath(
        source: CoachingTestFixtures.blackBishop,
        destination: CoachingTestFixtures.whiteQueen,
        role: .attacker
    )])
}
```

Add table-driven assertions that every `.candidatePieces` hint has nonempty source squares, every `.candidateMoves` hint has nonempty paths, and no source-selection prompt emits `.movementMarkers`.

- [ ] **Step 3: Run the hint/session tests and verify they fail**

Run:

```bash
xcodebuild test -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/LocalCoachingExplanationSourceTests \
  -only-testing:ChessTutorTests/CoachingSessionTests
```

Expected: FAIL because hints are still inferred from numeric levels and Safe context is absent at level zero.

- [ ] **Step 4: Add the semantic hint model to the presentation context**

In `CoachingModels.swift`, add:

```swift
enum CoachingHint: Equatable, Sendable {
    case checkMarker
    case dangerMarker
    case replyMarkers
    case candidatePieces
    case attackerRelationship
    case safeResponseIdeas
    case movementMarkers
    case candidateMoves
}
```

Add `let hint: CoachingHint?` to `CoachingPresentationContext` and `CoachingPresentation`. Retain `hintLevel` as `CoachingSession`'s internal progress index and for transcript assertions, but stop passing it to the explanation source. Update every test context initializer explicitly with `hint: nil`.

- [ ] **Step 5: Define finite, prompt-specific hint ladders**

Replace `maximumHintLevel(for:)` with:

```swift
private func hintSteps(for stage: CoachingStage) -> [CoachingHint] {
    switch stage {
    case .checkLocate:
        return [.checkMarker, .candidatePieces]
    case .checkResolve:
        return candidateMoves(for: stage).isEmpty ? [] : [.candidatePieces, .candidateMoves]
    case .safeLocate:
        return [.dangerMarker, .candidatePieces]
    case .safeIdentifyAttacker:
        return [.attackerRelationship, .candidatePieces]
    case .safeResolve:
        return candidateMoves(for: stage).isEmpty ? [.safeResponseIdeas] : [.safeResponseIdeas, .candidateMoves]
    case .takeChooseMove:
        return candidateMoves(for: stage).isEmpty ? [] : [.candidatePieces, .candidateMoves]
    case let .wakeChoosePiece(purpose):
        guard let advice = latestAdvice,
              !wakeSources(for: purpose, in: advice).isEmpty
        else { return [] }
        return [.candidatePieces, .candidateMoves]
    case .wakeChooseMove:
        return candidateMoves(for: stage).isEmpty ? [.movementMarkers] : [.movementMarkers, .candidateMoves]
    case .opponentCheck:
        return opponentIssueAnswerSquares(for: stage).isEmpty
            ? [.replyMarkers]
            : [.replyMarkers, .attackerRelationship]
    case .awaitingAdvice, .fallbackChooseMove, .reviseMove, .complete:
        return []
    }
}
```

Implement `currentHint(for:)` by indexing `hintSteps(for:)` with `hintLevel - 1`. The Hint action exists only while another semantic step is available. Choosing Hint increments by one, clears feedback/misses, increments `pulseID`, and rebuilds presentation exactly as before.

Use actual helpers rather than the pseudocode expression `latestAdvice` above when optional advice is absent; an absent advice object yields no answer-dependent hint steps.

- [ ] **Step 6: Build focus from the semantic hint plus persistent context**

Split the old destination-oriented `answerSquares(for:)` into:

```swift
private func candidateSourceSquares(for stage: CoachingStage) -> Set<Square>
private func candidateDestinationSquares(for stage: CoachingStage) -> Set<Square>
private func candidatePaths(for stage: CoachingStage) -> Set<CoachFocusPath>
private func opponentIssueAnswerSquares(for stage: CoachingStage) -> Set<Square>
private func persistentFocus(for stage: CoachingStage) -> CoachFocusPresentation
```

Add the purpose-filtered Wake helper used by those functions:

```swift
private func wakeSources(
    for purpose: CoachingWakePurpose,
    in advice: CoachingAdvice
) -> Set<Square> {
    Set(advice.wakeOpportunities
        .filter { wakePurpose(for: $0.concept, in: advice) == purpose }
        .flatMap(\.moves)
        .map(\.from))
}
```

Rules:

- `.candidatePieces` uses source squares.
- `.candidateMoves` uses destinations plus candidate paths.
- Wake source-stage candidate moves include every move in `advice.wakeOpportunities` that matches the current stage purpose; do not leave `.wakeChoosePiece` on the old `candidateMoves` default branch.
- For Wake source hints, filter highlighted sources and paths to opportunities matching the stage's current `CoachingWakePurpose`. Continue accepting a tap on any source in all verified Wake opportunities, then transition with that source's actual purpose. This keeps the hint faithful to the question without turning the preferred teaching focus into a unique required answer.
- `.attackerRelationship` uses attacker answer squares and attacker paths.
- marker and idea hints do not fabricate coach focus.
- `safeIdentifyAttacker` persistently emphasizes the selected target.
- `safeResolve` persistently emphasizes the selected target and selected attacker and includes their attacker path.

Merge persistent and hint focus without losing `pulseID`:

```swift
private func focus(for stage: CoachingStage, hint: CoachingHint?) -> CoachFocusPresentation {
    let persistent = persistentFocus(for: stage)
    let hinted = hintFocus(for: stage, hint: hint)
    return CoachFocusPresentation(
        emphasizedSquares: persistent.emphasizedSquares.union(hinted.emphasizedSquares),
        candidateSquares: hinted.candidateSquares,
        paths: persistent.paths.union(hinted.paths),
        pulseID: pulseID
    )
}
```

Clear `selectedSafeTarget` and `selectedSafeAttacker` on new start, unsupported position, Stop/session disposal, and committed-position replacement through the existing session lifecycle. Do not clear them merely when advancing from target to attacker to resolution.

- [ ] **Step 7: Map semantic hints to authored instructions**

Delete `levelOneInstruction` and the generic “highlighted choices / highlighted pieces” switch. Add:

```swift
private func hintedInstruction(
    for hint: CoachingHint,
    prompt: CoachingPrompt
) -> String {
    switch (hint, prompt) {
    case (.dangerMarker, .safeLocate):
        return "Look for the red danger marker, then tap your piece."
    case (.candidatePieces, .wakeChoosePiece(purpose: .openingDevelopment(firstMove: true))):
        return "Try one of the highlighted knights or center pawns."
    case let (.attackerRelationship, .safeIdentifyAttacker(piece)):
        return "Follow the highlighted line to the piece attacking your \(piece.rawValue)."
    case let (.safeResponseIdeas, .safeResolve(target, _)):
        return "Try moving your \(target.rawValue), protecting it, or taking the attacker."
    case let (.movementMarkers, .wakeChooseMove(piece, _)):
        return "Use the movement markers to choose where your \(piece.rawValue) should go."
    case (.replyMarkers, .opponentReply):
        return "Look for a red danger marker or a check marker."
    case (.candidatePieces, _):
        return "Try one of the highlighted pieces."
    case (.candidateMoves, _):
        return "Try one of the highlighted paths, then make the move yourself."
    case (.checkMarker, .checkLocate):
        return "Look for the check marker, then tap the checking piece."
    default:
        return baseCopy(for: prompt).instruction ?? ""
    }
}
```

The presentation includes the semantic hint so tests can verify copy/focus consistency.

- [ ] **Step 8: Update the full hint acceptance transcript**

Replace the old four-level generic test with an explicit, finite transcript:

```swift
XCTAssertTrue(session.handleCoachingSquareTap(unrelated))
XCTAssertEqual(
    session.coachingPresentation?.actions.first { $0.action == .hint }?.prominence,
    .primary
)

_ = session.chooseCoachingAction(.hint)
XCTAssertEqual(session.coachingPresentation?.hint, .attackerRelationship)
XCTAssertEqual(session.coachingPresentation?.focus.paths, [CoachFocusPath(
    source: attacker,
    destination: target,
    role: .attacker
)])

_ = session.chooseCoachingAction(.hint)
XCTAssertEqual(session.coachingPresentation?.hint, .candidatePieces)
XCTAssertEqual(session.coachingPresentation?.focus.candidateSquares, [attacker])
XCTAssertFalse(session.coachingPresentation?.actions.map(\.action).contains(.hint) == true)
XCTAssertEqual(session.state.board, unchangedBoard)
```

- [ ] **Step 9: Run focused and acceptance tests**

Run:

```bash
xcodebuild test -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/LocalCoachingExplanationSourceTests \
  -only-testing:ChessTutorTests/CoachingSessionTests \
  -only-testing:ChessTutorTests/CoachingAcceptanceTests
```

Expected: PASS.

- [ ] **Step 10: Commit the semantic-hint slice**

```bash
git add ChessTutor/Coaching/CoachingModels.swift \
  ChessTutor/Coaching/CoachingSession.swift \
  ChessTutor/Coaching/LocalCoachingExplanationSource.swift \
  ChessTutorTests/Coaching/LocalCoachingExplanationSourceTests.swift \
  ChessTutorTests/Coaching/CoachingSessionTests.swift \
  ChessTutorTests/Coaching/CoachingAcceptanceTests.swift
git commit -m "fix: align coaching hints with board focus"
```

---

### Task 4: Make the compact coaching panel resilient in both physical axes

**Files:**
- Modify: `ChessTutor/Coaching/CoachingSession.swift`
- Modify: `ChessTutor/UI/Coaching/CoachingPanelView.swift`
- Modify: `ChessTutor/UI/Theme/AppTheme.swift`
- Test: `ChessTutorTests/Coaching/CoachingSessionTests.swift`
- Test: `ChessTutorTests/UI/CoachingPanelLayoutTests.swift`

**Interfaces:**
- Consumes: final `CoachingPresentation` from Tasks 1–3 and existing `CoachingPanelLayout.physicalAxis`.
- Produces: `CoachingPanelComposition`, compact routine reservation, tall/wide tabletop arrangements, and overflow-safe conversation/actions.

- [ ] **Step 1: Add routine-visibility tests**

In `CoachingSessionTests.swift`, assert the routine is present only during the meaningful scan:

```swift
func testRoutineIsHiddenOutsideSafeTakeWakeDecisionStages() {
    var session = CoachingSession(learner: .white)
    let wakeMove = Move(
        from: CoachingTestFixtures.openingKnight,
        to: Square(file: .c, rank: 3)
    )
    session.receive(CoachingTestFixtures.startingPositionAdvice)
    XCTAssertEqual(session.presentation?.routine, [
        .safeCleared, .takeCleared, .wakeCurrent,
    ])

    session.handle(.squareTapped(CoachingTestFixtures.openingKnight))
    session.handle(.moveStaged(wakeMove))
    session.receive(CoachingTestFixtures.adviceForTentativeMove(
        wakeMove,
        origin: .wake,
        assessment: CoachingTestFixtures.acceptableAssessment(
            wakeMove,
            concepts: [.developsKnightOrBishop]
        )
    ))

    XCTAssertEqual(session.presentation?.routine, [])
    session.handle(.actionChosen(.looksSafe))
    XCTAssertEqual(session.presentation?.routine, [])
}
```

Also assert Check, fallback, revise, and completion omit the routine.

- [ ] **Step 2: Add physical-composition tests**

In `CoachingPanelLayoutTests.swift`, add:

```swift
func testPhysicalAxisSelectsCompactPanelComposition() {
    let tall = CoachingPanelLayout.make(
        sidebar: .make(for: 760, presentation: .verticalColumn)
    )
    let wide = CoachingPanelLayout.make(
        sidebar: .make(for: 760, presentation: .horizontalSegments)
    )

    XCTAssertEqual(tall.composition, .tall)
    XCTAssertEqual(wide.composition, .wide)
    XCTAssertEqual(tall.composition.routineTabletopAxis, .horizontal)
    XCTAssertEqual(wide.composition.routineTabletopAxis, .vertical)
    XCTAssertEqual(tall.composition.actionTabletopAxis, .vertical)
    XCTAssertEqual(wide.composition.actionTabletopAxis, .horizontal)
}
```

The “tabletop” naming is intentional: the entire tabletop rotates as a unit. A physical horizontal header is a vertical strip before the quarter-turn transform, and a physical vertical action column is a horizontal row before that transform.

- [ ] **Step 3: Run the session/layout tests and verify they fail**

Run:

```bash
xcodebuild test -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/CoachingSessionTests \
  -only-testing:ChessTutorTests/CoachingPanelLayoutTests
```

Expected: FAIL because opponent reply/completion still carry routine states and no composition model exists.

- [ ] **Step 4: Restrict the routine to active Safe–Take–Wake decisions**

Simplify `routine(for:)` in `CoachingSession.swift`:

```swift
private func routine(for stage: CoachingStage) -> [CoachingRoutineState] {
    switch stage {
    case .safeLocate, .safeIdentifyAttacker, .safeResolve:
        return [.safeCurrent, .takePending, .wakePending]
    case .takeChooseMove:
        return [.safeCleared, .takeCurrent, .wakePending]
    case .wakeChoosePiece, .wakeChooseMove:
        return [.safeCleared, .takeCleared, .wakeCurrent]
    case .awaitingAdvice, .checkLocate, .checkResolve, .fallbackChooseMove,
         .opponentCheck, .reviseMove, .complete:
        return []
    }
}
```

Delete the now-unused origin/completed overload.

- [ ] **Step 5: Add a testable composition value**

In `CoachingPanelView.swift`, add:

```swift
enum CoachingPanelComposition: Equatable {
    case tall
    case wide

    var routineTabletopAxis: CoachingPanelAxis {
        self == .tall ? .horizontal : .vertical
    }

    var actionTabletopAxis: CoachingPanelAxis {
        self == .tall ? .vertical : .horizontal
    }
}

extension CoachingPanelLayout {
    var composition: CoachingPanelComposition {
        physicalAxis == .vertical ? .tall : .wide
    }
}
```

- [ ] **Step 6: Move the routine outside the scrolling conversation**

Delete the routine from `conversation`. Add one reserved `routineHeader(axis:)` that always renders all supplied states in a single tabletop row or column; remove `ViewThatFits` and its stacked fallback.

Use compact tokens with 12–13 point rounded text, 26–28 point minimum height, reduced horizontal padding, and the existing colors/accessibility labels. Do not abbreviate Safe, Take, or Wake.

- [ ] **Step 7: Implement separate tall and wide tabletop compositions**

Use the composition value in `body`:

```swift
@ViewBuilder
private var panelContent: some View {
    switch layout.composition {
    case .tall:
        VStack(spacing: 10) {
            routineHeader(axis: .horizontal)
            scrollableConversation
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            panelDivider
            readableActions(axis: .vertical)
        }
    case .wide:
        HStack(spacing: 10) {
            routineHeader(axis: .vertical)
            panelDivider
            VStack(spacing: 10) {
                scrollableConversation
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                panelDivider
                readableActions(axis: .horizontal)
            }
        }
    }
}
```

When `presentation.routine` is empty, omit the routine header and its adjacent divider so opponent reply and completion use the full region. Keep `readableRotationDegrees` on each semantic group as in the current tabletop architecture.

Implement `readableActions(axis:)` with `VStack` for `.vertical` and `HStack` for `.horizontal`. Give each button a minimum 44×44 touch target and use:

```swift
Text(action.title)
    .multilineTextAlignment(.center)
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity, minHeight: 44)
```

- [ ] **Step 8: Make conversation overflow safe and reduce question dominance**

Add to `AppTheme.swift`:

```swift
static let coachingTitleFont = Font.system(size: 24, weight: .semibold, design: .serif)
```

Use it only for the coaching headline. Keep `panelTitleFont` unchanged for ordinary turn status.

Wrap the coaching conversation in a vertical `ScrollView` at every Dynamic Type size:

```swift
private var scrollableConversation: some View {
    ScrollView(.vertical) {
        conversation
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .scrollIndicators(dynamicTypeSize.isAccessibilitySize ? .visible : .automatic)
    .rotationEffect(.degrees(readableRotationDegrees))
}
```

The progress strip and action area remain outside this scroll view.

- [ ] **Step 9: Preserve semantic accessibility order**

Keep sort priorities in the order headline, instruction, routine, actions even though the routine is visually first. Add an assertion for both `.tall` and `.wide` compositions. The routine's labels must continue to expose “cleared,” “current step,” and “coming next.”

- [ ] **Step 10: Run focused tests**

Run the command from Step 3.

Expected: PASS.

- [ ] **Step 11: Build the app to catch SwiftUI generic/layout errors**

Run:

```bash
xcodebuild build -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 12: Commit the responsive-panel slice**

```bash
git add ChessTutor/Coaching/CoachingSession.swift \
  ChessTutor/UI/Coaching/CoachingPanelView.swift \
  ChessTutor/UI/Theme/AppTheme.swift \
  ChessTutorTests/Coaching/CoachingSessionTests.swift \
  ChessTutorTests/UI/CoachingPanelLayoutTests.swift
git commit -m "fix: make coaching panel resilient"
```

---

### Task 5: Run acceptance, regression, and simulator UAT gates

**Files:**
- Modify only if a failing acceptance case exposes a spec mismatch in the files owned by Tasks 1–4.
- Test: all `ChessTutorTests`.

**Interfaces:**
- Consumes: completed implementation from Tasks 1–4.
- Produces: verified test and simulator evidence; no new product behavior.

- [ ] **Step 1: Run the complete test suite**

Run:

```bash
xcodebuild test -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Expected: `** TEST SUCCEEDED **` with zero failures and zero skipped tests. If any test fails, fix the relevant task's implementation and rerun the complete command; do not weaken or skip the test.

- [ ] **Step 2: Build and install a deterministic UAT artifact**

Use the dedicated simulator and an explicit Derived Data location:

```bash
CHESS_UAT_UDID=2405386C-1815-48D7-BA99-53ED13F009A2
CHESS_UAT_DERIVED=/tmp/chess-coaching-scaffolding-derived
xcrun simctl bootstatus "$CHESS_UAT_UDID" -b
xcodebuild build -scheme ChessTutor \
  -destination "platform=iOS Simulator,id=$CHESS_UAT_UDID" \
  -derivedDataPath "$CHESS_UAT_DERIVED"
xcrun simctl install "$CHESS_UAT_UDID" \
  "$CHESS_UAT_DERIVED/Build/Products/Debug-iphonesimulator/ChessTutor.app"
xcrun simctl launch --terminate-running-process "$CHESS_UAT_UDID" \
  org.jasoncrawford.chesstutor
```

Expected: build and install succeed and `simctl launch` returns the ChessTutor process identifier.

- [ ] **Step 3: UAT the opening flow at standard text size**

Set standard text size:

```bash
xcrun simctl ui "$CHESS_UAT_UDID" content_size large
```

Using `/Users/jason/.codex/tools/chesstutor-simtouch`, exercise:

1. Press **Help me** from the starting position.
2. Confirm Safe and Take are cleared, Wake is current, and no candidate rings appear.
3. Tap the blocked a1 rook.
4. Confirm factual blocked-piece feedback and primary Hint.
5. Press Hint once.
6. Confirm the two knights and two center pawns are highlighted and the instruction does not mention movement markers.
7. Select g1 knight, stage g1–f3, choose Looks safe.
8. Confirm the completion introduces “developing” and no routine strip appears during reply/completion.

Capture evidence:

```bash
xcrun simctl io "$CHESS_UAT_UDID" screenshot /tmp/chess-opening-coaching-revised.png
```

- [ ] **Step 4: UAT the threat-priority flow**

Start a new game and reach `1. Nf3 e5 2. a3 e4`, producing a threatened a3 pawn and higher-priority f3 knight. Exercise:

1. Press **Help me**.
2. Tap the a3 pawn and confirm it is acknowledged, compared with the knight, and Hint becomes primary.
3. Tap the f3 knight and confirm the question explicitly requests the black attacker.
4. Tap the e4 pawn and confirm the target/path persist into “How could you help your knight?”
5. Stage a move that does not help the knight and confirm the response names the remaining pawn–knight danger when supported.
6. Stop coaching and confirm the tentative move remains tentative.

Capture evidence:

```bash
xcrun simctl io "$CHESS_UAT_UDID" screenshot /tmp/chess-threat-coaching-revised.png
```

- [ ] **Step 5: Verify the wide physical panel**

Rotate the Simulator one quarter turn with the Simulator menu shortcut automation, relaunch if necessary, and repeat opening Help:

```bash
osascript \
  -e 'tell application "Simulator" to activate' \
  -e 'tell application "System Events" to key code 123 using {command down}'
```

Confirm:

- the physical progress header spans the wide panel;
- conversation is physically left of the action column;
- all three routine labels are present;
- “I don’t see one,” “Looks safe,” and “Keep looking” are never truncated;
- captured pieces remain in their separate panel.

Capture:

```bash
xcrun simctl io "$CHESS_UAT_UDID" screenshot /tmp/chess-coaching-wide-revised.png
```

If macOS denies the Simulator or System Events automation, do not claim portrait/wide UAT; report the permission failure as an explicit verification gap instead.

- [ ] **Step 6: Verify accessibility Dynamic Type**

Set an accessibility size:

```bash
xcrun simctl ui "$CHESS_UAT_UDID" content_size accessibility-extra-large
```

Repeat opening Help and the long lower-priority feedback. Confirm the conversation scrolls while the routine and actions remain available, and capture:

```bash
xcrun simctl io "$CHESS_UAT_UDID" screenshot /tmp/chess-coaching-accessibility-text.png
```

Restore the standard size:

```bash
xcrun simctl ui "$CHESS_UAT_UDID" content_size large
```

- [ ] **Step 7: Inspect the final diff and rerun verification after any UAT fixes**

Run:

```bash
git diff --check
git status --short
xcodebuild test -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Expected: no whitespace errors; only scoped coaching files are modified; complete suite succeeds with zero failures and zero skipped tests.

- [ ] **Step 8: Commit any acceptance-only corrections**

If UAT required code or test corrections, stage only those scoped files and commit:

```bash
git add ChessTutor/Coaching/CoachingModels.swift \
  ChessTutor/Coaching/CoachingSession.swift \
  ChessTutor/Coaching/LocalCoachingExplanationSource.swift \
  ChessTutor/UI/Coaching/CoachingPanelView.swift \
  ChessTutor/UI/Theme/AppTheme.swift
git add ChessTutorTests/Coaching/LocalCoachingExplanationSourceTests.swift \
  ChessTutorTests/Coaching/CoachingSessionTests.swift \
  ChessTutorTests/Coaching/CoachingAcceptanceTests.swift \
  ChessTutorTests/UI/CoachingPanelLayoutTests.swift
git commit -m "fix: finish coaching scaffolding UAT"
```

If UAT required changes outside the scoped files listed in the file-responsibility map, stop and review the scope before committing.

If UAT required no changes, do not create an empty commit.

---

## Final handoff checklist

- [ ] Every exact acceptance criterion in the revision spec is covered by a test or named simulator check above.
- [ ] Full test suite succeeds with zero failures and zero skipped tests.
- [ ] Opening, threat priority, persistent context, opponent reply, Stop, Done, and Keep looking have been exercised.
- [ ] Tall, wide, standard text, and accessibility text presentations have been verified or a precise verification gap is reported.
- [ ] No evaluator, accepted-move, remote-play, promotion, or commit-path behavior changed.
- [ ] Branch is pushed to the existing coaching PR; auto-merge remains disabled.

Push the verified branch without merging it:

```bash
env -u GH_TOKEN -u GITHUB_TOKEN git push
```

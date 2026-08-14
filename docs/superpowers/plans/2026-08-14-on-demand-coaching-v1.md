# On-Demand Coaching V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an entirely local, on-demand chess coach that guides a young beginner through Safe–Take–Wake with board-native questions, progressive hints, and an immediate opponent-reply check.

**Architecture:** Pure coaching analysis lives in a new `Coaching` group and consumes immutable Core chess values. An async `CoachingAdvising` boundary returns semantic advice; a deterministic `CoachingSession` turns that advice and board events into presentation values and narrow directives. `GameSession` owns the live coaching episode and request revision checks, while SwiftUI only routes input and renders the combined coaching region and separate board focus.

**Tech Stack:** Swift 6, SwiftUI, Observation, XCTest, iOS 18, XcodeGen, existing `GameState`/`LegalMoveGenerator`/`PositionAnalyzer` APIs.

## Execution Prerequisite

Merge the approved design/plan PR, update `main`, and use `superpowers:using-git-worktrees` to create a fresh isolated implementation worktree on `codex/on-demand-coaching-v1`. Do not implement this plan on the documentation worktree or as a branch stacked on the documentation branch.

## Global Constraints

- Coaching starts only after the local player explicitly chooses **Help me**.
- V1 is entirely on-device: no Stockfish, network request, generated text, free-text input, or new dependency.
- Safe–Take–Wake is a priority scan, not three mandatory screens; compress only a literally empty Safe or Take scan.
- Use piece values pawn 1, knight 3, bishop 3, rook 5, queen 9; the king has no material value.
- Evaluate captures with the target value and at most one immediate legal recapture.
- Treat check as urgent and material danger as urgent at an estimated loss of at least 2 points.
- Treat a learner capture as profitable at an estimated gain of at least 1 point.
- Reject immediate mate and new clear material loss; notice harmless check without automatically rejecting the move.
- Accept every legal, safe, purposeful move covered by the v1 policy; never insist on a unique best move.
- The tutor may focus, judge, and explain. It never moves or commits a piece; only the existing **Done** path commits.
- Keep chess rules in Core, coaching judgment in `Coaching`, user-facing episode state in `GameSession`, and layout/input wiring in SwiftUI.
- Keep evaluation, insight, and explanation types semantic and provider-independent; no provider registry or plug-in framework.
- The combined coaching region replaces the message/control and selected-piece slots, reflows vertically or horizontally with the existing tabletop layout, and never hides captured pieces.
- Every specific explanation must be supported by current-position evidence. Unsupported positions use the low-confidence fallback.
- Do not change ambient danger, defense, legal-move, path, coverage, promotion, tentative-move, capture-tray, local-play, or remote-play semantics outside an active Help episode.

## File and Responsibility Map

### New app files

- `ChessTutor/Coaching/CoachingModels.swift` — provider-independent requests, evaluations, insights, move assessments, prompts, events, actions, presentations, and protocols.
- `ChessTutor/Coaching/MaterialTacticalEvaluator.swift` — piece values, one-recapture estimates, urgent danger, profitable captures, and one-opponent-reply assessment.
- `ChessTutor/Coaching/LocalCoachingInsightSource.swift` — deterministic Safe, Take, opening Wake, general Wake, ranking, and fallback policy.
- `ChessTutor/Coaching/LocalCoachingAdvisor.swift` — async app-facing composition of the local evaluator and insight source.
- `ChessTutor/Coaching/LocalCoachingExplanationSource.swift` — authored questions, feedback, completion explanations, action labels, hint focus, and accessibility copy.
- `ChessTutor/Coaching/CoachingSession.swift` — parameterized episode state machine, expected answers, hint/miss state, and directives.
- `ChessTutor/UI/Board/CoachFocusOverlay.swift` — visual rendering of coach-only square and relationship focus.
- `ChessTutor/UI/Coaching/CoachingPanelView.swift` — the combined conversation/action surface.

### Modified app files

- `ChessTutor/Game/GameSession.swift` — own the episode, inject the advisor, schedule/resolve versioned requests, route coaching events, preserve the existing move state, and cancel on lifecycle changes.
- `ChessTutor/UI/Board/ChessBoardView.swift` — route identification taps, preserve ordinary movement in move tasks, gate drag behavior, and render coach focus.
- `ChessTutor/UI/Controls/GameControlsView.swift` — present **Help me** beside the ordinary turn action when available.
- `ChessTutor/UI/Sidebar/SidePanelView.swift` — replace two ordinary slots with one responsive coaching region while preserving captured pieces and utilities.
- `ChessTutor/UI/Root/ContentView.swift` — resolve pending async coaching requests and keep promotion availability synchronized.
- `ChessTutor/UI/Theme/AppTheme.swift` — add the small set of coach-focus and panel tokens used by the new views.
- `project.yml` — no source-list change is required because both targets already include their directory roots.
- `ChessTutor.xcodeproj/project.pbxproj` — regenerate from `project.yml` after adding files.

### New test files

- `ChessTutorTests/Coaching/CoachingTestFixtures.swift` — reusable explicit positions and a controllable advisor.
- `ChessTutorTests/Coaching/MaterialTacticalEvaluatorTests.swift` — material and reply-horizon behavior.
- `ChessTutorTests/Coaching/LocalCoachingAdvisorTests.swift` — semantic Safe, Take, Wake, ordering, confidence, and fallback behavior.
- `ChessTutorTests/Coaching/LocalCoachingExplanationSourceTests.swift` — canonical child-facing copy and hint presentations.
- `ChessTutorTests/Coaching/CoachingSessionTests.swift` — event transcripts for every episode branch.
- `ChessTutorTests/Game/GameSessionCoachingTests.swift` — availability, async staleness, input preservation, promotion, and cancellation integration.
- `ChessTutorTests/UI/CoachFocusOverlayTests.swift` — focus geometry/style and reduced-motion policy.
- `ChessTutorTests/UI/CoachingPanelLayoutTests.swift` — combined-region sizing, ordering, axes, controls, and accessibility values.
- `ChessTutorTests/Coaching/CoachingAcceptanceTests.swift` — real-advisor transcripts spanning analysis, session flow, and `GameSession` commit behavior.

---

### Task 1: Establish semantic contracts and one-recapture material math

**Files:**
- Create: `ChessTutor/Coaching/CoachingModels.swift`
- Create: `ChessTutor/Coaching/MaterialTacticalEvaluator.swift`
- Create: `ChessTutorTests/Coaching/CoachingTestFixtures.swift`
- Create: `ChessTutorTests/Coaching/MaterialTacticalEvaluatorTests.swift`
- Modify: `ChessTutor.xcodeproj/project.pbxproj` via `xcodegen generate`

**Interfaces:**
- Consumes: `GameState`, `Board`, `Move`, `MoveCapture`, `Piece`, `PieceColor`, `Square`, `LegalMoveGenerator`.
- Produces: `CoachingRequest`, `CoachingCaptureEstimate`, `CoachingUrgentProblem`, `CoachingOpponentIssue`, `CoachingMoveAssessment`, `CoachingEvaluation`, `CoachingAdvice`, and `CoachingAdvising`; `MaterialTacticalEvaluator.captureEstimate(for:in:)` and `pieceValue(_:)`.

- [ ] **Step 1: Create the failing value and capture-estimate tests**

Create explicit positions containing both kings and assert the exact conventional values and one-recapture arithmetic:

```swift
import XCTest
@testable import ChessTutor

final class MaterialTacticalEvaluatorTests: XCTestCase {
    private let evaluator = MaterialTacticalEvaluator()

    func testUsesBeginnerPieceValues() {
        XCTAssertEqual(evaluator.pieceValue(.pawn), 1)
        XCTAssertEqual(evaluator.pieceValue(.knight), 3)
        XCTAssertEqual(evaluator.pieceValue(.bishop), 3)
        XCTAssertEqual(evaluator.pieceValue(.rook), 5)
        XCTAssertEqual(evaluator.pieceValue(.queen), 9)
        XCTAssertNil(evaluator.pieceValue(.king))
    }

    func testPawnTakingDefendedBishopHasNetGainTwo() throws {
        let attacker = Square(file: .c, rank: 4)
        let target = Square(file: .d, rank: 5)
        let recapturer = Square(file: .e, rank: 6)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                attacker: Piece(kind: .pawn, color: .white),
                target: Piece(kind: .bishop, color: .black),
                recapturer: Piece(kind: .pawn, color: .black),
            ]
        )

        let estimate = try XCTUnwrap(
            evaluator.captureEstimate(
                for: Move(from: attacker, to: target),
                in: state
            )
        )

        XCTAssertEqual(estimate.capturedSquare, target)
        XCTAssertEqual(estimate.netGainForMover, 2)
        XCTAssertEqual(estimate.immediateRecapture?.from, recapturer)
        XCTAssertEqual(estimate.immediateRecapture?.to, target)
    }
}
```

Add tests in the same file for an undefended capture, a losing queen-for-pawn capture, multiple legal recaptures, a pinned illegal recapturer, en passant’s distinct captured and landing squares, and a promoted capturing piece being valued at its promoted kind when recaptured.

- [ ] **Step 2: Run the focused tests and confirm the missing contracts fail**

Run:

```bash
xcodegen generate
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/MaterialTacticalEvaluatorTests
```

Expected: build failure naming missing `MaterialTacticalEvaluator` and coaching model types.

- [ ] **Step 3: Add the provider-independent model contracts**

Define the shared values with these exact public-to-the-module shapes:

```swift
struct CoachingRequest: Equatable, Sendable {
    enum Context: Equatable, Sendable {
        case start
        case tentativeMove(origin: CoachingMoveOrigin)
    }

    let committedState: GameState
    let tentativeMove: Move?
    let learner: PieceColor
    let positionRevision: Int
    let context: Context
}

enum CoachingMoveOrigin: Equatable, Sendable {
    case preexisting
    case check
    case safe
    case take
    case wake
    case fallback
}

protocol CoachingAdvising: Sendable {
    func advice(for request: CoachingRequest) async throws -> CoachingAdvice
}

enum CoachingConfidence: Equatable, Sendable {
    case high
    case unsupported
}

struct CoachingCaptureEstimate: Equatable, Sendable {
    let move: Move
    let capturedPiece: Piece
    let capturedSquare: Square
    let immediateRecapture: Move?
    let netGainForMover: Int
}

struct CoachingUrgentProblem: Equatable, Sendable {
    let target: Square
    let piece: Piece
    let captures: [CoachingCaptureEstimate]
    let worstEstimatedLoss: Int
}

enum CoachingOpponentIssueSeverity: Equatable, Sendable {
    case notice
    case reviseMove
}

enum CoachingOpponentIssueKind: Equatable, Sendable {
    case mateInOne
    case check
    case materialLoss(points: Int)
}

struct CoachingOpponentIssue: Equatable, Sendable {
    let reply: Move
    let kind: CoachingOpponentIssueKind
    let severity: CoachingOpponentIssueSeverity
    let answerSquares: Set<Square>
}

struct CoachingMoveAssessment: Equatable, Sendable {
    let move: Move
    let isLegal: Bool
    let resolvesRequiredDanger: Bool
    let opponentIssues: [CoachingOpponentIssue]
    let concepts: [CoachingConcept]
    let isAcceptable: Bool
}

enum CoachingConcept: Equatable, Hashable, Sendable {
    case kingInCheck
    case pieceNeedsHelp
    case checkingPiece
    case profitableAttacker
    case profitableCapture
    case mateInOne
    case captureResolvesDanger
    case developsKnightOrBishop
    case advancesCenterPawn
    case castlesForKingSafety
    case addsUsefulDefender
    case createsSafeImmediateThreat
    case improvesCentralActivity
    case allowsCheck
    case allowsMateInOne
    case allowsMaterialLoss
    case safeAfterReplyCheck
}

enum CoachingEvidence: Equatable, Sendable {
    case check(attackers: Set<Square>)
    case danger(target: Square, estimatedLoss: Int)
    case capture(CoachingCaptureEstimate)
    case development(source: Square, destination: Square)
    case centerPawn(source: Square, destination: Square)
    case castle(Move)
    case defender(source: Square, target: Square)
    case threat(source: Square, target: Square)
    case mobility(source: Square, destination: Square, before: Int, after: Int)
    case opponentReply(CoachingOpponentIssue)
    case verifiedSafe
}

struct CoachingInsight: Equatable, Sendable {
    let concept: CoachingConcept
    let subjectSquares: Set<Square>
    let candidateMoves: [Move]
    let priority: Int
    let confidence: CoachingConfidence
    let evidence: CoachingEvidence
}

struct CoachingOpportunity: Equatable, Sendable {
    let concept: CoachingConcept
    let subjectSquares: Set<Square>
    let moves: [Move]
    let priority: Int
    let evidence: CoachingEvidence
}

struct CoachingEvaluation: Equatable, Sendable {
    let request: CoachingRequest
    let checkingPieces: Set<Square>
    let opponentHasAnyLegalCapture: Bool
    let learnerHasAnyLegalCapture: Bool
    let opponentCaptureEstimates: [CoachingCaptureEstimate]
    let urgentProblems: [CoachingUrgentProblem]
    let learnerCaptureEstimates: [CoachingCaptureEstimate]
    let mateInOneMoves: Set<Move>
    let moveAssessments: [Move: CoachingMoveAssessment]
}

struct CoachingAdvice: Equatable, Sendable {
    let evaluation: CoachingEvaluation
    let insights: [CoachingInsight]
    let urgentProblems: [CoachingUrgentProblem]
    let takeOpportunities: [CoachingOpportunity]
    let wakeOpportunities: [CoachingOpportunity]
    let moveAssessments: [Move: CoachingMoveAssessment]
    let openingDevelopmentIsRelevant: Bool
    let confidence: CoachingConfidence

    var checkingPieces: Set<Square> { evaluation.checkingPieces }
}
```

Keep child-facing strings out of all these contracts. The evaluator initially leaves `concepts` empty and `isAcceptable` false; the insight source produces enriched move assessments after it has attached verified purpose.

- [ ] **Step 4: Implement one-recapture capture estimation**

Implement `MaterialTacticalEvaluator` as a value type. Use `LegalMoveGenerator.capture(for:in:)`, apply the candidate move, enumerate only immediate legal replies that capture the moving piece on `move.to`, and choose the recapture best for the replying side:

```swift
struct MaterialTacticalEvaluator: Sendable {
    func pieceValue(_ kind: Piece.Kind) -> Int? {
        switch kind {
        case .pawn: 1
        case .knight, .bishop: 3
        case .rook: 5
        case .queen: 9
        case .king: nil
        }
    }

    func captureEstimate(for move: Move, in state: GameState) -> CoachingCaptureEstimate? {
        guard let capture = LegalMoveGenerator.capture(for: move, in: state),
              let mover = state.board[move.from],
              LegalMoveGenerator.legalMoves(for: move.from, in: state).contains(move) else {
            return nil
        }

        let next = state.applyingUnchecked(move)
        let recaptures = LegalMoveGenerator.allLegalMoves(in: next).filter { reply in
            LegalMoveGenerator.capture(for: reply, in: next)?.square == move.to
        }
        let recapture = recaptures.sorted { lhs, rhs in
            let lhsGain = recaptureGain(lhs, in: next)
            let rhsGain = recaptureGain(rhs, in: next)
            if lhsGain != rhsGain { return lhsGain > rhsGain }
            return stableMoveKey(lhs) < stableMoveKey(rhs)
        }.first
        let movedKind: Piece.Kind
        if case let .promotion(kind) = move.special {
            movedKind = kind
        } else {
            movedKind = mover.kind
        }
        let net = pieceValue(capture.piece.kind)! - (recapture == nil ? 0 : pieceValue(movedKind)!)

        return CoachingCaptureEstimate(
            move: move,
            capturedPiece: capture.piece,
            capturedSquare: capture.square,
            immediateRecapture: recapture,
            netGainForMover: net
        )
    }

    private func recaptureGain(_ move: Move, in state: GameState) -> Int {
        guard let capture = LegalMoveGenerator.capture(for: move, in: state),
              let value = pieceValue(capture.piece.kind) else {
            return Int.min
        }
        return value
    }

    private func stableMoveKey(_ move: Move) -> Int {
        let source = (move.from.rank - 1) * 8 + move.from.file.rawValue
        let destination = (move.to.rank - 1) * 8 + move.to.file.rawValue
        return source * 1_000 + destination * 10 + specialOrder(move.special)
    }

    private func specialOrder(_ special: Move.Special?) -> Int {
        switch special {
        case nil: 0
        case .castleKingside: 1
        case .castleQueenside: 2
        case .enPassant: 3
        case .promotion(.queen): 4
        case .promotion(.rook): 5
        case .promotion(.bishop): 6
        case .promotion(.knight): 7
        case .promotion(.pawn), .promotion(.king): 8
        }
    }
}
```

Keep the reply search to one ply. Do not add static-exchange recursion.

- [ ] **Step 5: Add reusable explicit-position fixtures**

Create `CoachingTestFixtures.state(sideToMove:pieces:castlingRights:enPassantTarget:)`. It must insert a white king on a1 and black king on h8 only when the caller did not supply kings, so each test still controls meaningful piece placement.

- [ ] **Step 6: Regenerate the project and run the focused tests**

Run:

```bash
xcodegen generate
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/MaterialTacticalEvaluatorTests
```

Expected: `MaterialTacticalEvaluatorTests` passes with zero failures.

- [ ] **Step 7: Commit the material foundation**

```bash
git add ChessTutor/Coaching/CoachingModels.swift ChessTutor/Coaching/MaterialTacticalEvaluator.swift ChessTutorTests/Coaching/CoachingTestFixtures.swift ChessTutorTests/Coaching/MaterialTacticalEvaluatorTests.swift ChessTutor.xcodeproj/project.pbxproj
git commit -m "Add coaching material evaluation"
```

---

### Task 2: Evaluate urgent danger, profitable captures, and one opponent reply

**Files:**
- Modify: `ChessTutor/Coaching/CoachingModels.swift`
- Modify: `ChessTutor/Coaching/MaterialTacticalEvaluator.swift`
- Modify: `ChessTutorTests/Coaching/MaterialTacticalEvaluatorTests.swift`

**Interfaces:**
- Consumes: Task 1’s capture estimates and `CoachingRequest`.
- Produces: `MaterialTacticalEvaluator.evaluate(_:) -> CoachingEvaluation`, including `checkingPieces`, all opponent capture estimates, ordered `urgentProblems`, all learner capture estimates, and an assessment for every allowed learner move.

- [ ] **Step 1: Add failing policy tests for the exact v1 thresholds**

Add tests with explicit coordinates that assert:

```swift
func testMarksNetLossTwoAsUrgentButNotLonePawnLoss() {
    let bishop = Square(file: .d, rank: 4)
    let pawn = Square(file: .h, rank: 2)
    let state = CoachingTestFixtures.state(
        sideToMove: .white,
        pieces: [
            bishop: Piece(kind: .bishop, color: .white),
            pawn: Piece(kind: .pawn, color: .white),
            Square(file: .c, rank: 5): Piece(kind: .pawn, color: .black),
            Square(file: .h, rank: 7): Piece(kind: .rook, color: .black),
        ]
    )

    let evaluation = evaluator.evaluate(
        CoachingRequest(
            committedState: state,
            tentativeMove: nil,
            learner: .white,
            positionRevision: 7,
            context: .start
        )
    )

    XCTAssertEqual(evaluation.urgentProblems.map(\.target), [bishop])
    XCTAssertFalse(evaluation.urgentProblems.map(\.target).contains(pawn))
}
```

Add separate tests for check always being urgent, greatest-loss ordering, stable square-order ties, gain-1 Take inclusion, equal exchange exclusion, capture resolving Safe inclusion, mate-in-one inclusion, immediate mate rejection, new opponent material loss of 2 rejection, harmless-check notice severity, pinned-move illegality, and the best unavoidable worst-case defense.

- [ ] **Step 2: Run the focused tests and confirm the new evaluation assertions fail**

Run the same focused test target. Expected: failures because `evaluate(_:)` does not yet populate policy fields.

- [ ] **Step 3: Implement legal current-position danger analysis**

Build opponent capture candidates from `PositionAnalyzer.analyze(state).threatsByTarget` and reconstruct their exact `Move(source,destination)`. Before passing them through `captureEstimate`, copy the state, set `sideToMove` to the opponent, and clear `enPassantTarget`; en passant belongs only to the actual side to move. Retain every estimate in stable order so the Safe flow can distinguish a relevant-but-nonurgent tap. Group estimates by learner target. Set `worstEstimatedLoss` to the largest opponent `netGainForMover`, retain groups at 2 or more, and sort by loss descending, target piece value descending, then `rank * 10 + file.rawValue` ascending.

Use `LegalMoveGenerator.checkingPieceSquares(against:in:)` for check. Do not assign material value to the king.

- [ ] **Step 4: Implement learner captures and allowed-move assessments**

Enumerate legal captures from `LegalMoveGenerator.allLegalMoves(in:)`. Retain the estimate data for all captures; the insight layer will label gain 1 or greater as Take.

For every allowed learner move, including an allowed-but-check-illegal move, build `CoachingMoveAssessment`:

```swift
let legalMoves = Set(LegalMoveGenerator.allLegalMoves(in: state))
let allowedMoves = state.board.pieces
    .filter { $0.value.color == request.learner }
    .flatMap { LegalMoveGenerator.allowedMoves(for: $0.key, in: state) }

let assessments = Dictionary(uniqueKeysWithValues: allowedMoves.map { move in
    let isLegal = legalMoves.contains(move)
    return (
        move,
        assessMove(
            move,
            isLegal: isLegal,
            currentUrgentProblems: urgentProblems,
            in: state
        )
    )
})
```

For each legal learner move, apply it, enumerate the opponent’s legal replies, and mark the learner move in `mateInOneMoves` when the opponent has no reply and its king is in check. For opponent-reply assessment, apply each reply and classify it as mate when the learner then has no legal move and remains in check. Create `.mateInOne` with `.reviseMove`, `.check` with `.notice`, and material loss of 2 or more with provisional `.reviseMove`. If the same checking reply is mate, emit only mate. `answerSquares` contains checking piece squares for check/mate and the capturable learner target for material loss.

- [ ] **Step 5: Encode unavoidable-danger comparison without a deeper search**

For each legal learner move, calculate the largest resulting urgent material loss. Mark `resolvesRequiredDanger` when it resolves every avoidable higher-priority problem. If no legal move gets the worst loss below 2, mark every move tied for the smallest worst loss as resolving the required danger and downgrade that unavoidable material issue to `.notice`; moves with a worse reply retain `.reviseMove`. This lets the tutor accept “save what you can” moves without pretending the remaining loss disappeared. Keep this minimax comparison to the immediate capture horizon.

- [ ] **Step 6: Run evaluator and Core rule regression tests**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/MaterialTacticalEvaluatorTests -only-testing:ChessTutorTests/LegalMoveGeneratorTests -only-testing:ChessTutorTests/SpecialMoveTests
```

Expected: all selected suites pass with zero failures.

- [ ] **Step 7: Commit tactical policy evaluation**

```bash
git add ChessTutor/Coaching/CoachingModels.swift ChessTutor/Coaching/MaterialTacticalEvaluator.swift ChessTutorTests/Coaching/MaterialTacticalEvaluatorTests.swift
git commit -m "Evaluate coaching tactics and replies"
```

---

### Task 3: Generate Safe and Take insights behind the async advisor boundary

**Files:**
- Create: `ChessTutor/Coaching/LocalCoachingInsightSource.swift`
- Create: `ChessTutor/Coaching/LocalCoachingAdvisor.swift`
- Create: `ChessTutorTests/Coaching/LocalCoachingAdvisorTests.swift`
- Modify: `ChessTutor.xcodeproj/project.pbxproj` via `xcodegen generate`

**Interfaces:**
- Consumes: `MaterialTacticalEvaluator.evaluate(_:)` and Task 1 semantic contracts.
- Produces: `CoachingInsightSourcing.insights(for:) -> CoachingInsightSet`; `LocalCoachingAdvisor.advice(for:) async throws -> CoachingAdvice`.

- [ ] **Step 1: Add failing semantic-advice tests**

Create async tests that assert semantic identity rather than strings:

```swift
final class LocalCoachingAdvisorTests: XCTestCase {
    private let advisor = LocalCoachingAdvisor()

    func testCheckRanksBeforeMaterialDanger() async throws {
        let state = CoachingTestFixtures.checkedStateWithLooseQueen()
        let advice = try await advisor.advice(
            for: CoachingRequest(
                committedState: state,
                tentativeMove: nil,
                learner: .white,
                positionRevision: 1,
                context: .start
            )
        )

        XCTAssertEqual(advice.insights.first?.concept, .kingInCheck)
        XCTAssertEqual(advice.checkingPieces, [Square(file: .e, rank: 8)])
    }

    func testAnyUrgentPieceRemainsAValidSafeAnswer() async throws {
        let advice = try await advisor.advice(for: CoachingTestFixtures.multipleDangerRequest)

        XCTAssertEqual(Set(advice.urgentProblems.map(\.target)), [
            Square(file: .b, rank: 3),
            Square(file: .f, rank: 4),
        ])
    }
}
```

Add tests for the exact Safe ordering, all urgent targets remaining valid, profitable captures ranked by gain then stable board order, a resolving equal exchange accepted without a “winning” concept, mate-in-one Take, each move-check concept, an arbitrary safe-but-purposeless move remaining unacceptable outside fallback despite `.safeAfterReplyCheck`, and same-request deterministic equality.

- [ ] **Step 2: Run the advisor tests and confirm missing source/advisor failures**

Run:

```bash
xcodegen generate
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/LocalCoachingAdvisorTests
```

Expected: build failure naming `LocalCoachingAdvisor` and `CoachingInsightSourcing`.

- [ ] **Step 3: Implement semantic Safe and Take insight generation**

Define:

```swift
protocol CoachingInsightSourcing: Sendable {
    func insights(for evaluation: CoachingEvaluation) -> CoachingInsightSet
}

struct CoachingInsightSet: Equatable, Sendable {
    let ordered: [CoachingInsight]
    let urgentProblems: [CoachingUrgentProblem]
    let takeOpportunities: [CoachingOpportunity]
    let wakeOpportunities: [CoachingOpportunity]
    let openingDevelopmentIsRelevant: Bool
    let confidence: CoachingConfidence
}
```

Generate `.kingInCheck`, `.pieceNeedsHelp`, `.checkingPiece`, `.profitableAttacker`, `.profitableCapture`, `.mateInOne`, and `.captureResolvesDanger` with subject squares, candidate moves, priority, `.high` confidence, and exact `CoachingEvidence`. The `.kingInCheck` insight carries every legal check-resolving move, and each `.pieceNeedsHelp` insight carries every legal move that resolves its required danger—not only captures—so Safe accepts moving, defending, exchanging, or otherwise saving the piece.

Only include a Take opportunity when its assessment is legal, resolves required danger, and has no revise-level opponent reply. A superficially profitable capture that permits mate or a larger clear loss remains available for factual move feedback but is not offered as a Take answer.

Also derive move-check insights from every assessment: `.allowsMateInOne`, `.allowsCheck`, and `.allowsMaterialLoss` carry the corresponding `.opponentReply` evidence; a legal move with no revise-level reply emits `.safeAfterReplyCheck` with `.verifiedSafe`. These facts explain consequences but do not count as a move’s strategic purpose. Stable-sort every tie; never depend on dictionary iteration order.

- [ ] **Step 4: Compose the async local advisor**

Implement the source-independent boundary as:

```swift
struct LocalCoachingAdvisor: CoachingAdvising {
    private let evaluator: MaterialTacticalEvaluator
    private let insightSource: LocalCoachingInsightSource

    init(
        evaluator: MaterialTacticalEvaluator = MaterialTacticalEvaluator(),
        insightSource: LocalCoachingInsightSource = LocalCoachingInsightSource()
    ) {
        self.evaluator = evaluator
        self.insightSource = insightSource
    }

    func advice(for request: CoachingRequest) async throws -> CoachingAdvice {
        let evaluation = evaluator.evaluate(request)
        let insightSet = insightSource.insights(for: evaluation)
        let purposeConcepts: Set<CoachingConcept> = [
            .kingInCheck,
            .pieceNeedsHelp,
            .profitableCapture,
            .mateInOne,
            .captureResolvesDanger,
            .developsKnightOrBishop,
            .advancesCenterPawn,
            .castlesForKingSafety,
            .addsUsefulDefender,
            .createsSafeImmediateThreat,
            .improvesCentralActivity,
        ]
        let assessments = evaluation.moveAssessments.mapValues { assessment in
            let concepts = insightSet.ordered
                .filter { $0.candidateMoves.contains(assessment.move) }
                .map(\.concept)
            let hasRecognizedPurpose = concepts.contains { purposeConcepts.contains($0) }
            let hasRevisionIssue = assessment.opponentIssues.contains {
                $0.severity == .reviseMove
            }
            return CoachingMoveAssessment(
                move: assessment.move,
                isLegal: assessment.isLegal,
                resolvesRequiredDanger: assessment.resolvesRequiredDanger,
                opponentIssues: assessment.opponentIssues,
                concepts: concepts,
                isAcceptable: assessment.isLegal
                    && assessment.resolvesRequiredDanger
                    && !hasRevisionIssue
                    && (hasRecognizedPurpose || insightSet.confidence == .unsupported)
            )
        }
        return CoachingAdvice(
            evaluation: evaluation,
            insights: insightSet.ordered,
            urgentProblems: insightSet.urgentProblems,
            takeOpportunities: insightSet.takeOpportunities,
            wakeOpportunities: insightSet.wakeOpportunities,
            moveAssessments: assessments,
            openingDevelopmentIsRelevant: insightSet.openingDevelopmentIsRelevant,
            confidence: insightSet.confidence
        )
    }
}
```

The local implementation performs no detached task, network call, loading delay, or provider selection.

- [ ] **Step 5: Regenerate and run advisor plus evaluator tests**

Run:

```bash
xcodegen generate
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/LocalCoachingAdvisorTests -only-testing:ChessTutorTests/MaterialTacticalEvaluatorTests
```

Expected: both suites pass with zero failures.

- [ ] **Step 6: Commit Safe/Take semantic advice**

```bash
git add ChessTutor/Coaching/LocalCoachingInsightSource.swift ChessTutor/Coaching/LocalCoachingAdvisor.swift ChessTutorTests/Coaching/LocalCoachingAdvisorTests.swift ChessTutor.xcodeproj/project.pbxproj
git commit -m "Generate coaching safe and take advice"
```

---

### Task 4: Add opening and general Wake policy with abstention

**Files:**
- Modify: `ChessTutor/Coaching/LocalCoachingInsightSource.swift`
- Modify: `ChessTutorTests/Coaching/LocalCoachingAdvisorTests.swift`

**Interfaces:**
- Consumes: ordered legal move assessments and `PositionAnalyzer` evidence.
- Produces: ordered `.developsKnightOrBishop`, `.advancesCenterPawn`, `.castlesForKingSafety`, `.addsUsefulDefender`, `.createsSafeImmediateThreat`, and `.improvesCentralActivity` opportunities, or `.unsupported` fallback confidence.

- [ ] **Step 1: Add failing opening-context and Wake tests**

Add these exact assertions:

```swift
func testStartingPositionOffersMinorAndCenterPawnWakeMoves() async throws {
    let request = CoachingRequest(
        committedState: .startingPosition(),
        tentativeMove: nil,
        learner: .white,
        positionRevision: 0,
        context: .start
    )

    let advice = try await advisor.advice(for: request)
    let wakeMoves = Set(advice.wakeOpportunities.flatMap(\.moves))

    XCTAssertTrue(advice.openingDevelopmentIsRelevant)
    XCTAssertTrue(wakeMoves.contains(Move(
        from: Square(file: .g, rank: 1),
        to: Square(file: .f, rank: 3)
    )))
    XCTAssertTrue(wakeMoves.contains(Move(
        from: Square(file: .e, rank: 2),
        to: Square(file: .e, rank: 4)
    )))
    XCTAssertFalse(wakeMoves.contains(Move(
        from: Square(file: .a, rank: 2),
        to: Square(file: .a, rank: 3)
    )))
}

func testUnsupportedQuietPositionUsesFallbackConfidence() async throws {
    let advice = try await advisor.advice(for: CoachingTestFixtures.noRecognizedPurposeRequest)

    XCTAssertTrue(advice.urgentProblems.isEmpty)
    XCTAssertTrue(advice.takeOpportunities.isEmpty)
    XCTAssertTrue(advice.wakeOpportunities.isEmpty)
    XCTAssertEqual(advice.confidence, .unsupported)
}
```

Add fixtures and assertions for each side’s home squares, the exact opening-context material condition, legal castling, a newly added defender, a safe attack on an undefended piece, a safe attack on a more valuable piece, movement toward files c–f/ranks 3–6 with mobility increasing by at least two, an unsafe otherwise-purposeful move being excluded, preferred-source ordering, and every qualifying alternative remaining present.

- [ ] **Step 2: Run the advisor suite and confirm Wake tests fail**

Run the focused advisor suite. Expected: starting-position Wake and general-purpose assertions fail because Wake opportunities are empty.

- [ ] **Step 3: Implement exact opening-context detection**

Use position evidence, not move count:

```swift
private func openingDevelopmentIsRelevant(in state: GameState, learner: PieceColor) -> Bool {
    let learnerHomeRank = learner == .white ? 1 : 8
    let minorHomes = [
        Square(file: .b, rank: learnerHomeRank),
        Square(file: .c, rank: learnerHomeRank),
        Square(file: .f, rank: learnerHomeRank),
        Square(file: .g, rank: learnerHomeRank),
    ]
    let hasUndevelopedMinor = minorHomes.contains { square in
        guard let piece = state.board[square] else { return false }
        return piece.color == learner && (piece.kind == .knight || piece.kind == .bishop)
    }
    let bothQueensRemain = [PieceColor.white, .black].allSatisfy { color in
        state.board.pieces.values.contains(Piece(kind: .queen, color: color))
    }
    let bothSidesHaveThreeMajorOrMinorPieces = [PieceColor.white, .black].allSatisfy { color in
        state.board.pieces.values.filter {
            $0.color == color && $0.kind != .pawn && $0.kind != .king
        }.count >= 3
    }
    return hasUndevelopedMinor && bothQueensRemain && bothSidesHaveThreeMajorOrMinorPieces
}
```

Opening candidates are only safe legal moves that move a knight/bishop off its original home square, advance the d/e home pawn toward the center, or castle.

- [ ] **Step 4: Implement general Wake detectors**

For each safe legal move, compare pre-move and post-move analyses and emit evidence only when one of these predicates is proven:

```swift
private let centralSixteen = Set(
    Square.File.allCases
        .filter { (3...6).contains($0.rawValue) }
        .flatMap { file in (3...6).map { Square(file: file, rank: $0) } }
)

private func distanceToCentralSixteen(_ square: Square) -> Int {
    centralSixteen.map { center in
        abs(center.file.rawValue - square.file.rawValue) + abs(center.rank - square.rank)
    }.min() ?? 0
}

private func improvesCentralActivity(
    move: Move,
    learner: PieceColor,
    before: GameState,
    after: GameState
) -> Bool {
    guard let piece = before.board[move.from], piece.kind != .pawn else { return false }
    let beforeDistance = distanceToCentralSixteen(move.from)
    let afterDistance = distanceToCentralSixteen(move.to)
    let beforeMobility = LegalMoveGenerator.legalMoves(for: move.from, by: learner, in: before).count
    let afterMobility = LegalMoveGenerator.legalMoves(for: move.to, by: learner, in: after).count
    return afterDistance < beforeDistance && afterMobility >= beforeMobility + 2
}
```

“Adds a defender” requires the moved piece itself to become a new legal supporter of a learner piece that the opponent could capture before the move. “Creates a safe threat” requires the moved piece to gain a legal capture of an undefended opposing piece or a more valuable opposing piece. Castling is recognized by `Move.Special`, not king displacement inference.

- [ ] **Step 5: Implement candidate-source ordering and unsupported fallback**

Order the first teaching focus by development, defender, immediate threat, central activity, then stable source-square order. Keep every qualifying move in `wakeOpportunities`. Return `.unsupported` only when Safe, Take, opening Wake, and general Wake produce no high-confidence insight. Do not manufacture a generic positional claim.

- [ ] **Step 6: Run all coaching-analysis tests**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/LocalCoachingAdvisorTests -only-testing:ChessTutorTests/MaterialTacticalEvaluatorTests
```

Expected: all coaching-analysis tests pass with zero failures.

- [ ] **Step 7: Commit contextual Wake advice**

```bash
git add ChessTutor/Coaching/LocalCoachingInsightSource.swift ChessTutorTests/Coaching/LocalCoachingAdvisorTests.swift
git commit -m "Add contextual coaching wake advice"
```

---

### Task 5: Build authored presentation and progressive hint mapping

**Files:**
- Modify: `ChessTutor/Coaching/CoachingModels.swift`
- Create: `ChessTutor/Coaching/LocalCoachingExplanationSource.swift`
- Create: `ChessTutorTests/Coaching/LocalCoachingExplanationSourceTests.swift`
- Modify: `ChessTutor.xcodeproj/project.pbxproj` via `xcodegen generate`

**Interfaces:**
- Consumes: semantic prompts, concepts, evidence, hint level, routine status, actions, board task, and focus.
- Produces: `CoachingExplaining.presentation(for:) -> CoachingPresentation` with no chess-policy decisions.

- [ ] **Step 1: Add failing canonical-copy tests**

Create tests for each prompt family and action label. Include these exact examples:

```swift
func testSafeLocatePresentationAsksForBoardTap() {
    let presentation = explainer.presentation(
        for: CoachingPresentationContext(
            prompt: .safeLocate,
            feedback: nil,
            learner: .white,
            hintLevel: 0,
            missesAtCurrentLevel: 0,
            routine: [.safeCurrent, .takePending, .wakePending],
            actions: [.noAnswer, .hint, .stop],
            boardTask: .identify(allowsMoveRevision: false),
            focus: .empty
        )
    )

    XCTAssertEqual(presentation.headline, "Does one of your pieces need help?")
    XCTAssertEqual(presentation.instruction, "Tap that piece, or choose I don’t see one.")
    XCTAssertEqual(presentation.boardTask, .identify(allowsMoveRevision: false))
    XCTAssertEqual(presentation.actions.map(\.title), ["I don’t see one", "Hint", "Stop"])
}

func testFallbackDoesNotInventPurpose() {
    let presentation = explainer.presentation(
        for: CoachingPresentationContext(
            prompt: .fallbackChooseMove,
            feedback: nil,
            learner: .white,
            hintLevel: 0,
            missesAtCurrentLevel: 0,
            routine: [],
            actions: [.hint, .stop],
            boardTask: .move,
            focus: .empty
        )
    )

    XCTAssertEqual(
        presentation.headline,
        "Nothing urgent stands out. Try a move you like, and we’ll check it together."
    )
    XCTAssertEqual(presentation.boardTask, .move)
}
```

Add tests for check source, Safe attacker, Safe resolution, Take, opening Wake, general Wake, Wake destination, opponent reply check, illegal king safety, factual flaw, successful completion, harmless check acknowledgement, correct absence, unrelated tap, and the two-miss “Want a hint?” addition. Assert that no canonical copy contains “best,” evaluation numbers, or “wrong move.”

- [ ] **Step 2: Run the explanation tests and confirm missing presentation types fail**

Run:

```bash
xcodegen generate
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/LocalCoachingExplanationSourceTests
```

Expected: build failure naming missing prompt, presentation, and explainer types.

- [ ] **Step 3: Add semantic interaction and presentation types**

Add these exact shapes to `CoachingModels.swift`:

```swift
enum CoachingAction: Equatable, Hashable, Sendable {
    case noAnswer
    case looksSafe
    case hint
    case stop
    case done
    case keepLooking
}

enum CoachingBoardTask: Equatable, Sendable {
    case none
    case identify(allowsMoveRevision: Bool)
    case move
}

enum CoachingPrompt: Equatable, Sendable {
    case checkLocate
    case checkResolve
    case safeLocate
    case safeIdentifyAttacker(piece: Piece.Kind)
    case safeResolve(piece: Piece.Kind)
    case takeChooseMove
    case wakeChoosePiece(opening: Bool)
    case wakeChooseMove(piece: Piece.Kind)
    case opponentReply(opponent: PieceColor)
    case fallbackChooseMove
    case reviseMove
    case illegalKingSafety
    case complete(origin: CoachingMoveOrigin, idea: CoachingCompletionIdea)
}

enum CoachingCompletionIdea: Equatable, Sendable {
    case resolvesDanger(piece: Piece.Kind)
    case mate
    case profitableCapture(captured: Piece.Kind)
    case develops(piece: Piece.Kind)
    case advancesCenterPawn
    case castles
    case addsDefender(piece: Piece.Kind)
    case createsThreat(piece: Piece.Kind)
    case centralizes(piece: Piece.Kind)
    case verifiedSafe
}

enum CoachingFeedback: Equatable, Sendable {
    case correct
    case correctAlternative
    case relevantButNonurgent(piece: Piece.Kind)
    case unrelatedTap
    case correctAbsence
    case missedExistingAnswer
    case concreteFlaw(kind: CoachingOpponentIssueKind, affectedPiece: Piece.Kind?)
    case dangerStillPresent(piece: Piece.Kind)
    case noRecognizedPurpose
    case harmlessCheckFound
}

enum CoachingRoutineState: Equatable, Sendable {
    case safeCurrent, safeCleared
    case takePending, takeCurrent, takeCleared
    case wakePending, wakeCurrent, wakeCleared
}

struct CoachFocusPath: Equatable, Hashable, Sendable {
    enum Role: Equatable, Hashable, Sendable { case attacker, candidate }
    let source: Square
    let destination: Square
    let role: Role
}

struct CoachFocusPresentation: Equatable, Sendable {
    static let empty = CoachFocusPresentation(
        emphasizedSquares: [], candidateSquares: [], paths: [], pulseID: 0
    )
    let emphasizedSquares: Set<Square>
    let candidateSquares: Set<Square>
    let paths: Set<CoachFocusPath>
    let pulseID: Int
}

enum CoachingActionProminence: Equatable, Sendable {
    case primary
    case secondary
    case quiet
}

struct CoachingActionPresentation: Equatable, Sendable {
    let action: CoachingAction
    let title: String
    let accessibilityLabel: String
    let prominence: CoachingActionProminence
}

struct CoachingPresentationContext: Equatable, Sendable {
    let prompt: CoachingPrompt
    let feedback: CoachingFeedback?
    let learner: PieceColor
    let hintLevel: Int
    let missesAtCurrentLevel: Int
    let routine: [CoachingRoutineState]
    let actions: [CoachingAction]
    let boardTask: CoachingBoardTask
    let focus: CoachFocusPresentation
}

struct CoachingPresentation: Equatable, Sendable {
    let headline: String
    let instruction: String?
    let routine: [CoachingRoutineState]
    let actions: [CoachingActionPresentation]
    let boardTask: CoachingBoardTask
    let focus: CoachFocusPresentation
}

protocol CoachingExplaining: Sendable {
    func presentation(for context: CoachingPresentationContext) -> CoachingPresentation
}
```

- [ ] **Step 4: Implement the authored explanation source**

Implement `LocalCoachingExplanationSource` against `CoachingExplaining`. Map every `CoachingPrompt`/`CoachingFeedback` pair exhaustively. Piece names come from `Piece.Kind.rawValue`; opponent names are “White” or “Black.” `CoachingSession` derives a single `CoachingCompletionIdea` from the accepted move’s semantic concepts, evidence, and source-piece kind; the explanation source never examines chess rules. A completion requires “That works.” plus exactly one verified concept sentence chosen in this order: the originating Safe danger resolution, mate, profitable capture, development, center pawn, castle, defender, safe threat, central activity, verified safety.

Use this canonical base copy; feedback may replace the headline for one render while retaining the current instruction:

| Prompt | Headline | Instruction |
| --- | --- | --- |
| Check locate | “Your king is in check. What is giving check?” | “Tap the piece giving check.” |
| Check resolve | “Make a move that gets your king safe.” | “Move a piece on the board.” |
| Safe locate | “Does one of your pieces need help?” | “Tap that piece, or choose I don’t see one.” |
| Safe attacker | “What could take your {piece}?” | “Tap the attacker.” |
| Safe resolve | “How could you help your {piece}?” | “Make a move on the board.” |
| Take | “Can you find a capture that helps you?” | “Make the capture, or choose I don’t see one.” |
| Opening Wake | “Nothing is in danger yet. Can you help the center or wake up a piece?” | “Tap a piece that could get a job.” |
| General Wake | “Which piece could get a useful job?” | “Tap that piece.” |
| Wake destination | “Where could your {piece} help from?” | “Move it on the board.” |
| Opponent reply | “Could {opponent} check your king or win something?” | “Tap the problem, change your move, or choose Looks safe.” |
| Fallback | “Nothing urgent stands out. Try a move you like, and we’ll check it together.” | “Make a move on the board.” |
| Revise move | “Try another move.” | “Move a piece on the board.” |
| Illegal king safety | “This move leaves your king in check. Try another move.” | “Move a piece on the board.” |

Canonical feedback begins with one of: “Yes.”, “Yes, that works too.”, “That piece is threatened, but it isn’t in big danger.”, “That piece isn’t part of this problem.”, “Right—there isn’t one.”, “There is one to find.”, “Your {piece} would still need help.”, “That move looks safe, but give the piece a clear job.”, or a concrete reply such as “Black could take your queen.” Do not label the child or the move as wrong.

Map hint levels without changing chess judgment:

- level 0: no coach focus;
- level 1: instruction refers to the existing danger, defense, or movement marker;
- level 2: `candidateSquares` narrows to the small answer set;
- level 3: `emphasizedSquares` and an attacker relationship identify the relevant piece(s);
- level 4: add a candidate source/destination path, but do not stage the move.

- [ ] **Step 5: Regenerate and run the copy tests**

Run:

```bash
xcodegen generate
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/LocalCoachingExplanationSourceTests
```

Expected: the complete explanation suite passes with zero failures.

- [ ] **Step 6: Commit authored coaching presentation**

```bash
git add ChessTutor/Coaching/CoachingModels.swift ChessTutor/Coaching/LocalCoachingExplanationSource.swift ChessTutorTests/Coaching/LocalCoachingExplanationSourceTests.swift ChessTutor.xcodeproj/project.pbxproj
git commit -m "Add authored coaching presentation"
```

---

### Task 6: Implement the parameterized coaching episode state machine

**Files:**
- Create: `ChessTutor/Coaching/CoachingSession.swift`
- Create: `ChessTutorTests/Coaching/CoachingSessionTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingTestFixtures.swift`
- Modify: `ChessTutor.xcodeproj/project.pbxproj` via `xcodegen generate`

**Interfaces:**
- Consumes: `CoachingAdvice`, `CoachingExplaining`, `CoachingEvent`, and `CoachingAction`.
- Produces: `CoachingSession.presentation`, `stage`, `handle(_:) -> [CoachingDirective]`, and `receive(_:) -> [CoachingDirective]`.

- [ ] **Step 1: Add failing transcript tests for compressed and full flows**

Drive the state machine only through public events:

```swift
func testStartingPositionCompressesSafeAndTakeIntoOpeningWake() {
    var session = CoachingSession(learner: .white)

    session.receive(CoachingTestFixtures.startingPositionAdvice)

    XCTAssertEqual(session.stage, .wakeChoosePiece(opening: true))
    XCTAssertEqual(session.presentation?.routine, [
        .safeCleared, .takeCleared, .wakeCurrent,
    ])
    XCTAssertEqual(session.presentation?.headline, "Nothing is in danger yet. Can you help the center or wake up a piece?")
}

func testSafeTranscriptAcceptsAnyUrgentPieceThenItsAttacker() {
    var session = CoachingSession(learner: .white)
    session.receive(CoachingTestFixtures.multipleDangerAdvice)

    let chosenTarget = Square(file: .f, rank: 4)
    XCTAssertTrue(session.handle(.squareTapped(chosenTarget)).isEmpty)
    XCTAssertEqual(session.stage, .safeIdentifyAttacker(target: chosenTarget))

    let attacker = Square(file: .f, rank: 7)
    XCTAssertTrue(session.handle(.squareTapped(attacker)).isEmpty)
    XCTAssertEqual(session.stage, .safeResolve(target: chosenTarget))
    XCTAssertEqual(session.presentation?.boardTask, .move)
}
```

Add transcript tests for check and double-check identification, nontrivial Safe with correct/incorrect absence, Safe resolution, nontrivial Take with correct/incorrect absence, unprofitable capture feedback, all qualifying Wake source pieces, accepted Wake moves, fallback, opponent-reply issues, harmless check acknowledgement, successful Looks safe, changing a move, Stop, Keep looking, completion without commit, and hint advancement after two misses.

- [ ] **Step 2: Run the session tests and confirm the missing state machine fails**

Run:

```bash
xcodegen generate
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/CoachingSessionTests
```

Expected: build failure naming `CoachingSession`, `CoachingStage`, `CoachingEvent`, and `CoachingDirective`.

- [ ] **Step 3: Define the parameterized stages, events, and directives**

Use these exact cases:

```swift
enum CoachingStage: Equatable, Sendable {
    case awaitingAdvice(origin: CoachingMoveOrigin?)
    case checkLocate
    case checkResolve
    case safeLocate
    case safeIdentifyAttacker(target: Square)
    case safeResolve(target: Square)
    case takeChooseMove
    case wakeChoosePiece(opening: Bool)
    case wakeChooseMove(piece: Square, opening: Bool)
    case fallbackChooseMove
    case opponentCheck(move: Move, origin: CoachingMoveOrigin)
    case reviseMove(origin: CoachingMoveOrigin)
    case complete(move: Move, origin: CoachingMoveOrigin, concepts: [CoachingConcept])
}

enum CoachingEvent: Equatable, Sendable {
    case squareTapped(Square)
    case moveStaged(Move)
    case actionChosen(CoachingAction)
    case positionChanged(revision: Int)
}

enum CoachingDirective: Equatable, Sendable {
    case requestAdvice(context: CoachingRequest.Context)
    case selectSquare(Square)
    case stop(preservingTentativeMove: Bool)
    case commitWithExistingDonePath
}

struct CoachingSession: Sendable {
    private(set) var stage: CoachingStage
    private(set) var presentation: CoachingPresentation?
    private(set) var hintLevel: Int
    private(set) var missesAtCurrentLevel: Int

    init(
        learner: PieceColor,
        explainer: any CoachingExplaining = LocalCoachingExplanationSource()
    )

    @discardableResult
    mutating func receive(_ advice: CoachingAdvice) -> [CoachingDirective]

    mutating func receiveUnsupportedPosition()

    @discardableResult
    mutating func handle(_ event: CoachingEvent) -> [CoachingDirective]
}
```

Tests compare the session’s observable `stage` and `presentation`; the session itself does not need value equality. `CoachingSession` stores the learner, explainer, latest advice, selected subject, originating move stage, hint level, misses at that level, pulse counter, stage, and presentation. Expected answer sets remain private model state. Extend `CoachingTestFixtures` with the complete advice values consumed by the transcript tests.

- [ ] **Step 4: Implement initial branch selection and compression**

When initial advice arrives:

1. enter check when `checkingPieces` is nonempty;
2. otherwise compress Safe only when the opponent has no legal capture;
3. otherwise ask Safe even when `urgentProblems` is empty;
4. after Safe clears, compress Take only when the learner has no legal capture and no mate-in-one;
5. otherwise ask Take even when no Take opportunity exists;
6. enter opening/general Wake when supported;
7. enter fallback only when confidence is `.unsupported`.

Check maps to the Safe indicator state. Fallback omits the routine indicator rather than marking Wake current. Rebuild `presentation` after every mutation through `CoachingExplaining`; do not store independent UI strings in the state machine.

- [ ] **Step 5: Implement answer evaluation, misses, and hints**

Use semantic accepted sets from advice. Correct alternatives advance exactly like the preferred focus. An incorrect answer sets one factual `CoachingFeedback` and increments misses without increasing `hintLevel`. `.hint` increases the level by exactly one, caps at 4, resets misses, increments `pulseID`, and never stages a move. After two misses at one level, include the Hint action and “Want a hint?” copy.

For an accepted Wake source, return `.selectSquare(source)` and transition to `.wakeChooseMove`. Identification taps never return selection directives for Safe, Take, check, or opponent-reply questions.

- [ ] **Step 6: Implement tentative-move and opponent-reply handling**

`.moveStaged(move)` transitions to `.awaitingAdvice(origin:)` and returns one `.requestAdvice(context: .tentativeMove(origin:))`. If ordinary board input removes the currently checked tentative move before staging its replacement, `.positionChanged(revision:)` invalidates the old advice and enters `.reviseMove(origin:)`; external game mutations use the cancellation paths in Task 7 instead. `receiveUnsupportedPosition()` enters `.fallbackChooseMove` with a generic move task and no position-specific claim. When move advice arrives:

- illegal king-safety assessment returns to the originating move stage with `.illegalKingSafety` copy; `.preexisting` uses `.reviseMove(origin: .preexisting)` and a normal move task;
- a Take move without `.profitableCapture`, `.mateInOne`, or `.captureResolvesDanger` uses the retained capture estimate to explain the immediate recapture/material consequence and returns to `.takeChooseMove`;
- a Safe/check move that does not resolve the required danger returns to its resolution stage with one concrete fact;
- a Wake move without a qualifying Wake concept returns to `.wakeChooseMove` with “try a square where it has a job” copy;
- every other legal candidate enters `.opponentCheck` whether it has reply issues or not;
- answer squares from `.reviseMove` issues are valid identifications;
- finding a revise issue enters `.reviseMove` with board task `.move`;
- finding only notice-level issues acknowledges the check or unavoidable best-case loss and may complete an otherwise acceptable move;
- **Looks safe** completes only when no issue exists and `CoachingMoveAssessment.isAcceptable` is true;
- if no reply issue exists but `isAcceptable` is false, give factual “try a move with a clear purpose” feedback and return to the originating move stage;
- completion returns no commit directive until `.done` is chosen;
- `.keepLooking` and `.stop` return `.stop(preservingTentativeMove: true)`.

- [ ] **Step 7: Run transcript and explanation tests together**

Run:

```bash
xcodegen generate
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/CoachingSessionTests -only-testing:ChessTutorTests/LocalCoachingExplanationSourceTests
```

Expected: all selected tests pass with zero failures.

- [ ] **Step 8: Commit the coaching state machine**

```bash
git add ChessTutor/Coaching/CoachingSession.swift ChessTutorTests/Coaching/CoachingSessionTests.swift ChessTutorTests/Coaching/CoachingTestFixtures.swift ChessTutor.xcodeproj/project.pbxproj
git commit -m "Add coaching episode state machine"
```

---

### Task 7: Integrate versioned coaching episodes into `GameSession`

**Files:**
- Modify: `ChessTutor/Game/GameSession.swift`
- Modify: `ChessTutor/UI/Root/ContentView.swift`
- Create: `ChessTutorTests/Game/GameSessionCoachingTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingTestFixtures.swift`
- Modify: `ChessTutor.xcodeproj/project.pbxproj` via `xcodegen generate`

**Interfaces:**
- Consumes: `any CoachingAdvising`, `CoachingSession`, its events, and its directives.
- Produces: `canRequestCoaching`, `isCoachingActive`, `coachingPresentation`, `pendingCoachingRequestID`, `startCoaching()`, `resolvePendingCoachingAdvice() async`, `handleCoachingSquareTap(_:)`, `chooseCoachingAction(_:)`, and `stopCoaching()`.

- [ ] **Step 1: Add failing Help availability and preservation tests**

Create `GameSessionCoachingTests` and cover the ordinary synchronous boundary first:

```swift
func testHelpIsAvailableOnlyForOngoingUnlockedLocalTurn() {
    let session = GameSession()
    XCTAssertTrue(session.canRequestCoaching)

    session.whitePlayer = .remote(playerID: "maya")
    XCTAssertFalse(session.canRequestCoaching)
}

func testIdentificationTapDoesNotSelectOrClearTentativeMove() async {
    let session = GameSession(
        state: CoachingTestFixtures.looseBishopState,
        coachingAdvisor: ImmediateCoachingAdvisor(
            advice: CoachingTestFixtures.looseBishopAdvice
        )
    )
    session.select(Square(file: .a, rank: 2))
    _ = session.moveSelectedPiece(to: Square(file: .a, rank: 3))
    let tentativeBoard = session.state.board

    session.startCoaching()
    await session.resolvePendingCoachingAdvice()
    let consumed = session.handleCoachingSquareTap(Square(file: .d, rank: 4))

    XCTAssertTrue(consumed)
    XCTAssertEqual(session.state.board, tentativeBoard)
}
```

Add tests for unavailable checkmate/stalemate/remote-lock/promotion states, starting directly from a legal tentative move, starting from a check-illegal tentative move, accepted Wake tap selecting the source, Stop preserving a tentative move, Keep looking preserving it, and coaching Done returning the exact move from `finishTurn()`.

- [ ] **Step 2: Add failing async stale-result and cancellation tests**

Put a controllable actor in `CoachingTestFixtures.swift`:

```swift
actor ControllableCoachingAdvisor: CoachingAdvising {
    private var continuations: [Int: [CheckedContinuation<CoachingAdvice, any Error>]] = [:]

    func advice(for request: CoachingRequest) async throws -> CoachingAdvice {
        try await withCheckedThrowingContinuation { continuation in
            continuations[request.positionRevision, default: []].append(continuation)
        }
    }

    func resolve(revision: Int, with advice: CoachingAdvice) {
        guard var queued = continuations[revision], !queued.isEmpty else { return }
        let continuation = queued.removeFirst()
        continuations[revision] = queued.isEmpty ? nil : queued
        continuation.resume(returning: advice)
    }

    func hasPending(revision: Int) -> Bool {
        !(continuations[revision] ?? []).isEmpty
    }
}

struct ImmediateCoachingAdvisor: CoachingAdvising {
    let advice: CoachingAdvice

    func advice(for request: CoachingRequest) async throws -> CoachingAdvice {
        advice
    }
}

struct FailingCoachingAdvisor: CoachingAdvising {
    struct Failure: Error, Sendable {}

    func advice(for request: CoachingRequest) async throws -> CoachingAdvice {
        throw Failure()
    }
}
```

In `@MainActor` async tests, start resolution, yield until `hasPending(revision:)` is true, mutate the position or stop coaching, resolve the old request, await the task, and assert the old advice did not restore or alter coaching. Cover a newer tentative request superseding an older one, local commit, remote commit, new game, remote lock, checkmate/stalemate result, and explicit Stop. Use `FailingCoachingAdvisor` to prove a current request enters fallback while a stale failure does nothing.

- [ ] **Step 3: Run the integration tests and confirm missing session APIs fail**

Run:

```bash
xcodegen generate
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/GameSessionCoachingTests
```

Expected: build failure naming missing `GameSession` coaching initializer and properties.

- [ ] **Step 4: Add owned episode and versioned pending-request state**

Extend `GameSession` with:

```swift
private struct PendingCoachingRequest: Equatable, Sendable {
    let id: Int
    let request: CoachingRequest
}

private let coachingAdvisor: any CoachingAdvising
private var coachingSession: CoachingSession?
private var pendingCoachingRequest: PendingCoachingRequest?
private var nextCoachingRequestID = 0
private(set) var isAwaitingPromotionChoice = false

var coachingPresentation: CoachingPresentation? { coachingSession?.presentation }
var isCoachingActive: Bool { coachingSession != nil }
var pendingCoachingRequestID: Int? { pendingCoachingRequest?.id }
var canRequestCoaching: Bool {
    committedState.result == .ongoing
        && localCanActForCurrentTurn
        && !isAwaitingPromotionChoice
        && coachingSession == nil
}
```

Change the designated initializer to accept `coachingAdvisor: any CoachingAdvising = LocalCoachingAdvisor()` without altering existing call sites.

- [ ] **Step 5: Queue and resolve async advice with exact stale checks**

`startCoaching()` creates a `CoachingSession`, determines `.start` or `.tentativeMove(origin: .preexisting)` from the current tentative move, and queues a request built from `committedState`, the tentative move, side to move, and `analysisRevision`.

Implement resolution on the main actor:

```swift
@MainActor
func resolvePendingCoachingAdvice() async {
    guard let pending = pendingCoachingRequest,
          coachingSession != nil else { return }

    do {
        let advice = try await coachingAdvisor.advice(for: pending.request)
        guard pendingCoachingRequest?.id == pending.id,
              analysisRevision == pending.request.positionRevision,
              coachingSession != nil else { return }
        pendingCoachingRequest = nil
        applyCoachingDirectives(coachingSession?.receive(advice) ?? [])
    } catch is CancellationError {
        return
    } catch {
        guard pendingCoachingRequest?.id == pending.id,
              analysisRevision == pending.request.positionRevision,
              coachingSession != nil else { return }
        pendingCoachingRequest = nil
        coachingSession?.receiveUnsupportedPosition()
    }
}
```

`receiveUnsupportedPosition()` enters the authored fallback without inventing evaluation. The local advisor must never take this path for a valid ongoing position.

In `ContentView`, add `.task(id: session.pendingCoachingRequestID) { await session.resolvePendingCoachingAdvice() }`. This is scheduling only; SwiftUI does not inspect requests or advice.

- [ ] **Step 6: Route directives through existing move state**

Implement one private directive reducer. `.selectSquare` calls existing `select`; `.requestAdvice` queues a new revision-tagged request; `.stop` clears only coach state/focus/pending request; `.commitWithExistingDonePath` calls `finishTurn()` and returns its `Move?`. `chooseCoachingAction(_:)` returns that committed move so the view can invoke its existing `onCommittedMove` callback.

When ordinary selection or drag preparation removes a tentative move during `.opponentCheck`, clear the matching pending request and send `.positionChanged(revision: analysisRevision)` after `refreshDisplayedAnalysis()`. This moves coaching to `.reviseMove` while the child chooses a replacement. Do not emit this event for the refresh immediately followed by `.moveStaged(move)`.

Call `.moveStaged(move)` after `stage(_:)` has called `refreshDisplayedAnalysis()` and after `promote(from:to:to:)` completes a concrete promotion and refreshes analysis. This guarantees the queued request captures the revision for the displayed tentative board. Do not add a second tentative-move property.

- [ ] **Step 7: Integrate promotion and every cancellation point**

Set `isAwaitingPromotionChoice = true` when `stage(_:)` returns `.needsPromotion`; clear it in `promote`, a new `cancelPromotionChoice()` called from the sheet’s `onDismiss`, and every lifecycle reset. Suppress Help while true.

Call `stopCoaching()` from successful `finishTurn`, successful `commitRemoteMove`, `newGame`, `endRemoteGame`, restored committed moves, and debug state mutation helpers. Add `didSet` guards to `whitePlayer` and `blackPlayer` that stop an active episode only when the current side changes from locally controllable to nonlocal. Stopping clears coach-only focus and pending work but never restores the board.

- [ ] **Step 8: Regenerate and run GameSession coaching plus existing GameSession tests**

Run:

```bash
xcodegen generate
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/GameSessionCoachingTests -only-testing:ChessTutorTests/GameSessionTests
```

Expected: both suites pass with zero failures.

- [ ] **Step 9: Commit session integration**

```bash
git add ChessTutor/Game/GameSession.swift ChessTutor/UI/Root/ContentView.swift ChessTutorTests/Coaching/CoachingTestFixtures.swift ChessTutorTests/Game/GameSessionCoachingTests.swift ChessTutor.xcodeproj/project.pbxproj
git commit -m "Integrate on-demand coaching session"
```

---

### Task 8: Route board-native answers and render separate coach focus

**Files:**
- Create: `ChessTutor/UI/Board/CoachFocusOverlay.swift`
- Modify: `ChessTutor/UI/Board/ChessBoardView.swift`
- Modify: `ChessTutor/UI/Theme/AppTheme.swift`
- Create: `ChessTutorTests/UI/CoachFocusOverlayTests.swift`
- Modify: `ChessTutorTests/Game/GameSessionCoachingTests.swift`
- Modify: `ChessTutor.xcodeproj/project.pbxproj` via `xcodegen generate`

**Interfaces:**
- Consumes: `CoachingPresentation.boardTask`, `CoachFocusPresentation`, and `GameSession.handleCoachingSquareTap(_:)`.
- Produces: coaching input routing, `CoachFocusStyle`, `CoachFocusPathLayout`, and `CoachFocusOverlay` without modifying `BoardGuidancePresentation` semantics.

- [ ] **Step 1: Add failing input-routing and focus tests**

Assert in `GameSessionCoachingTests` that identification consumes correct and incorrect taps without changing selection; absence is answered only through the panel action; move tasks return `false` so the ordinary board handles taps; accepted opponent-issue taps are consumed; and opponent-check taps that form an ordinary tentative-move revision pass through.

Create pure geometry/style tests (`import SwiftUI` for `CGPoint.zero`):

```swift
func testCandidatePathUsesReadableBoardGeometry() {
    let source = Square(file: .b, rank: 1)
    let destination = Square(file: .c, rank: 3)
    let geometry = BoardGuidanceGeometry(
        side: 640,
        origin: .zero,
        viewingAngle: .clockwiseQuarterTurn
    )

    let layout = CoachFocusPathLayout.make(
        from: source,
        to: destination,
        geometry: geometry
    )

    XCTAssertEqual(layout.start, geometry.center(of: source))
    XCTAssertEqual(layout.end, geometry.center(of: destination))
}

func testReducedMotionDisablesCoachPulse() {
    XCTAssertEqual(CoachFocusMotionPolicy(reducesMotion: true).pulseScale, 1)
    XCTAssertGreaterThan(CoachFocusMotionPolicy(reducesMotion: false).pulseScale, 1)
}
```

- [ ] **Step 2: Run the selected tests and confirm focus/input behavior fails**

Run:

```bash
xcodegen generate
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/CoachFocusOverlayTests -only-testing:ChessTutorTests/GameSessionCoachingTests
```

Expected: build failure for missing focus types and failing pass-through assertions.

- [ ] **Step 3: Implement model-owned tap routing**

At the start of `ChessBoardView.handleTap(_:)`, ask `GameSession` whether coaching consumed the square. A `.move` task always passes through. An `.identify` task consumes the tap unless the active opponent-check stage reports that the tap is a valid ordinary revision interaction; `GameSession`, not SwiftUI, makes that decision using current selection, tentative move, and actionable destinations.

During identification without move revision, prevent drag preparation. During opponent check, allow ordinary drag revision and allow tap revision for an actionable source/destination that is not an accepted answer square. Every resulting staged move continues through existing animation and promotion callbacks before the coaching event is sent.

- [ ] **Step 4: Implement the separate coach-focus overlay**

Render `CoachFocusPresentation` in a new non-hit-testing overlay above existing guidance paths and below dragged pieces. Use distinct theme tokens for a soft focus ring and candidate path, while reusing `BoardGuidanceGeometry` for orientation. Pulse once when `pulseID` changes; replace the pulse with a static emphasis under Reduce Motion.

Do not add coach fields to `BoardGuidancePresentation`. Do not alter danger bursts, defense shields, legal dots, attacker paths, coverage colors, or `CoverageContext`.

- [ ] **Step 5: Add text-backed accessibility behavior**

Mark the focus drawing accessibility-hidden. Keep the corresponding question/instruction in the coaching panel as the sole accessible meaning. When identification mode is active, append the current instruction to the board accessibility context without changing individual piece identity/threat labels.

- [ ] **Step 6: Run focus, guidance, and board integration tests**

Run:

```bash
xcodegen generate
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/CoachFocusOverlayTests -only-testing:ChessTutorTests/GameSessionCoachingTests -only-testing:ChessTutorTests/BoardGuidancePresentationTests -only-testing:ChessTutorTests/BoardGuidanceStyleTests
```

Expected: all selected suites pass with zero failures.

- [ ] **Step 7: Commit board-native coaching interaction**

```bash
git add ChessTutor/UI/Board/CoachFocusOverlay.swift ChessTutor/UI/Board/ChessBoardView.swift ChessTutor/UI/Theme/AppTheme.swift ChessTutorTests/UI/CoachFocusOverlayTests.swift ChessTutorTests/Game/GameSessionCoachingTests.swift ChessTutor.xcodeproj/project.pbxproj
git commit -m "Add board-native coaching interaction"
```

---

### Task 9: Build Help controls and the responsive combined coaching region

**Files:**
- Create: `ChessTutor/UI/Coaching/CoachingPanelView.swift`
- Modify: `ChessTutor/UI/Controls/GameControlsView.swift`
- Modify: `ChessTutor/UI/Sidebar/SidePanelView.swift`
- Create: `ChessTutorTests/UI/CoachingPanelLayoutTests.swift`
- Modify: `ChessTutorTests/UI/GameControlsPresentationTests.swift`
- Modify: `ChessTutorTests/UI/CaptureTrayLayoutTests.swift`
- Modify: `ChessTutor.xcodeproj/project.pbxproj` via `xcodegen generate`

**Interfaces:**
- Consumes: `GameSession.canRequestCoaching`, `coachingPresentation`, `startCoaching()`, and `chooseCoachingAction(_:)`.
- Produces: `CoachingPanelLayout`, `SidebarColumnLayout.coachingRegionSize`, ordinary Help presentation, and one combined coach surface spanning the two existing slots.

- [ ] **Step 1: Add failing pure control and layout tests**

Extend `GameControlsPresentationTests` to require a Help action on an eligible ongoing local turn and no Help action during coaching, remote turn, remote lock, pending promotion, or completed game.

Create layout tests with exact current dimensions:

```swift
func testVerticalCoachingRegionSpansMessageAndSelectedSlots() {
    let layout = SidebarColumnLayout.make(for: 760, presentation: .verticalColumn)

    XCTAssertEqual(
        layout.coachingRegionSize.height,
        layout.size(for: .messageAndDone).height
            + SidebarColumnLayout.segmentSpacing
            + layout.size(for: .selectedPiece).height,
        accuracy: 0.01
    )
    XCTAssertEqual(layout.coachingPhysicalAxis, .vertical)
    XCTAssertEqual(layout.size(for: .capturedPieces).height, 255.36, accuracy: 0.01)
}

func testHorizontalCoachingRegionUsesTwoAdjacentSlots() {
    let layout = SidebarColumnLayout.make(for: 760, presentation: .horizontalSegments)
    let segment = layout.size(for: .selectedPiece)

    XCTAssertEqual(
        layout.coachingRegionPhysicalSize.width,
        segment.width * 2 + SidebarColumnLayout.segmentSpacing,
        accuracy: 0.01
    )
    XCTAssertEqual(layout.coachingPhysicalAxis, .horizontal)
    XCTAssertTrue(layout.showsCapturedPanelUtilityFooter)
}
```

Add tests for captured-first and captured-last tabletop ordering, conversation-before-actions accessibility order, action prominence, completion Done/Keep looking, and Stop always present.

- [ ] **Step 2: Run layout/control tests and confirm the new surface fails**

Run:

```bash
xcodegen generate
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/CoachingPanelLayoutTests -only-testing:ChessTutorTests/GameControlsPresentationTests -only-testing:ChessTutorTests/CaptureTrayLayoutTests
```

Expected: build failure for missing `CoachingPanelLayout` and failing Help-action assertions.

- [ ] **Step 3: Add Help to ordinary turn controls**

Extend `GameControlsPresentation` with an optional `.help` supplemental action rather than replacing its existing primary action:

```swift
struct GameControlsPresentation: Equatable {
    enum SupplementalAction: Equatable {
        case help
    }

    // Keep the existing PrimaryAction and SecondaryAction cases.
    let primaryAction: PrimaryAction
    let supplementalActions: [SupplementalAction]
    let secondaryActions: [SecondaryAction]

    init(
        result: GameResult,
        isRemoteGameEnded: Bool = false,
        isRemotePlayAvailable: Bool = false,
        canRequestCoaching: Bool = false
    )
}
```

`GameControlsView` renders the ordinary primary action and a quieter **Help me** control only when `session.canRequestCoaching`. The action calls `session.startCoaching()`. It does not analyze the board in the view. Existing presentation call sites keep their behavior through the default argument.

- [ ] **Step 4: Compute one combined region from the two existing slots**

Add the following pure layout values. `coachingRegionSize` is in the unrotated tabletop coordinate system; the physical size is transposed only when the tabletop makes the ordinary square segments appear side-by-side:

```swift
enum CoachingPanelAxis: Equatable {
    case vertical
    case horizontal
}

enum CoachingPanelAccessibleElement: Equatable {
    case headline
    case instruction
    case routine
    case actions
}

enum CoachingPanelAccessibilityOrder {
    static let elements: [CoachingPanelAccessibleElement] = [
        .headline, .instruction, .routine, .actions,
    ]

    static func sortPriority(for element: CoachingPanelAccessibleElement) -> Double {
        Double(elements.count - (elements.firstIndex(of: element) ?? elements.count))
    }
}

struct CoachingPanelLayout: Equatable {
    let tabletopRegionSize: CGSize
    let physicalRegionSize: CGSize
    let physicalAxis: CoachingPanelAxis

    static func make(sidebar: SidebarColumnLayout) -> CoachingPanelLayout {
        CoachingPanelLayout(
            tabletopRegionSize: sidebar.coachingRegionSize,
            physicalRegionSize: sidebar.coachingRegionPhysicalSize,
            physicalAxis: sidebar.coachingPhysicalAxis
        )
    }
}

extension SidebarColumnLayout {
    var coachingRegionSize: CGSize {
        let message = size(for: .messageAndDone)
        let selected = size(for: .selectedPiece)
        return CGSize(
            width: max(message.width, selected.width),
            height: message.height + Self.segmentSpacing + selected.height
        )
    }

    var coachingPhysicalAxis: CoachingPanelAxis {
        presentation == .verticalColumn ? .vertical : .horizontal
    }

    var coachingRegionPhysicalSize: CGSize {
        guard presentation == .horizontalSegments else {
            return coachingRegionSize
        }
        return CGSize(width: coachingRegionSize.height, height: coachingRegionSize.width)
    }
}
```

Preserve captured-panel dimensions, utility-strip placement, and the captured-panel footer.

Replace the ordinary `ForEach` only while coaching is active:

```swift
@ViewBuilder
private func segmentStack(
    layout: SidebarColumnLayout,
    secondaryActions: [GameControlsPresentation.SecondaryAction]
) -> some View {
    if let coaching = session.coachingPresentation {
        coachingSegmentStack(
            coaching,
            layout: layout,
            secondaryActions: secondaryActions
        )
    } else {
        ordinarySegmentStack(layout: layout, secondaryActions: secondaryActions)
    }
}
```

The coaching stack contains exactly two regions: the combined coaching surface and the unchanged captured-pieces segment. Place captured pieces first or last according to `viewingAngle.sidebarSegmentsInTabletopOrder`.

- [ ] **Step 5: Implement readable responsive coach content**

`CoachingPanelView` renders conversation first and actions second. Keep their outer arrangement as a `VStack` in tabletop coordinates in both presentations: it is physically above/below in the unrotated landscape tabletop and becomes physically side-by-side when the tabletop rotates for portrait. Do not switch the outer region to an `HStack`. Counter-rotate the conversation and action contents individually so text is upright; never counter-rotate the non-square combined outer surface as one unit.

Render short text without overlays. Permit vertical scrolling only at accessibility text sizes when the authored copy cannot fit. Stage states use text plus shape, not color alone. Buttons use at least 44-point hit targets. Apply `CoachingPanelAccessibilityOrder.sortPriority(for:)` so VoiceOver reads headline, instruction, Safe–Take–Wake status, then actions.

- [ ] **Step 6: Route coaching actions through the session**

For every action presentation, call `session.chooseCoachingAction(action)`. If it returns a move for `.done`, invoke the existing `onCommittedMove(move)` callback. **Stop** and **Keep looking** do not call that callback. The normal selected-piece and turn panels return immediately after the episode exits.

- [ ] **Step 7: Run layout, control, capture, and status tests**

Run:

```bash
xcodegen generate
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/CoachingPanelLayoutTests -only-testing:ChessTutorTests/GameControlsPresentationTests -only-testing:ChessTutorTests/CaptureTrayLayoutTests -only-testing:ChessTutorTests/TurnStatusPresentationTests
```

Expected: all selected suites pass with zero failures.

- [ ] **Step 8: Commit responsive coaching UI**

```bash
git add ChessTutor/UI/Coaching/CoachingPanelView.swift ChessTutor/UI/Controls/GameControlsView.swift ChessTutor/UI/Sidebar/SidePanelView.swift ChessTutorTests/UI/CoachingPanelLayoutTests.swift ChessTutorTests/UI/GameControlsPresentationTests.swift ChessTutorTests/UI/CaptureTrayLayoutTests.swift ChessTutor.xcodeproj/project.pbxproj
git commit -m "Add responsive coaching panel"
```

---

### Task 10: Prove complete v1 transcripts and regression safety

**Files:**
- Create: `ChessTutorTests/Coaching/CoachingAcceptanceTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingTestFixtures.swift`
- Modify: `ChessTutorTests/Coaching/CoachingSessionTests.swift`
- Modify: `ChessTutorTests/Game/GameSessionCoachingTests.swift`
- Modify: `ChessTutor.xcodeproj/project.pbxproj` via `xcodegen generate`

**Interfaces:**
- Consumes: the completed local advisor, coaching state machine, `GameSession` integration, and presentation values.
- Produces: executable acceptance transcripts matching every design-spec acceptance criterion.

- [ ] **Step 1: Add end-to-end acceptance transcripts**

Create tests that use the real `LocalCoachingAdvisor`, call `GameSession.startCoaching()`, resolve each pending request, answer through public square/action methods, stage through ordinary move APIs, and assert no move commits before Done:

```swift
@MainActor
func testStartingPositionHelpDevelopsKnightAndWaitsForDone() async {
    let session = GameSession()
    session.startCoaching()
    await session.resolvePendingCoachingAdvice()

    XCTAssertEqual(session.coachingPresentation?.boardTask, .identify(allowsMoveRevision: false))
    XCTAssertTrue(session.handleCoachingSquareTap(Square(file: .g, rank: 1)))

    _ = session.moveSelectedPiece(to: Square(file: .f, rank: 3))
    await session.resolvePendingCoachingAdvice()
    session.chooseCoachingAction(.looksSafe)

    XCTAssertEqual(session.state.sideToMove, .white)
    XCTAssertTrue(session.canFinishTurn)
    XCTAssertEqual(session.coachingPresentation?.actions.map(\.action), [.done, .keepLooking, .stop])

    let move = session.chooseCoachingAction(.done)
    XCTAssertEqual(move, Move(
        from: Square(file: .g, rank: 1),
        to: Square(file: .f, rank: 3)
    ))
    XCTAssertEqual(session.state.sideToMove, .black)
}
```

Add real-advisor transcripts for check resolution, a complete noncompressed Safe–Take–Wake scan, urgent threatened piece, profitable capture with recapture explanation, opening center pawn, general Wake defender, fallback move, serious opponent reply found by the child, harmless check found and accepted, incorrect taps plus four explicit hints, Stop, and Keep looking. Replay one complete transcript twice and assert identical presentations/directives to prove interaction-history determinism.

- [ ] **Step 2: Run acceptance tests and fix only concrete cross-layer gaps**

Run:

```bash
xcodegen generate
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/CoachingAcceptanceTests
```

Expected: all acceptance transcripts pass. If a transcript fails, make the smallest change in the owning layer identified by the failure; do not bypass semantic advice in tests or add chess policy to SwiftUI.

- [ ] **Step 3: Run the full suite**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Expected: all coaching and existing tests pass with zero failures and zero skipped tests.

- [ ] **Step 4: Verify generated project and scope hygiene**

Run these commands independently:

```bash
xcodegen generate
```

```bash
git diff --check
```

```bash
git status --short
```

```bash
rg -n "Stockfish|OpenAI|URLSession|best move|wrong move" ChessTutor/Coaching ChessTutor/UI/Coaching
```

Expected: project generation exits successfully; `git diff --check` is silent; status contains only coaching-v1 files; the search finds no provider/network reference and no prohibited child-facing phrasing except a deliberate test assertion that verifies absence.

- [ ] **Step 5: Verify the responsive surface in both physical orientations**

Run the app on the iPad (A16) simulator and perform this exact smoke path:

1. At the starting position, choose **Help me** and confirm the combined region replaces the ordinary control and selected-piece panels while the capture panel remains.
2. Rotate between landscape and portrait; confirm conversation/actions change from above/below to side-by-side, all text remains upright, and captured pieces remain visible.
3. Choose a Wake piece, stage a move, use **Keep looking**, and confirm the ordinary panels return with the tentative move preserved.
4. Re-enter Help, complete the move, choose **Done**, and confirm the existing move animation/commit and next-turn UI occur once.
5. Enable the largest accessibility text size and Reduce Motion; confirm the panel remains operable, focus is static, and VoiceOver reads conversation before actions.

Expected: all five observations match without clipped required actions, hidden capture state, board rollback, double commit, or coach-driven piece movement.

- [ ] **Step 6: Commit acceptance coverage and final corrections**

```bash
git add ChessTutor ChessTutorTests ChessTutor.xcodeproj/project.pbxproj
git commit -m "Complete on-demand coaching v1"
```

- [ ] **Step 7: Push the implementation branch and open its PR**

```bash
git push -u origin HEAD
```

Expected: `codex/on-demand-coaching-v1` is pushed, CI starts, and a new implementation PR remains open for user review without auto-merge.

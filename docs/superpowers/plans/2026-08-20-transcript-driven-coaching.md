# Transcript-Driven Coaching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace vague, internally-derived coaching copy with deterministic conversations proven by twelve executable board-position transcripts.

**Architecture:** Preserve the authoritative derived-state pipeline (`GameSession` snapshot → `CoachingSession` → `CoachingReconciler` → `CoachingPresentationProjector` → explainer). Enrich the facts crossing that pipeline, separate the previous-action response from the one current ask, and make actions/focus derive from the same semantic question. Golden fixtures exercise the real evaluator and conversation pipeline; production never depends on test transcripts.

**Tech Stack:** Swift 6, SwiftUI, XCTest/XCUITest, XcodeGen, iOS 18, existing pure `Core` chess rules.

## Global Constraints

- Stay inside on-demand Safe–Take–Wake; do not add proactive alerts, review, curriculum, engine analysis, or online AI.
- The deterministic layer owns move verdicts, evidence, actions, and board focus; an explainer only phrases supplied facts.
- The committed board interaction remains authoritative. Never add history-specific rewind transitions.
- Every presentation has one current ask, one explicit answer grammar, and only actions valid for that ask.
- A response to the previous child action is semantically separate from the current ask.
- Hint clears the previous miss response and reveals exactly one truthful clue without mutating ordinary board selection.
- Safe must inspect every attacked learner piece and must treat every positive immediate expected loss, including one pawn, as danger.
- Use `attack`, `threat`, `take`, `capture`, `protect`, `safe`, `center`, and `develop` only with concrete piece relationships or an immediate explanation.
- Do not emit `part of this problem`, `big danger`, `job`, `Tap the problem`, `Nothing urgent stands out`, `clear plan`, `reply to notice`, `win some material`, `come into the game`, `attack something`, `protect another piece`, or `more useful place` as child-facing copy.
- Do not change ordinary chess legality, movement visualization, tentative-move ownership, remote play, or the physical-board layout outside the coaching conversation region.
- Every task follows red → green, runs its focused suite with zero skips, receives review, and ends in one scoped commit.

---

## File map

**Create once in Task 1:**

- `ChessTutorTests/Coaching/CoachingGoldenFixtures.swift` — test-only FEN parser, named positions, named moves, and expected-turn value types.
- `ChessTutorTests/Coaching/CoachingGoldenPositionTests.swift` — proves every fixture and tactical relationship against `Core`.
- `ChessTutorTests/Coaching/CoachingGoldenTranscriptTests.swift` — accumulates end-to-end transcripts as later tasks make each anchor green.

**Modify across focused tasks:**

- `ChessTutor/Coaching/CoachingModels.swift` — semantic evidence, prompts, feedback, candidate grades, and presentation values.
- `ChessTutor/Coaching/CoachingState.swift` — question identity/evidence only when new semantic prerequisites require it.
- `ChessTutor/Coaching/MaterialTacticalEvaluator.swift` — danger threshold and complete opponent-response evidence.
- `ChessTutor/Coaching/LocalCoachingInsightSource.swift` — concrete opportunities and deterministic candidate grading.
- `ChessTutor/Coaching/LocalCoachingAdvisor.swift` — preserve enriched evidence into advice.
- `ChessTutor/Coaching/CoachingReconciler.swift` — derive one current question from current advice, evidence, and interaction.
- `ChessTutor/Coaching/CoachingPresentationProjector.swift` — project semantic facts, contextual actions, hints, and focus.
- `ChessTutor/Coaching/LocalCoachingExplanationSource.swift` — phrase response, ask, instruction, and factual completion separately.
- `ChessTutor/Coaching/CoachingSession.swift` — reduce only current-question actions and identification attempts.
- `ChessTutor/Game/GameSession.swift` — keep action routing and authoritative snapshots aligned with renamed visible semantics.
- `ChessTutor/UI/Coaching/CoachingPanelView.swift` — render response → ask → instruction and preserve accessibility order.
- `ChessTutor/App/CoachingPanelAccessibilityFixture.swift` — fixture for response/ask/instruction semantics in both physical compositions.

**Focused existing tests:**

- `ChessTutorTests/Coaching/MaterialTacticalEvaluatorTests.swift`
- `ChessTutorTests/Coaching/LocalCoachingAdvisorTests.swift`
- `ChessTutorTests/Coaching/CoachingReconcilerTests.swift`
- `ChessTutorTests/Coaching/CoachingPresentationProjectorTests.swift`
- `ChessTutorTests/Coaching/LocalCoachingExplanationSourceTests.swift`
- `ChessTutorTests/Coaching/CoachingSessionTests.swift`
- `ChessTutorTests/Coaching/CoachingAcceptanceTests.swift`
- `ChessTutorTests/Game/GameSessionCoachingTests.swift`
- `ChessTutorTests/UI/CoachingPanelLayoutTests.swift`
- `ChessTutorUITests/CoachingPanelAccessibilityUITests.swift`

---

### Task 1: Add executable golden board fixtures

**Files:**

- Create: `ChessTutorTests/Coaching/CoachingGoldenFixtures.swift`
- Create: `ChessTutorTests/Coaching/CoachingGoldenPositionTests.swift`
- Create: `ChessTutorTests/Coaching/CoachingGoldenTranscriptTests.swift`
- Modify: `ChessTutor.xcodeproj/project.pbxproj` via `xcodegen generate`

**Interfaces:**

- Consumes: `GameState`, `Board`, `Move`, `LegalMoveGenerator` from `ChessTutor/Core`.
- Produces: `CoachingGoldenPosition.state`, named `CoachingGoldenMoves`, and `CoachingGoldenTurn` for Tasks 2–8.

- [ ] **Step 1: Add the test-only position parser and all named fixtures**

Create `CoachingGoldenFixtures.swift` with this complete fixture interface:

```swift
@testable import ChessTutor

enum CoachingGoldenPosition: String, CaseIterable {
    case starting
    case readyToCastle
    case endangeredKnight
    case twoDangerPriorities
    case endangeredPawn
    case protectedPawn
    case winningCapture
    case losingCapture
    case protectPawn
    case createRookThreat
    case cornerKnight
    case exposedQueen
    case harmlessCheck
    case forcedCheck
    case unsupportedEndgame

    var fen: String {
        switch self {
        case .starting:
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        case .readyToCastle:
            "r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4"
        case .endangeredKnight:
            "6k1/8/8/8/4p3/5N2/8/6K1 w - - 0 1"
        case .twoDangerPriorities:
            "r5k1/8/8/8/4p3/P4N2/8/6K1 w - - 0 1"
        case .endangeredPawn:
            "6k1/8/1b6/8/8/4P3/8/7K w - - 0 1"
        case .protectedPawn:
            "6k1/8/5n2/8/6P1/7P/8/6K1 w - - 0 1"
        case .winningCapture:
            "k7/5r2/8/8/2B5/8/8/6K1 w - - 0 1"
        case .losingCapture:
            "6k1/5p2/8/8/2B5/8/8/6K1 w - - 0 1"
        case .protectPawn:
            "6k1/8/5n2/8/6P1/8/7P/6K1 w - - 0 1"
        case .createRookThreat:
            "6k1/8/8/8/3r4/8/8/N5K1 w - - 0 1"
        case .cornerKnight:
            "6k1/8/8/8/8/8/8/N5K1 w - - 0 1"
        case .exposedQueen:
            "3r2k1/8/8/8/8/8/8/3Q2K1 w - - 0 1"
        case .harmlessCheck:
            "r5k1/8/8/8/8/8/8/1N4K1 w - - 0 1"
        case .forcedCheck:
            "k3r3/8/8/1B6/8/8/8/4K3 w - - 0 1"
        case .unsupportedEndgame:
            "7k/8/8/8/3K4/8/8/8 w - - 0 1"
        }
    }

    var state: GameState { CoachingFENParser.parse(fen) }
}

enum CoachingGoldenCase: String, CaseIterable {
    case t1Entry, t1BlockedRook, t1FlankPawn, t1Hint, t1KnightSelected
    case t1PreferredKnight, t1EdgeKnight, t1CenterPawn
    case t2Entry, t2OneSquareKingMove, t2KnightSwitch, t2Castle
    case t3WrongOwnPiece, t3Target, t3WrongAttacker, t3Attacker
    case t3UnresolvedMove, t3ResolvedMove
    case t4LowerPriorityPawn, t4PrimaryKnight
    case t5PawnDanger, t5PawnResolved, t5ProtectedTap, t5ProtectedAbsence
    case t6WrongSource, t6Hint, t6Capture
    case t7UnsafeCapture, t7NoSafeCapture
    case t8AddsDefender
    case t9Entry, t9Hint, t9Completed
    case t10Entry, t10Completed
    case t11Safe, t11QueenLoss, t11IncorrectLooksSafe, t11HarmlessCheck
    case t12CheckLocate, t12WrongChecker, t12Capture, t12Block, t12KingMove
    case t12UnsupportedEntry, t12UnsupportedSafeMove
}

enum CoachingGoldenMoves {
    static let castle = Move(from: sq("e1"), to: sq("g1"), special: .castleKingside)
    static let knightTaken = Move(from: sq("e4"), to: sq("f3"))
    static let pawnTaken = Move(from: sq("a8"), to: sq("a3"))
    static let pawnEscapes = Move(from: sq("e3"), to: sq("e4"))
    static let bishopWinsRook = Move(from: sq("c4"), to: sq("f7"))
    static let bishopTakesPawn = Move(from: sq("c4"), to: sq("f7"))
    static let kingTakesBishop = Move(from: sq("g8"), to: sq("f7"))
    static let addsPawnDefender = Move(from: sq("h2"), to: sq("h3"))
    static let knightTakesPawn = Move(from: sq("f6"), to: sq("g4"))
    static let pawnRecapturesKnight = Move(from: sq("h3"), to: sq("g4"))
    static let knightThreatB3 = Move(from: sq("a1"), to: sq("b3"))
    static let knightThreatC2 = Move(from: sq("a1"), to: sq("c2"))
    static let exposesQueen = Move(from: sq("d1"), to: sq("d4"))
    static let rookTakesQueen = Move(from: sq("d8"), to: sq("d4"))
    static let developsKnight = Move(from: sq("b1"), to: sq("c3"))
    static let rookChecks = Move(from: sq("a8"), to: sq("a1"))
    static let capturesChecker = Move(from: sq("b5"), to: sq("e8"))
    static let blocksChecker = Move(from: sq("b5"), to: sq("e2"))
}

struct CoachingGoldenTurn: Equatable {
    let response: String?
    let ask: String
    let instruction: String?
    let actions: [CoachingAction]
    let actionTitles: [String]
    let boardTask: CoachingBoardTask
    let routine: [CoachingRoutineState]
    let emphasizedSquares: Set<Square>
    let candidateSquares: Set<Square>
    let paths: Set<CoachFocusPath>
}

func sq(_ algebraic: String) -> Square {
    let bytes = Array(algebraic.utf8)
    precondition(bytes.count == 2, "Expected an algebraic square such as e4")
    guard let file = Square.File(rawValue: Int(bytes[0]) - 96),
          let rank = Int(String(UnicodeScalar(bytes[1]))) else {
        preconditionFailure("Invalid algebraic square: \(algebraic)")
    }
    return Square(file: file, rank: rank)
}

enum CoachingFENParser {
    static func parse(_ fen: String) -> GameState {
        let fields = fen.split(separator: " ")
        precondition(fields.count == 6, "FEN must contain six fields")
        precondition(Int(fields[4]) != nil && Int(fields[5]) != nil,
                     "FEN clocks must be integers")

        let ranks = fields[0].split(separator: "/")
        precondition(ranks.count == 8, "FEN must contain eight ranks")
        var pieces: [Square: Piece] = [:]
        for (rankOffset, encodedRank) in ranks.enumerated() {
            var file = 1
            for token in encodedRank {
                if let emptyCount = token.wholeNumberValue {
                    file += emptyCount
                    continue
                }
                guard let squareFile = Square.File(rawValue: file),
                      let piece = piece(for: token) else {
                    preconditionFailure("Invalid FEN board field: \(fields[0])")
                }
                pieces[Square(file: squareFile, rank: 8 - rankOffset)] = piece
                file += 1
            }
            precondition(file == 9, "Each FEN rank must describe eight files")
        }

        let sideToMove: PieceColor
        switch fields[1] {
        case "w": sideToMove = .white
        case "b": sideToMove = .black
        default: preconditionFailure("Invalid FEN side to move")
        }

        let rightsField = fields[2]
        precondition(rightsField == "-" || rightsField.allSatisfy("KQkq".contains),
                     "Invalid FEN castling rights")
        let rights = CastlingRights(
            whiteKingside: rightsField.contains("K"),
            whiteQueenside: rightsField.contains("Q"),
            blackKingside: rightsField.contains("k"),
            blackQueenside: rightsField.contains("q")
        )
        let enPassant = fields[3] == "-" ? nil : sq(String(fields[3]))
        return GameState(
            board: Board(pieces: pieces),
            sideToMove: sideToMove,
            castlingRights: rights,
            enPassantTarget: enPassant
        )
    }

    private static func piece(for token: Character) -> Piece? {
        let color: PieceColor = token.isUppercase ? .white : .black
        let kind: Piece.Kind
        switch token.lowercased() {
        case "k": kind = .king
        case "q": kind = .queen
        case "r": kind = .rook
        case "b": kind = .bishop
        case "n": kind = .knight
        case "p": kind = .pawn
        default: return nil
        }
        return Piece(kind: kind, color: color)
    }
}
```

Keep `sq(_:)` internal to the test target because every golden transcript test uses it. Keep the FEN parser test-only. It parses board, side to move, castling rights, and en-passant target; halfmove/fullmove values are validated but intentionally not stored because `GameState` has no fields for them. Do not add a production FEN parser.

- [ ] **Step 2: Write rule-validation tests before transcript tests**

Create `CoachingGoldenPositionTests.swift` with one test per tactical family:

```swift
final class CoachingGoldenPositionTests: XCTestCase {
    func testAllFixturesContainOneKingPerColor() {
        for fixture in CoachingGoldenPosition.allCases {
            let pieces = fixture.state.board.pieces.values
            XCTAssertEqual(pieces.filter { $0 == Piece(kind: .king, color: .white) }.count, 1, fixture.rawValue)
            XCTAssertEqual(pieces.filter { $0 == Piece(kind: .king, color: .black) }.count, 1, fixture.rawValue)
        }
    }

    func testReadyToCastleFixtureAllowsKingsideCastling() {
        let state = CoachingGoldenPosition.readyToCastle.state
        XCTAssertTrue(LegalMoveGenerator.legalMoves(for: sq("e1"), in: state).contains(CoachingGoldenMoves.castle))
    }

    func testDangerFixturesContainTheSpecifiedCaptures() {
        assertLegal(CoachingGoldenMoves.knightTaken, by: .black, in: .endangeredKnight)
        assertLegal(CoachingGoldenMoves.pawnTaken, by: .black, in: .twoDangerPriorities)
        assertLegal(CoachingGoldenMoves.knightTaken, by: .black, in: .twoDangerPriorities)
        assertLegal(Move(from: sq("b6"), to: sq("e3")), by: .black, in: .endangeredPawn)
        assertLegal(CoachingGoldenMoves.pawnEscapes, by: .white, in: .endangeredPawn)
    }

    func testCaptureFixturesContainWinningAndLosingLines() {
        assertLegal(CoachingGoldenMoves.bishopWinsRook, by: .white, in: .winningCapture)
        let afterBishopTakes = CoachingGoldenPosition.losingCapture.state
            .applyingUnchecked(CoachingGoldenMoves.bishopTakesPawn)
        XCTAssertTrue(LegalMoveGenerator.legalMoves(for: sq("g8"), in: afterBishopTakes).contains(CoachingGoldenMoves.kingTakesBishop))
    }

    func testProtectionFixtureContainsRecaptureLine() {
        let afterH3 = CoachingGoldenPosition.protectPawn.state
            .applyingUnchecked(CoachingGoldenMoves.addsPawnDefender)
        let afterKnightTakes = afterH3.applyingUnchecked(CoachingGoldenMoves.knightTakesPawn)
        XCTAssertTrue(LegalMoveGenerator.legalMoves(for: sq("h3"), in: afterKnightTakes).contains(CoachingGoldenMoves.pawnRecapturesKnight))
    }

    func testCornerKnightMobilityRisesFromTwoToSix() {
        let before = CoachingGoldenPosition.cornerKnight.state
        XCTAssertEqual(LegalMoveGenerator.legalMoves(for: sq("a1"), in: before).count, 2)
        for move in [CoachingGoldenMoves.knightThreatB3, CoachingGoldenMoves.knightThreatC2] {
            let after = before.applyingUnchecked(move)
            XCTAssertEqual(LegalMoveGenerator.legalMoves(for: move.to, by: .white, in: after).count, 6)
        }
    }

    func testOpponentAndCheckFixturesContainTheSpecifiedLines() {
        let queenState = CoachingGoldenPosition.exposedQueen.state.applyingUnchecked(CoachingGoldenMoves.exposesQueen)
        XCTAssertTrue(LegalMoveGenerator.legalMoves(for: sq("d8"), in: queenState).contains(CoachingGoldenMoves.rookTakesQueen))

        let checkingState = CoachingGoldenPosition.harmlessCheck.state
            .applyingUnchecked(CoachingGoldenMoves.developsKnight)
            .applyingUnchecked(CoachingGoldenMoves.rookChecks)
        XCTAssertTrue(LegalMoveGenerator.isKingInCheck(.white, in: checkingState.board))
        XCTAssertFalse(LegalMoveGenerator.allLegalMoves(in: checkingState).isEmpty)

        let forced = CoachingGoldenPosition.forcedCheck.state
        XCTAssertTrue(LegalMoveGenerator.isKingInCheck(.white, in: forced.board))
        XCTAssertTrue(LegalMoveGenerator.legalMoves(for: sq("b5"), in: forced).contains(CoachingGoldenMoves.capturesChecker))
        XCTAssertTrue(LegalMoveGenerator.legalMoves(for: sq("b5"), in: forced).contains(CoachingGoldenMoves.blocksChecker))
    }

    private func assertLegal(
        _ move: Move,
        by color: PieceColor,
        in fixture: CoachingGoldenPosition,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var state = fixture.state
        state.sideToMove = color
        XCTAssertTrue(
            LegalMoveGenerator.legalMoves(for: move.from, in: state).contains(move),
            "Expected \(move) to be legal in \(fixture.rawValue)",
            file: file,
            line: line
        )
    }
}
```

- [ ] **Step 3: Add a skipped-free empty transcript test shell**

Create `CoachingGoldenTranscriptTests.swift` with an ordinary passing inventory test, not skipped placeholders:

```swift
final class CoachingGoldenTranscriptTests: XCTestCase {
    func testCorpusContainsEveryApprovedAnchor() {
        XCTAssertEqual(CoachingGoldenPosition.allCases.count, 15)
        XCTAssertEqual(Set(CoachingGoldenPosition.allCases.map(\.rawValue)).count, 15)
        XCTAssertEqual(CoachingGoldenCase.allCases.count, 46)
        XCTAssertEqual(Set(CoachingGoldenCase.allCases.map(\.rawValue)).count, 46)
    }
}
```

Tasks 4–8 add `goldenTurn(_:)` branches to this class as their production behavior becomes available. Its only public test-helper signature is:

```swift
private func goldenTurn(_ testCase: CoachingGoldenCase) -> CoachingGoldenTurn
```

Each branch must drive a real `CoachingSession` or `GameSession`, perform the board/action steps named by `testCase`, and copy the resulting `CoachingPresentation` plus focus fields into `CoachingGoldenTurn`. Do not add a second `(position, moment)` vocabulary or call the explainer directly.

- [ ] **Step 4: Regenerate the project and run the focused tests**

Run:

```bash
xcodegen generate
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/CoachingGoldenPositionTests -only-testing:ChessTutorTests/CoachingGoldenTranscriptTests
```

Expected: all new tests pass, zero skipped.

- [ ] **Step 5: Commit**

```bash
git add ChessTutorTests/Coaching/CoachingGoldenFixtures.swift ChessTutorTests/Coaching/CoachingGoldenPositionTests.swift ChessTutorTests/Coaching/CoachingGoldenTranscriptTests.swift ChessTutor.xcodeproj/project.pbxproj
git commit -m "test: add coaching transcript fixtures"
```

---

### Task 2: Separate the previous response from the current ask

**Files:**

- Modify: `ChessTutor/Coaching/CoachingModels.swift`
- Modify: `ChessTutor/Coaching/LocalCoachingExplanationSource.swift`
- Modify: `ChessTutor/UI/Coaching/CoachingPanelView.swift`
- Modify: `ChessTutor/App/CoachingPanelAccessibilityFixture.swift`
- Modify: `ChessTutorTests/Coaching/LocalCoachingExplanationSourceTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingAcceptanceTests.swift`
- Modify: `ChessTutorTests/UI/CoachingPanelLayoutTests.swift`
- Modify: `ChessTutorUITests/CoachingPanelAccessibilityUITests.swift`

**Interfaces:**

- Consumes: unchanged `CoachingPresentationContext` prompt/feedback/hint semantics.
- Produces: `CoachingPresentation.response: String?`; `headline` now means only the current ask/completion; accessibility reads response → ask → instruction.

- [ ] **Step 1: Write failing semantic-separation tests**

Add these exact cases to `LocalCoachingExplanationSourceTests.swift`:

```swift
func testMissResponseDoesNotReplaceOpeningAsk() {
    let presentation = source.presentation(for: context(
        prompt: .wakeChoosePiece(purpose: .openingDevelopment(firstMove: true)),
        feedback: .blockedWakePiece(piece: .rook)
    ))
    XCTAssertEqual(presentation.response, "That rook can’t come out yet because other pieces are in the way.")
    XCTAssertEqual(presentation.headline, "A good first step is to move a center pawn or bring out a knight. Which would you like to try?")
    XCTAssertEqual(presentation.instruction, "Tap the piece you want to move.")
}

func testCorrectAbsenceIsSeparateFromNextAsk() {
    let presentation = source.presentation(for: context(
        prompt: .takeChooseMove,
        feedback: .correctAbsence
    ))
    XCTAssertEqual(presentation.response, "Right—there isn’t one.")
    XCTAssertEqual(presentation.headline, "Can one of your pieces make a useful capture?")
}

func testHintHasNoStaleMissResponse() {
    let presentation = source.presentation(for: context(
        prompt: .wakeChoosePiece(purpose: .openingDevelopment(firstMove: true)),
        feedback: nil,
        hint: .candidatePieces
    ))
    XCTAssertNil(presentation.response)
    XCTAssertEqual(presentation.instruction, "Try one of the highlighted knights or center pawns.")
}
```

Add a rendered/accessibility expectation that conversation labels are ordered `response`, `headline`, `instruction` when all three exist and omit `response` cleanly when nil.

- [ ] **Step 2: Run the exact red suite**

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/LocalCoachingExplanationSourceTests -only-testing:ChessTutorTests/CoachingPanelLayoutTests -only-testing:ChessTutorUITests/CoachingPanelAccessibilityUITests
```

Expected: compile failure because `CoachingPresentation.response` does not exist.

- [ ] **Step 3: Add the response field and split explanation construction**

Change `CoachingPresentation` to:

```swift
struct CoachingPresentation: Equatable, Sendable {
    let response: String?
    let headline: String
    let instruction: String?
    let hint: CoachingHint?
    let routine: [CoachingRoutineState]
    let actions: [CoachingActionPresentation]
    let boardTask: CoachingBoardTask
    let focus: CoachFocusPresentation
}
```

In `LocalCoachingExplanationSource.presentation`, keep `baseCopy` as the current ask and replace the merged `headline(for:base:)` path with:

```swift
let base = baseCopy(for: context.prompt, learner: context.learner)
return CoachingPresentation(
    response: responseCopy(for: context),
    headline: base.headline,
    instruction: instruction(for: context, base: base.instruction),
    hint: context.hint,
    routine: context.routine,
    actions: context.actions.map { actionPresentation(for: $0, context: context) },
    boardTask: context.boardTask,
    focus: context.focus
)
```

`responseCopy` returns nil without feedback, returns the acknowledgement alone for ordinary feedback, and returns acknowledgement as `response` while leaving the completion purpose as `headline` for `.complete`. It must never concatenate response and ask.

- [ ] **Step 4: Render and expose semantic order**

In `CoachingPanelView.conversation`, render:

```swift
VStack(alignment: .leading, spacing: 10) {
    if let response = presentation.response {
        Text(response)
            .font(AppTheme.panelBodyFont)
            .foregroundStyle(AppTheme.ink.opacity(0.78))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilitySortPriority(3)
    }
    Text(presentation.headline)
        .font(AppTheme.coachingTitleFont)
        .foregroundStyle(AppTheme.ink)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilitySortPriority(2)
    if let instruction = presentation.instruction {
        Text(instruction)
            .font(AppTheme.panelBodyFont)
            .foregroundStyle(AppTheme.ink.opacity(0.78))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilitySortPriority(1)
    }
}
```

Update the DEBUG accessibility fixture to include all three fields and update the UI tree test to assert `response → headline → instruction → routine → actions` in tall and wide composition.

- [ ] **Step 5: Update exact legacy assertions and run focused green**

Move former merged feedback prefixes into `response` assertions. Keep current copy byte-for-byte in this task; do not start transcript copy changes yet.

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/LocalCoachingExplanationSourceTests -only-testing:ChessTutorTests/CoachingAcceptanceTests -only-testing:ChessTutorTests/CoachingPanelLayoutTests -only-testing:ChessTutorUITests/CoachingPanelAccessibilityUITests
```

Expected: pass, zero skipped.

- [ ] **Step 6: Commit**

```bash
git add ChessTutor/Coaching/CoachingModels.swift ChessTutor/Coaching/LocalCoachingExplanationSource.swift ChessTutor/UI/Coaching/CoachingPanelView.swift ChessTutor/App/CoachingPanelAccessibilityFixture.swift ChessTutorTests/Coaching/LocalCoachingExplanationSourceTests.swift ChessTutorTests/Coaching/CoachingAcceptanceTests.swift ChessTutorTests/UI/CoachingPanelLayoutTests.swift ChessTutorUITests/CoachingPanelAccessibilityUITests.swift
git commit -m "refactor: separate coaching response and ask"
```

---

### Task 3: Make actions and transitions question-specific

**Files:**

- Modify: `ChessTutor/Coaching/CoachingModels.swift`
- Modify: `ChessTutor/Coaching/CoachingPresentationProjector.swift`
- Modify: `ChessTutor/Coaching/CoachingSession.swift`
- Modify: `ChessTutor/Coaching/LocalCoachingExplanationSource.swift`
- Modify: `ChessTutor/UI/Coaching/CoachingPanelView.swift`
- Modify: `ChessTutorTests/Coaching/CoachingPresentationProjectorTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingSessionTests.swift`
- Modify: `ChessTutorTests/Coaching/LocalCoachingExplanationSourceTests.swift`
- Modify: `ChessTutorTests/Game/GameSessionCoachingTests.swift`

**Interfaces:**

- Consumes: `CoachingPresentation.response/headline/instruction` from Task 2.
- Produces: `CoachingAbsenceKind`; contextual visible labels for existing reducer actions; Safe absence action only when absence is a valid claim.

- [ ] **Step 1: Write failing action-validity and wording tests**

Add projector/session cases asserting:

```swift
func testKnownDangerDoesNotOfferAbsenceAction() {
    let context = projector.context(
        learner: .white,
        derived: derived(stage: .safeLocate, questionID: .safeLocate),
        episode: episode(advice: CoachingTestFixtures.singleDangerAdvice)
    )
    XCTAssertEqual(context?.actions, [.hint, .stop])
}

func testTakeAbsenceUsesCaptureSpecificResponse() {
    var session = session(advice: CoachingTestFixtures.noUsefulCaptureAdvice)
    session.handle(.actionChosen(.noAnswer))
    XCTAssertEqual(session.presentation?.response, "Right—there is no safe capture here.")
}

func testCompletionActionsDescribeTheirConsequences() {
    let presentation = source.presentation(for: completeContext())
    XCTAssertEqual(presentation.actions.map(\.title), ["Play this move", "Try another move", "Close help"])
}

func testBlockedRookHintClearsResponseAndRestoresCurrentAsk() {
    var session = startingSession()
    session.handle(.interactionChanged(snapshot(selected: sq("a1"))))
    XCTAssertNotNil(session.presentation?.response)
    session.handle(.actionChosen(.hint))
    XCTAssertNil(session.presentation?.response)
    XCTAssertEqual(session.presentation?.headline, "A center pawn or knight is a simple way to start. Which would you like to move?")
    XCTAssertEqual(session.presentation?.instruction, "Tap a highlighted piece.")
}
```

- [ ] **Step 2: Run red**

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/CoachingPresentationProjectorTests -only-testing:ChessTutorTests/CoachingSessionTests -only-testing:ChessTutorTests/LocalCoachingExplanationSourceTests -only-testing:ChessTutorTests/GameSessionCoachingTests
```

Expected: exact action arrays and new strings fail.

- [ ] **Step 3: Add semantic absence kind and contextual action titles**

Add:

```swift
enum CoachingAbsenceKind: Equatable, Sendable {
    case noPieceNeedsHelp
    case noSafeCapture
}

enum CoachingFeedback: Equatable, Sendable {
    // existing factual cases
    case correctAbsence(CoachingAbsenceKind)
    case missedExistingAnswer(CoachingAbsenceKind)
}
```

Keep the internal `CoachingAction` cases so directive routing remains stable, but derive visible titles from the current prompt:

```swift
case .noAnswer:
    let title = context.prompt == .safeLocate ? "No piece needs help" : "No safe capture"
case .done:
    let title = "Play this move"
case .keepLooking:
    let title = "Try another move"
case .stop:
    let title = "Close help"
```

Use the same exact phrases for accessibility labels, with “Close help” expanded to “Close coaching help.”

- [ ] **Step 4: Make the projected action set depend on current evidence**

Change `actions` to consume `advice` and feedback state. For `.safeLocate`, include `.noAnswer` only when `advice.urgentProblems.isEmpty`; for `.takeChooseMove`, include it as before; for a stated known danger, return only available Hint plus Stop. Hint continues to clear `feedback`, `feedbackAnchor`, and misses before reconciliation.

When handling `.noAnswer`, record `.correctAbsence(.noPieceNeedsHelp)` or `.correctAbsence(.noSafeCapture)` and `.missedExistingAnswer` with the matching kind.

- [ ] **Step 5: Update current opening copy to the approved T1 baseline**

Use exactly:

```text
Ask: A center pawn or knight is a simple way to start. Which would you like to move?
Instruction: Tap one of your two center pawns or one of your knights.
Hint ask: Here are the four pieces you can try.
Hint instruction: Tap a highlighted piece.
```

Do not yet add blocker identity or candidate grading; those arrive in Task 6.

- [ ] **Step 6: Run green and commit**

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/CoachingPresentationProjectorTests -only-testing:ChessTutorTests/CoachingSessionTests -only-testing:ChessTutorTests/LocalCoachingExplanationSourceTests -only-testing:ChessTutorTests/GameSessionCoachingTests
git add ChessTutor/Coaching/CoachingModels.swift ChessTutor/Coaching/CoachingPresentationProjector.swift ChessTutor/Coaching/CoachingSession.swift ChessTutor/Coaching/LocalCoachingExplanationSource.swift ChessTutor/UI/Coaching/CoachingPanelView.swift ChessTutorTests/Coaching/CoachingPresentationProjectorTests.swift ChessTutorTests/Coaching/CoachingSessionTests.swift ChessTutorTests/Coaching/LocalCoachingExplanationSourceTests.swift ChessTutorTests/Game/GameSessionCoachingTests.swift
git commit -m "fix: make coaching actions question-specific"
```

Expected: focused tests pass, zero skipped; only scoped files are committed.

---

### Task 4: Align Safe with danger and protection facts

**Files:**

- Modify: `ChessTutor/Coaching/CoachingModels.swift`
- Modify: `ChessTutor/Coaching/MaterialTacticalEvaluator.swift`
- Modify: `ChessTutor/Coaching/LocalCoachingInsightSource.swift`
- Modify: `ChessTutor/Coaching/LocalCoachingAdvisor.swift`
- Modify: `ChessTutor/Coaching/CoachingReconciler.swift`
- Modify: `ChessTutor/Coaching/CoachingPresentationProjector.swift`
- Modify: `ChessTutor/Coaching/CoachingSession.swift`
- Modify: `ChessTutor/Coaching/LocalCoachingExplanationSource.swift`
- Modify: `ChessTutorTests/Coaching/MaterialTacticalEvaluatorTests.swift`
- Modify: `ChessTutorTests/Coaching/LocalCoachingAdvisorTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingReconcilerTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingSessionTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingGoldenTranscriptTests.swift`

**Interfaces:**

- Consumes: contextual actions and separate response/ask from Tasks 2–3.
- Produces: `CoachingDangerProblem`, positive-loss Safe policy, primary danger comparison, attacked-but-protected fact, and concrete danger resolution.

- [ ] **Step 1: Write failing evaluator and transcript tests for T3, T4, T5, and T8**

Add exact evaluator cases:

```swift
func testOnePawnLossIsADangerProblem() {
    let evaluation = evaluator.evaluate(request(for: CoachingGoldenPosition.endangeredPawn.state))
    XCTAssertEqual(evaluation.dangerProblems.map(\.target), [sq("e3")])
    XCTAssertEqual(evaluation.dangerProblems.first?.worstEstimatedLoss, 1)
}

func testProtectedAttackIsNotPositiveLoss() {
    let evaluation = evaluator.evaluate(request(for: CoachingGoldenPosition.protectedPawn.state))
    XCTAssertTrue(evaluation.dangerProblems.isEmpty)
    let attack = try XCTUnwrap(evaluation.opponentCaptureEstimates.first { $0.capturedSquare == sq("g4") })
    XCTAssertEqual(attack.immediateRecapture, Move(from: sq("h3"), to: sq("g4")))
    XCTAssertLessThanOrEqual(attack.netGainForMover, 0)
}
```

Add golden transcript assertions with these exact response/ask pairs:

```swift
XCTAssertEqual(goldenTurn(.t3Entry).ask, "One of your pieces is in danger. Which one?")
XCTAssertEqual(goldenTurn(.t4LowerPriorityPawn).response,
               "You found a threatened pawn. A knight is worth about three pawns, so losing the knight would cost more.")
XCTAssertEqual(goldenTurn(.t4LowerPriorityPawn).ask,
               "Which piece should you help first?")
XCTAssertEqual(goldenTurn(.t5PawnResolved).ask,
               "Your pawn moved out of the bishop’s path. It is safe now.")
XCTAssertEqual(goldenTurn(.t5ProtectedTap).response,
               "The pawn is attacked, but your other pawn protects it. If the knight takes it, your pawn can take the knight back. No piece needs help right now.")
XCTAssertEqual(goldenTurn(.t8AddsDefender).ask,
               "Your other pawn now protects the threatened pawn. If the knight takes it, your pawn can take the knight back.")
```

- [ ] **Step 2: Run red**

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/MaterialTacticalEvaluatorTests -only-testing:ChessTutorTests/LocalCoachingAdvisorTests -only-testing:ChessTutorTests/CoachingReconcilerTests -only-testing:ChessTutorTests/CoachingSessionTests -only-testing:ChessTutorTests/CoachingGoldenTranscriptTests
```

Expected: compile failure for `dangerProblems`, followed by transcript failures after the type exists.

- [ ] **Step 3: Rename urgency data to danger data and lower the inclusion threshold**

Replace `CoachingUrgentProblem` with:

```swift
struct CoachingDangerProblem: Equatable, Sendable {
    let target: Square
    let piece: Piece
    let pieceValue: Int
    let captures: [CoachingCaptureEstimate]
    let worstEstimatedLoss: Int
}
```

Rename `urgentProblems` to `dangerProblems` in evaluation, advice, insight source, reconciler, projector, fixtures, and tests. In `MaterialTacticalEvaluator`, change the inclusion guard to `worstEstimatedLoss >= 1`. Preserve sort by estimated loss, then piece value, then stable square.

Add:

```swift
extension CoachingAdvice {
    var primaryDangerProblems: [CoachingDangerProblem] {
        guard let first = dangerProblems.first else { return [] }
        return dangerProblems.filter {
            $0.worstEstimatedLoss == first.worstEstimatedLoss
                && $0.pieceValue == first.pieceValue
        }
    }
}
```

Populate `pieceValue` from `MaterialTacticalEvaluator.pieceValue(_:)` when the problem is built. Sort danger problems by estimated loss, then piece value, then stable square, as before. Only a target tied with the first problem on both loss and piece value advances to attacker identification; this accepts genuinely equal dangers without letting stable square order become pedagogy. Any lower-ranked target produces contrastive feedback and returns to Safe locate.

In the same evaluator change, lower the unavoidable-danger and resolution boundary from two points to one point:

```swift
let dangerIsUnavoidable = smallestWorstLoss.map { $0 >= 1 } ?? false
// ...
resolvesRequiredDanger = largestReplyLoss < 1 || isBestUnavoidableDefense
```

This is required for a move that adds a defender to a one-point pawn threat to count as resolving Safe; changing only the problem-list threshold would leave that transcript internally inconsistent.

- [ ] **Step 4: Carry the actual priority and protection facts**

Replace kind-only danger feedback with:

```swift
case lowerPriorityDanger(
    chosen: Piece.Kind,
    chosenLoss: Int,
    primary: Piece.Kind,
    primaryLoss: Int
)
case attackedButProtected(
    target: Piece.Kind,
    attacker: Piece.Kind,
    defender: Piece.Kind
)
```

Classify a learner-piece tap from `opponentCaptureEstimates`:

- target in `primaryDangerProblems`: retain it as `safeTarget`;
- target in a lower-loss danger problem: clear attempted target evidence and record `lowerPriorityDanger`;
- attacked target with `netGainForMover <= 0` and a concrete immediate recapture: set `confirmedSafeAbsence` only when `dangerProblems.isEmpty`, derive the next step, and carry `attackedButProtected` as the one-shot response;
- no opponent capture: record the existing safe-piece fact.

Derive attacker and defender kinds from the committed board at the capture's `move.from` and `immediateRecapture.from`.

- [ ] **Step 5: Make danger resolution factual**

Add:

```swift
enum CoachingDangerResolution: Equatable, Sendable {
    case movedTarget(target: Piece.Kind, attacker: Piece.Kind)
    case capturedAttacker(target: Piece.Kind, attacker: Piece.Kind)
    case addedDefender(defender: Piece.Kind, target: Piece.Kind, attacker: Piece.Kind)
}
```

Carry it in `CoachingCompletionIdea.resolvesDanger`. Derive it by comparing the coached move with the identified target/attacker and by checking whether the move creates the immediate recapture that removes positive loss. Phrase T3, T5, and T8 exactly as the design.

- [ ] **Step 6: Run green, then the broader coaching slice**

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/MaterialTacticalEvaluatorTests -only-testing:ChessTutorTests/LocalCoachingAdvisorTests -only-testing:ChessTutorTests/CoachingReconcilerTests -only-testing:ChessTutorTests/CoachingPresentationProjectorTests -only-testing:ChessTutorTests/CoachingSessionTests -only-testing:ChessTutorTests/CoachingAcceptanceTests -only-testing:ChessTutorTests/CoachingGoldenTranscriptTests
```

Expected: all selected tests pass, zero skipped. Update old threshold fixtures to assert the new product policy; do not weaken expectations.

- [ ] **Step 7: Commit**

```bash
git add ChessTutor/Coaching/CoachingModels.swift ChessTutor/Coaching/MaterialTacticalEvaluator.swift ChessTutor/Coaching/LocalCoachingInsightSource.swift ChessTutor/Coaching/LocalCoachingAdvisor.swift ChessTutor/Coaching/CoachingReconciler.swift ChessTutor/Coaching/CoachingPresentationProjector.swift ChessTutor/Coaching/CoachingSession.swift ChessTutor/Coaching/LocalCoachingExplanationSource.swift ChessTutorTests/Coaching/MaterialTacticalEvaluatorTests.swift ChessTutorTests/Coaching/LocalCoachingAdvisorTests.swift ChessTutorTests/Coaching/CoachingReconcilerTests.swift ChessTutorTests/Coaching/CoachingSessionTests.swift ChessTutorTests/Coaching/CoachingGoldenTranscriptTests.swift
git commit -m "fix: align coaching danger with board facts"
```

---

### Task 5: Explain safe and unsafe captures concretely

**Files:**

- Modify: `ChessTutor/Coaching/CoachingModels.swift`
- Modify: `ChessTutor/Coaching/MaterialTacticalEvaluator.swift`
- Modify: `ChessTutor/Coaching/CoachingReconciler.swift`
- Modify: `ChessTutor/Coaching/CoachingPresentationProjector.swift`
- Modify: `ChessTutor/Coaching/LocalCoachingExplanationSource.swift`
- Modify: `ChessTutorTests/Coaching/MaterialTacticalEvaluatorTests.swift`
- Modify: `ChessTutorTests/Coaching/LocalCoachingExplanationSourceTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingSessionTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingGoldenTranscriptTests.swift`

**Interfaces:**

- Consumes: `CoachingCaptureEstimate` and separate response/ask.
- Produces: `CoachingExchangeFact`; safe-capture prompt; T6/T7 capture and recapture explanations.

- [ ] **Step 1: Write failing exchange-fact tests**

```swift
func testWinningCaptureFactNamesMoverTargetAndNoRecapture() throws {
    let advice = try advice(for: .winningCapture)
    let fact = try XCTUnwrap(exchangeFact(for: CoachingGoldenMoves.bishopWinsRook, in: advice))
    XCTAssertEqual(fact.mover, .bishop)
    XCTAssertEqual(fact.captured, .rook)
    XCTAssertNil(fact.immediateRecapturer)
    XCTAssertEqual(fact.netGainForLearner, 5)
}

func testLosingCaptureFactNamesKingRecapture() throws {
    let advice = try advice(for: .losingCapture, tentativeMove: CoachingGoldenMoves.bishopTakesPawn)
    let fact = try XCTUnwrap(advice.exchangeFact)
    XCTAssertEqual(fact.mover, .bishop)
    XCTAssertEqual(fact.captured, .pawn)
    XCTAssertEqual(fact.immediateRecapturer, .king)
    XCTAssertEqual(fact.netGainForLearner, -2)
}

func testT6AndT7Copy() {
XCTAssertEqual(goldenTurn(.t6WrongSource).ask, "Can one of your pieces safely take a black piece?")
XCTAssertEqual(goldenTurn(.t6Capture).ask,
               "Your bishop took a rook, and Black cannot take the bishop back.")
XCTAssertEqual(goldenTurn(.t7UnsafeCapture).response,
               "Black’s king could take your bishop. You would lose a bishop to take one pawn.")
XCTAssertEqual(goldenTurn(.t7NoSafeCapture).response,
               "Right—there is no safe capture here.")
}
```

- [ ] **Step 2: Run red**

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/MaterialTacticalEvaluatorTests -only-testing:ChessTutorTests/LocalCoachingExplanationSourceTests -only-testing:ChessTutorTests/CoachingSessionTests -only-testing:ChessTutorTests/CoachingGoldenTranscriptTests
```

- [ ] **Step 3: Add the exchange fact and carry it to feedback/completion**

```swift
struct CoachingExchangeFact: Equatable, Sendable {
    let move: Move
    let mover: Piece.Kind
    let captured: Piece.Kind
    let immediateRecapture: Move?
    let immediateRecapturer: Piece.Kind?
    let netGainForLearner: Int
}
```

Build it from the committed board, `CoachingCaptureEstimate`, and tentative opponent issue. Add:

```swift
case unsafeCapture(CoachingExchangeFact)
case safeCapture(CoachingExchangeFact)
```

to semantic feedback/completion as appropriate. Do not reconstruct piece identities inside the explainer.

- [ ] **Step 4: Define safe-capture acceptance and copy**

Keep a Take opportunity only when it is legal, resolves required danger, retains `netGainForLearner > 0` after the best immediate recapture represented by the evaluator, and has no `.reviseMove` opponent issue. Use:

```text
Ask: Can one of your pieces safely take a black piece?
Instruction: Make the capture, or choose No safe capture.
Miss: That piece has no safe capture here.
Hint response: Your bishop has a safe capture.
Hint instruction: Tap the highlighted white piece.
```

For unsupported T7 after `No safe capture`, project response “Right—there is no safe capture here.” and the separate fallback ask “I do not have a confident plan for this position yet.”

- [ ] **Step 5: Run green and commit**

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/MaterialTacticalEvaluatorTests -only-testing:ChessTutorTests/LocalCoachingExplanationSourceTests -only-testing:ChessTutorTests/CoachingSessionTests -only-testing:ChessTutorTests/CoachingAcceptanceTests -only-testing:ChessTutorTests/CoachingGoldenTranscriptTests
git add ChessTutor/Coaching/CoachingModels.swift ChessTutor/Coaching/MaterialTacticalEvaluator.swift ChessTutor/Coaching/CoachingReconciler.swift ChessTutor/Coaching/CoachingPresentationProjector.swift ChessTutor/Coaching/LocalCoachingExplanationSource.swift ChessTutorTests/Coaching/MaterialTacticalEvaluatorTests.swift ChessTutorTests/Coaching/LocalCoachingExplanationSourceTests.swift ChessTutorTests/Coaching/CoachingSessionTests.swift ChessTutorTests/Coaching/CoachingGoldenTranscriptTests.swift
git commit -m "fix: explain coaching captures concretely"
```

Expected: focused tests pass, zero skipped.

---

### Task 6: Ground constructive Wake advice in named evidence

**Files:**

- Modify: `ChessTutor/Coaching/CoachingModels.swift`
- Modify: `ChessTutor/Coaching/LocalCoachingInsightSource.swift`
- Modify: `ChessTutor/Coaching/CoachingReconciler.swift`
- Modify: `ChessTutor/Coaching/CoachingPresentationProjector.swift`
- Modify: `ChessTutor/Coaching/CoachingSession.swift`
- Modify: `ChessTutor/Coaching/LocalCoachingExplanationSource.swift`
- Modify: `ChessTutorTests/Coaching/LocalCoachingAdvisorTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingReconcilerTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingPresentationProjectorTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingSessionTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingGoldenTranscriptTests.swift`
- Modify: `ChessTutorTests/Game/GameSessionCoachingTests.swift`

**Interfaces:**

- Consumes: existing `CoachingEvidence.development/centerPawn/castle/defender/threat/mobility`.
- Produces: graded `CoachingCandidateMove`, concrete `CoachingWakeTask`, blocker identity, and T1/T2/T9/T10 wording.

- [ ] **Step 1: Write failing candidate-grade and concrete-task tests**

```swift
func testStartingKnightMovesHavePreferredAndAcceptableGrades() async throws {
    let advice = try await advisor.advice(for: request(for: CoachingGoldenPosition.starting.state))
    XCTAssertEqual(advice.grade(for: Move(from: sq("g1"), to: sq("f3"))), .preferred)
    XCTAssertEqual(advice.grade(for: Move(from: sq("g1"), to: sq("h3"))), .acceptable)
    XCTAssertEqual(advice.grade(for: Move(from: sq("b1"), to: sq("c3"))), .preferred)
    XCTAssertEqual(advice.grade(for: Move(from: sq("b1"), to: sq("a3"))), .acceptable)
}

func testThreatTaskNamesKnightAndRook() async throws {
    let advice = try await advisor.advice(for: request(for: CoachingGoldenPosition.createRookThreat.state))
    let task = try XCTUnwrap(advice.wakeTasks.first)
    XCTAssertEqual(task, .createThreat(source: sq("a1"), sourcePiece: .knight,
                                      target: sq("d4"), targetPiece: .rook,
                                      candidates: [
                                        .init(move: CoachingGoldenMoves.knightThreatB3, grade: .acceptable),
                                        .init(move: CoachingGoldenMoves.knightThreatC2, grade: .acceptable),
                                      ]))
}

func testMobilityTaskKeepsBeforeAndAfterCounts() async throws {
    let advice = try await advisor.advice(for: request(for: CoachingGoldenPosition.cornerKnight.state))
    XCTAssertTrue(advice.wakeTasks.contains(.improveMobility(
        source: sq("a1"), piece: .knight, before: 2,
        candidates: [
            .init(move: CoachingGoldenMoves.knightThreatB3, grade: .acceptable, resultingMobility: 6),
            .init(move: CoachingGoldenMoves.knightThreatC2, grade: .acceptable, resultingMobility: 6),
        ]
    )))
}
```

Add golden exact copy assertions:

```swift
XCTAssertEqual(goldenTurn(.t1Entry).ask,
               "A center pawn or knight is a simple way to start. Which would you like to move?")
XCTAssertEqual(goldenTurn(.t1BlockedRook).response,
               "Your pawn is blocking that rook. Choose a center pawn or knight.")
XCTAssertEqual(goldenTurn(.t2Entry).ask, "Your king is ready to castle.")
XCTAssertEqual(goldenTurn(.t2Entry).instruction,
               "Move your king two squares toward the rook.")
XCTAssertEqual(goldenTurn(.t9Entry).ask,
               "Your knight can move to a square where it attacks Black’s rook. Can you find the square?")
XCTAssertEqual(goldenTurn(.t10Completed).ask,
               "From there your knight can reach six squares instead of two. That is why knights are often stronger near the center.")
```

- [ ] **Step 2: Run red**

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/LocalCoachingAdvisorTests -only-testing:ChessTutorTests/CoachingReconcilerTests -only-testing:ChessTutorTests/CoachingPresentationProjectorTests -only-testing:ChessTutorTests/CoachingSessionTests -only-testing:ChessTutorTests/CoachingGoldenTranscriptTests -only-testing:ChessTutorTests/GameSessionCoachingTests
```

- [ ] **Step 3: Add candidate and Wake task values**

```swift
enum CoachingCandidateGrade: Equatable, Sendable {
    case preferred
    case acceptable
}

struct CoachingCandidateMove: Equatable, Sendable {
    let move: Move
    let grade: CoachingCandidateGrade
    let resultingMobility: Int?

    init(move: Move, grade: CoachingCandidateGrade, resultingMobility: Int? = nil) {
        self.move = move
        self.grade = grade
        self.resultingMobility = resultingMobility
    }
}

enum CoachingWakeTask: Equatable, Sendable {
    case opening(firstMove: Bool, candidates: [CoachingCandidateMove])
    case castle(move: Move)
    case protect(source: Square, sourcePiece: Piece.Kind, target: Square, targetPiece: Piece.Kind,
                 candidates: [CoachingCandidateMove])
    case createThreat(source: Square, sourcePiece: Piece.Kind, target: Square, targetPiece: Piece.Kind,
                      candidates: [CoachingCandidateMove])
    case improveMobility(source: Square, piece: Piece.Kind, before: Int,
                         candidates: [CoachingCandidateMove])
}

extension CoachingWakeTask {
    var candidates: [CoachingCandidateMove] {
        switch self {
        case let .opening(_, candidates),
             let .protect(_, _, _, _, candidates),
             let .createThreat(_, _, _, _, candidates),
             let .improveMobility(_, _, _, candidates):
            candidates
        case .castle:
            []
        }
    }
}

extension CoachingAdvice {
    func grade(for move: Move) -> CoachingCandidateGrade? {
        wakeTasks.lazy
            .flatMap(\.candidates)
            .first(where: { $0.move == move })?
            .grade
    }
}
```

Add `let wakeTasks: [CoachingWakeTask]` to `CoachingAdvice`. Group current per-move opportunities into semantic tasks by exact evidence identity: same purpose, source, target, and measurement values. Sort each task's candidates with the existing stable move key and sort tasks by the best underlying insight priority followed by that stable first-candidate key. Existing insights may remain per move. The `grade(for:)` and `wakeTasks` APIs above are the only new read surface consumed by the tests and projector.

- [ ] **Step 4: Grade only evidence-backed opening moves**

For a knight leaving its original square:

- grade `preferred` when destination is closer to the central sixteen and has strictly greater mobility than the alternative edge destination;
- otherwise grade `acceptable`.

For the starting position this yields f3/c3 preferred and h3/a3 acceptable. Center pawn moves remain `preferred` under the bounded first-move curriculum. All other verified Wake candidates default to `acceptable` unless their existing evidence provides the explicit same-purpose comparison; do not invent grades.

- [ ] **Step 5: Preserve concrete source/target and blocker data**

Change blocked feedback to:

```swift
case blockedWakePiece(piece: Piece.Kind, blocker: Piece.Kind)
```

Find the first occupied square on each allowed sliding ray when a selected home bishop/rook/queen has no move. T1 a1 must identify the a2 pawn. Do not infer a blocker for knights or kings.

Project `CoachingPrompt` with a `CoachingWakeTask` rather than a purpose-only enum. Opening may ask for any grouped source; threat and mobility tasks name their verified source/target; castling skips the source quiz and gives the direct instruction.

- [ ] **Step 6: Produce factual completion by candidate grade**

Use the exact completion rules:

- preferred center knight: “You developed your knight toward the center. From there it can reach more squares.”
- acceptable edge knight: “You developed your knight. A square closer to the center would usually give it more choices.”
- center pawn: “Your center pawn moved forward and now helps control the center.”
- castle: “You castled. Your king moved toward safety, and your rook moved toward the center.”
- threat: “Your knight now attacks the rook. Black may need to move or protect it.”
- mobility: use exact before/after counts from evidence.

- [ ] **Step 7: Run green and commit**

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/LocalCoachingAdvisorTests -only-testing:ChessTutorTests/CoachingReconcilerTests -only-testing:ChessTutorTests/CoachingPresentationProjectorTests -only-testing:ChessTutorTests/CoachingSessionTests -only-testing:ChessTutorTests/CoachingAcceptanceTests -only-testing:ChessTutorTests/CoachingGoldenTranscriptTests -only-testing:ChessTutorTests/GameSessionCoachingTests
git add ChessTutor/Coaching/CoachingModels.swift ChessTutor/Coaching/LocalCoachingInsightSource.swift ChessTutor/Coaching/CoachingReconciler.swift ChessTutor/Coaching/CoachingPresentationProjector.swift ChessTutor/Coaching/CoachingSession.swift ChessTutor/Coaching/LocalCoachingExplanationSource.swift ChessTutorTests/Coaching/LocalCoachingAdvisorTests.swift ChessTutorTests/Coaching/CoachingReconcilerTests.swift ChessTutorTests/Coaching/CoachingPresentationProjectorTests.swift ChessTutorTests/Coaching/CoachingSessionTests.swift ChessTutorTests/Coaching/CoachingGoldenTranscriptTests.swift ChessTutorTests/Game/GameSessionCoachingTests.swift
git commit -m "feat: ground coaching plans in evidence"
```

Expected: focused tests pass, zero skipped.

---

### Task 7: Use one opponent-response grammar and explain check resolution

**Files:**

- Modify: `ChessTutor/Coaching/CoachingModels.swift`
- Modify: `ChessTutor/Coaching/MaterialTacticalEvaluator.swift`
- Modify: `ChessTutor/Coaching/CoachingSession.swift`
- Modify: `ChessTutor/Coaching/CoachingReconciler.swift`
- Modify: `ChessTutor/Coaching/CoachingPresentationProjector.swift`
- Modify: `ChessTutor/Coaching/LocalCoachingExplanationSource.swift`
- Modify: `ChessTutorTests/Coaching/MaterialTacticalEvaluatorTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingSessionTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingAcceptanceTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingGoldenTranscriptTests.swift`
- Modify: `ChessTutorTests/UI/CoachFocusOverlayTests.swift`

**Interfaces:**

- Consumes: current tentative move assessment and full opponent `reply` move.
- Produces: opponent source/destination/affected target fact, source-only answer grammar, hypothetical reply focus, check-resolution method, and honest fallback.

- [ ] **Step 1: Write failing T11/T12 and focus tests**

```swift
func testMaterialIssueUsesOpponentSourceAsAnswer() throws {
    let assessment = try assessment(
        position: .exposedQueen,
        tentativeMove: CoachingGoldenMoves.exposesQueen
    )
    let issue = try XCTUnwrap(assessment.opponentIssues.first)
    XCTAssertEqual(issue.reply, CoachingGoldenMoves.rookTakesQueen)
    XCTAssertEqual(issue.answerSquares, [sq("d8")])
    XCTAssertEqual(issue.affectedSquare, sq("d4"))
}

func testOpponentPromptHasOneTapGrammar() {
    let turn = goldenTurn(.t11QueenLoss)
    XCTAssertEqual(turn.ask, "What could Black do after your move?")
    XCTAssertEqual(turn.instruction,
                   "Tap a black piece that could check your king or take one of your pieces. Otherwise choose Looks safe.")
}

func testQueenLossAndHarmlessCheckCopy() {
    XCTAssertEqual(goldenTurn(.t11QueenLoss).response,
                   "Black’s rook could take your queen.")
    XCTAssertEqual(goldenTurn(.t11HarmlessCheck).response,
                   "That rook could move down to your back row and check your king. You could answer the check, so your knight move still works.")
}

func testForcedCheckCompletionNamesMethod() {
    XCTAssertEqual(goldenTurn(.t12Capture).ask,
                   "Your bishop took the checking rook. Your king is safe.")
    XCTAssertEqual(goldenTurn(.t12Block).ask,
                   "Your bishop blocked the rook’s path. Your king is safe.")
}
```

Add a focus assertion that the queen-loss Hint path is d8→d4 and the harmless-check Hint path is a8→a1.

- [ ] **Step 2: Run red**

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/MaterialTacticalEvaluatorTests -only-testing:ChessTutorTests/CoachingSessionTests -only-testing:ChessTutorTests/CoachingAcceptanceTests -only-testing:ChessTutorTests/CoachingGoldenTranscriptTests -only-testing:ChessTutorTests/CoachFocusOverlayTests
```

- [ ] **Step 3: Preserve full opponent-response facts**

Change `CoachingOpponentIssue` to:

```swift
struct CoachingOpponentIssue: Equatable, Sendable {
    let reply: Move
    let kind: CoachingOpponentIssueKind
    let severity: CoachingOpponentIssueSeverity
    let affectedSquare: Square?
    let checkingSquares: Set<Square>

    var answerSquares: Set<Square> { [reply.from] }
}
```

For material loss, set `affectedSquare` to the captured learner square. For check/mate, preserve the visible checking squares separately. Identification accepts only `reply.from`; a wrong tap produces a category response that asks for the opponent piece, never the learner target.

Project reply paths from `reply.from` to `reply.to`. For material loss, add the reply-to-affected relationship only when capture geometry needs a distinct target; never synthesize a path from the learner target back to itself.

- [ ] **Step 4: Simplify opponent copy and bound its claim**

Use T11's exact prompt/instruction. When Looks safe is correct, say the opponent “cannot immediately” produce a qualifying issue. When Looks safe is wrong, response names the opponent source and affected learner piece; actions become Hint and Close help until the child identifies the opponent source or changes the tentative move.

For `.notice` check, response names the check and says that the move remains acceptable because legal check responses exist. For `.reviseMove`, ask the child to change the move.

- [ ] **Step 5: Classify check resolution**

Add:

```swift
enum CoachingCheckResolution: Equatable, Sendable {
    case movedKing
    case blocked(attacker: Piece.Kind, blocker: Piece.Kind)
    case capturedChecker(checker: Piece.Kind, capturer: Piece.Kind)
}
```

Derive it before applying the coached move, but accept it only after ordinary legality and a post-move king-safety check succeed:

```swift
func checkResolution(
    for move: Move,
    in state: GameState,
    learner: PieceColor,
    checkingSquares: Set<Square>
) -> CoachingCheckResolution? {
    guard LegalMoveGenerator.legalMoves(for: move.from, in: state).contains(move),
          let mover = state.board[move.from] else {
        return nil
    }
    let after = state.applyingUnchecked(move)
    guard !LegalMoveGenerator.isKingInCheck(learner, in: after.board) else {
        return nil
    }
    if mover.kind == .king {
        return .movedKing
    }
    guard checkingSquares.count == 1,
          let checkerSquare = checkingSquares.first,
          let checker = state.board[checkerSquare] else {
        return nil
    }
    if move.to == checkerSquare {
        return .capturedChecker(checker: checker.kind, capturer: mover.kind)
    }
    return .blocked(attacker: checker.kind, blocker: mover.kind)
}
```

The successful post-move safety check is the proof that the final non-king, non-capture branch actually blocked the line; the explainer must not re-run geometry. Carry the resulting value into completion copy for T12A.

Change the unsupported fallback to:

```text
Ask: I can check immediate dangers, but I do not have a confident plan for this position yet.
Instruction: Choose a move you are considering, and I will check it with you.
```

Omit the routine strip and candidate focus.

- [ ] **Step 6: Add color-mirrored tests**

Mirror T1, T3, and T11 across the horizontal centerline and swap colors. This preserves chess files and therefore preserves kingside/queenside semantics:

```swift
private func colorMirror(_ square: Square) -> Square {
    Square(file: square.file, rank: 9 - square.rank)
}

private func colorMirror(_ move: Move) -> Move {
    Move(from: colorMirror(move.from), to: colorMirror(move.to), special: move.special)
}

private func colorMirror(_ state: GameState) -> GameState {
    let mirroredPieces = Dictionary(uniqueKeysWithValues: state.board.pieces.map { square, piece in
        (colorMirror(square), Piece(kind: piece.kind, color: piece.color.opposite))
    })
    return GameState(
        board: Board(pieces: mirroredPieces),
        sideToMove: state.sideToMove.opposite,
        castlingRights: CastlingRights(
            whiteKingside: state.castlingRights.blackKingside,
            whiteQueenside: state.castlingRights.blackQueenside,
            blackKingside: state.castlingRights.whiteKingside,
            blackQueenside: state.castlingRights.whiteQueenside
        ),
        enPassantTarget: state.enPassantTarget.map(colorMirror)
    )
}
```

Assert that every `White`/`Black`, `white`/`black`, learner/opponent piece reference changes correctly while actions and semantic focus equal the square-mirrored original. Mirror the expected paths and square sets with the same helper; do not compare raw coordinates.

- [ ] **Step 7: Run green and commit**

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/MaterialTacticalEvaluatorTests -only-testing:ChessTutorTests/CoachingSessionTests -only-testing:ChessTutorTests/CoachingAcceptanceTests -only-testing:ChessTutorTests/CoachingGoldenTranscriptTests -only-testing:ChessTutorTests/CoachFocusOverlayTests
git add ChessTutor/Coaching/CoachingModels.swift ChessTutor/Coaching/MaterialTacticalEvaluator.swift ChessTutor/Coaching/CoachingSession.swift ChessTutor/Coaching/CoachingReconciler.swift ChessTutor/Coaching/CoachingPresentationProjector.swift ChessTutor/Coaching/LocalCoachingExplanationSource.swift ChessTutorTests/Coaching/MaterialTacticalEvaluatorTests.swift ChessTutorTests/Coaching/CoachingSessionTests.swift ChessTutorTests/Coaching/CoachingAcceptanceTests.swift ChessTutorTests/Coaching/CoachingGoldenTranscriptTests.swift ChessTutorTests/UI/CoachFocusOverlayTests.swift
git commit -m "fix: simplify opponent reply coaching"
```

Expected: focused tests pass, zero skipped.

---

### Task 8: Lock the full corpus, accessibility, and UAT

**Files:**

- Modify: `ChessTutorTests/Coaching/CoachingGoldenTranscriptTests.swift`
- Modify: `ChessTutorTests/Coaching/LocalCoachingExplanationSourceTests.swift`
- Modify: `ChessTutorTests/Coaching/CoachingAcceptanceTests.swift`
- Modify: `ChessTutorTests/Game/GameSessionCoachingTests.swift`
- Modify: `ChessTutorTests/UI/CoachingPanelLayoutTests.swift`
- Modify: `ChessTutorUITests/CoachingPanelAccessibilityUITests.swift`
- Modify: `ChessTutor/App/CoachingPanelAccessibilityFixture.swift` only if the permanent corpus fixture needs an additional launch argument.

**Interfaces:**

- Consumes: all production behavior from Tasks 2–7.
- Produces: complete executable transcript corpus, structural copy audit, physical/accessibility regression coverage, and UAT report.

- [ ] **Step 1: Fill the golden transcript table with every approved branch**

Drive real `GameSession` or `CoachingSession` instances through these named cases; do not call the explainer in isolation:

```swift
func testEveryApprovedBranchHasAGoldenTurn() {
    let requiredCases: [CoachingGoldenCase] = [
        .t1Entry, .t1BlockedRook, .t1FlankPawn, .t1Hint, .t1KnightSelected,
        .t1PreferredKnight, .t1EdgeKnight, .t1CenterPawn,
        .t2Entry, .t2OneSquareKingMove, .t2KnightSwitch, .t2Castle,
        .t3WrongOwnPiece, .t3Target, .t3WrongAttacker, .t3Attacker,
        .t3UnresolvedMove, .t3ResolvedMove,
        .t4LowerPriorityPawn, .t4PrimaryKnight,
        .t5PawnDanger, .t5PawnResolved, .t5ProtectedTap, .t5ProtectedAbsence,
        .t6WrongSource, .t6Hint, .t6Capture,
        .t7UnsafeCapture, .t7NoSafeCapture,
        .t8AddsDefender,
        .t9Entry, .t9Hint, .t9Completed,
        .t10Entry, .t10Completed,
        .t11Safe, .t11QueenLoss, .t11IncorrectLooksSafe, .t11HarmlessCheck,
        .t12CheckLocate, .t12WrongChecker, .t12Capture, .t12Block, .t12KingMove,
        .t12UnsupportedEntry, .t12UnsupportedSafeMove,
    ]

    XCTAssertEqual(requiredCases, CoachingGoldenCase.allCases)
    XCTAssertEqual(requiredCases.map(goldenTurn).count, 46)
}
```

Each case asserts `response`, `headline`, `instruction`, action titles, board task, routine, emphasized squares, candidate squares, and paths. Add direct-versus-history-rich equality for T1 source switching, T3 target switching, and T11 tentative-move replacement.

- [ ] **Step 2: Add corpus-wide semantic invariants**

Implement assertions over all produced presentations:

```swift
func assertCoherent(_ presentation: CoachingPresentation, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertFalse(presentation.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, file: file, line: line)
    XCTAssertEqual(Set(presentation.actions.map(\.action)).count, presentation.actions.count, file: file, line: line)
    if presentation.instruction?.contains("highlighted") == true {
        XCTAssertFalse(presentation.focus.candidateSquares.isEmpty && presentation.focus.paths.isEmpty,
                       file: file, line: line)
    }
    if presentation.response?.contains("attacks") == true || presentation.headline.contains("attacks") {
        XCTAssertFalse(presentation.focus.emphasizedSquares.isEmpty && presentation.focus.paths.isEmpty,
                       file: file, line: line)
    }
}
```

Also assert that no absence action appears after an existing answer is stated, no miss response survives Hint, and direct/current-state derivation equals history-rich derivation.

- [ ] **Step 3: Replace the prohibited-copy audit with structural coverage**

Collect every child-facing `response`, `headline`, `instruction`, title, and accessibility label from the golden corpus plus a table covering every semantic enum case. Assert case-insensitively that none contains:

```swift
let prohibited = [
    "part of this problem", "big danger", "job", "tap the problem",
    "nothing urgent stands out", "clear plan", "reply to notice",
    "win some material", "come into the game", "attack something",
    "protect another piece", "more useful place",
]
```

Do not search production source text because tests and migration comments legitimately quote old wording; audit produced child-facing values.

- [ ] **Step 4: Run the complete focused coaching slice**

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

Expected: all selected tests pass, zero skipped.

- [ ] **Step 5: Build, install, and perform direct simulator UAT**

Build and install on the dedicated iPad simulator using the repository's existing UAT workflow. Exercise at standard and accessibility-extra-large text:

1. T1: rook miss → Hint → candidate → knight → rook switch → center pawn → preferred knight → Looks safe → completion.
2. T4: lower-priority pawn → primary knight → attacker → unresolved move → resolved move.
3. T7: unsafe bishop capture → concrete king recapture explanation → No safe capture → honest fallback.
4. T11B: expose queen → identify black rook → revise tentative move.
5. T12A: locate checking rook and separately complete capture, block, and king-move resolutions.

For each, inspect words, actions, focus, scrolling, and selection changes. Rotate through both supported physical compositions. Restore the simulator's content-size category after UAT. Save screenshots and exact commands under `.superpowers/sdd/2026-08-20-transcript-driven-coaching/task-8-artifacts/` and write `.superpowers/sdd/2026-08-20-transcript-driven-coaching/task-8-report.md`.

- [ ] **Step 6: Run the full scheme and clean build**

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
xcodebuild build -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
git diff --check
git status --short
```

Expected: full test and build exit 0, zero failed and zero skipped tests, no temporary UAT sources or debug launch gates, and only the intended Task 8 files remain.

- [ ] **Step 7: Commit**

```bash
git add ChessTutorTests/Coaching/CoachingGoldenTranscriptTests.swift ChessTutorTests/Coaching/LocalCoachingExplanationSourceTests.swift ChessTutorTests/Coaching/CoachingAcceptanceTests.swift ChessTutorTests/Game/GameSessionCoachingTests.swift ChessTutorTests/UI/CoachingPanelLayoutTests.swift ChessTutorUITests/CoachingPanelAccessibilityUITests.swift ChessTutor/App/CoachingPanelAccessibilityFixture.swift
git commit -m "test: lock transcript-driven coaching"
```

Do not commit `.superpowers/sdd` artifacts if that directory remains ignored by repository policy.

---

## Final completion gate

Before requesting merge review:

```bash
git diff --check HEAD~8 HEAD
git status --short
git log --oneline -10
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
xcodebuild build -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Require:

- eight scoped implementation commits after this plan;
- every approved transcript branch green through the real pipeline;
- full suite and simulator build green with zero skipped tests;
- no generic child-facing phrases from the prohibited list;
- UAT evidence for standard and accessibility text in both physical compositions;
- clean tracked worktree and no temporary test harness.

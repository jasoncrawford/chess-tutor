# Threat and Defense Guidance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add proactive threat and defense markers, symmetric piece inspection, tentative-move analysis, and an invoked two-sided coverage lens for beginning chess players.

**Architecture:** `LegalMoveGenerator` remains the sole rules authority and gains color-independent queries plus canonical capture resolution. A new pure `PositionAnalyzer` indexes those facts once per displayed position; `GameSession` projects them into `BoardGuidancePresentation`, and SwiftUI renders that presentation without deriving chess rules.

**Tech Stack:** Swift 5, SwiftUI, Observation, XCTest, Xcode/iPad Simulator; no new dependencies.

## Global Constraints

- Preserve the physical-board feel and keep the playable board as the main experience.
- Ambient danger bursts and non-king defense shields are on by default for both sides during an ongoing game.
- Yellow always means the side to move; red always means the other side. Coverage also distinguishes sides by round versus diamond shape.
- Broad movement/coverage may include a move blocked by king-safety rules; danger, attacker, and defender claims must use strict legal relationships.
- Preserve `BeginnerAssistSettings.showLegalMovesOnSelection`: it gates selected outward paths but does not disable ambient danger/defense or the explicitly invoked coverage lens.
- Opponent pieces are inspectable but never movable by the local player.
- During a remote opponent's turn, read-only inspection and coverage remain available while all local dragging/staging stays locked.
- Coverage survives taps, inspections, drags, staged moves, and reversions. It closes only through **Hide coverage**, a committed local or remote move, game reset, or game end.
- Finished games show no movement, coverage, attacker, supporter, or ambient guidance. Checkmate retains only the losing king's coral danger burst; stalemate has no annotation.
- `PositionAnalyzer` contains no piece geometry, pawn direction, sliding, check/pin, castling, promotion, or en passant rules.
- Coverage visibility and selection are local UI state and are not serialized or sent through remote play.
- Use exact button copy: **Show coverage** and **Hide coverage**.
- Use the iPad simulator destination `platform=iOS Simulator,name=iPad (A16)`.

---

## File Map

### New files

- `ChessTutor/Core/PositionAnalyzer.swift` — immutable position-wide indexes built only from `LegalMoveGenerator` facts.
- `ChessTutor/Game/BoardGuidancePresentation.swift` — SwiftUI-independent paths, marker sets, coverage sets, emphasis, and accessibility copy.
- `ChessTutor/UI/Board/BoardGuidanceOverlay.swift` — visual shapes and rendering for trajectories, bursts, shields, supporter echoes, and coverage pips.
- `ChessTutorTests/Core/PositionAnalyzerTests.swift` — aggregation, pin, special-move, immutability, and coverage tests.
- `ChessTutorTests/Game/BoardGuidancePresentationTests.swift` — projection, visual-role, emphasis, terminal-state, and accessibility tests.
- `ChessTutorTests/UI/BoardGuidanceStyleTests.swift` — stable style, shape, layer-order, and panel-fit assertions.

### Existing files

- `ChessTutor/Core/Move.swift` — define canonical `MoveCapture`.
- `ChessTutor/Core/LegalMoveGenerator.swift` — canonical capture resolution and color-independent movement/control/support/check-source queries.
- `ChessTutor/Core/GameState.swift` — consume canonical capture resolution while applying moves.
- `ChessTutor/Game/GameSession.swift` — cache analysis, separate inspection from actionable moves, own coverage state, and produce board guidance.
- `ChessTutor/Game/MoveHistoryFormatter.swift` — consume canonical capture resolution for notation.
- `ChessTutor/UI/Board/ChessBoardView.swift` — replace beads/capture glow with ready-made guidance layers and preserve gesture behavior.
- `ChessTutor/UI/Sidebar/SelectedPiecePanelView.swift` — place the coverage control at the bottom of the panel.
- `ChessTutor/UI/Sidebar/SidePanelView.swift` — bind the selected panel to coverage state/actions.
- `ChessTutor/UI/Theme/AppTheme.swift` — add coral, teal, yellow, and red guidance colors.
- `ChessTutor.xcodeproj/project.pbxproj` — add the six new Swift files to the appropriate source/test groups and build phases.
- Existing Core, Game, history, and UI test files — update assertions affected by the new presentation and add focused regressions.

---

### Task 1: Canonical Capture Resolution

**Files:**
- Modify: `ChessTutor/Core/Move.swift`
- Modify: `ChessTutor/Core/LegalMoveGenerator.swift`
- Modify: `ChessTutor/Core/GameState.swift`
- Modify: `ChessTutor/Game/GameSession.swift`
- Modify: `ChessTutor/Game/MoveHistoryFormatter.swift`
- Test: `ChessTutorTests/Core/SpecialMoveTests.swift`
- Test: `ChessTutorTests/Game/GameSessionTests.swift`
- Test: `ChessTutorTests/Game/MoveHistoryFormatterTests.swift`

**Interfaces:**
- Produces: `MoveCapture`, `LegalMoveGenerator.capture(for:in:) -> MoveCapture?`.
- Consumers: move application, capture tray/history, notation, and Task 3's threat relationships.

- [ ] **Step 1: Write failing canonical-capture tests**

Add exact ordinary-capture and en-passant expectations:

```swift
func testCaptureResolutionReturnsDestinationForOrdinaryCapture() {
    let target = Square(file: .d, rank: 5)
    let blackPawn = Piece(kind: .pawn, color: .black)
    let state = GameState(
        board: Board(pieces: [
            Square(file: .e, rank: 4): Piece(kind: .pawn, color: .white),
            target: blackPawn,
            Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
            Square(file: .e, rank: 8): Piece(kind: .king, color: .black),
        ]),
        sideToMove: .white
    )
    let move = Move(from: Square(file: .e, rank: 4), to: target)

    XCTAssertEqual(
        LegalMoveGenerator.capture(for: move, in: state),
        MoveCapture(square: target, piece: blackPawn)
    )
}

func testCaptureResolutionReturnsAdjacentPawnForEnPassant() {
    let capturedSquare = Square(file: .d, rank: 5)
    let blackPawn = Piece(kind: .pawn, color: .black)
    let state = GameState(
        board: Board(pieces: [
            Square(file: .e, rank: 5): Piece(kind: .pawn, color: .white),
            capturedSquare: blackPawn,
            Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
            Square(file: .e, rank: 8): Piece(kind: .king, color: .black),
        ]),
        sideToMove: .white,
        enPassantTarget: Square(file: .d, rank: 6)
    )
    let move = Move(
        from: Square(file: .e, rank: 5),
        to: Square(file: .d, rank: 6),
        special: .enPassant
    )

    XCTAssertEqual(
        LegalMoveGenerator.capture(for: move, in: state),
        MoveCapture(square: capturedSquare, piece: blackPawn)
    )
}
```

Also keep the existing `GameSession` en-passant capture-tray and `MoveHistoryFormatter` `exd6` tests as integration coverage.

- [ ] **Step 2: Run the focused tests and verify the missing API fails**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/SpecialMoveTests -only-testing:ChessTutorTests/GameSessionTests -only-testing:ChessTutorTests/MoveHistoryFormatterTests
```

Expected: build failure because `MoveCapture` and `capture(for:in:)` do not exist.

- [ ] **Step 3: Add the canonical value and Core resolver**

Add to `Move.swift`:

```swift
struct MoveCapture: Equatable, Hashable, Sendable {
    let square: Square
    let piece: Piece
}
```

Add to `LegalMoveGenerator`:

```swift
static func capture(for move: Move, in state: GameState) -> MoveCapture? {
    let capturedSquare: Square
    if move.special == .enPassant {
        capturedSquare = Square(file: move.to.file, rank: move.from.rank)
    } else {
        capturedSquare = move.to
    }
    return state.board[capturedSquare].map {
        MoveCapture(square: capturedSquare, piece: $0)
    }
}
```

Replace each local capture inference with this API:

```swift
let capture = LegalMoveGenerator.capture(for: move, in: state)
let isCapture = capture != nil
```

In `GameState.applyingUnchecked`, pass `capture?.piece` and `capture?.square ?? move.to` to castling-right updates. In `GameSession`, delete the private `capturedPiece(for:in:)` function and build tray entries from `MoveCapture`.

- [ ] **Step 4: Run focused tests and then the full suite**

Run the focused command from Step 2, then:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Expected: all capture, history, session, and existing tests pass.

- [ ] **Step 5: Commit the capture cleanup**

```bash
git add ChessTutor/Core/Move.swift ChessTutor/Core/LegalMoveGenerator.swift ChessTutor/Core/GameState.swift ChessTutor/Game/GameSession.swift ChessTutor/Game/MoveHistoryFormatter.swift ChessTutorTests/Core/SpecialMoveTests.swift ChessTutorTests/Game/GameSessionTests.swift ChessTutorTests/Game/MoveHistoryFormatterTests.swift
git commit -m "Centralize chess capture resolution"
```

---

### Task 2: Color-Independent Reach, Control, and Support Queries

**Files:**
- Modify: `ChessTutor/Core/LegalMoveGenerator.swift`
- Test: `ChessTutorTests/Core/LegalMoveGeneratorTests.swift`

**Interfaces:**
- Produces:
  - `allowedMoves(for:by:in:) -> [Move]`
  - `legalMoves(for:by:in:) -> [Move]`
  - `controlledSquares(for:by:in:) -> Set<Square>`
  - `legalSupportTargets(for:by:in:) -> Set<Square>`
  - `checkingPieceSquares(against:in:) -> Set<Square>`
- Preserves: existing turn-scoped `allowedMoves(for:in:)`, `legalMoves(for:in:)`, and `allLegalMoves(in:)` wrappers used to commit play.

- [ ] **Step 1: Write failing perspective and control tests**

Add tests demonstrating that analysis can ask about black during white's turn without mutating the state, that pawn control differs from forward movement, and that a blocker square is included but squares beyond it are not:

```swift
func testLegalMovesCanAnalyzePieceWhoseColorIsNotSideToMove() {
    let state = GameState.startingPosition()
    let before = state

    let moves = LegalMoveGenerator.legalMoves(
        for: Square(file: .g, rank: 8),
        by: .black,
        in: state
    )

    XCTAssertEqual(Set(moves.map(\.to)), [
        Square(file: .f, rank: 6),
        Square(file: .h, rank: 6),
    ])
    XCTAssertEqual(state, before)
}

func testPawnControlsDiagonalsButNotForwardSquare() {
    let state = GameState.startingPosition()

    XCTAssertEqual(
        LegalMoveGenerator.controlledSquares(
            for: Square(file: .e, rank: 2),
            by: .white,
            in: state
        ),
        [Square(file: .d, rank: 3), Square(file: .f, rank: 3)]
    )
}
```

Add two pin cases: a pinned knight does not legally support its friendly target; a rook pinned on its file still supports a friendly target along that same file when the hypothetical capture keeps its king covered.

- [ ] **Step 2: Run the generator tests and verify the new calls fail**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/LegalMoveGeneratorTests
```

Expected: build failure for the new color-independent APIs.

- [ ] **Step 3: Generalize movement without weakening play validation**

Keep the current public wrappers and add explicit-color overloads:

```swift
static func allowedMoves(for square: Square, in state: GameState) -> [Move] {
    allowedMoves(for: square, by: state.sideToMove, in: state)
}

static func allowedMoves(
    for square: Square,
    by color: PieceColor,
    in state: GameState
) -> [Move] {
    guard let piece = state.board[square], piece.color == color else {
        return []
    }
    return pseudoLegalMoves(for: square, piece: piece, in: state)
}

static func legalMoves(
    for square: Square,
    by color: PieceColor,
    in state: GameState
) -> [Move] {
    allowedMoves(for: square, by: color, in: state).filter { move in
        !isKingInCheck(color, in: state.applyingUnchecked(move).board)
    }
}
```

The existing no-color `legalMoves` must continue to reject a piece not owned by `state.sideToMove`. Gate en passant inside the generalized path with `piece.color == state.sideToMove` so a transient right is not fabricated for the other side.

- [ ] **Step 4: Add Core-owned control, support, and check-source facts**

Refactor private jump/sliding geometry so `controlledSquares` includes the first occupied square of either color and stops there. Pawn control is always its two forward diagonals; it never contains the pawn's ordinary forward destination. Castling is not control.

Implement strict support entirely inside `LegalMoveGenerator`:

```swift
static func legalSupportTargets(
    for square: Square,
    by color: PieceColor,
    in state: GameState
) -> Set<Square> {
    guard let source = state.board[square], source.color == color else {
        return []
    }

    return Set(controlledSquares(for: square, by: color, in: state).filter { target in
        guard let occupant = state.board[target],
              occupant.color == color,
              occupant.kind != .king else {
            return false
        }
        var captureState = state
        captureState.board[target] = Piece(kind: occupant.kind, color: color.opposite)
        return legalMoves(for: square, by: color, in: captureState).contains { $0.to == target }
    })
}
```

Expose check sources and reuse them in `isKingInCheck`:

```swift
static func checkingPieceSquares(against color: PieceColor, in board: Board) -> Set<Square> {
    guard let kingSquare = kingSquare(for: color, in: board) else {
        preconditionFailure("Cannot determine check state: missing \(color.rawValue) king")
    }
    return Set(board.pieces.compactMap { square, piece in
        piece.color != color && attacks(square: kingSquare, from: square, piece: piece, board: board)
            ? square
            : nil
    })
}
```

- [ ] **Step 5: Run generator and special-move tests**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/LegalMoveGeneratorTests -only-testing:ChessTutorTests/SpecialMoveTests
```

Expected: all tests pass, including the existing en-passant pin and castling tests.

- [ ] **Step 6: Commit the Core analysis surface**

```bash
git add ChessTutor/Core/LegalMoveGenerator.swift ChessTutorTests/Core/LegalMoveGeneratorTests.swift
git commit -m "Expose color independent chess analysis"
```

---

### Task 3: Pure Position Analyzer

**Files:**
- Create: `ChessTutor/Core/PositionAnalyzer.swift`
- Create: `ChessTutorTests/Core/PositionAnalyzerTests.swift`
- Modify: `ChessTutor.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: every Core query from Tasks 1–2.
- Produces: `ThreatRelation`, `PositionAnalysis`, and `PositionAnalyzer.analyze(_:)`.

- [ ] **Step 1: Add the new source/test files to the Xcode project**

Add `PositionAnalyzer.swift` under the app's Core group and app Sources phase. Add `PositionAnalyzerTests.swift` under the test Core group and test Sources phase. Confirm membership with:

```bash
xcodebuild -project ChessTutor.xcodeproj -scheme ChessTutor -showBuildSettings
```

Expected: command exits successfully and both paths appear in `project.pbxproj` exactly once as file references and once in their respective Sources phases.

- [ ] **Step 2: Write failing analyzer tests**

Define a compact position with a threatened-and-defended white bishop, two black attackers, a pinned apparent supporter, and both kings. Assert exact reverse indexes:

```swift
func testIndexesThreatsSupportersAndCoverageForBothColors() {
    let state = makeThreatAndSupportPosition()
    let before = state

    let analysis = PositionAnalyzer.analyze(state)

    XCTAssertEqual(
        Set(analysis.threats(targeting: Square(file: .d, rank: 4)).map(\.source)),
        [Square(file: .b, rank: 6), Square(file: .f, rank: 6)]
    )
    XCTAssertEqual(
        analysis.supporters(of: Square(file: .d, rank: 4)),
        [Square(file: .c, rank: 2)]
    )
    XCTAssertTrue(analysis.coverage(for: .white).contains(Square(file: .e, rank: 5)))
    XCTAssertTrue(analysis.coverage(for: .black).contains(Square(file: .e, rank: 5)))
    XCTAssertEqual(state, before)
}
```

Add focused tests for:

- en passant: `ThreatRelation.target` is the captured pawn while `destination` is the empty landing square;
- castling: the destination is in allowed moves and coverage but never in threats/supporters;
- a pinned piece's broad coverage remains while its illegal capture creates no threat;
- promotion produces one destination in set-based coverage despite four promotion moves;
- the checked king is threatened through `checkingPieceSquares`, while kings never appear in `defendedSquares`.

- [ ] **Step 3: Run analyzer tests and verify the missing types fail**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/PositionAnalyzerTests
```

Expected: build failure because `PositionAnalyzer`, `PositionAnalysis`, and `ThreatRelation` do not exist.

- [ ] **Step 4: Implement immutable analysis values**

Use these exact public-to-module shapes:

```swift
struct ThreatRelation: Equatable, Hashable, Sendable {
    let source: Square
    let target: Square
    let destination: Square
    let color: PieceColor
}

struct PositionAnalysis: Equatable, Sendable {
    let allowedMovesBySource: [Square: [Move]]
    let threatsByTarget: [Square: Set<ThreatRelation>]
    let supportersByTarget: [Square: Set<Square>]
    let coverageByColor: [PieceColor: Set<Square>]

    func allowedMoves(from square: Square) -> [Move] {
        allowedMovesBySource[square] ?? []
    }

    func threats(targeting square: Square) -> Set<ThreatRelation> {
        threatsByTarget[square] ?? []
    }

    func supporters(of square: Square) -> Set<Square> {
        supportersByTarget[square] ?? []
    }

    func coverage(for color: PieceColor) -> Set<Square> {
        coverageByColor[color] ?? []
    }

    var threatenedSquares: Set<Square> { Set(threatsByTarget.keys) }
    var defendedSquares: Set<Square> { Set(supportersByTarget.keys) }
}
```

`PositionAnalyzer.analyze(_:)` loops over `state.board.pieces`, calls only `LegalMoveGenerator` APIs, reverses legal capture results into `ThreatRelation`, reverses `legalSupportTargets` into supporter sets, and unions `allowedMoves.map(\.to)` with `controlledSquares` for coverage. It then adds checked-king threat relations from `checkingPieceSquares`. It contains no `switch` over `Piece.Kind`.

- [ ] **Step 5: Add a source-level architecture guard**

Add an XCTest that reads `PositionAnalyzer.swift` using `#filePath` to resolve the repository file and rejects rule tokens:

```swift
func testAnalyzerDoesNotReimplementPieceRules() throws {
    let testFile = URL(fileURLWithPath: #filePath)
    let sourceURL = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("ChessTutor/Core/PositionAnalyzer.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    for forbidden in ["switch piece.kind", "fileDelta", "rankDelta", "isKingInCheck", "enPassantTarget"] {
        XCTAssertFalse(source.contains(forbidden), "PositionAnalyzer contains rule token: \(forbidden)")
    }
}
```

- [ ] **Step 6: Run analyzer tests and commit**

Run the command from Step 3. Expected: all `PositionAnalyzerTests` pass.

```bash
git add ChessTutor/Core/PositionAnalyzer.swift ChessTutorTests/Core/PositionAnalyzerTests.swift ChessTutor.xcodeproj/project.pbxproj
git commit -m "Add pure chess position analysis"
```

---

### Task 4: Session Guidance Projection and Persistent Coverage State

**Files:**
- Create: `ChessTutor/Game/BoardGuidancePresentation.swift`
- Create: `ChessTutorTests/Game/BoardGuidancePresentationTests.swift`
- Modify: `ChessTutor/Game/GameSession.swift`
- Modify: `ChessTutorTests/Game/GameSessionTests.swift`
- Modify: `ChessTutor.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `PositionAnalysis` from Task 3.
- Produces: `BoardGuidancePath`, `BoardCoveragePresentation`, `BoardGuidancePresentation`, `GameSession.boardGuidance`, `GameSession.isCoverageVisible`, `toggleCoverage()`.
- Preserves: `legalDestinations` as the actionable drop-target set; inspection paths do not authorize moves.

- [ ] **Step 1: Register the presentation source and test files**

Add `BoardGuidancePresentation.swift` to the app Game group/Sources phase and `BoardGuidancePresentationTests.swift` to the tests Game group/test Sources phase. Run `xcodebuild -project ChessTutor.xcodeproj -scheme ChessTutor -showBuildSettings` and expect success.

- [ ] **Step 2: Write failing session-state tests**

Add tests for symmetric selection and persistent coverage:

```swift
func testSelectingOpponentPieceInspectsItWithoutMakingItActionable() {
    let session = GameSession(state: makeInspectionPosition(sideToMove: .white))
    let blackRook = Square(file: .d, rank: 6)

    session.select(blackRook)

    XCTAssertEqual(session.selectedSquare, blackRook)
    XCTAssertFalse(session.boardGuidance.selectedPaths.isEmpty)
    XCTAssertTrue(session.legalDestinations.isEmpty)
    XCTAssertEqual(session.moveSelectedPiece(to: Square(file: .d, rank: 5)), .illegal("Choose a white piece."))
}

func testCoveragePersistsThroughSelectionStagingAndReversion() {
    let session = GameSession()
    session.toggleCoverage()
    session.select(Square(file: .e, rank: 2))
    _ = session.moveSelectedPiece(to: Square(file: .e, rank: 4))

    XCTAssertTrue(session.isCoverageVisible)
    XCTAssertEqual(session.selectedSquare, Square(file: .e, rank: 4))

    _ = session.moveSelectedPiece(to: Square(file: .e, rank: 2))
    XCTAssertTrue(session.isCoverageVisible)
}
```

Add separate assertions that successful `finishTurn`, `commitRemoteMove`, `newGame`, `endRemoteGame`, checkmate, and stalemate close/suppress coverage; a failed **Done** attempt does not close it. Add tests that a staged move immediately recalculates danger/support for the moved piece and promotion inspects the promoted piece.

- [ ] **Step 3: Write failing presentation-value tests**

Use these expectations:

```swift
func testSelectedOpponentUsesRedOutgoingAndYellowIncomingPaths() {
    let presentation = BoardGuidancePresentation.make(
        state: makeInspectionPosition(sideToMove: .white),
        analysis: PositionAnalyzer.analyze(makeInspectionPosition(sideToMove: .white)),
        selectedSquare: Square(file: .d, rank: 6),
        showsCoverage: false,
        keepsOnlyCheckmateKingThreat: false
    )

    XCTAssertTrue(presentation.selectedPaths.contains { $0.role == .allowed && $0.color == .black })
    XCTAssertTrue(presentation.selectedPaths.contains { $0.role == .attacker && $0.color == .white })
}

func testSelectionQuietsOnlyUnrelatedAmbientMarkers() {
    let presentation = makePresentationWithRelatedAndUnrelatedThreats()

    XCTAssertEqual(presentation.markerOpacity(at: presentation.selectedSquare!), 1)
    XCTAssertEqual(presentation.markerOpacity(at: unrelatedThreatSquare), 0.20)
}
```

Also assert supporter echoes contain source squares and no supporter path role exists.

- [ ] **Step 4: Implement SwiftUI-independent presentation values**

Use exact types:

```swift
struct BoardGuidancePath: Equatable, Hashable, Sendable {
    enum Role: Equatable, Hashable, Sendable {
        case allowed
        case attacker
    }

    let source: Square
    let destination: Square
    let captureSquare: Square?
    let color: PieceColor
    let role: Role
}

struct BoardCoveragePresentation: Equatable, Sendable {
    let sideToMove: PieceColor
    let sideToMoveSquares: Set<Square>
    let otherSideSquares: Set<Square>
}

struct BoardGuidancePresentation: Equatable, Sendable {
    let sideToMove: PieceColor
    let threatenedSquares: Set<Square>
    let defendedSquares: Set<Square>
    let selectedSquare: Square?
    let selectedPaths: Set<BoardGuidancePath>
    let supporterSquares: Set<Square>
    let coverage: BoardCoveragePresentation?
    let emphasizedSquares: Set<Square>

    func markerOpacity(at square: Square) -> Double {
        selectedSquare == nil || emphasizedSquares.contains(square) ? 1 : 0.20
    }

    static func empty(sideToMove: PieceColor) -> BoardGuidancePresentation {
        BoardGuidancePresentation(
            sideToMove: sideToMove,
            threatenedSquares: [],
            defendedSquares: [],
            selectedSquare: nil,
            selectedPaths: [],
            supporterSquares: [],
            coverage: nil,
            emphasizedSquares: []
        )
    }
}
```

`BoardGuidancePresentation.make(...)` maps allowed moves to `.allowed` paths when `showsSelectedReach` is true, indexed threats to `.attacker` paths, and supporters to teal-echo squares. `captureSquare` uses the canonical relation target, preserving en passant's distinct landing/capture squares. Suppress all king squares from `defendedSquares`. Store `state.sideToMove` so the view can map actual piece colors to relative yellow/red without reading `GameState`.

- [ ] **Step 5: Cache analysis and separate inspection from move authorization**

In `GameSession`:

```swift
private var displayedAnalysis: PositionAnalysis
private var actionableMovesForSelection: [Move] = []
private(set) var analysisRevision = 0
var isCoverageVisible = false

private var isCheckmate: Bool {
    if case .checkmate = committedState.result { return true }
    return false
}

var boardGuidance: BoardGuidancePresentation {
    if boardLockMessage != nil {
        return .empty(sideToMove: state.sideToMove)
    }
    return BoardGuidancePresentation.make(
        state: state,
        analysis: displayedAnalysis,
        selectedSquare: selectedSquare,
        showsSelectedReach: assistSettings.showLegalMovesOnSelection,
        showsCoverage: isCoverageVisible,
        keepsOnlyCheckmateKingThreat: isCheckmate
    )
}

func toggleCoverage() {
    guard committedState.result == .ongoing, boardLockMessage == nil else { return }
    isCoverageVisible.toggle()
}
```

Initialize analysis from the supplied state and call one `refreshDisplayedAnalysis()` after each actual displayed-position change: tentative landing, reversion, promotion choice, local/remote commit, restored move, new game, and debug board mutation. Selection and coverage toggles do not refresh.

Change `select(_:)` so either color can be inspected during an ongoing game. Populate `actionableMovesForSelection` only when the piece belongs to `committedState.sideToMove` and `localCanActForCurrentTurn`; derive `legalDestinations` only from that array. After staging or promoting, set `selectedSquare = move.to`, clear ordinary actionable moves, retain only the existing explicit reversion destination, and refresh analysis from the tentative `state`.

In `moveSelectedPiece(to:)`, reject an inspection-only selection before looking up allowed moves:

```swift
guard let selectedPiece = state.board[selectedSquare],
      selectedPiece.color == committedState.sideToMove else {
    let message = "Choose a \(committedState.sideToMove.rawValue) piece."
    self.message = message
    return .illegal(message)
}
```

At game end, retain piece identity selection but return terminal guidance. For checkmate, keep only the losing king in `threatenedSquares`; for stalemate or remote forfeit, return empty guidance.

- [ ] **Step 6: Run Game and presentation tests**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/GameSessionTests -only-testing:ChessTutorTests/BoardGuidancePresentationTests
```

Expected: all tests pass, including one-analysis-per-position assertions using `analysisRevision`.

- [ ] **Step 7: Commit the session layer**

```bash
git add ChessTutor/Game/BoardGuidancePresentation.swift ChessTutor/Game/GameSession.swift ChessTutorTests/Game/BoardGuidancePresentationTests.swift ChessTutorTests/Game/GameSessionTests.swift ChessTutor.xcodeproj/project.pbxproj
git commit -m "Project board guidance from game session"
```

---

### Task 5: Coverage Control in the Selected-Piece Panel

**Files:**
- Modify: `ChessTutor/UI/Sidebar/SelectedPiecePanelView.swift`
- Modify: `ChessTutor/UI/Sidebar/SidePanelView.swift`
- Modify: `ChessTutor/UI/Theme/AppTheme.swift`
- Test: `ChessTutorTests/UI/CaptureTrayLayoutTests.swift`

**Interfaces:**
- Consumes: `GameSession.isCoverageVisible`, `toggleCoverage()`, and terminal availability.
- Produces: a full-width bottom control with stable panel geometry and accessibility state.

- [ ] **Step 1: Write failing layout and copy tests**

Extend `SelectedPiecePanelLayout` expectations:

```swift
func testSelectedPiecePanelFitsCoverageButtonWithoutGrowingPanel() {
    let column = SidebarColumnLayout.make(for: 760, presentation: .verticalColumn)
    let layout = SelectedPiecePanelLayout.current

    XCTAssertEqual(column.size(for: .selectedPiece).height, 240, accuracy: 0.01)
    XCTAssertEqual(column.size(for: .capturedPieces).height, 255.36, accuracy: 0.01)
    XCTAssertEqual(layout.coverageButtonHeight, 36, accuracy: 0.01)
    XCTAssertEqual(layout.coverageButtonSpacing, 8, accuracy: 0.01)
    XCTAssertGreaterThanOrEqual(
        column.size(for: .selectedPiece).height - SidebarPanelMetrics.contentPadding * 2,
        layout.requiredContentHeight + layout.coverageButtonSpacing + layout.coverageButtonHeight
    )
}

func testCoverageButtonCopyMatchesExpandedState() {
    XCTAssertEqual(CoverageButtonPresentation(isVisible: false).title, "Show coverage")
    XCTAssertEqual(CoverageButtonPresentation(isVisible: true).title, "Hide coverage")
}
```

- [ ] **Step 2: Run UI layout tests and verify failure**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/CaptureTrayLayoutTests
```

Expected: build failures for the new layout properties and presentation value.

- [ ] **Step 3: Add the bottom control without a new panel**

Set the vertical selected panel height to 240 points, taking two points from the captured panel budget. Define:

```swift
struct CoverageButtonPresentation: Equatable {
    let isVisible: Bool
    var title: String { isVisible ? "Hide coverage" : "Show coverage" }
    var systemImage: String { isVisible ? "eye.slash" : "eye" }
}
```

Extend `SelectedPiecePanelView` with:

```swift
let isCoverageVisible: Bool
let isCoverageAvailable: Bool
let onToggleCoverage: () -> Void
```

Render the existing selected/empty content above a bottom button. Give the visible button 36 points, reserve 8 points above it, and make the combined 44-point footer the hit region. Disable and hide the footer when the game is terminal. Add `.accessibilityValue(isCoverageVisible ? "Shown" : "Hidden")`.

In `SidePanelView`, pass `session.isCoverageVisible`, `session.state.result == .ongoing && !session.isRemoteGameEnded`, and `session.toggleCoverage`.

- [ ] **Step 4: Run layout and GameSession tests**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/CaptureTrayLayoutTests -only-testing:ChessTutorTests/GameSessionTests
```

Expected: all tests pass and existing sidebar segment sums still equal the board height.

- [ ] **Step 5: Commit the coverage affordance**

```bash
git add ChessTutor/UI/Sidebar/SelectedPiecePanelView.swift ChessTutor/UI/Sidebar/SidePanelView.swift ChessTutor/UI/Theme/AppTheme.swift ChessTutorTests/UI/CaptureTrayLayoutTests.swift
git commit -m "Add persistent coverage control"
```

---

### Task 6: Board Guidance Visual System

**Files:**
- Create: `ChessTutor/UI/Board/BoardGuidanceOverlay.swift`
- Create: `ChessTutorTests/UI/BoardGuidanceStyleTests.swift`
- Modify: `ChessTutor/UI/Board/ChessBoardView.swift`
- Modify: `ChessTutor/UI/Theme/AppTheme.swift`
- Modify: `ChessTutorTests/UI/CaptureTrayLayoutTests.swift`
- Modify: `ChessTutor.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `GameSession.boardGuidance` only; no Core rule calls.
- Produces: coverage pips, thin selected trajectories, coral bursts, teal shields, and teal supporter echoes.

- [ ] **Step 1: Register overlay and style-test files**

Add `BoardGuidanceOverlay.swift` to the app Board group/Sources phase and `BoardGuidanceStyleTests.swift` to the test UI group/test Sources phase. Verify project loading with `xcodebuild -project ChessTutor.xcodeproj -scheme ChessTutor -showBuildSettings`.

- [ ] **Step 2: Write failing stable-style tests**

Define testable constants rather than snapshotting pixels:

```swift
func testGuidanceUsesSmallArrowheadsAndQuietUnrelatedMarkers() {
    let style = BoardGuidanceStyle.current

    XCTAssertLessThanOrEqual(style.arrowheadLengthInCells, 0.16)
    XCTAssertLessThanOrEqual(style.pathLineWidthInCells, 0.035)
    XCTAssertEqual(style.unrelatedMarkerOpacity, 0.20, accuracy: 0.001)
}

func testCoverageUsesRoundYellowAndDiamondRedPips() {
    XCTAssertEqual(CoveragePipStyle.sideToMove.shape, .circle)
    XCTAssertEqual(CoveragePipStyle.otherSide.shape, .diamond)
    XCTAssertNotEqual(CoveragePipStyle.sideToMove.offset, CoveragePipStyle.otherSide.offset)
}

func testLayerOrderKeepsPathsBelowPiecesAndAboveCoverage() {
    XCTAssertLessThan(GuidanceLayer.coverage.rawValue, GuidanceLayer.paths.rawValue)
    XCTAssertLessThan(GuidanceLayer.paths.rawValue, GuidanceLayer.pieceMarkers.rawValue)
}
```

Update the old capture-glow tests to assert the obsolete glow and square-halo styles are removed.

- [ ] **Step 3: Run style tests and verify missing visual types fail**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/BoardGuidanceStyleTests -only-testing:ChessTutorTests/CaptureTrayLayoutTests
```

Expected: build failures for `BoardGuidanceStyle`, `CoveragePipStyle`, and `GuidanceLayer`.

- [ ] **Step 4: Implement the visual primitives**

Use these stable values as the starting visual grammar:

```swift
enum GuidanceLayer: Int {
    case coverage
    case paths
    case pieceMarkers
}

struct BoardGuidanceStyle: Equatable {
    static let current = BoardGuidanceStyle(
        arrowheadLengthInCells: 0.14,
        pathLineWidthInCells: 0.028,
        unrelatedMarkerOpacity: 0.20,
        dangerBurstScale: 0.92,
        shieldScale: 0.22,
        supporterEchoScale: 0.94
    )

    let arrowheadLengthInCells: CGFloat
    let pathLineWidthInCells: CGFloat
    let unrelatedMarkerOpacity: Double
    let dangerBurstScale: CGFloat
    let shieldScale: CGFloat
    let supporterEchoScale: CGFloat
}
```

Add to `AppTheme` opaque base colors whose opacity is controlled at the view layer:

```swift
static let guidanceYellow = Color(red: 0.96, green: 0.72, blue: 0.12)
static let guidanceRed = Color(red: 0.86, green: 0.19, blue: 0.16)
static let guidanceCoral = Color(red: 0.94, green: 0.30, blue: 0.24)
static let guidanceTeal = Color(red: 0.08, green: 0.55, blue: 0.50)
```

`BoardGuidanceOverlay.swift` contains:

- `CoveragePipsLayer`: one yellow circle and/or red diamond per covered square with fixed non-overlapping offsets;
- `GuidancePathsLayer`: `Canvas` strokes from source to destination, shortened around piece centers, plus a triangular head no longer than `0.14 * cellSize`;
- `DangerBurstShape`: an alternating-radius 16-point comic burst behind a piece;
- `DefenseShieldView`: a small filled `shield.fill` token positioned at the readable foot of the piece;
- `SupporterEchoView`: a restrained teal ring around supporter pieces;
- a `BoardGuidanceGeometry` helper that maps `Square` to centers using `BoardViewingAngle` and never reads game rules.

Guidance markers never pulse continuously. When Reduce Motion is off, a newly changed burst or shield may use one brief scale-and-opacity transition before settling; otherwise every marker remains static.

- [ ] **Step 5: Replace legacy beads and capture glow in board layering**

In the main `ZStack`, render:

```swift
board(side: side)
CoveragePipsLayer(...)
GuidancePathsLayer(...)
piecesOverlay(side: side, origin: origin)
draggedPiece
```

Within `piecesOverlay`, render burst and supporter echo, then `PieceIconView`, then the shield token. Apply `boardGuidance.markerOpacity(at:)` to ambient burst/shield markers. Remove `legalMoveInlay`, `captureGuidanceHalo`, `CaptureGuidanceStyle`, `CaptureGuidanceGlowStyle`, and `PieceCaptureGlowView`.

Keep drag behavior unchanged except that a successful stage now leaves the destination selected through `GameSession`. Starting a drag does not toggle coverage. Paths and pips update only after `session.state.board` changes on landing.

Add `session.localCanActForCurrentTurn` to the drag-start guard so a remote side-to-move piece cannot visually lift before the session rejects it:

```swift
guard session.localCanActForCurrentTurn,
      let from = square(at: value.startLocation, side: side, origin: origin),
      let piece = session.state.board[from],
      piece.color == session.state.sideToMove else {
    return
}
```

- [ ] **Step 6: Run UI and session tests**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/BoardGuidanceStyleTests -only-testing:ChessTutorTests/CaptureTrayLayoutTests -only-testing:ChessTutorTests/GameSessionTests
```

Expected: all tests pass and `ChessBoardView.swift` contains no `LegalMoveGenerator` or `PositionAnalyzer` references.

- [ ] **Step 7: Commit the board visual system**

```bash
git add ChessTutor/UI/Board/BoardGuidanceOverlay.swift ChessTutor/UI/Board/ChessBoardView.swift ChessTutor/UI/Theme/AppTheme.swift ChessTutorTests/UI/BoardGuidanceStyleTests.swift ChessTutorTests/UI/CaptureTrayLayoutTests.swift ChessTutor.xcodeproj/project.pbxproj
git commit -m "Render threat defense and coverage guidance"
```

---

### Task 7: Accessibility, Terminal States, Performance, and Visual Verification

**Files:**
- Modify: `ChessTutor/Game/BoardGuidancePresentation.swift`
- Modify: `ChessTutor/Game/GameSession.swift`
- Modify: `ChessTutor/UI/Board/BoardGuidanceOverlay.swift`
- Modify: `ChessTutor/UI/Board/ChessBoardView.swift`
- Modify: `ChessTutor/UI/Sidebar/SelectedPiecePanelView.swift`
- Modify: `ChessTutorTests/Core/PositionAnalyzerTests.swift`
- Modify: `ChessTutorTests/Game/BoardGuidancePresentationTests.swift`
- Modify: `ChessTutorTests/Game/GameSessionTests.swift`
- Modify: `ChessTutorTests/UI/BoardGuidanceStyleTests.swift`

**Interfaces:**
- Produces: `BoardGuidancePresentation.accessibilityLabel(for:piece:)`, `coverageAccessibilityLabel(for:)`, Reduce Motion behavior, and final performance/architecture guards.

- [ ] **Step 1: Add failing accessibility and terminal-state tests**

Use exact copy assertions:

```swift
func testPieceAccessibilityIncludesThreatAndDefenseStatus() {
    let label = presentation.accessibilityLabel(
        for: targetSquare,
        piece: Piece(kind: .bishop, color: .white)
    )

    XCTAssertEqual(label, "White bishop on d4, threatened and defended")
}

func testCoverageAccessibilityNamesBothSidesOnContestedSquare() {
    XCTAssertEqual(
        presentation.coverageAccessibilityLabel(for: contestedSquare),
        "d5, covered by White and Black"
    )
}

func testCheckmateShowsOnlyLosingKingDanger() {
    XCTAssertEqual(session.boardGuidance.threatenedSquares, [losingKingSquare])
    XCTAssertTrue(session.boardGuidance.selectedPaths.isEmpty)
    XCTAssertNil(session.boardGuidance.coverage)
}

func testStalemateHasNoBoardGuidance() {
    XCTAssertEqual(session.boardGuidance, .empty(sideToMove: .black))
}
```

Add tests that identity selection still updates `selectedPieceInfo` after checkmate/stalemate while `legalDestinations` and all path/supporter sets remain empty.

- [ ] **Step 2: Add performance and one-analysis-pass tests**

Add a dense-position XCTest measurement:

```swift
func testDensePositionAnalysisPerformance() {
    let state = GameState.startingPosition()

    measure {
        for _ in 0..<100 {
            _ = PositionAnalyzer.analyze(state)
        }
    }
}
```

In `GameSessionTests`, capture `analysisRevision`, select several pieces, show/hide coverage, and assert the revision is unchanged. Stage one move and assert it increments exactly once.

- [ ] **Step 3: Run focused tests and verify failures**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/PositionAnalyzerTests -only-testing:ChessTutorTests/BoardGuidancePresentationTests -only-testing:ChessTutorTests/GameSessionTests
```

Expected: failures for missing accessibility copy and any terminal/profiling behavior not yet wired.

- [ ] **Step 4: Implement accessibility and Reduce Motion behavior**

Build labels from piece color/kind/square and the presentation marker sets. Coverage labels derive names from `BoardCoveragePresentation.sideToMove` so they say actual colors, not “yellow” and “red.”

Apply the combined label to each occupied board square and hide decorative burst, shield, echo, path, and pip elements from accessibility. Add `.accessibilityValue("Shown"/"Hidden")` to the coverage button.

Read `@Environment(\.accessibilityReduceMotion)` in `ChessBoardView`. When true, use opacity-only transitions with no scale, travel, or spring for guidance changes. Piece movement keeps the app's established physical settling behavior; only guidance ornament motion is reduced.

- [ ] **Step 5: Add final architecture assertions**

Add source inspections that verify:

```swift
XCTAssertFalse(chessBoardSource.contains("LegalMoveGenerator"))
XCTAssertFalse(chessBoardSource.contains("PositionAnalyzer"))
XCTAssertFalse(positionAnalyzerSource.contains("switch piece.kind"))
```

Also assert `GameSession` coverage toggles do not affect remote position fingerprints or any serialized snapshot value by comparing `PositionFingerprinting.fingerprint(for:)` before and after local selection/coverage changes.

- [ ] **Step 6: Run the entire automated suite**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Expected: the baseline 315 tests plus all new tests pass with zero failures.

- [ ] **Step 7: Perform simulator visual verification**

Launch the app on `iPad (A16)` and inspect these concrete positions through test fixtures or the debug lab:

1. Sparse position with one threatened-and-defended piece: burst and shield coexist without obscuring the piece.
2. Dense middlegame: ambient markers remain readable and do not look like a field of arrows.
3. Selected own piece: yellow outgoing paths, red inbound attackers, teal supporter echoes, unrelated ambient markers at 20%.
4. Selected opponent piece: red outgoing paths and yellow inbound attackers; dragging it does nothing.
5. Coverage: round yellow and diamond red pips coexist on contested squares; selection paths remain above pips.
6. Tentative blunder: moved piece settles, remains selected, and gains a fresh danger burst before **Done**.
7. Persistence: coverage survives drag start, landing, and reversion, then closes after successful **Done**.
8. Checkmate: only the losing king's burst remains; stalemate has no guidance.
9. En passant: captured pawn bursts while the trajectory lands on the empty square.
10. All four tabletop rotations and Reduce Motion enabled.

Record any visual-only tuning by changing the constants in `BoardGuidanceStyle.current`, rerun `BoardGuidanceStyleTests`, and repeat the affected scenario.

- [ ] **Step 8: Run final repository checks and commit**

Run:

```bash
git diff --check
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Expected: no whitespace errors and zero test failures.

```bash
git add ChessTutor/Game/BoardGuidancePresentation.swift ChessTutor/Game/GameSession.swift ChessTutor/UI/Board/BoardGuidanceOverlay.swift ChessTutor/UI/Board/ChessBoardView.swift ChessTutor/UI/Sidebar/SelectedPiecePanelView.swift ChessTutorTests/Core/PositionAnalyzerTests.swift ChessTutorTests/Game/BoardGuidancePresentationTests.swift ChessTutorTests/Game/GameSessionTests.swift ChessTutorTests/UI/BoardGuidanceStyleTests.swift
git commit -m "Polish accessible board guidance"
```

---

## Completion Gate

Before declaring the feature complete:

- Re-read `docs/superpowers/specs/2026-08-10-threat-defense-guidance-design.md` and map every requirement to a passing test or a visually verified scenario above.
- Confirm `git status --short` is clean.
- Confirm the full iPad simulator suite reports zero failures.
- Confirm no Core rule call appears in `ChessBoardView` and no piece-rule implementation appears in `PositionAnalyzer`.
- Confirm coverage remains local to `GameSession` presentation state and is absent from remote snapshots, codecs, transports, and fingerprints.
- Request code review before integration.

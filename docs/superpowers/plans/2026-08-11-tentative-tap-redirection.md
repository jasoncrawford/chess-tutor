# Tentative Tap Redirection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an empty-square tap replace an existing tentative move when the square is a valid alternative destination from the original source, while animating directly from the displayed staged square to the replacement destination.

**Architecture:** `GameSession` remains the sole owner of tentative-move state and validates the replacement against `committedState`. A valid replacement swaps `tentativeMove` in one state transition and refreshes displayed analysis once, so `ChessBoardView` observes only the displayed-board change from the first destination to the second and its existing `VisualPiece` identity matching supplies the direct animation. Invalid taps continue through the existing quiet-reversion path; no chess rules or redirect sequencing move into SwiftUI.

**Tech Stack:** Swift, Observation, SwiftUI, XCTest, Xcode/iOS Simulator

## Global Constraints

- Treat the replacement as one move from the original square in the committed position, never as a second move from the staged square.
- Publish no intermediate committed-board state for a valid replacement; the displayed piece must animate directly between tentative destinations.
- Keep chess-rule validation in `GameSession` and the existing legal-move model helpers, not `ChessBoardView`.
- Preserve quiet reversion for invalid empty-square taps, hidden-hint tap movement, coverage visibility, promotion handling, and the existing second-drag behavior.
- Do not add new UI controls, messages, or dependencies.

---

### Task 1: Atomically replace a tentative move from an empty-square tap

**Files:**
- Modify: `ChessTutorTests/Game/GameSessionTests.swift:1020`
- Modify: `ChessTutor/Game/GameSession.swift:227-319`

**Interfaces:**
- Consumes: `GameSession.tapEmptySquare(at:) -> MoveAttemptResult?`, `GameSession.moveSelectedPiece(to:) -> MoveAttemptResult`, `allowedMoves(forSelectionAt:) -> [Move]`, and the existing `tentativeMove`, `committedState`, selection, coverage, and analysis state.
- Produces: a private `stage(_ move: Move) -> MoveAttemptResult` helper used for both initial and replacement tentative moves; `tapEmptySquare(at:)` returns `.moved` for a valid atomic replacement and `nil` for the existing quiet reversion.

- [ ] **Step 1: Add a regression test for the reported redirect and atomic publication**

Add this test beside `testEmptySquareAttemptAfterTentativeMoveRestoresCommittedBoard` in `ChessTutorTests/Game/GameSessionTests.swift`:

```swift
func testTappingAlternativeDestinationAtomicallyRedirectsTentativeMove() {
    let origin = Square(file: .d, rank: 1)
    let stagedDestination = Square(file: .d, rank: 3)
    let alternativeDestination = Square(file: .d, rank: 2)
    let queen = Piece(kind: .queen, color: .white)
    let session = GameSession(
        state: GameState(
            board: Board(
                pieces: [
                    origin: queen,
                    Square(file: .a, rank: 1): Piece(kind: .king, color: .white),
                    Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
                ]
            ),
            sideToMove: .white
        )
    )
    session.assistSettings.showLegalMovesOnSelection = false
    session.toggleCoverage()
    session.select(origin)
    _ = session.moveSelectedPiece(to: stagedDestination)
    let revisionAfterFirstMove = session.analysisRevision

    let result = session.tapEmptySquare(at: alternativeDestination)

    XCTAssertEqual(result, .moved)
    XCTAssertEqual(session.state.board[alternativeDestination], queen)
    XCTAssertNil(session.state.board[origin])
    XCTAssertNil(session.state.board[stagedDestination])
    XCTAssertEqual(session.selectedSquare, alternativeDestination)
    XCTAssertTrue(session.canFinishTurn)
    XCTAssertTrue(session.isCoverageVisible)
    XCTAssertEqual(session.analysisRevision, revisionAfterFirstMove + 1)
}
```

The final assertion is the regression guard for direct animation: a restore-then-restage implementation refreshes analysis twice, while an atomic replacement refreshes it once.

- [ ] **Step 2: Run the new test and observe the reported failure**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/GameSessionTests/testTappingAlternativeDestinationAtomicallyRedirectsTentativeMove -resultBundlePath /tmp/ChessTutor-tentative-tap-redirection-red.xcresult
```

Expected: FAIL because `tapEmptySquare(at:)` returns `nil`, restores the queen to `d1`, and leaves `d2` empty. This is the required local reproduction before changing production code.

- [ ] **Step 3: Centralize tentative-move staging**

In `ChessTutor/Game/GameSession.swift`, replace the promotion/staging tail of `moveSelectedPiece(to:)` with:

```swift
return stage(move)
```

Add this private helper near the other tentative-move helpers:

```swift
private func stage(_ move: Move) -> MoveAttemptResult {
    if case .promotion = move.special {
        message = nil
        return .needsPromotion(from: move.from, to: move.to)
    }

    tentativeMove = move
    selectedSquare = move.to
    actionableMovesForSelection = []
    message = nil
    refreshDisplayedAnalysis()
    return .moved
}
```

This preserves the existing initial-move and promotion behavior while giving tap redirection one canonical staging operation.

- [ ] **Step 4: Replace a valid tentative move without restoring first**

Change the tentative branch in `tapEmptySquare(at:)` to validate from the original source against the committed position and stage the replacement directly:

```swift
if let tentativeMove {
    guard let replacementMove = allowedMoves(forSelectionAt: tentativeMove.from)
        .first(where: { $0.to == square }) else {
        restoreCommittedPosition()
        return nil
    }

    return stage(replacementMove)
}
```

Do not call `restoreCommittedPosition()` on the valid path. Replacing `tentativeMove` directly makes `session.state.board` change from the first destination to the alternative destination in one observable transition, allowing the existing `ChessBoardView.nextVisualPieces()` matching to keep the queen's visual identity and animate `d3 → d2`.

- [ ] **Step 5: Run focused session tests**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/GameSessionTests -resultBundlePath /tmp/ChessTutor-tentative-tap-redirection-focused.xcresult
```

Expected: all `GameSessionTests` pass with zero skipped tests, including:

- the new valid atomic redirect;
- the existing invalid empty-square quiet reversion;
- hidden-hint empty-square movement;
- second-drag redirection;
- coverage persistence.

- [ ] **Step 6: Run the complete test suite**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -resultBundlePath /tmp/ChessTutor-tentative-tap-redirection-full.xcresult
```

Expected: the complete suite passes with zero failures and zero skipped tests. Inspect the result bundle summary rather than relying only on the command exit code.

- [ ] **Step 7: Verify the displayed transition in the simulator**

Build and launch the app on the iPad simulator. Create a playable line in which the queen has an unobstructed original path to two squares, stage the queen on the farther square, then tap the nearer alternative square.

Expected:

- the queen moves directly from the first tentative destination to the second;
- it does not appear at its original square between those positions;
- the second destination remains tentative with **Done** available;
- guidance and any open coverage lens refresh for the second tentative position.

- [ ] **Step 8: Commit the tested fix**

```bash
git add ChessTutor/Game/GameSession.swift ChessTutorTests/Game/GameSessionTests.swift
git commit -m "Fix tentative move tap redirection"
```


# Coordinate Grid Guidance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make board coordinate labels readable and add quiet selected-square guidance for beginners.

**Architecture:** Keep rules in `Core` unchanged. Add square-coordinate presentation fields to `SelectedPieceInfo`, render them in `SelectedPiecePanelView`, and style coordinate labels in `ChessBoardView` based on `session.selectedSquare`.

**Tech Stack:** Swift 6, SwiftUI, Observation, XCTest, iPad simulator.

---

## File Structure

- Modify: `ChessTutor/Game/GameSession.swift`
  - Add `squareID` and `squareCoordinateSummary` to `SelectedPieceInfo`.
- Modify: `ChessTutorTests/Game/GameSessionTests.swift`
  - Cover selected square ID and beginner coordinate summary.
- Modify: `ChessTutor/UI/Sidebar/SelectedPiecePanelView.swift`
  - Show selected square ID and "file/rank" summary in the selected-piece panel.
- Modify: `ChessTutor/UI/Board/ChessBoardView.swift`
  - Nudge coordinate labels inward and color-highlight the selected file/rank labels.
- Modify: `ChessTutorTests/UI/CaptureTrayLayoutTests.swift`
  - Add focused assertions for coordinate label style constants.

### Task 1: Selected Square Presentation

**Files:**
- Modify: `ChessTutor/Game/GameSession.swift`
- Modify: `ChessTutorTests/Game/GameSessionTests.swift`

- [ ] **Step 1: Write failing test**

Add to `GameSessionTests`:

```swift
func testSelectedPieceInfoIncludesSquareCoordinates() {
    let session = GameSession()

    session.select(Square(file: .e, rank: 2))

    XCTAssertEqual(session.selectedPieceInfo?.squareID, "e2")
    XCTAssertEqual(session.selectedPieceInfo?.squareCoordinateSummary, "file e, rank 2")
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/GameSessionTests/testSelectedPieceInfoIncludesSquareCoordinates
```

Expected: fails because the new fields do not exist.

- [ ] **Step 3: Implement presentation fields**

Update `SelectedPieceInfo`:

```swift
struct SelectedPieceInfo: Equatable, Sendable {
    let piece: Piece
    let square: Square
    let squareID: String
    let squareCoordinateSummary: String
    let title: String
    let movementSummary: String
}
```

Update `selectedPieceInfo`:

```swift
return SelectedPieceInfo(
    piece: piece,
    square: selectedSquare,
    squareID: "\(selectedSquare.file)\(selectedSquare.rank)",
    squareCoordinateSummary: "file \(selectedSquare.file), rank \(selectedSquare.rank)",
    title: "\(piece.color.rawValue.capitalized) \(piece.kind.rawValue)",
    movementSummary: movementSummary(for: piece.kind)
)
```

Update existing tests that construct `SelectedPieceInfo` literals to include the new fields.

- [ ] **Step 4: Run focused tests**

Run the same `xcodebuild test` command. Expected: pass.

### Task 2: Side Panel Coordinate Treatment

**Files:**
- Modify: `ChessTutor/UI/Sidebar/SelectedPiecePanelView.swift`
- Modify: `ChessTutorTests/UI/CaptureTrayLayoutTests.swift`

- [ ] **Step 1: Add layout coverage**

Add a test that ensures the selected-piece panel has enough planned height for icon, coordinate row, title, and two-line summary:

```swift
func testSelectedPiecePanelLayoutIncludesCoordinateRow() {
    let layout = SelectedPiecePanelLayout.current

    XCTAssertEqual(layout.coordinateRowHeight, 24, accuracy: 0.01)
    XCTAssertEqual(layout.requiredContentHeight, 194, accuracy: 0.01)
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/CaptureTrayLayoutTests/testSelectedPiecePanelLayoutIncludesCoordinateRow
```

Expected: fails because `coordinateRowHeight` does not exist.

- [ ] **Step 3: Render selected square ID**

Add `coordinateRowHeight: 24` to `SelectedPiecePanelLayout.current`, store it as a property, and include it in `requiredContentHeight`. Reduce the icon slot and text metrics so `requiredContentHeight` remains 194, preserving the current square-panel fit. In the selected state, render a compact row between the icon and title:

```swift
HStack(spacing: 8) {
    Text(selectedPieceInfo.squareID)
        .font(.system(size: 15, weight: .bold, design: .rounded))
        .foregroundStyle(AppTheme.panelBackground)
        .padding(.horizontal, 10)
        .frame(height: layout.coordinateRowHeight)
        .background {
            Capsule()
                .fill(AppTheme.boardFrame)
        }

    Text(selectedPieceInfo.squareCoordinateSummary)
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(AppTheme.mutedInk)
        .lineLimit(1)
        .minimumScaleFactor(0.82)
}
.frame(height: layout.coordinateRowHeight, alignment: .leading)
```

- [ ] **Step 4: Run focused tests**

Run the same `xcodebuild test` command. Expected: pass.

### Task 3: Board Coordinate Label Styling

**Files:**
- Modify: `ChessTutor/UI/Board/ChessBoardView.swift`
- Modify: `ChessTutorTests/UI/CaptureTrayLayoutTests.swift`

- [ ] **Step 1: Add style coverage**

Add a test:

```swift
func testBoardCoordinateLabelsAreInsetClearOfFrame() {
    XCTAssertEqual(BoardCoordinateLabelStyle.current.padding, 9, accuracy: 0.01)
    XCTAssertGreaterThan(BoardCoordinateLabelStyle.current.padding, 5)
    XCTAssertLessThan(BoardCoordinateLabelStyle.current.padding, 13)
}

func testBoardCoordinateHighlightsUseSeparateLightSquareContrast() {
    XCTAssertEqual(BoardCoordinateLabelStyle.current.normalOpacity, 0.60, accuracy: 0.01)
    XCTAssertGreaterThan(BoardCoordinateLabelStyle.current.selectedLightSquareOpacity, 0.88)
    XCTAssertGreaterThan(BoardCoordinateLabelStyle.current.selectedDarkSquareOpacity, 0.88)
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/CaptureTrayLayoutTests/testBoardCoordinateLabelsAreInsetClearOfFrame
```

Expected: fails because `BoardCoordinateLabelStyle` does not exist or does not have adaptive highlight fields.

- [ ] **Step 3: Add style and highlight selected rank/file**

Add a small style struct near `CaptureGuidanceStyle`:

```swift
struct BoardCoordinateLabelStyle: Equatable {
    static let current = BoardCoordinateLabelStyle(
        padding: 9,
        normalOpacity: 0.60,
        selectedLightSquareOpacity: 0.95,
        selectedDarkSquareOpacity: 0.95
    )

    let padding: CGFloat
    let normalOpacity: Double
    let selectedLightSquareOpacity: Double
    let selectedDarkSquareOpacity: Double
}
```

Update `coordinateLabels(for:)` to compute whether each visible edge label belongs to `session.selectedSquare`, use `BoardCoordinateLabelStyle.current.padding`, and switch highlighted labels to dark board-frame ink on light squares and warm selected-square color on dark squares.

- [ ] **Step 4: Run focused tests**

Run the same `xcodebuild test` command. Expected: pass.

### Task 4: Verification

**Files:**
- Verify all modified files.

- [ ] **Step 1: Run full tests**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Expected: all tests pass with zero failures.

- [ ] **Step 2: Inspect git diff**

Run:

```bash
git diff --stat
git diff
```

Expected: changes are scoped to coordinate guidance docs, presentation state, selected-piece panel, board label styling, and tests.

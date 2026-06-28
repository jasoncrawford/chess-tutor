# Side Panel Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the side area so it supports game state, selected-piece beginner help, and separate physical capture boxes, while keeping New Game/About inside the status square under Done.

**Architecture:** Keep chess rules unchanged. Add selected-piece presentation state to `GameSession`, split the side-panel SwiftUI into focused views, and keep `ContentView` responsible for layout, orientation, sheets, and wiring. Capture boxes remain driven by `session.capturedPieces` and continue using matched geometry IDs.

**Tech Stack:** Swift 6, SwiftUI, Observation, XCTest, iPad simulator visual verification.

---

## File Structure

- Modify: `ChessTutor/Game/GameSession.swift`
  - Add `SelectedPieceInfo` and a computed `selectedPieceInfo` property that describes the selected piece without adding rule logic to SwiftUI.
- Modify: `ChessTutorTests/Game/GameSessionTests.swift`
  - Add tests for selected-piece info appearing, clearing, and using beginner-friendly display names.
- Create: `ChessTutor/UI/Sidebar/SidebarPanelView.swift`
  - Shared warm panel shell and utility styling for the side panels.
- Create: `ChessTutor/UI/Sidebar/SidePanelView.swift`
  - Owns the three square side parts and their rotation behavior.
- Create: `ChessTutor/UI/Sidebar/TurnStatusPanelView.swift`
  - Presents status, guidance, Done, New Game, and About inside the first square.
- Create: `ChessTutor/UI/Sidebar/SelectedPiecePanelView.swift`
  - Presents a large selected piece, piece name, and empty resting state.
- Create: `ChessTutor/UI/Sidebar/CapturedPiecesPanelView.swift`
  - Presents captured pieces as two standalone stacked wooden boxes with felt-like interiors, with no enclosing white square and no labels.
- Modify: `ChessTutor/UI/Root/ContentView.swift`
  - Replace local sidebar tile methods with `SidePanelView`; keep sheets and orientation wiring here.
- Modify: `ChessTutor/UI/Board/ChessBoardView.swift`
  - Rename `SidebarSegment.newGame` to `selectedPiece` and update tabletop ordering.
- Modify: `ChessTutor/UI/Theme/AppTheme.swift`
  - Add warmer panel, wooden box, and felt tokens for capture boxes and selected-piece display.
- Modify: `ChessTutor.xcodeproj/project.pbxproj`
  - Add new Swift files to the app target.
- Optional visual artifact: capture simulator screenshots for landscape and portrait after implementation.

## Task 1: Add Selected-Piece Presentation State

**Files:**
- Modify: `ChessTutor/Game/GameSession.swift`
- Modify: `ChessTutorTests/Game/GameSessionTests.swift`

- [ ] **Step 1: Write failing tests**

Add these tests to `GameSessionTests`:

```swift
func testSelectedPieceInfoNamesSelectedPiece() {
    let session = GameSession()

    session.select(Square(file: .g, rank: 1))

    XCTAssertEqual(
        session.selectedPieceInfo,
        SelectedPieceInfo(
            piece: Piece(kind: .knight, color: .white),
            square: Square(file: .g, rank: 1),
            title: "White knight",
            movementSummary: "Moves in an L shape."
        )
    )
}

func testSelectedPieceInfoClearsWhenSelectionClears() {
    let session = GameSession()

    session.select(Square(file: .g, rank: 1))
    session.select(Square(file: .a, rank: 6))

    XCTAssertNil(session.selectedPieceInfo)
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/GameSessionTests/testSelectedPieceInfoNamesSelectedPiece -only-testing:ChessTutorTests/GameSessionTests/testSelectedPieceInfoClearsWhenSelectionClears
```

Expected: fails because `SelectedPieceInfo` and `selectedPieceInfo` do not exist.

- [ ] **Step 3: Add selected-piece presentation model**

In `GameSession.swift`, add this near `CapturedPiece`:

```swift
struct SelectedPieceInfo: Equatable, Sendable {
    let piece: Piece
    let square: Square
    let title: String
    let movementSummary: String
}
```

Add this computed property inside `GameSession`:

```swift
var selectedPieceInfo: SelectedPieceInfo? {
    guard let selectedSquare,
          let piece = state.board[selectedSquare] else {
        return nil
    }

    return SelectedPieceInfo(
        piece: piece,
        square: selectedSquare,
        title: "\(piece.color.rawValue.capitalized) \(piece.kind.rawValue)",
        movementSummary: movementSummary(for: piece.kind)
    )
}
```

Add this private helper inside `GameSession`:

```swift
private func movementSummary(for kind: Piece.Kind) -> String {
    switch kind {
    case .king:
        return "Moves one square in any direction."
    case .queen:
        return "Moves in straight lines and diagonals."
    case .rook:
        return "Moves in straight lines."
    case .bishop:
        return "Moves diagonally."
    case .knight:
        return "Moves in an L shape."
    case .pawn:
        return "Moves forward and captures diagonally."
    }
}
```

- [ ] **Step 4: Run focused tests**

Run the command from Step 2 again.

Expected: both tests pass.

- [ ] **Step 5: Commit**

```bash
git add ChessTutor/Game/GameSession.swift ChessTutorTests/Game/GameSessionTests.swift
git commit -m "Add selected piece presentation info"
```

## Task 2: Rename The Third Sidebar Segment

**Files:**
- Modify: `ChessTutor/UI/Board/ChessBoardView.swift`
- Modify: `ChessTutor/UI/Root/ContentView.swift`
- Test: `ChessTutorTests/Core/BoardTests.swift`

- [ ] **Step 1: Update sidebar segment enum**

In `ChessBoardView.swift`, change:

```swift
case newGame
```

to:

```swift
case selectedPiece
```

Then update `sidebarSegmentsInTabletopOrder`:

```swift
var sidebarSegmentsInTabletopOrder: [SidebarSegment] {
    switch self {
    case .normal, .counterclockwiseQuarterTurn:
        return [.messageAndDone, .selectedPiece, .capturedPieces]
    case .clockwiseQuarterTurn, .halfTurn:
        return [.capturedPieces, .selectedPiece, .messageAndDone]
    }
}
```

- [ ] **Step 2: Update `ContentView` switch temporarily**

In `ContentView.sidebarSegment(_:)`, replace `.newGame` with `.selectedPiece` and keep returning `newGameTile` temporarily:

```swift
case .selectedPiece:
    newGameTile
```

This keeps the app compiling while the dedicated views are introduced.

- [ ] **Step 3: Update board ordering tests**

In `ChessTutorTests/Core/BoardTests.swift`, update the expected arrays in the `sidebarSegmentsInTabletopOrder` assertions from `.newGame` to `.selectedPiece`, while preserving orientation-specific order.

Expected examples: normal and counterclockwise order should be `[.messageAndDone, .selectedPiece, .capturedPieces]`; clockwise and half-turn order should be `[.capturedPieces, .selectedPiece, .messageAndDone]`.

- [ ] **Step 4: Run focused board tests**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/BoardTests
```

Expected: board ordering tests pass.

- [ ] **Step 5: Commit**

```bash
git add ChessTutor/UI/Board/ChessBoardView.swift ChessTutor/UI/Root/ContentView.swift ChessTutorTests
git commit -m "Reserve sidebar segment for selected piece help"
```

## Task 3: Add Sidebar View Components

**Files:**
- Create: `ChessTutor/UI/Sidebar/SidebarPanelView.swift`
- Create: `ChessTutor/UI/Sidebar/TurnStatusPanelView.swift`
- Create: `ChessTutor/UI/Sidebar/SelectedPiecePanelView.swift`
- Create: `ChessTutor/UI/Sidebar/CapturedPiecesPanelView.swift`
- Create: `ChessTutor/UI/Sidebar/SidePanelView.swift`
- Modify: `ChessTutor.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create the shared panel shell**

Create `SidebarPanelView.swift`:

```swift
import SwiftUI

struct SidebarPanelView<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .frame(width: 240, height: 240)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.panel)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppTheme.panelStroke, lineWidth: 1)
                    }
                    .shadow(color: AppTheme.panelShadow, radius: 18, y: 8)
            )
    }
}
```

- [ ] **Step 2: Create turn status panel**

Create `TurnStatusPanelView.swift`:

```swift
import SwiftUI

struct TurnStatusPanelView: View {
    @Bindable var session: GameSession
    let onAbout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.statusText)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)

            ZStack(alignment: .topLeading) {
                if let guidanceText = session.guidanceText {
                    Text(guidanceText)
                        .font(.body)
                        .foregroundStyle(AppTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.vertical, session.guidanceText == nil ? 0 : 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(session.guidanceText == nil ? Color.clear : AppTheme.panelInset)
            )

            Spacer(minLength: 0)

            GameControlsView(session: session, placement: .done)

            GameControlsView(session: session, placement: .newGame, onAbout: onAbout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
```

- [ ] **Step 3: Create selected piece panel**

Create `SelectedPiecePanelView.swift`:

```swift
import SwiftUI

struct SelectedPiecePanelView: View {
    let selectedPieceInfo: SelectedPieceInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selectedPieceInfo {
                PieceIconView(piece: selectedPieceInfo.piece)
                    .frame(width: 112, height: 112)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)

                Text(selectedPieceInfo.title)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(AppTheme.ink)

                Text(selectedPieceInfo.movementSummary)
                    .font(.callout)
                    .foregroundStyle(AppTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Spacer(minLength: 0)

                Image(systemName: "hand.point.up.left")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(AppTheme.mutedInk.opacity(0.42))
                    .frame(maxWidth: .infinity)

                Text("Choose a piece")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(AppTheme.mutedInk.opacity(0.78))
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
```

- [ ] **Step 4: Create captured pieces panel**

Create `CapturedPiecesPanelView.swift`:

```swift
import SwiftUI

struct CapturedPiecesPanelView: View {
    let capturedPieces: [CapturedPiece]
    let captureNamespace: Namespace.ID

    var body: some View {
        VStack(spacing: 10) {
            captureBox(for: .black)
            captureBox(for: .white)
        }
        .frame(width: 240, height: 240)
    }

    private func captureBox(for color: PieceColor) -> some View {
        let pieces = capturedPieces.filter { $0.piece.color == color }

        return ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.captureBoxWood)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.20), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .shadow(color: AppTheme.captureBoxShadow, radius: 14, y: 8)

            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(AppTheme.captureBoxFelt)
                .padding(9)
                .shadow(color: .black.opacity(0.18), radius: 5, y: -1)

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 6),
                alignment: .center,
                spacing: 4
            ) {
                ForEach(pieces) { capturedPiece in
                    PieceIconView(piece: capturedPiece.piece)
                        .matchedGeometryEffect(id: capturedPiece.id, in: captureNamespace)
                        .frame(width: 30, height: 30)
                        .opacity(capturedPiece.state == .tentative ? 0.62 : 1)
                        .scaleEffect(capturedPiece.state == .tentative ? 0.92 : 1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 5: Create composed side panel view**

Create `SidePanelView.swift`:

```swift
import SwiftUI

struct SidePanelView: View {
    @Bindable var session: GameSession
    let viewingAngle: BoardViewingAngle
    let readableRotationDegrees: Double
    let captureNamespace: Namespace.ID
    let onAbout: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ForEach(viewingAngle.sidebarSegmentsInTabletopOrder, id: \.self) { segment in
                sidebarSegment(segment)
                    .rotationEffect(.degrees(readableRotationDegrees))
            }
        }
        .frame(width: 260, height: 760, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: viewingAngle.sidebarSegmentsInTabletopOrder)
    }

    @ViewBuilder
    private func sidebarSegment(_ segment: SidebarSegment) -> some View {
        switch segment {
        case .messageAndDone:
            SidebarPanelView {
                TurnStatusPanelView(session: session, onAbout: onAbout)
            }
        case .selectedPiece:
            SidebarPanelView {
                SelectedPiecePanelView(selectedPieceInfo: session.selectedPieceInfo)
            }
        case .capturedPieces:
            CapturedPiecesPanelView(
                capturedPieces: session.capturedPieces,
                captureNamespace: captureNamespace
            )
        }
    }
}
```

- [ ] **Step 6: Add new files to the Xcode project**

Add all files under `ChessTutor/UI/Sidebar/` to the app target in `ChessTutor.xcodeproj/project.pbxproj`, matching the existing project file style.

- [ ] **Step 7: Build**

Run:

```bash
xcodebuild build -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Expected: build succeeds.

- [ ] **Step 8: Commit**

```bash
git add ChessTutor/UI/Sidebar ChessTutor.xcodeproj/project.pbxproj
git commit -m "Add side panel component views"
```

## Task 4: Wire New Side Panel Into ContentView

**Files:**
- Modify: `ChessTutor/UI/Root/ContentView.swift`

- [ ] **Step 1: Replace side panel implementation**

In `ContentView`, replace `sidePanelContainer` with:

```swift
private var sidePanelContainer: some View {
    SidePanelView(
        session: session,
        viewingAngle: viewingAngle,
        readableRotationDegrees: readableRotationDegrees,
        captureNamespace: captureNamespace,
        onAbout: {
            isShowingAbout = true
        }
    )
    .frame(width: 260)
    .frame(height: 760, alignment: .top)
}
```

- [ ] **Step 2: Remove moved private views**

Delete these private members from `ContentView` after `SidePanelView` replaces them:

```swift
private var sidePanel: some View
private var turnTile: some View
private var newGameTile: some View
private func sidebarSegment(_ segment: SidebarSegment) -> some View
private func sidebarTile<Content: View>(...)
private var captureTrays: some View
private func captureTray(for color: PieceColor) -> some View
```

- [ ] **Step 3: Build**

Run:

```bash
xcodebuild build -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add ChessTutor/UI/Root/ContentView.swift
git commit -m "Wire redesigned side panel into content view"
```

## Task 5: Tune Panel And Tray Visuals

**Files:**
- Modify: `ChessTutor/UI/Theme/AppTheme.swift`
- Modify: `ChessTutor/UI/Sidebar/SidebarPanelView.swift`
- Modify: `ChessTutor/UI/Sidebar/CapturedPiecesPanelView.swift`
- Modify: `ChessTutor/UI/Sidebar/SelectedPiecePanelView.swift`

- [ ] **Step 1: Add theme tokens**

Add these tokens to `AppTheme`:

```swift
static let panelWarmth = Color(red: 0.96, green: 0.91, blue: 0.80).opacity(0.72)
static let panelTopLight = Color.white.opacity(0.28)
static let captureBoxWood = Color(red: 0.53, green: 0.40, blue: 0.24)
static let captureBoxFelt = Color(red: 0.26, green: 0.43, blue: 0.35)
static let captureBoxShadow = Color.black.opacity(0.15)
static let selectedPiecePlinth = Color(red: 0.32, green: 0.23, blue: 0.14).opacity(0.12)
```

- [ ] **Step 2: Make the shared panel warmer**

In `SidebarPanelView`, change the background fill to a subtle vertical material stack:

```swift
.fill(AppTheme.panelWarmth)
.overlay {
    RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(
            LinearGradient(
                colors: [AppTheme.panelTopLight, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
}
```

Keep the stroke and shadow after the gradient overlay.

- [ ] **Step 3: Make the capture boxes feel physical**

In `CapturedPiecesPanelView`, use `AppTheme.captureBoxWood` for each outer box and `AppTheme.captureBoxFelt` for the inner surface. Do not add text labels or a large enclosing panel behind the boxes.

```swift
RoundedRectangle(cornerRadius: 16, style: .continuous)
    .fill(AppTheme.captureBoxWood)

RoundedRectangle(cornerRadius: 11, style: .continuous)
    .fill(AppTheme.captureBoxFelt)
    .padding(9)
```

- [ ] **Step 4: Make selected piece panel feel like a display plinth**

In `SelectedPiecePanelView`, wrap the large piece in:

```swift
PieceIconView(piece: selectedPieceInfo.piece)
    .frame(width: 112, height: 112)
    .frame(maxWidth: .infinity, alignment: .center)
    .padding(.vertical, 8)
    .background(
        Circle()
            .fill(AppTheme.selectedPiecePlinth)
            .frame(width: 132, height: 132)
    )
```

- [ ] **Step 5: Run full tests**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Expected: all tests pass with 0 failures.

- [ ] **Step 6: Commit**

```bash
git add ChessTutor/UI/Theme/AppTheme.swift ChessTutor/UI/Sidebar
git commit -m "Polish side panel capture boxes"
```

## Task 6: Visual Verification

**Files:**
- No production file changes expected unless the screenshots reveal layout problems.

- [ ] **Step 1: Run the app in the iPad simulator**

Run:

```bash
xcodebuild build -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Expected: build succeeds.

- [ ] **Step 2: Capture landscape and portrait screenshots**

Use the simulator controls or `xcrun simctl io booted screenshot` to capture:

```bash
xcrun simctl io booted screenshot /tmp/chess-side-panel-landscape.png
xcrun simctl io booted screenshot /tmp/chess-side-panel-portrait.png
```

- [ ] **Step 3: Verify visual requirements**

Check both screenshots:

- The side area has three live-game panels: game state, selected piece, captures.
- New Game/About live inside the first square under Done.
- The selected-piece panel has a calm empty state when nothing is selected.
- Selecting a piece shows a large Celtic piece and beginner-friendly name.
- Captured pieces sit in two separate stacked wooden boxes with felt-like interiors, no labels, and no white enclosing square.
- Text does not overlap or overflow in landscape or portrait.
- Table rotation still keeps panel contents readable.

- [ ] **Step 4: Fix any screenshot issues**

If text or controls crowd the side area, adjust spacing in the relevant focused view rather than reintroducing layout logic into `ContentView`.

- [ ] **Step 5: Final test run**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Expected: all tests pass with 0 failures.

- [ ] **Step 6: Final commit if visual fixes were needed**

If Step 4 changed files:

```bash
git add ChessTutor/UI ChessTutorTests
git commit -m "Refine side panel layout after visual review"
```

## Self-Review Notes

- Spec coverage: The plan keeps New Game/About inside the status square, adds selected-piece beginner help, keeps the game-state panel, and redesigns captures as separate stacked wooden boxes.
- Scope control: This does not add recommendations, coaching, move review, accounts, sync, or curriculum.
- Type consistency: `SelectedPieceInfo`, `selectedPieceInfo`, `SidebarSegment.selectedPiece`, and `SidePanelView` are introduced before downstream use.
- Testing: Model behavior gets focused XCTest coverage; UI layout gets build, full test, and screenshot verification.

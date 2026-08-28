# Games Board-Rack Revision Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the generic Games list with a tactile board rack whose game cards reliably open the intended board.

**Architecture:** Keep the persisted `GameLibrary` and its `GameLibraryEntry` ordering unchanged. Move Games presentation into focused SwiftUI rack/card views in `ContentView.swift`; each card uses one explicit `Button` action wired to the existing local, pending-remote, and remote-open handlers. Derive thumbnail board positions from stored moves rather than drawing a generic checkerboard.

**Tech Stack:** Swift 6, SwiftUI, XCTest, iOS Simulator.

## Global Constraints

- Preserve the existing `GameLibrary` persistence format and route restoration.
- Do not introduce archive, delete, search, naming, review, or replay features.
- `Start a Game` must continue to present the existing local/remote chooser.
- A pending invitation card opens its pending board; invitation decisions remain board-specific.
- Use the existing `AppTheme` materials and physical-board visual language.
- Run `xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'` before completion.

---

### Task 1: Make game-card actions deterministic in the library model

**Files:**
- Modify: `ChessTutor/Game/GameLifecycle.swift`
- Modify: `ChessTutorTests/Game/GameSessionTests.swift`

**Interfaces:**
- Consumes: `GameLibrary.entries`, `GameLibrary.showBoard(_:)`, `ManagedGameID`.
- Produces: a small `GameLibraryEntry` presentation helper for card labels/status and model tests proving a selected entry route is a board route.

- [ ] **Step 1: Write failing route tests for every card kind**

```swift
@MainActor
func testGameLibraryOpensLocalAndPendingCardsByTheirManagedIDs() {
    let library = GameLibrary()
    let local = library.createLocalGame()
    let pending = library.createPendingRemoteBoard(makeInvite())

    library.showBoard(local.id)
    XCTAssertEqual(library.route, .board(local.id))

    library.showBoard(pending.id)
    XCTAssertEqual(library.route, .board(pending.id))
}
```

- [ ] **Step 2: Run the focused test and observe the pre-change behavior**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/GameSessionTests/testGameLibraryOpensLocalAndPendingCardsByTheirManagedIDs
```

Expected: the test either exposes a missing card-presentation helper or confirms that only the view wiring, not the route model, needs correction.

- [ ] **Step 3: Add minimal entry presentation helpers when the view would otherwise duplicate game-kind branching**

```swift
extension GameLibraryEntry {
    var cardTitle: String { /* local / pending / remote title */ }
    var cardStatus: String { /* turn, finish, or invitation state */ }
}
```

Keep route ownership in `GameLibrary`; do not add UI state to the model.

- [ ] **Step 4: Run focused model tests**

Run the command from Step 2 and:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/GameSessionTests
```

Expected: all selected tests pass.

- [ ] **Step 5: Commit the tested model boundary**

```bash
git add ChessTutor/Game/GameLifecycle.swift ChessTutorTests/Game/GameSessionTests.swift
git commit -m "Clarify game card routing"
```

### Task 2: Build real miniature board thumbnails

**Files:**
- Modify: `ChessTutor/UI/Root/ContentView.swift`
- Test: `ChessTutorTests/Game/GameSessionTests.swift`

**Interfaces:**
- Consumes: `Move`, `GameSession(replayingCommittedMoves:)`, `RemoteMoveCodec.decode(_:)`, and `GameLibraryEntry`.
- Produces: `GameThumbnail` rendering stored board positions rather than an unpopulated checkerboard.

- [ ] **Step 1: Write a failing pure thumbnail-state test**

```swift
func testReplayingThumbnailMovesPlacesWhitePawnOnE4() {
    let session = GameSession(replayingCommittedMoves: [
        Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4))
    ])

    XCTAssertEqual(session.state.board[Square(file: .e, rank: 4)], Piece(kind: .pawn, color: .white))
}
```

- [ ] **Step 2: Run it**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/GameSessionTests/testReplayingThumbnailMovesPlacesWhitePawnOnE4
```

Expected: pass if the existing replay contract already supplies the thumbnail state; otherwise fix replay before touching SwiftUI.

- [ ] **Step 3: Replace generic thumbnail drawing with board-state drawing**

Use an eight-by-eight `LazyVGrid`. Derive `GameState` once per card, render square colors with existing `AppTheme.lightSquare`/`AppTheme.darkSquare`, and use `PieceIconView` at thumbnail scale for occupied squares. Do not instantiate a live `GameSession` inside a SwiftUI `body`; calculate a value-type `GameState` helper before constructing the grid.

- [ ] **Step 4: Run the focused game-session suite**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/GameSessionTests
```

Expected: all tests pass.

- [ ] **Step 5: Commit thumbnail rendering**

```bash
git add ChessTutor/UI/Root/ContentView.swift ChessTutorTests/Game/GameSessionTests.swift
git commit -m "Render game board thumbnails"
```

### Task 3: Replace the system Games list with the board rack

**Files:**
- Modify: `ChessTutor/UI/Root/ContentView.swift`

**Interfaces:**
- Consumes: `GameLibraryEntry`, existing `openLocalGame(_:)`, `openPendingRemoteBoard(_:)`, `openRemoteGame(_:)`, and `startNewGame()`.
- Produces: `GamesRackView`, `GameRackCard`, and a single explicit action per card.

- [ ] **Step 1: Add a screenshot/manual regression checklist before changing layout**

Record the current simulator failures to compare after the revision:

```text
1. Open Games from a board.
2. Confirm the current screen shows a generic navigation/list presentation.
3. Tap Start a Game and each existing card; record any non-response.
```

- [ ] **Step 2: Replace `GamesListView` with a tabletop rack**

Implement a `GeometryReader`-based screen with:

```swift
struct GamesRackView: View {
    let entries: [GameLibraryEntry]
    let onStartGame: () -> Void
    let onOpenEntry: (GameLibraryEntry) -> Void
}
```

Use a wood-framed cream rack over `AppTheme.table`; a `LazyVGrid` uses three columns in wide landscape and two in compact widths. Insert the Start card before all game cards. Keep all content inside the rack—no `NavigationStack`, `List`, chevrons, or system section headers.

- [ ] **Step 3: Give every card one action and a testable identifier**

```swift
Button(action: onStartGame) { StartGameRackCard() }
    .buttonStyle(.plain)
    .accessibilityIdentifier("games-start-card")

Button { onOpenEntry(entry) } label: { GameRackCard(entry: entry) }
    .buttonStyle(.plain)
    .accessibilityIdentifier("game-card-\(entry.id.rawValue.uuidString)")
```

Map `GameLibraryEntry` to the existing open handlers in one `switch` at the rack boundary. Do not embed a `Button` inside any card or list container.

- [ ] **Step 4: Add the empty rack state**

When `entries.isEmpty`, retain the Start card and render one short text line below it: `Your boards will appear here.` Do not use `ContentUnavailableView`.

- [ ] **Step 5: Build and exercise the simulator manually**

Run:

```bash
xcodebuild build -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Install/launch the resulting app, open Games, and tap Start a Game plus each card. Capture landscape screenshots for populated and empty states. Expected: every card responds, and the screen reads as a tabletop object rather than Settings.

- [ ] **Step 6: Commit the rack UI**

```bash
git add ChessTutor/UI/Root/ContentView.swift
git commit -m "Replace games list with board rack"
```

### Task 4: Verify the complete revision

**Files:**
- Modify only if required by test failures.

**Interfaces:**
- Consumes: all prior tasks.
- Produces: verified board-rack revision with no unrelated worktree changes.

- [ ] **Step 1: Run static diff checks**

```bash
git diff --check HEAD~3..HEAD
git status --short
```

Expected: no whitespace errors; only intended tracked changes.

- [ ] **Step 2: Run all automated tests**

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Expected: exit code 0 and zero test failures.

- [ ] **Step 3: Perform the final visual smoke test**

Verify:

```text
- Empty rack has one prominent Start card and no system empty-state treatment.
- Local, remote, and pending cards have a square board thumbnail, label, and status under the thumbnail.
- Start card opens the local/remote choice.
- Each game card opens its saved route.
- No status is positioned like a right-edge action.
```

- [ ] **Step 4: Commit verification-only fixes if needed**

```bash
git add <only-files-fixed-by-verification>
git commit -m "Polish games board rack"
```

# Contextual Threat and Defense Markers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the visually dense full-size threat and defense markers with small ambient danger badges plus prominent, selection-relevant danger bursts and shields.

**Architecture:** Keep `PositionAnalysis` as the complete source of threat and defense facts. `BoardGuidancePresentation` projects those facts into `prominentThreatSquares` and `visibleDefenseSquares`; SwiftUI consumes those sets without making chess decisions and renders one of two danger treatments with rotation- and Reduce Motion-aware behavior.

**Tech Stack:** Swift 5, SwiftUI, XCTest, Xcode/iPad Simulator; no new dependencies.

## Global Constraints

- Show a small, quiet coral danger badge on every legally threatened piece on both sides while play is active.
- Expand the danger treatment only for a threatened selected piece and pieces that the selected piece can legally capture.
- Show shields only for a defended selected piece and defended pieces that the selected piece can legally capture.
- Do not show shields for unrelated pieces, attackers, or supporters unless they are also legal capture targets.
- Preserve full threat and defense facts for VoiceOver even when visual shields are suppressed.
- Preserve supporter echoes, selected trajectories, coverage, tentative-move analysis, terminal-game suppression, and the checkmate losing-king burst.
- En passant prominence belongs to the captured pawn's occupied square, not the empty landing square.
- Keep chess rules in Core, presentation projection in the Game layer, and drawing in SwiftUI.
- Use the iPad simulator destination `platform=iOS Simulator,name=iPad (A16)`.

---

## File Map

- Modify `ChessTutor/Game/BoardGuidancePresentation.swift` — replace selection-based opacity with explicit prominent-threat and visible-defense projections.
- Modify `ChessTutorTests/Game/BoardGuidancePresentationTests.swift` — prove selected, capture-target, unrelated, en-passant, checkmate, and accessibility behavior.
- Modify `ChessTutorTests/Game/GameSessionTests.swift` — prove a tentatively moved threatened piece is prominent immediately.
- Modify `ChessTutor/UI/Board/BoardGuidanceOverlay.swift` — define compact/prominent marker sizes, readable shoulder geometry, and Reduce Motion behavior.
- Modify `ChessTutor/UI/Board/ChessBoardView.swift` — render ambient versus prominent danger and only contextually visible shields.
- Modify `ChessTutorTests/UI/BoardGuidanceStyleTests.swift` — verify marker scale hierarchy and readable shoulder placement through all board rotations.

---

### Task 1: Project Marker Relevance in the Game Layer

**Files:**
- Modify: `ChessTutor/Game/BoardGuidancePresentation.swift`
- Test: `ChessTutorTests/Game/BoardGuidancePresentationTests.swift`
- Test: `ChessTutorTests/Game/GameSessionTests.swift`

**Interfaces:**
- Consumes: `PositionAnalysis.threatenedSquares`, `PositionAnalysis.defendedSquares`, and `PositionAnalysis.threats(from:) -> Set<ThreatRelation>`.
- Produces: `BoardGuidancePresentation.prominentThreatSquares: Set<Square>` and `BoardGuidancePresentation.visibleDefenseSquares: Set<Square>`.
- Preserves: `threatenedSquares` and `defendedSquares` as complete facts for ambient rendering and accessibility.

- [ ] **Step 1: Replace the opacity regression with failing relevance tests**

In `BoardGuidancePresentationTests`, replace `testSelectionQuietsOnlyUnrelatedAmbientMarkers` with a real analyzed position containing a threatened selected bishop on d4, its legal capture target on f6, and an unrelated threatened pawn on h2:

```swift
func testSelectionPromotesOnlyThreatenedSelectionAndLegalCaptureTargets() {
    let selected = Square(file: .d, rank: 4)
    let captureTarget = Square(file: .f, rank: 6)
    let unrelatedThreat = Square(file: .h, rank: 2)
    let presentation = markerRelevancePresentation(selectedSquare: selected)

    XCTAssertTrue(presentation.threatenedSquares.isSuperset(of: [
        selected, captureTarget, unrelatedThreat,
    ]))
    XCTAssertEqual(presentation.prominentThreatSquares, [selected, captureTarget])
    XCTAssertFalse(presentation.prominentThreatSquares.contains(unrelatedThreat))
}

func testSelectionShowsDefenseOnlyForSelectionAndLegalCaptureTargets() {
    let selected = Square(file: .d, rank: 4)
    let captureTarget = Square(file: .f, rank: 6)
    let unrelatedDefendedPiece = Square(file: .h, rank: 2)
    let presentation = markerRelevancePresentation(selectedSquare: selected)

    XCTAssertTrue(presentation.defendedSquares.isSuperset(of: [
        selected, captureTarget, unrelatedDefendedPiece,
    ]))
    XCTAssertEqual(presentation.visibleDefenseSquares, [selected, captureTarget])
}

func testNoSelectionKeepsAllFactsButHasNoProminentThreatsOrVisibleDefense() {
    let presentation = markerRelevancePresentation(selectedSquare: nil)

    XCTAssertFalse(presentation.threatenedSquares.isEmpty)
    XCTAssertFalse(presentation.defendedSquares.isEmpty)
    XCTAssertTrue(presentation.prominentThreatSquares.isEmpty)
    XCTAssertTrue(presentation.visibleDefenseSquares.isEmpty)
}
```

Use this helper so the assertions exercise legal chess relationships instead of handcrafted presentation data:

```swift
private func markerRelevancePresentation(selectedSquare: Square?) -> BoardGuidancePresentation {
    let state = GameState(
        board: Board(
            pieces: [
                Square(file: .a, rank: 1): Piece(kind: .king, color: .white),
                Square(file: .d, rank: 4): Piece(kind: .bishop, color: .white),
                Square(file: .d, rank: 1): Piece(kind: .rook, color: .white),
                Square(file: .h, rank: 2): Piece(kind: .pawn, color: .white),
                Square(file: .h, rank: 1): Piece(kind: .rook, color: .white),
                Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
                Square(file: .b, rank: 6): Piece(kind: .bishop, color: .black),
                Square(file: .f, rank: 6): Piece(kind: .knight, color: .black),
                Square(file: .f, rank: 8): Piece(kind: .rook, color: .black),
                Square(file: .f, rank: 3): Piece(kind: .knight, color: .black),
            ]
        ),
        sideToMove: .white
    )
    return BoardGuidancePresentation.make(
        state: state,
        analysis: PositionAnalyzer.analyze(state),
        selectedSquare: selectedSquare,
        showsSelectedReach: true,
        showsCoverage: false,
        keepsOnlyCheckmateKingThreat: false
    )
}
```

- [ ] **Step 2: Add failing en-passant, terminal, tentative, and initializer assertions**

Extend the existing en-passant test by selecting the white pawn and asserting the captured pawn, rather than the landing square, becomes prominent:

```swift
XCTAssertEqual(presentation.prominentThreatSquares, [blackPawn])
XCTAssertFalse(presentation.prominentThreatSquares.contains(landing))
```

Extend `testCheckmateGuidanceKeepsOnlyLosingKingDanger`:

```swift
XCTAssertEqual(presentation.prominentThreatSquares, [losingKing])
XCTAssertTrue(presentation.visibleDefenseSquares.isEmpty)
```

Extend `GameSessionTests.testTentativeMoveStaysSelectedAndRefreshesItsDanger`:

```swift
XCTAssertTrue(session.boardGuidance.prominentThreatSquares.contains(destination))
```

Update all four direct `BoardGuidancePresentation(...)` values in the accessibility and coverage-accessibility tests with empty `prominentThreatSquares` and `visibleDefenseSquares`. Keep `defendedSquares` populated in the piece-accessibility cases to prove hidden visual defense remains spoken.

- [ ] **Step 3: Run the focused tests and verify they fail**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/BoardGuidancePresentationTests -only-testing:ChessTutorTests/GameSessionTests
```

Expected: build failure because `prominentThreatSquares` and `visibleDefenseSquares` do not exist.

- [ ] **Step 4: Implement the minimal relevance projection**

In `BoardGuidancePresentation`, add:

```swift
let prominentThreatSquares: Set<Square>
let visibleDefenseSquares: Set<Square>
```

Delete `emphasizedSquares` and `markerOpacity(at:)`. In normal live-play construction, derive the selection-relevant group strictly from the selected square and its legal capture relations:

```swift
var relevantSquares: Set<Square> = []
if let selectedSquare, state.board[selectedSquare] != nil {
    relevantSquares.insert(selectedSquare)
    relevantSquares.formUnion(analysis.threats(from: selectedSquare).map(\.target))
}

let prominentThreatSquares = analysis.threatenedSquares.intersection(relevantSquares)
let visibleDefenseSquares = defendedSquares.intersection(relevantSquares)
```

Populate both new sets in every initializer path. `empty` uses empty sets. The checkmate-only branch uses the losing king as both `threatenedSquares` and `prominentThreatSquares`, with empty defense sets. Do not change path, supporter, coverage, or accessibility derivation.

- [ ] **Step 5: Run the focused tests and verify they pass**

Run the command from Step 3.

Expected: all `BoardGuidancePresentationTests` and `GameSessionTests` pass.

- [ ] **Step 6: Commit the presentation projection**

```bash
git add ChessTutor/Game/BoardGuidancePresentation.swift ChessTutorTests/Game/BoardGuidancePresentationTests.swift ChessTutorTests/Game/GameSessionTests.swift
git commit -m "Project contextual threat and defense markers"
```

---

### Task 2: Render the Two-Level Marker Hierarchy

**Files:**
- Modify: `ChessTutor/UI/Board/BoardGuidanceOverlay.swift`
- Modify: `ChessTutor/UI/Board/ChessBoardView.swift`
- Test: `ChessTutorTests/UI/BoardGuidanceStyleTests.swift`

**Interfaces:**
- Consumes: `BoardGuidancePresentation.threatenedSquares`, `prominentThreatSquares`, and `visibleDefenseSquares` from Task 1.
- Produces: `DangerBurstView(cellSize:readableShoulderOffset:isProminent:reducesMotion:)` and `BoardGuidanceGeometry.readableShoulderOffset(horizontal:vertical:) -> CGPoint`.
- Preserves: piece layering, supporter echoes, readable piece rotation, hit testing, and accessibility.

- [ ] **Step 1: Write failing scale and orientation tests**

Add to `BoardGuidanceStyleTests`:

```swift
func testAmbientDangerBadgeIsMuchSmallerThanProminentBurst() {
    let style = BoardGuidanceStyle.current

    XCTAssertLessThanOrEqual(style.ambientDangerBadgeScale, 0.30)
    XCTAssertGreaterThan(style.prominentDangerBurstScale, style.ambientDangerBadgeScale * 2.5)
    XCTAssertGreaterThan(style.shieldScale, 0.16)
}

func testReadableShoulderOffsetTracksUpperRightShoulderThroughRotations() {
    let horizontal: CGFloat = 21
    let vertical: CGFloat = -19
    let expectations: [(BoardViewingAngle, CGPoint)] = [
        (.normal, CGPoint(x: 21, y: -19)),
        (.clockwiseQuarterTurn, CGPoint(x: -19, y: -21)),
        (.halfTurn, CGPoint(x: -21, y: 19)),
        (.counterclockwiseQuarterTurn, CGPoint(x: 19, y: 21)),
    ]

    for (viewingAngle, expected) in expectations {
        let geometry = BoardGuidanceGeometry(
            side: 672,
            origin: .zero,
            viewingAngle: viewingAngle
        )
        let actual = geometry.readableShoulderOffset(
            horizontal: horizontal,
            vertical: vertical
        )

        XCTAssertEqual(actual.x, expected.x, accuracy: 0.001)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run the style tests and verify they fail**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/BoardGuidanceStyleTests
```

Expected: build failure because the two scale names and shoulder-offset API do not exist.

- [ ] **Step 3: Add explicit marker scales and readable shoulder geometry**

Replace `dangerBurstScale` in `BoardGuidanceStyle` with:

```swift
ambientDangerBadgeScale: 0.28,
prominentDangerBurstScale: 0.92,
shieldScale: 0.22,
```

Add the corresponding stored properties. Add this rotation-aware geometry method:

```swift
func readableShoulderOffset(horizontal: CGFloat, vertical: CGFloat) -> CGPoint {
    let radians = viewingAngle.tableRotationDegrees * .pi / 180
    return CGPoint(
        x: horizontal * cos(radians) + vertical * sin(radians),
        y: -horizontal * sin(radians) + vertical * cos(radians)
    )
}
```

- [ ] **Step 4: Make the danger view switch between ambient and prominent treatments**

Change `DangerBurstView` to accept `readableShoulderOffset` and `isProminent`. Extract the existing filled/stroked burst into a private helper. With normal motion, render one burst and animate its frame and offset between:

```swift
let scale = isProminent
    ? BoardGuidanceStyle.current.prominentDangerBurstScale
    : BoardGuidanceStyle.current.ambientDangerBadgeScale
let offset = isProminent ? CGPoint.zero : readableShoulderOffset
```

Use a restrained spring animation keyed to `isProminent`. With Reduce Motion, render both the ambient and prominent variants in a `ZStack` and cross-fade their opacities with a short ease-out animation; do not animate scale or position in that branch. Keep the marker noninteractive and accessibility-hidden.

Simplify `DefenseShieldView` by removing its opacity parameter. Render it at the new `shieldScale`, at 90% opacity, with the existing readable rotation and a scale/opacity insertion transition when motion is enabled or opacity-only when Reduce Motion is enabled.

- [ ] **Step 5: Consume the explicit presentation sets in `ChessBoardView`**

At the start of `piecesOverlay`, compute:

```swift
let shoulderOffset = geometry.readableShoulderOffset(
    horizontal: cellSize * 0.25,
    vertical: -cellSize * 0.23
)
```

For every square in `threatenedSquares`, render `DangerBurstView` centered on the piece and pass:

```swift
readableShoulderOffset: shoulderOffset,
isProminent: guidance.prominentThreatSquares.contains(visualPiece.square)
```

Remove all `markerOpacity` usage. Render `DefenseShieldView` only when `visibleDefenseSquares` contains the square. Keep its existing readable-foot placement after the piece layer so a relevant piece can show both burst and shield.

- [ ] **Step 6: Run focused presentation and style tests**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/BoardGuidancePresentationTests -only-testing:ChessTutorTests/BoardGuidanceStyleTests -only-testing:ChessTutorTests/GameSessionTests
```

Expected: all focused tests pass.

- [ ] **Step 7: Commit the renderer refinement**

```bash
git add ChessTutor/UI/Board/BoardGuidanceOverlay.swift ChessTutor/UI/Board/ChessBoardView.swift ChessTutorTests/UI/BoardGuidanceStyleTests.swift
git commit -m "Refine threat and defense marker hierarchy"
```

---

### Task 3: Full Regression Verification

**Files:**
- Verify only; no source changes expected.

**Interfaces:**
- Consumes: the Game-layer projection and SwiftUI rendering from Tasks 1 and 2.
- Produces: evidence that the refinement preserves the complete live-game guidance feature.

- [ ] **Step 1: Run the full test suite**

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Expected: all tests pass with zero failures.

- [ ] **Step 2: Inspect the final diff and worktree**

```bash
git diff HEAD~2 --check
git status --short
```

Expected: no whitespace errors and a clean worktree.

- [ ] **Step 3: Check the representative interaction states in the iPad simulator**

Verify:

- no selection: every threatened piece has only the compact shoulder badge and no shields are visible;
- selected threatened piece: its badge expands behind it while unrelated threats remain compact;
- selected legal capture target: the target has a full burst and shows the larger shield only when defended;
- tentative move: the moved piece immediately receives the appropriate prominent danger and contextual shield;
- coverage open: compact/prominent markers remain legible above coverage pips;
- all four tabletop orientations: compact badge stays at the readable shoulder and shield stays at the readable foot;
- Reduce Motion: compact/full danger changes cross-fade without traveling or scaling;
- checkmate: only the losing king retains the full burst; stalemate has no guidance markers.

# Dedicated Coverage Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the noisy whole-board coverage pips with a dedicated, four-state square map that remains playable and restores only contextual selected-piece guidance.

**Architecture:** This is exclusively a SwiftUI rendering change. `BoardGuidanceOverlay.swift` defines the view-level coverage surface and emphasis vocabulary, while `ChessBoardView.swift` derives visual states from the two existing `BoardCoveragePresentation` sets and applies them without changing `PositionAnalyzer`, `BoardGuidancePresentation`, or `GameSession`. Existing accessibility labels and coverage lifecycle behavior remain authoritative and unchanged.

**Tech Stack:** Swift, SwiftUI, XCTest, Xcode/iOS Simulator

## Global Constraints

- Do not change `PositionAnalyzer`, `BoardGuidancePresentation`, `GameSession`, legal-move generation, coverage semantics, persistence, or accessibility facts.
- Preserve the existing **Show coverage** / **Hide coverage** control and all current close/persistence rules.
- Coverage has four view-derived states: side-to-move only, other-side only, both, and neither.
- Resting coverage hides coordinate labels and ambient status markers and slightly recesses all pieces.
- Selecting a piece keeps the coverage surface visible, restores its existing contextual paths and markers, and emphasizes only pieces involved in that context.
- The board remains fully playable during coverage, including taps, drags, tentative moves, and reversal.
- Keep exact opacity, saturation, dimming, and transition values in the existing view-style layer so they can be tuned after testing on iPad.
- Respect Reduce Motion and do not add new controls, messages, dependencies, or pixel-snapshot tests.

---

### Task 1: Replace coverage pips with four-state square surfaces

**Files:**
- Modify: `ChessTutor/UI/Board/BoardGuidanceOverlay.swift:3-67,204-266`
- Modify: `ChessTutor/UI/Board/ChessBoardView.swift:219-238,284-300`
- Test: `ChessTutorTests/UI/BoardGuidanceStyleTests.swift:5-39`

**Interfaces:**
- Consumes: existing `BoardCoveragePresentation.sideToMoveSquares`, `BoardCoveragePresentation.otherSideSquares`, `AppTheme.guidanceYellow`, `AppTheme.guidanceRed`, and `AppTheme.boardFrame`.
- Produces: `CoverageSurfaceState.init(sideToMoveCovers:otherSideCovers:)`, `CoverageSurfaceView`, and coverage opacity/transition values on `BoardGuidanceStyle.current`.

- [ ] **Step 1: Verify the committed branch starts green**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -resultBundlePath /tmp/ChessTutor-coverage-map-baseline.xcresult
```

Inspect the result bundle summary. Expected: all tests pass with zero failures and zero skipped tests before changing test or production code.

- [ ] **Step 2: Replace the pip-layout tests with a failing four-state classification test**

Remove `testContestedCoverageProducesTwoDistinctNonoverlappingMarkers` and `testSingleCoverageMarkersKeepTheirShapeAndStablePosition` from `ChessTutorTests/UI/BoardGuidanceStyleTests.swift`. Add:

```swift
func testCoverageSurfaceClassifiesEveryReachCombination() {
    XCTAssertEqual(
        CoverageSurfaceState(sideToMoveCovers: false, otherSideCovers: false),
        .neither
    )
    XCTAssertEqual(
        CoverageSurfaceState(sideToMoveCovers: true, otherSideCovers: false),
        .sideToMoveOnly
    )
    XCTAssertEqual(
        CoverageSurfaceState(sideToMoveCovers: false, otherSideCovers: true),
        .otherSideOnly
    )
    XCTAssertEqual(
        CoverageSurfaceState(sideToMoveCovers: true, otherSideCovers: true),
        .both
    )
}

func testCoverageSurfaceOpacitiesStaySubordinateToPieces() {
    let style = BoardGuidanceStyle.current

    XCTAssertGreaterThan(style.coverageSideToMoveOpacity, style.coverageNeitherOpacity)
    XCTAssertGreaterThan(style.coverageOtherSideOpacity, style.coverageNeitherOpacity)
    XCTAssertLessThan(style.coverageSideToMoveOpacity, 1)
    XCTAssertLessThan(style.coverageOtherSideOpacity, 1)
}
```

The named break is an implementation that collapses contested, one-sided, or uncovered squares into the same visual state. The opacity assertions prevent the map from becoming more prominent than the pieces it is meant to support.

- [ ] **Step 3: Run the new tests and verify RED**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/BoardGuidanceStyleTests/testCoverageSurfaceClassifiesEveryReachCombination -only-testing:ChessTutorTests/BoardGuidanceStyleTests/testCoverageSurfaceOpacitiesStaySubordinateToPieces -resultBundlePath /tmp/ChessTutor-coverage-map-task1-red.xcresult
```

Expected: compilation fails because `CoverageSurfaceState` and the new coverage style fields do not exist. This confirms the new test reaches the missing behavior rather than passing against the old pip implementation.

- [ ] **Step 4: Add the four-state surface vocabulary and tunable style values**

In `ChessTutor/UI/Board/BoardGuidanceOverlay.swift`, add these arguments to `BoardGuidanceStyle.current`:

```swift
coverageSideToMoveOpacity: 0.50,
coverageOtherSideOpacity: 0.44,
coverageNeitherOpacity: 0.18,
coverageRecessedPieceOpacity: 0.68,
coverageTransitionDuration: 0.18,
```

Add matching stored properties:

```swift
let coverageSideToMoveOpacity: Double
let coverageOtherSideOpacity: Double
let coverageNeitherOpacity: Double
let coverageRecessedPieceOpacity: Double
let coverageTransitionDuration: Double
```

Replace `CoveragePipShape`, `CoveragePipMarker`, and `CoveragePipLayout` with:

```swift
enum CoverageSurfaceState: Equatable {
    case neither
    case sideToMoveOnly
    case otherSideOnly
    case both

    init(sideToMoveCovers: Bool, otherSideCovers: Bool) {
        switch (sideToMoveCovers, otherSideCovers) {
        case (false, false):
            self = .neither
        case (true, false):
            self = .sideToMoveOnly
        case (false, true):
            self = .otherSideOnly
        case (true, true):
            self = .both
        }
    }
}

struct CoverageDiagonalHalfShape: Shape {
    enum Half {
        case sideToMove
        case otherSide
    }

    let half: Half

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch half {
        case .sideToMove:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .otherSide:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

struct CoverageSurfaceView: View {
    let state: CoverageSurfaceState

    var body: some View {
        let style = BoardGuidanceStyle.current

        switch state {
        case .neither:
            Rectangle()
                .fill(AppTheme.boardFrame.opacity(style.coverageNeitherOpacity))
        case .sideToMoveOnly:
            Rectangle()
                .fill(AppTheme.guidanceYellow.opacity(style.coverageSideToMoveOpacity))
        case .otherSideOnly:
            Rectangle()
                .fill(AppTheme.guidanceRed.opacity(style.coverageOtherSideOpacity))
        case .both:
            ZStack {
                CoverageDiagonalHalfShape(half: .sideToMove)
                    .fill(AppTheme.guidanceYellow.opacity(style.coverageSideToMoveOpacity))
                CoverageDiagonalHalfShape(half: .otherSide)
                    .fill(AppTheme.guidanceRed.opacity(style.coverageOtherSideOpacity))
            }
        }
    }
}
```

Delete `CoveragePipsLayer`; coverage will be rendered inside each existing board square so the board frame, rounded clipping, hit testing, and tabletop geometry remain unchanged.

- [ ] **Step 5: Render the surface inside each square and remove the pip layer**

In `ChessTutor/UI/Board/ChessBoardView.swift`, remove the `CoveragePipsLayer(...)` call from the board `ZStack`.

In `squareView(_:guidance:)`, place the surface after the base square rectangle and before the selected-square highlight:

```swift
if let coverage = guidance.coverage {
    CoverageSurfaceView(
        state: CoverageSurfaceState(
            sideToMoveCovers: coverage.sideToMoveSquares.contains(square),
            otherSideCovers: coverage.otherSideSquares.contains(square)
        )
    )
    .transition(.opacity)
}
```

Apply a view-level transition to the square content without changing input handling:

```swift
.animation(
    accessibilityReduceMotion
        ? nil
        : .easeInOut(duration: BoardGuidanceStyle.current.coverageTransitionDuration),
    value: guidance.coverage
)
```

- [ ] **Step 6: Run the focused style tests and verify GREEN**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/BoardGuidanceStyleTests -resultBundlePath /tmp/ChessTutor-coverage-map-task1-green.xcresult
```

Expected: every `BoardGuidanceStyleTests` test passes with zero skipped tests, and no source reference to `CoveragePipShape`, `CoveragePipMarker`, `CoveragePipLayout`, or `CoveragePipsLayer` remains.

- [ ] **Step 7: Commit the four-state surface map**

```bash
git add ChessTutor/UI/Board/BoardGuidanceOverlay.swift ChessTutor/UI/Board/ChessBoardView.swift ChessTutorTests/UI/BoardGuidanceStyleTests.swift
git commit -m "Replace coverage pips with surface map"
```

---

### Task 2: Quiet the map and restore only selected-piece context

**Files:**
- Modify: `ChessTutor/UI/Board/BoardGuidanceOverlay.swift:3-24`
- Modify: `ChessTutor/UI/Board/ChessBoardView.swift:284-450`
- Test: `ChessTutorTests/UI/BoardGuidanceStyleTests.swift`

**Interfaces:**
- Consumes: `BoardGuidancePresentation.coverage`, `selectedSquare`, `selectedPaths`, `supporterSquares`, `prominentThreatSquares`, and `visibleDefenseSquares` without changing any of those fields.
- Produces: `CoverageMapRenderingPolicy`, `CoverageContext.squares(in:)`, hidden coordinates/ambient badges during coverage, and contextual piece emphasis during selection.

- [ ] **Step 1: Add failing view-policy tests**

Add to `ChessTutorTests/UI/BoardGuidanceStyleTests.swift`:

```swift
func testCoverageRenderingPolicyQuietsAmbientBoardButKeepsContextProminent() {
    let coveragePolicy = CoverageMapRenderingPolicy(isCoverageVisible: true)

    XCTAssertFalse(coveragePolicy.showsCoordinates)
    XCTAssertFalse(coveragePolicy.showsAmbientThreats)
    XCTAssertEqual(coveragePolicy.pieceOpacity(isContextual: true), 1)
    XCTAssertLessThan(coveragePolicy.pieceOpacity(isContextual: false), 1)

    let normalPolicy = CoverageMapRenderingPolicy(isCoverageVisible: false)
    XCTAssertTrue(normalPolicy.showsCoordinates)
    XCTAssertTrue(normalPolicy.showsAmbientThreats)
    XCTAssertEqual(normalPolicy.pieceOpacity(isContextual: false), 1)
}

func testCoverageContextContainsOnlySelectedRelationships() {
    let selected = Square(file: .c, rank: 4)
    let destination = Square(file: .f, rank: 7)
    let attacker = Square(file: .b, rank: 6)
    let supporter = Square(file: .e, rank: 3)
    let unrelated = Square(file: .h, rank: 8)
    let guidance = BoardGuidancePresentation(
        sideToMove: .white,
        threatenedSquares: [selected],
        prominentThreatSquares: [selected],
        defendedSquares: [selected],
        visibleDefenseSquares: [selected],
        selectedSquare: selected,
        selectedPaths: [
            BoardGuidancePath(
                source: selected,
                destination: destination,
                captureSquare: destination,
                color: .white,
                role: .allowed
            ),
            BoardGuidancePath(
                source: attacker,
                destination: selected,
                captureSquare: selected,
                color: .black,
                role: .attacker
            ),
        ],
        supporterSquares: [supporter],
        coverage: BoardCoveragePresentation(
            sideToMove: .white,
            sideToMoveSquares: [selected, destination],
            otherSideSquares: [selected, attacker]
        )
    )

    let contextualSquares = CoverageContext.squares(in: guidance)

    XCTAssertTrue(contextualSquares.isSuperset(of: [
        selected,
        destination,
        attacker,
        supporter,
    ]))
    XCTAssertFalse(contextualSquares.contains(unrelated))
}
```

The named breaks are ambient markers/coordinates leaking into coverage mode and unrelated pieces retaining full emphasis after selection.

- [ ] **Step 2: Run the policy tests and verify RED**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/BoardGuidanceStyleTests/testCoverageRenderingPolicyQuietsAmbientBoardButKeepsContextProminent -only-testing:ChessTutorTests/BoardGuidanceStyleTests/testCoverageContextContainsOnlySelectedRelationships -resultBundlePath /tmp/ChessTutor-coverage-map-task2-red.xcresult
```

Expected: compilation fails because `CoverageMapRenderingPolicy` and `CoverageContext` do not exist.

- [ ] **Step 3: Add the view-only rendering policy and context projection**

In `ChessTutor/UI/Board/BoardGuidanceOverlay.swift`, add:

```swift
struct CoverageMapRenderingPolicy: Equatable {
    let isCoverageVisible: Bool

    var showsCoordinates: Bool {
        !isCoverageVisible
    }

    var showsAmbientThreats: Bool {
        !isCoverageVisible
    }

    func pieceOpacity(isContextual: Bool) -> Double {
        guard isCoverageVisible, !isContextual else {
            return 1
        }
        return BoardGuidanceStyle.current.coverageRecessedPieceOpacity
    }
}

enum CoverageContext {
    static func squares(in guidance: BoardGuidancePresentation) -> Set<Square> {
        guard let selectedSquare = guidance.selectedSquare else {
            return []
        }

        var squares: Set<Square> = [selectedSquare]
        for path in guidance.selectedPaths {
            squares.insert(path.source)
            squares.insert(path.destination)
            if let captureSquare = path.captureSquare {
                squares.insert(captureSquare)
            }
        }
        squares.formUnion(guidance.supporterSquares)
        squares.formUnion(guidance.prominentThreatSquares)
        squares.formUnion(guidance.visibleDefenseSquares)
        return squares
    }
}
```

These are rendering helpers only. Do not add a computed property or field to `BoardGuidancePresentation`.

- [ ] **Step 4: Hide coordinates and ambient danger while coverage is active**

In `squareView(_:guidance:)`, construct:

```swift
let renderingPolicy = CoverageMapRenderingPolicy(
    isCoverageVisible: guidance.coverage != nil
)
```

Render coordinates only when `renderingPolicy.showsCoordinates` is true. Do not alter `accessibilityLabel(for:guidance:)`; hidden visual coordinates must remain named through accessibility.

In `piecesOverlay(side:origin:guidance:)`, render the compact ambient `DangerBurstView` only when `renderingPolicy.showsAmbientThreats` is true. Continue rendering prominent danger bursts, supporter echoes, and visible defense shields from their existing contextual sets.

- [ ] **Step 5: Recess unrelated pieces without changing movement animation**

At the start of `piecesOverlay(side:origin:guidance:)`, derive:

```swift
let renderingPolicy = CoverageMapRenderingPolicy(
    isCoverageVisible: guidance.coverage != nil
)
let contextualSquares = CoverageContext.squares(in: guidance)
```

For each stable `PieceIconView`, compute:

```swift
let pieceOpacity = renderingPolicy.pieceOpacity(
    isContextual: contextualSquares.contains(visualPiece.square)
)
```

Apply it after positioning without changing matched-geometry identity or drag settling:

```swift
.opacity(pieceOpacity)
.animation(
    accessibilityReduceMotion
        ? nil
        : .easeInOut(duration: BoardGuidanceStyle.current.coverageTransitionDuration),
    value: pieceOpacity
)
```

The separate dragged-piece overlay stays at full opacity. With coverage visible and no selection, `contextualSquares` is empty and every stable piece recedes. With a selection, only the selected piece, path sources/destinations, capture targets, attackers, supporters, and relevant status targets return to full opacity.

- [ ] **Step 6: Run all view-style and presentation tests**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/BoardGuidanceStyleTests -only-testing:ChessTutorTests/BoardGuidancePresentationTests -only-testing:ChessTutorTests/GameSessionTests -resultBundlePath /tmp/ChessTutor-coverage-map-task2-green.xcresult
```

Expected: all selected suites pass with zero failures and zero skipped tests. Existing `BoardGuidancePresentationTests` and `GameSessionTests` should be unchanged, proving the experiment did not alter presentation data or coverage lifecycle behavior.

- [ ] **Step 7: Commit contextual coverage emphasis**

```bash
git add ChessTutor/UI/Board/BoardGuidanceOverlay.swift ChessTutor/UI/Board/ChessBoardView.swift ChessTutorTests/UI/BoardGuidanceStyleTests.swift
git commit -m "Focus selected guidance in coverage map"
```

---

### Task 3: Verify the real iPad experiment

**Files:**
- Verify only: `ChessTutor/UI/Board/BoardGuidanceOverlay.swift`
- Verify only: `ChessTutor/UI/Board/ChessBoardView.swift`
- Verify only: `ChessTutorTests/UI/BoardGuidanceStyleTests.swift`

**Interfaces:**
- Consumes: the committed view-only coverage map from Tasks 1 and 2.
- Produces: full-suite evidence and an app build left running for hands-on visual evaluation.

- [ ] **Step 1: Confirm the implementation stayed inside the approved layer**

Run:

```bash
git diff 9486a1f..HEAD --name-only
```

Expected output contains only the plan plus the approved view and view-test files:

```text
docs/superpowers/plans/2026-08-11-dedicated-coverage-map.md
ChessTutor/UI/Board/BoardGuidanceOverlay.swift
ChessTutor/UI/Board/ChessBoardView.swift
ChessTutorTests/UI/BoardGuidanceStyleTests.swift
```

Run:

```bash
rg -n "CoveragePipShape|CoveragePipMarker|CoveragePipLayout|CoveragePipsLayer" ChessTutor ChessTutorTests
```

Expected: no matches.

- [ ] **Step 2: Run the complete test suite**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -resultBundlePath /tmp/ChessTutor-dedicated-coverage-map-full.xcresult
```

Inspect the result bundle summary. Expected: the complete suite passes with zero failures and zero skipped tests.

- [ ] **Step 3: Launch the tested app for hands-on evaluation**

Launch `org.jasoncrawford.chesstutor` on the iPad (A16) simulator used by the tests. Leave the simulator and tested build running for the user.

Visually inspect, or ask the user to inspect when scripted touch access is unavailable:

1. Open coverage with a selected piece and confirm the square map replaces every pip.
2. Tap an empty invalid square to clear selection; confirm all pieces recede and no ambient badges, shields, echoes, paths, or coordinates remain.
3. Select a threatened and defended piece; confirm its paths, attackers, supporters, full burst, and shield appear while unrelated pieces and markers remain quiet.
4. Drag and tap-move while coverage stays open; confirm the dragged piece is full strength and the map recomputes after landing.
5. Revert a tentative move and then press **Done** on a staged move; confirm existing persistence and close behavior.
6. Rotate through every supported tabletop orientation and enable Reduce Motion; confirm surfaces remain square-bound and emphasis changes do not rely on motion.

- [ ] **Step 4: Record tuning feedback without broadening scope**

If the real app feels too strong or too weak, adjust only these `BoardGuidanceStyle.current` values and rerun Task 2 Step 6 plus the full suite:

```swift
coverageSideToMoveOpacity
coverageOtherSideOpacity
coverageNeitherOpacity
coverageRecessedPieceOpacity
coverageTransitionDuration
```

Do not change coverage semantics, add controls, or move logic into model/presentation code during visual tuning.

- [ ] **Step 5: Commit visual tuning if the real-board check changed style values**

If Step 4 changed any `BoardGuidanceStyle.current` values after the verified real-board check, rerun Task 2 Step 6 and Task 3 Step 2, then commit only the tuned view file:

```bash
git add ChessTutor/UI/Board/BoardGuidanceOverlay.swift
git commit -m "Tune coverage map visual balance"
```

If the initial values require no adjustment, leave the clean tree as-is and do not create an empty commit.

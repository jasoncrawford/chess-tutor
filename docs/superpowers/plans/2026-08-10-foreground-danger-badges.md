# Foreground Danger Badges Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move compact ambient danger bursts from the piece's shoulder to a foreground status slot over its readable foot, while keeping prominent bursts behind the piece.

**Architecture:** This is a SwiftUI presentation-only change. A small `BoardPieceMarkerLayout` value makes the shared foot anchor and foreground/background layer order explicit and testable; `BoardGuidancePresentation`, `GameSession`, `PositionAnalyzer`, and all chess rules remain unchanged.

**Tech Stack:** Swift 5, SwiftUI, CoreGraphics, XCTest, Xcode/iPad Simulator; no new dependencies.

## Global Constraints

- Compact ambient danger bursts render in front of the lower piece silhouette.
- Compact ambient bursts and contextual shields use the same rotation-aware readable-foot anchor.
- Prominent danger bursts remain centered behind the piece.
- A prominent threatened-and-defended piece shows the full burst behind it and the shield at the foreground foot without collision.
- Normal motion uses a brief scale-and-fade handoff; Reduce Motion uses opacity only.
- Threat/defense analysis, accessibility labels, trajectories, coverage, tentative-move behavior, and terminal-game behavior do not change.
- Use the iPad simulator destination `platform=iOS Simulator,name=iPad (A16)`.

---

## File Map

- Modify `ChessTutor/UI/Board/BoardGuidanceOverlay.swift` — add testable marker centers/layers and split ambient/prominent burst treatments.
- Modify `ChessTutor/UI/Board/ChessBoardView.swift` — render prominent danger below the piece and compact danger above it at the shared foot anchor.
- Modify `ChessTutorTests/UI/BoardGuidanceStyleTests.swift` — replace shoulder-placement coverage with foot-anchor and layer-order regressions.

---

### Task 1: Place Compact Danger in the Foreground Foot Slot

**Files:**
- Modify: `ChessTutor/UI/Board/BoardGuidanceOverlay.swift`
- Modify: `ChessTutor/UI/Board/ChessBoardView.swift`
- Test: `ChessTutorTests/UI/BoardGuidanceStyleTests.swift`

**Interfaces:**
- Consumes: `BoardGuidanceGeometry.readableFootOffset(distance:)`, `BoardGuidancePresentation.threatenedSquares`, `BoardGuidancePresentation.prominentThreatSquares`, and `BoardGuidancePresentation.visibleDefenseSquares`.
- Produces: `BoardPieceMarkerLayout.make(pieceCenter:readableFootOffset:) -> BoardPieceMarkerLayout`, `BoardPieceMarkerLayer`, and `DangerBurstTreatment`.
- Preserves: `DangerBurstShape`, the current 0.28/0.92 burst scales, the 0.22 shield scale, and all Game/Core interfaces.

- [ ] **Step 1: Write failing placement and layer-order tests**

Replace `testReadableShoulderOffsetTracksUpperRightShoulderThroughRotations` in `BoardGuidanceStyleTests` with:

```swift
func testCompactDangerAndShieldShareReadableFootWhileProminentDangerStaysCentered() {
    let pieceCenter = CGPoint(x: 42, y: 42)
    let readableFootOffset = CGPoint(x: 0, y: 24)

    let layout = BoardPieceMarkerLayout.make(
        pieceCenter: pieceCenter,
        readableFootOffset: readableFootOffset
    )

    XCTAssertEqual(layout.prominentDangerCenter, pieceCenter)
    XCTAssertEqual(layout.ambientDangerCenter, CGPoint(x: 42, y: 66))
    XCTAssertEqual(layout.defenseCenter, layout.ambientDangerCenter)
}

func testCompactDangerIsForegroundAndProminentDangerIsBackground() {
    XCTAssertLessThan(
        BoardPieceMarkerLayer.prominentDanger.zIndex,
        BoardPieceMarkerLayer.piece.zIndex
    )
    XCTAssertGreaterThan(
        BoardPieceMarkerLayer.foregroundStatus.zIndex,
        BoardPieceMarkerLayer.piece.zIndex
    )
}
```

These tests catch a regression back to the shoulder offset or to drawing the compact burst behind the piece.

- [ ] **Step 2: Run the style tests and verify they fail**

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/BoardGuidanceStyleTests
```

Expected: build failure because `BoardPieceMarkerLayout` and `BoardPieceMarkerLayer` do not exist.

- [ ] **Step 3: Add the minimal marker layout and layer model**

In `BoardGuidanceOverlay.swift`, delete `readableShoulderOffset(horizontal:vertical:)` and add:

```swift
enum BoardPieceMarkerLayer: Double, Equatable {
    case prominentDanger = 0
    case piece = 1
    case foregroundStatus = 2

    var zIndex: Double { rawValue }
}

struct BoardPieceMarkerLayout: Equatable {
    let prominentDangerCenter: CGPoint
    let ambientDangerCenter: CGPoint
    let defenseCenter: CGPoint

    static func make(
        pieceCenter: CGPoint,
        readableFootOffset: CGPoint
    ) -> BoardPieceMarkerLayout {
        let footCenter = CGPoint(
            x: pieceCenter.x + readableFootOffset.x,
            y: pieceCenter.y + readableFootOffset.y
        )
        return BoardPieceMarkerLayout(
            prominentDangerCenter: pieceCenter,
            ambientDangerCenter: footCenter,
            defenseCenter: footCenter
        )
    }
}
```

- [ ] **Step 4: Split the compact and prominent burst treatments**

Add:

```swift
enum DangerBurstTreatment: Equatable {
    case ambient
    case prominent
}
```

Change `DangerBurstView` to accept `treatment`, `isVisible`, and `reducesMotion`. Derive scale, fill/stroke emphasis, and hidden scale from the treatment:

```swift
private var scale: CGFloat {
    treatment == .prominent
        ? BoardGuidanceStyle.current.prominentDangerBurstScale
        : BoardGuidanceStyle.current.ambientDangerBadgeScale
}

private var hiddenScale: CGFloat {
    treatment == .prominent ? 0.30 : 0.86
}
```

Render one fixed-position burst. Set opacity to `isVisible ? 1 : 0`. With Reduce Motion, keep `scaleEffect(1)` and animate only opacity with `.easeOut(duration: 0.16)`. Otherwise use `scaleEffect(isVisible ? 1 : hiddenScale)` and the existing restrained spring keyed to `isVisible`. Keep the ambient fill/stroke/shadow quieter than the prominent treatment.

- [ ] **Step 5: Render the two danger treatments on opposite sides of the piece layer**

In `ChessBoardView.piecesOverlay`, keep:

```swift
let footOffset = geometry.readableFootOffset(distance: cellSize * 0.31)
```

Delete `shoulderOffset`. For each visual piece, create:

```swift
let markerLayout = BoardPieceMarkerLayout.make(
    pieceCenter: pieceCenter,
    readableFootOffset: footOffset
)
let isThreatened = guidance.threatenedSquares.contains(visualPiece.square)
let isProminentThreat = guidance.prominentThreatSquares.contains(visualPiece.square)
```

Before `PieceIconView`, render the prominent treatment at `markerLayout.prominentDangerCenter`, visible only when both booleans are true, and apply `.zIndex(BoardPieceMarkerLayer.prominentDanger.zIndex)`. Apply `.zIndex(BoardPieceMarkerLayer.piece.zIndex)` to `PieceIconView`.

After `PieceIconView`, render the ambient treatment at `markerLayout.ambientDangerCenter`, visible only when `isThreatened && !isProminentThreat`, and apply `.zIndex(BoardPieceMarkerLayer.foregroundStatus.zIndex)`. Render `DefenseShieldView` at `markerLayout.defenseCenter` with the same foreground z-index when `visibleDefenseSquares` contains the square.

Only create the two danger views when `isThreatened` is true. Supporter echoes retain their current placement and behavior.

- [ ] **Step 6: Run focused tests**

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/BoardGuidanceStyleTests -only-testing:ChessTutorTests/BoardGuidancePresentationTests -only-testing:ChessTutorTests/GameSessionTests
```

Expected: all focused tests pass.

- [ ] **Step 7: Commit the foreground placement**

```bash
git add ChessTutor/UI/Board/BoardGuidanceOverlay.swift ChessTutor/UI/Board/ChessBoardView.swift ChessTutorTests/UI/BoardGuidanceStyleTests.swift
git commit -m "Move ambient danger badges onto pieces"
```

---

### Task 2: Full Regression Verification

**Files:**
- Verify only; no source changes expected.

**Interfaces:**
- Consumes: the view-layer placement from Task 1.
- Produces: fresh evidence that the complete chess app remains green.

- [ ] **Step 1: Run the full test suite**

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -resultBundlePath /tmp/ChessTutor-foreground-4b12de4.xcresult
```

Expected: zero failed and zero skipped tests.

- [ ] **Step 2: Read the `.xcresult` summary**

```bash
xcrun xcresulttool get test-results summary --path /tmp/ChessTutor-foreground-4b12de4.xcresult
```

Expected: `result` is `Passed`, `failedTests` is `0`, and `skippedTests` is `0`.

- [ ] **Step 3: Audit the final tree**

```bash
git diff HEAD~1 --check
git status --short
```

Expected: no whitespace errors and a clean worktree.

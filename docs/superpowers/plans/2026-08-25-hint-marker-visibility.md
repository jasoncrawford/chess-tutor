# Hint Marker Visibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make coaching candidate hints clearly visible behind large pieces on either board color.

**Architecture:** Keep the current `CoachFocusPresentation` data and board-layer order unchanged. Extend the existing `CoachFocusStyle` with candidate-specific stroke widths, then render each candidate ellipse twice: a solid warm-ivory keyline followed by the blue-violet dashed stroke.

**Tech Stack:** Swift 6, SwiftUI `Canvas`/`GraphicsContext`, XCTest, iOS Simulator.

## Global Constraints

- Candidate-ring diameter is exactly 80% of one square.
- Candidate keyline is `#FFF4CF` at 98% opacity and 7.2% of one square wide.
- Candidate dashed stroke keeps the existing blue-violet hue at 95% opacity and is 3.6% of one square wide.
- The marker remains beneath the piece in this iteration.
- Do not change coaching logic, focus selection, emphasized rings, relationship paths, interaction, or accessibility semantics.
- Preserve the existing one-shot pulse and Reduced Motion behavior.

---

### Task 1: Render a high-contrast candidate target ring

**Files:**
- Modify: `ChessTutor/UI/Board/CoachFocusOverlay.swift:3-21,120-140`
- Modify: `ChessTutor/UI/Theme/AppTheme.swift:39-42`
- Modify: `ChessTutorTests/UI/CoachFocusOverlayTests.swift:81-88`

**Interfaces:**
- Consumes: `CoachFocusPresentation.candidateSquares`, `BoardGuidanceGeometry.cellSize`, and the existing `focus.pulseID` animation.
- Produces: `CoachFocusStyle.candidateRingScale`, `candidateRingLineWidthInCells`, and `candidateRingKeylineWidthInCells`; `AppTheme.coachCandidateKeyline`; a two-stroke candidate ellipse.

- [ ] **Step 1: Write the failing style contract**

Replace the old “candidates are quieter” size assertion with an exact visibility contract:

```swift
func testCandidateHintUsesLargeContrastingKeylinedRing() {
    let style = CoachFocusStyle.current

    XCTAssertEqual(style.candidateRingScale, 0.80, accuracy: 0.001)
    XCTAssertEqual(style.candidateRingLineWidthInCells, 0.036, accuracy: 0.001)
    XCTAssertEqual(style.candidateRingKeylineWidthInCells, 0.072, accuracy: 0.001)
    XCTAssertGreaterThan(
        style.candidateRingKeylineWidthInCells,
        style.candidateRingLineWidthInCells
    )
    XCTAssertFalse(style.pathDash(for: .candidate).isEmpty)
}
```

Retain the existing assertions that attacker paths are solid and coaching paths remain quieter than mechanical guidance paths.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
xcodebuild test -quiet \
  -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/CoachFocusOverlayTests
```

Expected: compilation fails because the candidate-specific width properties do not exist, or the old 0.60 scale fails the new assertion. No production files may be changed before this RED is recorded.

- [ ] **Step 3: Add the candidate-specific style tokens**

Update `CoachFocusStyle.current` and the stored properties:

```swift
static let current = CoachFocusStyle(
    emphasizedRingScale: 0.76,
    candidateRingScale: 0.80,
    ringLineWidthInCells: 0.026,
    candidateRingLineWidthInCells: 0.036,
    candidateRingKeylineWidthInCells: 0.072,
    pathLineWidthInCells: 0.020,
    candidatePathDashInCells: [0.08, 0.07]
)

let candidateRingLineWidthInCells: CGFloat
let candidateRingKeylineWidthInCells: CGFloat
```

Add the visual tokens without altering unrelated colors:

```swift
static let coachCandidateKeyline = Color(
    red: 1.00,
    green: 0.96,
    blue: 0.81
).opacity(0.98)
static let coachCandidateRing = Color(
    red: 0.33,
    green: 0.35,
    blue: 0.57
).opacity(0.95)
```

- [ ] **Step 4: Draw the keyline and dashed ring beneath each piece**

In `drawCandidateRings`, construct the ellipse once, draw the solid keyline first, and then draw the dashed candidate stroke:

```swift
let ring = Path(ellipseIn: rect)
context.stroke(
    ring,
    with: .color(AppTheme.coachCandidateKeyline),
    style: StrokeStyle(
        lineWidth: geometry.cellSize * style.candidateRingKeylineWidthInCells,
        lineCap: .round,
        lineJoin: .round
    )
)
context.stroke(
    ring,
    with: .color(AppTheme.coachCandidateRing),
    style: StrokeStyle(
        lineWidth: geometry.cellSize * style.candidateRingLineWidthInCells,
        lineCap: .round,
        lineJoin: .round,
        dash: style.candidatePathDashInCells.map { $0 * geometry.cellSize }
    )
)
```

Do not move `CoachFocusOverlay` relative to `piecesOverlay` in `ChessBoardView`.

- [ ] **Step 5: Run focused GREEN verification**

Run the command from Step 2. Expected: all `CoachFocusOverlayTests` pass with zero failures or skips.

- [ ] **Step 6: Inspect the exact difficult visual states**

Build, install, and launch the normal app on `iPad (A16)`. From the starting position, choose Help and then Hint. Inspect:

- the white knight on dark `g1`;
- the white knight on light `b1`;
- the center-pawn candidates on both square colors;
- the static marker with Reduce Motion enabled.

The ivory keyline and dashed violet stroke must remain clearly visible outside every silhouette and must not resemble the red danger marker, blue legal-move dots, orange capture halo, or selected-square treatment. If the ring remains obscured, stop and report that moving it above pieces is required; do not silently change the approved layering.

- [ ] **Step 7: Run proportional and full verification**

Run:

```bash
xcodebuild test -quiet \
  -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/CoachFocusOverlayTests \
  -only-testing:ChessTutorTests/CoachingGoldenTranscriptTests \
  -only-testing:ChessTutorTests/GameSessionCoachingTests

xcodebuild test -quiet \
  -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)'

xcodebuild build -quiet \
  -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Expected: every command exits 0 with no failed, skipped, or expected-failure tests.

- [ ] **Step 8: Review, commit, and leave the UAT build running**

Run `git diff --check`, inspect the scoped diff, request a read-only code review, address any Critical or Important findings, and commit:

```bash
git add \
  ChessTutor/UI/Board/CoachFocusOverlay.swift \
  ChessTutor/UI/Theme/AppTheme.swift \
  ChessTutorTests/UI/CoachFocusOverlayTests.swift
git commit -m "fix: make coaching hints easier to see"
```

Reinstall and launch the verified normal build on the user-facing `iPad (A16)` without test arguments.


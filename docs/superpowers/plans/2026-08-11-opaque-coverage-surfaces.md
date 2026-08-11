# Opaque Coverage Surfaces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render each coverage state with one opaque, stable appearance so light and dark chess squares cannot split four logical states into eight perceptual states.

**Architecture:** Keep the change entirely inside the existing board-guidance view style and renderer. Replace coverage overlay opacities with explicit RGBA surface tokens whose alpha is `1`, then render those tokens directly; do not change `CoverageSurfaceState`, `BoardGuidancePresentation`, `GameSession`, coverage lifecycle, accessibility descriptions, or chess analysis.

**Tech Stack:** Swift 6, SwiftUI, XCTest, Xcode/iOS Simulator

## Global Constraints

- Coverage temporarily replaces the checkerboard while the lens is open; the wooden frame, 8×8 boundaries, pieces, and existing interaction preserve chessboard identity.
- Side-to-move-only, other-side-only, contested, and neither coverage must each look identical on light and dark source squares.
- Coverage surfaces must have alpha `1`; do not use per-square opacity, blending, checkerboard modulation, inset tokens, or corner reminders.
- Preserve the existing yellow/coral diagonal split for contested squares.
- Preserve piece recession, selected-piece context, coordinates, markers, paths, interaction, persistence, accessibility, Reduce Motion behavior, and game-end behavior unchanged.
- Keep all changes in the view layer and its view-style tests; do not modify model or session code.

---

### Task 1: Replace translucent overlays with opaque coverage tokens

**Files:**
- Modify: `ChessTutor/UI/Board/BoardGuidanceOverlay.swift:3-140`
- Test: `ChessTutorTests/UI/BoardGuidanceStyleTests.swift:5-25`

**Interfaces:**
- Consumes: existing `CoverageSurfaceState` and `CoverageSurfaceView(state:)`.
- Produces: `CoverageSurfaceColor`, `BoardGuidanceStyle.coverageSideToMoveColor`, `coverageOtherSideColor`, and `coverageNeitherColor`; all other guidance style fields and renderer interfaces remain unchanged.

- [ ] **Step 1: Verify the branch is clean and the existing view-style suite is green**

Run:

```bash
git status --short --branch
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/BoardGuidanceStyleTests -resultBundlePath /tmp/ChessTutor-opaque-coverage-baseline.xcresult
xcrun xcresulttool get test-results summary --path /tmp/ChessTutor-opaque-coverage-baseline.xcresult
```

Expected: the branch has no uncommitted tracked files, and all `BoardGuidanceStyleTests` pass with zero failures and zero skipped tests.

- [ ] **Step 2: Write the failing rendered-appearance test**

Add `SwiftUI` and `UIKit` imports to `ChessTutorTests/UI/BoardGuidanceStyleTests.swift`, then add this test and real-render helper inside `BoardGuidanceStyleTests` immediately after `testCoverageSurfaceClassifiesEveryReachCombination()`:

```swift
@MainActor
func testCoverageSurfaceAppearanceDoesNotDependOnUnderlyingSquareColor() {
    let states: [CoverageSurfaceState] = [
        .neither,
        .sideToMoveOnly,
        .otherSideOnly,
        .both,
    ]

    for state in states {
        XCTAssertEqual(
            renderedCoveragePixels(state: state, baseColor: AppTheme.lightSquare),
            renderedCoveragePixels(state: state, baseColor: AppTheme.darkSquare),
            "\(state) inherited the underlying board-square color"
        )
    }
}

@MainActor
private func renderedCoveragePixels(
    state: CoverageSurfaceState,
    baseColor: Color
) -> [[UInt8]] {
    let side = 16
    let renderer = ImageRenderer(
        content: ZStack {
            Rectangle().fill(baseColor)
            CoverageSurfaceView(state: state)
        }
        .frame(width: CGFloat(side), height: CGFloat(side))
    )
    renderer.scale = 1

    guard let image = renderer.uiImage?.cgImage else {
        XCTFail("Coverage surface did not render")
        return []
    }

    var bytes = [UInt8](repeating: 0, count: side * side * 4)
    bytes.withUnsafeMutableBytes { buffer in
        let context = CGContext(
            data: buffer.baseAddress,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    }

    let points = state == .both ? [(3, 3), (12, 12)] : [(8, 8)]
    return points.map { x, y in
        let offset = (y * side + x) * 4
        return Array(bytes[offset..<(offset + 4)])
    }
}
```

This exercises the real `CoverageSurfaceView` with the real board colors. The solid states are sampled at their centers, while the contested state is sampled well inside each diagonal half to avoid testing anti-aliasing at the seam.

- [ ] **Step 3: Run the new test and verify RED**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/BoardGuidanceStyleTests/testCoverageSurfaceAppearanceDoesNotDependOnUnderlyingSquareColor -resultBundlePath /tmp/ChessTutor-opaque-coverage-red.xcresult
```

Expected: the test compiles and fails because the pixels rendered over `AppTheme.lightSquare` differ from the pixels rendered over `AppTheme.darkSquare`. The failure must name at least one `CoverageSurfaceState` that inherited its underlying square color.

- [ ] **Step 4: Add the opaque surface color token**

In `ChessTutor/UI/Board/BoardGuidanceOverlay.swift`, add above `BoardGuidanceStyle`:

```swift
struct CoverageSurfaceColor: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}
```

Replace the three coverage opacity arguments in `BoardGuidanceStyle.current`:

```swift
coverageSideToMoveOpacity: 0.50,
coverageOtherSideOpacity: 0.44,
coverageNeitherOpacity: 0.18,
```

with the opaque colors approved in mockup A:

```swift
coverageSideToMoveColor: CoverageSurfaceColor(
    red: 0.94,
    green: 0.78,
    blue: 0.37,
    alpha: 1
),
coverageOtherSideColor: CoverageSurfaceColor(
    red: 0.86,
    green: 0.50,
    blue: 0.42,
    alpha: 1
),
coverageNeitherColor: CoverageSurfaceColor(
    red: 0.50,
    green: 0.51,
    blue: 0.47,
    alpha: 1
),
```

Replace the matching stored opacity properties with:

```swift
let coverageSideToMoveColor: CoverageSurfaceColor
let coverageOtherSideColor: CoverageSurfaceColor
let coverageNeitherColor: CoverageSurfaceColor
```

Keep `coverageRecessedPieceOpacity` and `coverageTransitionDuration` unchanged.

- [ ] **Step 5: Render the opaque tokens directly**

Update `CoverageSurfaceView.body` so it no longer composites an opacity over the light/dark board square:

```swift
switch state {
case .neither:
    Rectangle()
        .fill(style.coverageNeitherColor.color)
case .sideToMoveOnly:
    Rectangle()
        .fill(style.coverageSideToMoveColor.color)
case .otherSideOnly:
    Rectangle()
        .fill(style.coverageOtherSideColor.color)
case .both:
    ZStack {
        CoverageDiagonalHalfShape(half: .sideToMove)
            .fill(style.coverageSideToMoveColor.color)
        CoverageDiagonalHalfShape(half: .otherSide)
            .fill(style.coverageOtherSideColor.color)
    }
}
```

Do not change `ChessBoardView.squareView`, the base checkerboard, surface transitions, the contested diagonal geometry, or any input/accessibility code. The opaque surface replaces the checkerboard visually only while `guidance.coverage` exists.

- [ ] **Step 6: Run focused tests and source-boundary checks**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/BoardGuidanceStyleTests -resultBundlePath /tmp/ChessTutor-opaque-coverage-green.xcresult
xcrun xcresulttool get test-results summary --path /tmp/ChessTutor-opaque-coverage-green.xcresult
rg -n 'coverage(SideToMove|OtherSide|Neither)Opacity|AppTheme\.(guidanceYellow|guidanceRed|boardFrame)\.opacity\(style\.coverage' ChessTutor ChessTutorTests
git diff --check
git diff --name-only
```

Expected: all view-style tests pass with zero failures and zero skipped tests; the `rg` command returns no matches; whitespace checks pass; and only `BoardGuidanceOverlay.swift` and `BoardGuidanceStyleTests.swift` have uncommitted changes.

- [ ] **Step 7: Build and launch the real iPad experiment**

Run:

```bash
xcodebuild build -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
xcrun simctl install AA821CF0-9DC9-45EE-8E1E-6B4D3593A85A DerivedData/ChessTutor/Build/Products/Debug-iphonesimulator/ChessTutor.app
xcrun simctl launch AA821CF0-9DC9-45EE-8E1E-6B4D3593A85A org.jasoncrawford.chesstutor
```

Open **Show coverage** and inspect the real app:

1. Confirm yellow-only, coral-only, and neither squares each have one stable appearance across the whole board.
2. Confirm both halves of every contested square match their corresponding single-side colors exactly.
3. Confirm the wooden frame, cell boundaries, pieces, and interaction still make the opaque map read as a chessboard.
4. Select and clear pieces to confirm existing contextual paths and piece emphasis remain unchanged.
5. Rotate the board and enable Reduce Motion to confirm the refinement does not depend on orientation or animation.

If the real app needs tuning, change only the three RGB triples above. Keep every alpha at `1`, rerun Steps 6 and 7, and do not add per-square modulation.

- [ ] **Step 8: Run the complete suite**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -resultBundlePath /tmp/ChessTutor-opaque-coverage-full.xcresult
xcrun xcresulttool get test-results summary --path /tmp/ChessTutor-opaque-coverage-full.xcresult
```

Expected: the complete suite passes with zero failures and zero skipped tests.

- [ ] **Step 9: Commit the opaque renderer**

Run:

```bash
git add ChessTutor/UI/Board/BoardGuidanceOverlay.swift ChessTutorTests/UI/BoardGuidanceStyleTests.swift
git commit -m "Make coverage surfaces opaque"
```

Expected: one implementation commit containing only the coverage style/renderer and its view-style test. Leave the tested app running in the iPad simulator for user evaluation.

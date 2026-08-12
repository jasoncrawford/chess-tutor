# Coverage Grid Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore stable square boundaries in the opaque coverage map with a uniform, low-contrast 8×8 grid.

**Architecture:** Add one board-wide SwiftUI shape that draws the seven internal horizontal and seven internal vertical lines. Overlay it on the existing board only while coverage is visible, above all square content but below the already-separate path and piece layers; do not alter coverage data, individual square rendering, interaction, or accessibility facts.

**Tech Stack:** Swift 6, SwiftUI, XCTest, Xcode/iOS Simulator

## Global Constraints

- Draw one uniform grid across the entire coverage map regardless of neighboring coverage states.
- Draw only the 14 internal boundaries; the existing wooden board frame owns the outer perimeter.
- Start with `AppTheme.boardFrame` at `0.18` opacity and a `0.75`-point stroke; keep both as view-style constants for simulator tuning.
- Show the grid only while coverage is visible.
- Place the grid above square surfaces and selection highlights but below trajectories, pieces, and piece markers.
- The grid must ignore input and expose no separate accessibility element.
- Preserve opaque coverage colors, selected-piece context, coverage lifecycle, board rotation, Reduce Motion behavior, and every model/session interface unchanged.

---

### Task 1: Add the board-wide coverage grid

**Files:**
- Modify: `ChessTutor/UI/Board/BoardGuidanceOverlay.swift:3-165`
- Modify: `ChessTutor/UI/Board/ChessBoardView.swift:260-280`
- Test: `ChessTutorTests/UI/BoardGuidanceStyleTests.swift:25-90`

**Interfaces:**
- Consumes: `BoardGuidancePresentation.coverage`, `BoardGuidanceStyle.current`, `AppTheme.boardFrame`, and the existing board-sized overlay composition.
- Produces: `CoverageGridShape`, `CoverageGridView`, `BoardGuidanceStyle.coverageGridLineWidth`, and `BoardGuidanceStyle.coverageGridOpacity`; no model or session interface changes.

- [ ] **Step 1: Verify the clean focused baseline**

Run:

```bash
git status --short --branch
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/BoardGuidanceStyleTests -resultBundlePath /tmp/ChessTutor-coverage-grid-baseline.xcresult
xcrun xcresulttool get test-results summary --path /tmp/ChessTutor-coverage-grid-baseline.xcresult
```

Expected: the branch is clean and all 11 current view-style tests pass with zero failures and zero skipped tests.

- [ ] **Step 2: Write the failing rendered-grid test**

Add this test inside `BoardGuidanceStyleTests`:

```swift
@MainActor
func testCoverageGridDrawsEveryInternalBoundaryWithoutAnOuterStroke() {
    let side = 128
    let interiorPoint = (8, 8)
    let internalBoundaryPoints = (1..<8).flatMap { index in
        let coordinate = index * side / 8
        return [(coordinate, 8), (8, coordinate)]
    }
    let outerPoints = [(1, 8), (8, 1), (side - 2, 8), (8, side - 2)]
    let points = [interiorPoint] + internalBoundaryPoints + outerPoints
    let pixels = renderedPixels(
        content: ZStack {
            Rectangle().fill(BoardGuidanceStyle.current.coverageSideToMoveColor.color)
            CoverageGridView()
        },
        side: side,
        points: points
    )
    let interiorPixel = pixels[0]
    let boundaryPixels = pixels[1...(internalBoundaryPoints.count)]
    let outerPixels = pixels.suffix(outerPoints.count)

    XCTAssertTrue(boundaryPixels.allSatisfy { $0 != interiorPixel })
    XCTAssertTrue(outerPixels.allSatisfy { $0 == interiorPixel })
}
```

Add this reusable real-render helper next to `renderedCoveragePixels(state:baseColor:)`:

```swift
@MainActor
private func renderedPixels<Content: View>(
    content: Content,
    side: Int,
    points: [(Int, Int)]
) -> [[UInt8]] {
    let renderer = ImageRenderer(
        content: content.frame(width: CGFloat(side), height: CGFloat(side))
    )
    renderer.scale = 1

    guard let image = renderer.uiImage?.cgImage else {
        XCTFail("View did not render")
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

    return points.map { x, y in
        let offset = (y * side + x) * 4
        return Array(bytes[offset..<(offset + 4)])
    }
}
```

Refactor the existing `renderedCoveragePixels(state:baseColor:)` to create its `ZStack`, choose its solid-state or contested-state sample points, and delegate rasterization to `renderedPixels(content:side:points:)`. Preserve the existing light-versus-dark regression assertions unchanged.

- [ ] **Step 3: Run the new test and verify RED**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/BoardGuidanceStyleTests/testCoverageGridDrawsEveryInternalBoundaryWithoutAnOuterStroke -resultBundlePath /tmp/ChessTutor-coverage-grid-red.xcresult
```

Expected: compilation fails because `CoverageGridView` does not exist. Confirm there are no unrelated compile errors.

- [ ] **Step 4: Add the grid style constants and geometry**

In `BoardGuidanceStyle.current`, add:

```swift
coverageGridLineWidth: 0.75,
coverageGridOpacity: 0.18,
```

Add the matching stored properties:

```swift
let coverageGridLineWidth: CGFloat
let coverageGridOpacity: Double
```

Add these view-only types after `CoverageSurfaceView` in `BoardGuidanceOverlay.swift`:

```swift
struct CoverageGridShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 1..<8 {
            let progress = CGFloat(index) / 8
            let x = rect.minX + rect.width * progress
            let y = rect.minY + rect.height * progress
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

struct CoverageGridView: View {
    var body: some View {
        let style = BoardGuidanceStyle.current
        CoverageGridShape()
            .stroke(
                AppTheme.boardFrame.opacity(style.coverageGridOpacity),
                lineWidth: style.coverageGridLineWidth
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
```

The shape deliberately omits the outer rectangle, so the board frame remains the only perimeter treatment.

- [ ] **Step 5: Overlay the grid only during coverage**

In `ChessBoardView.board(side:guidance:)`, attach this overlay to the returned `Grid`:

```swift
.overlay {
    if guidance.coverage != nil {
        CoverageGridView()
            .transition(.opacity)
    }
}
```

Keep the overlay inside `board(side:guidance:)`. This places it above the square-local selected highlight while the outer `ChessBoardView` ZStack continues to place trajectories and pieces above it. Do not add a gesture or accessibility modifier in `ChessBoardView`; `CoverageGridView` already owns those guarantees.

- [ ] **Step 6: Run focused tests and inspect scope**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/BoardGuidanceStyleTests -resultBundlePath /tmp/ChessTutor-coverage-grid-green.xcresult
xcrun xcresulttool get test-results summary --path /tmp/ChessTutor-coverage-grid-green.xcresult
git diff --check
git diff --name-only
```

Expected: all 12 view-style tests pass with zero failures and zero skipped tests; whitespace checks pass; and only `BoardGuidanceOverlay.swift`, `ChessBoardView.swift`, and `BoardGuidanceStyleTests.swift` have uncommitted changes.

- [ ] **Step 7: Build and launch the iPad experiment**

Run:

```bash
xcodebuild build -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
xcrun simctl install AA821CF0-9DC9-45EE-8E1E-6B4D3593A85A DerivedData/ChessTutor/Build/Products/Debug-iphonesimulator/ChessTutor.app
xcrun simctl launch AA821CF0-9DC9-45EE-8E1E-6B4D3593A85A org.jasoncrawford.chesstutor
```

Open coverage and verify that all 64 squares remain legible inside large same-state regions, the grid is lower contrast than any coverage color boundary or selected path, no doubled shared edges appear, and the board frame remains the only outer border. If tuning is needed, change only `coverageGridLineWidth` and `coverageGridOpacity`, then rerun Steps 6 and 7.

- [ ] **Step 8: Run the complete suite**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -resultBundlePath /tmp/ChessTutor-coverage-grid-full.xcresult
xcrun xcresulttool get test-results summary --path /tmp/ChessTutor-coverage-grid-full.xcresult
```

Expected: the complete suite passes with zero failures and zero skipped tests.

- [ ] **Step 9: Commit the coverage grid**

Run:

```bash
git add ChessTutor/UI/Board/BoardGuidanceOverlay.swift ChessTutor/UI/Board/ChessBoardView.swift ChessTutorTests/UI/BoardGuidanceStyleTests.swift
git commit -m "Add coverage square grid"
```

Expected: one implementation commit containing only the grid style, grid renderer, board integration, and rendering test. Leave the tested build running in the iPad simulator.

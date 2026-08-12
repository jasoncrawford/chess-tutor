# Consolidated Guidance Rays Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Draw one guidance arrow to the farthest reachable square on each visual ray and place its tip slightly closer to the final square's center.

**Architecture:** Keep `BoardGuidancePresentation.selectedPaths` unchanged as the complete semantic set. Add a pure view-layer rendering policy beside `GuidancePathsLayer` that groups paths by source, role, color, and normalized direction, retains the farthest path in each group, and supplies that reduced set to the existing canvas. Adjust only `GuidancePathLayout` for the endpoint placement.

**Tech Stack:** Swift 6, SwiftUI Canvas, CoreGraphics, XCTest, Xcode/iOS Simulator

## Global Constraints

- This is a view-only change; do not modify chess rules, position analysis, `GameSession`, or `BoardGuidancePresentation` construction.
- Preserve every semantic path in `BoardGuidancePresentation.selectedPaths` for context and accessibility consumers.
- Group visual paths only when source square, role, color, and normalized signed direction all match.
- Retain the farthest destination and its capture metadata in each visual ray.
- Preserve arrowhead size, shaft weight, color, opacity, z-order, animation, input, and accessibility behavior.
- Change the destination inset from `0.30` to `0.22` cell widths.
- The complete test suite must finish with zero failures and zero skipped tests.

---

### Task 1: Consolidate collinear paths in the trajectory renderer

**Files:**
- Modify: `ChessTutor/UI/Board/BoardGuidanceOverlay.swift:330-405`
- Test: `ChessTutorTests/UI/BoardGuidanceStyleTests.swift:190-225`

**Interfaces:**
- Consumes: `Set<BoardGuidancePath>`, including each path's `source`, `destination`, `color`, `role`, and `captureSquare`.
- Produces: `GuidancePathRenderingPolicy.visiblePaths(in:) -> Set<BoardGuidancePath>`; `GuidancePathsLayer` uses its result before sorting and drawing.

- [ ] **Step 1: Verify the focused baseline**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -parallel-testing-enabled NO -only-testing:ChessTutorTests/BoardGuidanceStyleTests
```

Expected: all current `BoardGuidanceStyleTests` pass.

- [ ] **Step 2: Add a test-only path builder and failing ray tests**

Add this helper inside `BoardGuidanceStyleTests`:

```swift
private func guidancePath(
    from source: Square,
    to destination: Square,
    captureSquare: Square? = nil,
    color: PieceColor = .white,
    role: BoardGuidancePath.Role = .allowed
) -> BoardGuidancePath {
    BoardGuidancePath(
        source: source,
        destination: destination,
        captureSquare: captureSquare,
        color: color,
        role: role
    )
}
```

Add these tests before the existing trajectory-layout tests:

```swift
func testTrajectoryRenderingKeepsOnlyFarthestPathOnEachRay() {
    let source = Square(file: .d, rank: 4)
    let rightNear = guidancePath(
        from: source,
        to: Square(file: .f, rank: 4)
    )
    let rightFar = guidancePath(
        from: source,
        to: Square(file: .h, rank: 4),
        captureSquare: Square(file: .h, rank: 4)
    )
    let left = guidancePath(
        from: source,
        to: Square(file: .a, rank: 4)
    )
    let up = guidancePath(
        from: source,
        to: Square(file: .d, rank: 8)
    )

    let visible = GuidancePathRenderingPolicy.visiblePaths(
        in: [rightNear, rightFar, left, up]
    )

    XCTAssertEqual(visible, [rightFar, left, up])
    XCTAssertEqual(
        visible.first(where: { $0.destination == rightFar.destination })?.captureSquare,
        rightFar.captureSquare
    )
}

func testTrajectoryRenderingDoesNotMergeDifferentSourcesRolesOrColors() {
    let source = Square(file: .d, rank: 4)
    let allowedWhite = guidancePath(
        from: source,
        to: Square(file: .h, rank: 4)
    )
    let attackerWhite = guidancePath(
        from: source,
        to: Square(file: .g, rank: 4),
        role: .attacker
    )
    let allowedBlack = guidancePath(
        from: source,
        to: Square(file: .f, rank: 4),
        color: .black
    )
    let otherSource = guidancePath(
        from: Square(file: .c, rank: 4),
        to: Square(file: .h, rank: 4)
    )

    let visible = GuidancePathRenderingPolicy.visiblePaths(
        in: [allowedWhite, attackerWhite, allowedBlack, otherSource]
    )

    XCTAssertEqual(visible, [allowedWhite, attackerWhite, allowedBlack, otherSource])
}
```

The first test would fail if shorter same-ray paths were still rendered, if opposite directions merged, or if the farthest capture metadata were lost. The second would fail if the renderer grouped across any semantic visual boundary.

- [ ] **Step 3: Run the new tests and verify RED**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -parallel-testing-enabled NO -only-testing:ChessTutorTests/BoardGuidanceStyleTests/testTrajectoryRenderingKeepsOnlyFarthestPathOnEachRay -only-testing:ChessTutorTests/BoardGuidanceStyleTests/testTrajectoryRenderingDoesNotMergeDifferentSourcesRolesOrColors
```

Expected: compilation fails because `GuidancePathRenderingPolicy` does not exist. This is the missing view behavior, not a model failure.

- [ ] **Step 4: Add the minimal view-layer ray policy**

Add this policy immediately before `GuidancePathsLayer` in `BoardGuidanceOverlay.swift`:

```swift
enum GuidancePathRenderingPolicy {
    private struct Ray: Hashable {
        let source: Square
        let role: BoardGuidancePath.Role
        let color: PieceColor
        let fileStep: Int
        let rankStep: Int
    }

    static func visiblePaths(
        in paths: Set<BoardGuidancePath>
    ) -> Set<BoardGuidancePath> {
        var farthestByRay: [Ray: BoardGuidancePath] = [:]

        for path in paths {
            let fileDelta = path.destination.file.rawValue - path.source.file.rawValue
            let rankDelta = path.destination.rank - path.source.rank
            let divisor = greatestCommonDivisor(abs(fileDelta), abs(rankDelta))
            let ray = Ray(
                source: path.source,
                role: path.role,
                color: path.color,
                fileStep: divisor == 0 ? 0 : fileDelta / divisor,
                rankStep: divisor == 0 ? 0 : rankDelta / divisor
            )

            guard let current = farthestByRay[ray] else {
                farthestByRay[ray] = path
                continue
            }
            if distanceSquared(of: path) > distanceSquared(of: current) {
                farthestByRay[ray] = path
            }
        }

        return Set(farthestByRay.values)
    }

    private static func distanceSquared(of path: BoardGuidancePath) -> Int {
        let fileDelta = path.destination.file.rawValue - path.source.file.rawValue
        let rankDelta = path.destination.rank - path.source.rank
        return fileDelta * fileDelta + rankDelta * rankDelta
    }

    private static func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
        var dividend = lhs
        var divisor = rhs
        while divisor != 0 {
            let remainder = dividend % divisor
            dividend = divisor
            divisor = remainder
        }
        return dividend
    }
}
```

The signed normalized steps keep opposite rays distinct. Including source, role, and color prevents paths that only happen to be geometrically aligned from merging.

- [ ] **Step 5: Wire the canvas to the reduced visual set**

Change the `paths` declaration in `GuidancePathsLayer.body` from:

```swift
let paths = guidance.selectedPaths.sorted(by: pathOrder)
```

to:

```swift
let paths = GuidancePathRenderingPolicy.visiblePaths(
    in: guidance.selectedPaths
).sorted(by: pathOrder)
```

Do not mutate `guidance.selectedPaths` or move this reduction into `BoardGuidancePresentation`.

- [ ] **Step 6: Run the focused guidance tests and inspect scope**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -parallel-testing-enabled NO -only-testing:ChessTutorTests/BoardGuidanceStyleTests
git diff --check
git diff --name-only
```

Expected: all focused tests pass; only `BoardGuidanceOverlay.swift` and `BoardGuidanceStyleTests.swift` are modified.

- [ ] **Step 7: Commit the ray consolidation**

Run:

```bash
git add ChessTutor/UI/Board/BoardGuidanceOverlay.swift ChessTutorTests/UI/BoardGuidanceStyleTests.swift
git commit -m "Consolidate collinear guidance arrows"
```

Expected: one view-layer implementation commit containing the reducer, its renderer wiring, and its focused tests.

---

### Task 2: Extend each arrow tip into the final square

**Files:**
- Modify: `ChessTutor/UI/Board/BoardGuidanceOverlay.swift:210-265`
- Test: `ChessTutorTests/UI/BoardGuidanceStyleTests.swift:203-220`

**Interfaces:**
- Consumes: `GuidancePathLayout.make(from:to:cellSize:)`.
- Produces: the same `GuidancePathLayout` interface with its `tip` positioned `0.22 * cellSize` before the destination center.

- [ ] **Step 1: Tighten the existing endpoint test**

In `testTrajectoryStopsClearOfPieceCenters()`, change the destination to a long ray so the cell-based inset is exercised:

```swift
let destination = CGPoint(x: 294, y: 42)
```

Then add this assertion after `XCTAssertLessThan(layout.tip.x, destination.x)`:

```swift
XCTAssertEqual(
    destination.x - layout.tip.x,
    84 * 0.22,
    accuracy: 0.001
)
```

The literal expectation is independently derived from the approved design and detects both a regression to the old inset and an overshoot through the destination center.

- [ ] **Step 2: Run the endpoint test and verify RED**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -parallel-testing-enabled NO -only-testing:ChessTutorTests/BoardGuidanceStyleTests/testTrajectoryStopsClearOfPieceCenters
```

Expected: FAIL because the current tip remains `25.2` points (`84 * 0.30`) from the destination instead of `18.48` points (`84 * 0.22`).

- [ ] **Step 3: Change only the destination inset**

In `GuidancePathLayout.make(from:to:cellSize:)`, replace:

```swift
let destinationInset = min(cellSize * 0.30, distance * 0.22)
```

with:

```swift
let destinationInset = min(cellSize * 0.22, distance * 0.22)
```

Leave source inset and arrowhead geometry unchanged.

- [ ] **Step 4: Run the focused guidance tests**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -parallel-testing-enabled NO -only-testing:ChessTutorTests/BoardGuidanceStyleTests
```

Expected: every guidance-style test passes with zero failures and zero skipped tests.

- [ ] **Step 5: Run the complete suite and verify exact counts**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -parallel-testing-enabled NO -resultBundlePath /tmp/ChessTutor-consolidated-guidance-rays-full.xcresult
xcrun xcresulttool get test-results summary --path /tmp/ChessTutor-consolidated-guidance-rays-full.xcresult
```

Expected: the complete suite passes with zero failures and zero skipped tests.

- [ ] **Step 6: Build and launch the iPad experiment**

Run:

```bash
xcodebuild build -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
xcrun simctl install AA821CF0-9DC9-45EE-8E1E-6B4D3593A85A DerivedData/ChessTutor/Build/Products/Debug-iphonesimulator/ChessTutor.app
xcrun simctl launch AA821CF0-9DC9-45EE-8E1E-6B4D3593A85A org.jasoncrawford.chesstutor
```

Select a rook, bishop, queen, and starting pawn. Verify one arrowhead per direction, no darkened overlapping shafts, separate opposite rays, preserved capture endpoints, and tips modestly closer to the final square centers.

- [ ] **Step 7: Commit the endpoint adjustment**

Run:

```bash
git add ChessTutor/UI/Board/BoardGuidanceOverlay.swift ChessTutorTests/UI/BoardGuidanceStyleTests.swift
git commit -m "Extend guidance arrows into destination squares"
```

Expected: a second small view-layer commit containing only the endpoint geometry and its regression assertion. Leave the tested build running in the iPad simulator.

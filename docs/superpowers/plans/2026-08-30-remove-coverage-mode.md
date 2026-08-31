# Remove Coverage Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the optional coverage-board mode while preserving all active move, capture, threat, defense, and check-safety guidance.

**Architecture:** Delete coverage-only data from pure position analysis, then simplify the session and guidance presentation so the board and side panel no longer have a coverage mode. The normal board presentation becomes the only rendering path.

**Tech Stack:** Swift, SwiftUI, XCTest, Xcode/iPad Simulator.

## Global Constraints

- Keep chess rules in pure model code and presentation state in `GameSession`/`BoardGuidancePresentation`.
- Preserve allowed move/capture, threat/defense, check-safety, coordinate, and turn-flow behavior.
- Do not redesign unrelated side-panel or board UI.

---

### Task 1: Remove coverage from model and presentation state

**Files:**

- Modify: `ChessTutor/Core/PositionAnalyzer.swift`
- Modify: `ChessTutor/Game/BoardGuidancePresentation.swift`
- Modify: `ChessTutor/Game/GameSession.swift`
- Modify: `ChessTutorTests/Core/PositionAnalyzerTests.swift`
- Modify: `ChessTutorTests/Game/BoardGuidancePresentationTests.swift`
- Modify: `ChessTutorTests/Game/GameSessionTests.swift`
- Modify: `ChessTutorTests/Remote/PositionFingerprintingTests.swift`

**Interfaces:** Removes `PositionAnalysis.coverage(for:)`, `BoardCoveragePresentation`, `BoardGuidancePresentation.coverage`, `showsCoverage`, `GameSession.isCoverageVisible`, and `GameSession.toggleCoverage()`.

- [ ] Delete coverage-only unit tests and setup arguments; retain move/capture, threat, defense, and fingerprint behavior assertions.
- [ ] Run the focused model/game test classes once to record their current passing baseline.
- [ ] Remove coverage accumulation/API from `PositionAnalyzer`, coverage construction/accessibility from `BoardGuidancePresentation`, and visibility/toggle/reset paths from `GameSession`.
- [ ] Run `xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/PositionAnalyzerTests -only-testing:ChessTutorTests/BoardGuidancePresentationTests -only-testing:ChessTutorTests/GameSessionTests -only-testing:ChessTutorTests/PositionFingerprintingTests`; expect PASS.
- [ ] Commit with `git commit -m "Remove coverage guidance state"`.

### Task 2: Remove coverage-only SwiftUI rendering and controls

**Files:**

- Modify: `ChessTutor/UI/Board/BoardGuidanceOverlay.swift`
- Modify: `ChessTutor/UI/Board/ChessBoardView.swift`
- Modify: `ChessTutor/UI/Sidebar/SelectedPiecePanelView.swift`
- Modify: `ChessTutor/UI/Sidebar/SidePanelView.swift`
- Modify: `ChessTutor/UI/Theme/AppTheme.swift`
- Modify: `ChessTutorTests/UI/BoardGuidanceStyleTests.swift`
- Modify: `ChessTutorTests/UI/CaptureTrayLayoutTests.swift`

**Interfaces:** The board retains a normal rendering path with coordinates, ambient threats, ordinary accessibility labels, and full-opacity pieces. `SelectedPiecePanelView` receives only selected-piece information.

- [ ] Delete coverage-surface/grid, rendering-policy/context, and coverage-button tests/harnesses while retaining unrelated board-overlay and panel layout tests.
- [ ] Delete coverage views, colors, animations, grid and surface rendering; make existing normal board rendering unconditional.
- [ ] Remove coverage inputs/button/footer layout from `SelectedPiecePanelView` and its call in `SidePanelView`.
- [ ] Run `xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/BoardGuidanceStyleTests -only-testing:ChessTutorTests/CaptureTrayLayoutTests`; expect PASS.
- [ ] Run `rg -n -i 'coverage' ChessTutor ChessTutorTests`; expect no active-feature references.
- [ ] Commit with `git commit -m "Remove coverage board interface"`.

### Task 3: Verify the complete app

**Files:**

- Modify: `docs/superpowers/plans/2026-08-30-remove-coverage-mode.md` (mark completed tasks).

- [ ] Run `xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'`; expect zero failures and zero skipped tests.
- [ ] Run `git diff main...HEAD --check` and `git status --short`; expect no whitespace errors or uncommitted application changes.
- [ ] Commit plan tracking if edited, then push `codex/remove-coverage` and open a review-only pull request without auto-merge.

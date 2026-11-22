# Visual coaching play-test fixes

> **For agentic workers:** Use superpowers:executing-plans. This is review feedback on open PR #28, in its existing isolated worktree.

**Goal:** Make linked advice readable and distinguish board answers, pending replies, and the player's staged move.

**Architecture:** Keep the existing structured response and session routing. Use native attributed text layout instead of a word/button flow layout. Derive UI instructions and commit labels from the existing expected response and draft, without model calls or prose parsing.

**Tech Stack:** SwiftUI, XCTest, existing hosted coaching presentation model.

**Spec:** The November 22 user feedback supersedes the quiet-border and per-link 44-point layout-box choices in `../specs/2026-11-21-visual-coaching-design.md`.

## Design and constraints

- Natural text links wrap within phrases and preserve ordinary paragraph line height. Remove miniature pieces from prose; the linked description already names the piece. Preserve local highlighting and accessible target descriptions.
- A staged move is explicitly **Play my move**, with an accessible description identifying the actual staged piece and destination. A suggested alternative is never silently committed. Only the prompt's control name/meaning changes; no protocol, model, chess-policy, or paid eval change.
- A visible board banner says **Tap the piece that needs help**, **Tap a piece you can capture**, or **Tap a piece to answer**, derived from `expects`, not inferred from prose. It occupies its own space, never covers playable squares, and rotates with readable UI.
- Pending answers show **Checking your answer…** and the existing full-size animated thinking indicator. Further answers, dragging, Play instead, and Close help keep their existing behavior.
- Replace the anonymous header replay icon with a named **Show arrow** action near the explanation. It restores the existing local arrow and never sends a request.
- Retain the current warm palette, plum links/board gestures, serif Coach title and rounded body face. These are corrections within the existing design, not a restyle.

## Review focus

1. Long reference phrases at narrow widths and large type must wrap without new blank space or punctuation lines.
2. A suggested alternative from a different piece must not change what the commit action plays.
3. Banner and pending state must remain readable at all four physical rotations without blocking a square.
4. Reference and replay taps must remain local and accessible, including wrapped links.
5. Answer replacement, drag escape, failures, and close must not leave a stale banner/loading state.

## Tasks

### Task 1: Reproduce and fix paragraph layout

Files: `CoachingMessageView.swift`, `CoachingPanelLayoutTests.swift`, `VisualCoachingUITests.swift`.
- [x] Add screenshot-derived paragraph measurement tests against ordinary text at narrow/large sizes; observe the excess height with current renderer.
- [x] Replace custom word/button layout with one attributed paragraph and local link activation.
- [x] Verify paragraph measurements, link activation and accessible targets, including rotated panels.

### Task 2: Make interaction state explicit

Files: `HostedCoachingPresentationProjector.swift`, `CoachingModels.swift`, `CoachingPanelView.swift`, `ChessBoardView.swift`, existing hosted/UI tests and fixture.
- [x] Add failing tests for explicitly named draft commit, board-answer banner, and prominent pending-answer feedback.
- [x] Project board prompt from `expects`; render a banner outside the square grid, with rotation-aware layout.
- [x] Keep the actual staged move as the commit target and identify it in the action's accessible description.
- [x] Move replay to a named Show arrow action and use full-size pending animation.
- [x] Verify local replay/links, draft commit, pending replacement/drag/escape, wide and rotated layouts.

### Task 3: Verify and hand off

- [x] Run native unit and UI suites; inspect full-screen screenshots.
- [x] Independent review of this feedback diff; fix important findings with regression tests.
- [ ] Update report, commit/push to PR #28, check CI, relaunch Coaching Smoke with local server. No production deployment or physical iPad installation.

## Progress

- PR #28 remains open; working tree clean at `2486b0f`. Current main is already its base through PR #27. Continuing this PR's review feedback in the same worktree.
- Confirmed code path: links have 44-point minimum row height and are indivisible HStacks; replay currently restores the same arrow; Done commits the draft independent of coach visuals.

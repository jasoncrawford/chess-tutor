# Coaching References and Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make board references discoverable and draft controls unambiguous.
**Architecture:** Native attributed prose owns icons and wrapping. The hosted
presentation projector owns commit visibility. A new pinned prompt teaches the
matching interaction; offline evaluation diagnoses weak references and supplies
the judge with per-turn controls.
**Tech Stack:** SwiftUI, UIKit/TextKit, XCTest, Python unittest.
**Spec:** `docs/superpowers/specs/2026-11-22-coaching-references-controls-design.md`

## Global Constraints

Keep existing artwork and layout. No paid calls or production rollout. Do not
change old pinned prompts. No prose-based sentiment classification. Retain normal
draft editing, local highlights, readable rotations, and accessible links.

## Review Focus

- A different piece's suggestion and a same-piece revision both hide commit.
- A matching arrow or opponent attack does not hide ordinary draft commit.
- Long linked phrases wrap with normal line heights at large text sizes.
- Icons and words activate the same target, including rotated panels.
- Judge metadata describes the current controls, not historical control names.

### Task 1: References, controls, and their evaluation contract

**Files:** `ChessTutor/UI/Coaching/CoachingMessageView.swift`,
`CoachingPanelView.swift`, `ChessTutor/Coaching/Hosted/HostedCoachingPresentationProjector.swift`,
their native/UI tests; `Tools/CoachingEval/benchmark/{grader,visual_metrics,visual_evaluation}.py`,
`Tools/CoachingEval/tests/test_visual_benchmark.py`; new visual-v5 prompt/config/candidate,
server default/bundle, handoff/report.

**Interfaces:** Consumes validated `ModelCoachingVisualContent`, committed board,
and tentative move; produces presentation actions and attributed link text. Eval
consumes the candidate turn and original request's tentative move.

- [x] Add failing native tests for icon presence/line height, default commit,
  same/different move arrows, and close-help preserving the original draft.
- [x] Update UI tests to require absence of Show arrow, preserve link activation,
  and exercise long wrapped references plus rotated layouts.
- [x] Add offline tests for pronoun-only link diagnostics and per-turn controls.
- [x] Run focused tests and observe the expected old-behavior failures.
- [x] Implement native attachments, remove replay control, condition commit on
  canonical arrow equality; retain a spoken description of the displayed arrow.
- [x] Add visual-v5 prompt/config/candidate and switch current defaults/bundle;
  update eval acceptance and controls. Export prompts without paid calls.
- [x] Run full native suite (one simulator job), server suite, and offline eval
  suite; inspect screenshots, obtain one independent review, fix material findings.
- [x] Commit/push to PR #28, update its description, restart Coaching Smoke with
  the saved game preserved. Record evidence and scope in the handoff/report.

**Verification:** `xcodebuild test -project ChessTutor.xcodeproj -scheme ChessTutor
-destination 'platform=iOS Simulator,id=2405386C-1815-48D7-BA99-53ED13F009A2'
-derivedDataPath /tmp/chess-visual-coaching-review`; Python unittest discovery in
`CoachingServer/tests` and `Tools/CoachingEval/tests`. Expected: zero failures/skips.

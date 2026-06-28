# About Attribution Popup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a compact About popup near New Game that exposes ChessTutor attribution and the Celtic piece license credit.

**Architecture:** Keep the About button in `GameControlsView`, where the New Game control already lives, and present the sheet from top-level `ContentView` so SwiftUI owns the modal from a stable presenter. Put static About copy in a tiny testable model so tests can lock down the attribution without depending on SwiftUI inspection.

**Tech Stack:** SwiftUI, XCTest, Xcode project resources.

---

### Task 1: Add About Attribution Content

**Files:**
- Create: `ChessTutor/UI/Controls/AboutAttribution.swift`
- Modify: `ChessTutor.xcodeproj/project.pbxproj`
- Test: `ChessTutorTests/UI/PieceAssetTests.swift`

- [ ] **Step 1: Add an internal `AboutAttribution` struct with app and Celtic piece attribution strings.**
- [ ] **Step 2: Add `AboutAttribution.swift` to the app target sources.**
- [ ] **Step 3: Add tests that verify the About copy names Maurizio Monge, Chess Art, and MIT.**

### Task 2: Present About Popup From New Game Tile

**Files:**
- Modify: `ChessTutor/UI/Controls/GameControlsView.swift`
- Modify: `ChessTutor/UI/Root/ContentView.swift`

- [ ] **Step 1: Add a quiet `About` button next to the New Game control.**
- [ ] **Step 2: Let `GameControlsView` invoke an optional `onAbout` callback.**
- [ ] **Step 3: Add `isShowingAbout` state to `ContentView`.**
- [ ] **Step 4: Present a compact sheet using `AboutAttribution` copy and a Done button.**

### Task 3: Verify

**Files:**
- Verify app UI in simulator.

- [ ] **Step 1: Run focused tests for `PieceAssetTests`.**
- [ ] **Step 2: Run the full `ChessTutor` test suite.**
- [ ] **Step 3: Capture a screenshot of the New Game/About control layout.**

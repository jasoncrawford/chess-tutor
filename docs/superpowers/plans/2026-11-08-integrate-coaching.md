# Integrate Coaching with the Game Library

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Combine the tested hosted-coaching work with current main's multiple-game experience, without rewriting either history.

**Architecture:** Start from main and merge the coaching integration branch after PR #23. Keep the existing game library as the owner of persisted games and GameSession as the owner of transient coaching. Centralize managed-game session creation in the lifecycle layer so reopening a board preserves its game identity and injects the configured provider consistently.

**Tech Stack:** Swift 6, SwiftUI, XCTest, XcodeGen; existing Python server and eval tools.

**Spec:** User-approved integration sequence in this chat (2026-11-08); existing `docs/superpowers/specs/2026-08-28-games-board-rack-revision-design.md` and coaching behavior from PR #23. No new coaching or visual design is requested.

## Global Constraints

- Main is read-only; ship through a new PR targeting main. Do not merge that new PR automatically.
- Preserve both histories; no rebase, cherry-pick, or force-push.
- Keep the Games rack, local/remote game creation, saved-game restoration, and coverage-mode removal from main.
- Preserve the current coaching prompt, model configuration, response contract, and polished panel unchanged.
- Use the persistent managed-game UUID for trace correlation; never share transient coaching sessions or continuations across boards.
- Run tests without paid model calls. Keep the existing experiment budget unchanged.
- Use Coaching Smoke only; leave A16 and physical devices alone.
- Close PR #3 as superseded once its replacement PR exists; retain old worktrees and ignored evaluation evidence.

## Review Focus

- Switching boards while a help request is pending must not display the old answer on the new board.
- A reopened local game must keep its trace identity, moves, and hosted provider, with no stale question or draft.
- Remote games must keep player seats, correct move history, and remote-turn/ended-game restrictions on Help.
- Pending invitations must remain locked and offer neither Help nor Done.
- Coverage mode and the obsolete in-board Play Remotely button must not return via a clean textual merge.

### Task 1: Combine the existing implementations

**Files:** `ChessTutor/Game/GameSession.swift`, `ChessTutor/UI/Root/ContentView.swift`, `ChessTutor/UI/Controls/GameControlsView.swift`, `ChessTutor/UI/Sidebar/SidePanelView.swift`, generated `ChessTutor.xcodeproj/project.pbxproj`.

**Interfaces:** Preserve `GameControlsPresentation`'s invitation handling and supplemental Help policy. Preserve `GameSession`'s coaching API and main's board-lock API.

- [x] Merge PR #23 after fresh green CI/head verification; merged as c7629e7.
- [x] Create isolated branch `codex/integrate-coaching` from main 9141920; baseline 376 tests passed, no skips or failures. Baseline has two existing Swift actor-isolation compile warnings.
- [ ] Merge c7629e7 with `--no-commit`; reconcile the three conflicts by combining behavior, not by selecting a whole side.
- [ ] Regenerate the Xcode project and run focused controls/lifecycle tests; retain both branches' relevant assertions.

### Task 2: Pin cross-game coaching behavior

**Files:** `ChessTutor/Game/GameLifecycle.swift`, `ChessTutor/Game/GameSession.swift`, `ChessTutor/UI/Root/ContentView.swift`, `ChessTutorTests/Game/GameLifecycleTests.swift`, `ChessTutorTests/UI/GameControlsPresentationTests.swift`.

**Interfaces:** A lifecycle-layer factory creates sessions for managed local, remote, and pending boards, using the configured `HostedCoachingTurning` provider and the managed game UUID. `GameSession` accepts an optional explicit coaching game ID without changing random episode/request IDs. Existing standalone sessions retain their defaults.

- [ ] Write and run regressions for restored-game trace/provider identity and board isolation before adding the missing behavior.
- [ ] Cover remote-seat restrictions, locked invitations, move replay, captures, and invalid remote snapshots through real session/lifecycle code and transport test doubles only at the provider boundary.
- [ ] Wire initial launch and every board-opening path to those tested factories. Stop transient coaching when leaving a board and distinguish async task identity when sessions change.
- [ ] Run focused tests to green. Inspect merged coverage-mode removal and game controls for obsolete behavior.

### Task 3: Verify and deliver

**Files:** Integration report, current handoff reference, PR description; no prompt edits.

- [ ] Run full native and Python suites, Node review-tool tests if present, and inspect no skipped/failing tests.
- [ ] Review the integration diff independently, addressing significant findings with regression tests.
- [ ] Verify simulator navigation/new-game/reopen paths and final controls. Use deterministic coaching responses for automation; no paid model eval.
- [ ] Commit merge and integration fixes, push, and open a PR against main with verification and scope notes. Close #3 with a link to the replacement.
- [ ] Reload Coaching Smoke with the combined hosted-coaching build and report PR/test status; do not merge the final PR or delete old evidence/worktrees.

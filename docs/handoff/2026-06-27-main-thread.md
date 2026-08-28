# Main Thread Handoff - 2026-06-27

## Product Direction

Build a native iPad chess app for children learning through play. The MVP should feel like a physical chessboard with gentle guardrails, not a lesson product. Coaching mode, lessons, computer play, game review, accounts, sync, and online play are later layers.

## Current MVP Shape

- Local human-vs-human play on one iPad.
- Explicit `Done` button finishes a turn, so kids can move a piece, think, and put it back before committing.
- Board and pieces should behave physically: pieces drag, slide, shrink/grow into capture trays, and avoid jumps/snaps.
- Captured pieces are visible in side trays and animate into/out of those trays.
- UI is intentionally minimal: no title, no move list during play, no coaching mode, no flip-board button.
- New game is separated from per-turn controls and requires confirmation when abandoning a game.

## Interaction And UI Decisions

- The board stays in a stable physical location as the iPad rotates.
- Pieces rotate in place to stay upright for the current device orientation.
- The side/control area has three square-ish segments ordered message/done, captured trays, new game. In landscape they stack top-to-bottom; in portrait they run left-to-right. The segments animate when reordering.
- Turn text uses kid-friendly phrasing such as `White's turn`.
- Status and guidance messages are separate from the turn indicator.
- The message area should keep a stable width but shrink/expand vertically with minimal padding.

## Chess Rule Presentation

The app distinguishes two move concepts:

- Allowed movement: how a piece inherently moves, ignoring check safety.
- Legal movement: allowed movement filtered by king-safety rules.

Selection guidance should show allowed movement. A move that follows the piece's movement but leaves the king in check may be staged, but `Done` stays disabled and guidance explains the check issue.

For en passant, the helper indicators are:

- normal move dot on the empty landing square
- capture ring around the pawn that will actually be captured

Normal captures still show the capture ring on the destination square.

## Architecture Notes

- `Core` contains pure chess value types and rules.
- `GameSession` is the observable app model that SwiftUI talks to.
- UI should consume session presentation state rather than duplicating rule logic.
- `LegalMoveGenerator.allowedMoves` is the source for inherent piece movement.
- `LegalMoveGenerator.legalMoves` invokes `allowedMoves` and filters for check safety.

## Current Branch State

Primary working branch: `codex/chess-ui-polish`.

Recent checkpoints include:

- physical board orientation and sidebar behavior
- staged check-rule guidance
- en passant regression coverage
- en passant capture indicator UI
- Celtic vector piece set and warm side-panel visual polish

Tests were passing at the last checkpoint with:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Last observed result: 56 tests, 0 failures.

## Suggested Next Threads

- Promotion UX polish.
- Captured tray layout with more captured pieces.
- Game-review mode and move history reintroduction.
- Beginner explanation copy for check, checkmate, stalemate, castling, and en passant.
- App icon and visual asset refinement.
- Persistence/auto-resume once the play loop stabilizes.

## Workflow Recommendation

Use a fresh thread and isolated worktree per feature or bug. Start each new thread by reading this handoff plus the relevant spec/plan docs in `docs/superpowers/`, then run the baseline test suite before changing code.

## Collaboration Preference

- The product owner prefers browser mockups by default for UI and product-design discussions. Use them without the standard opt-in warning unless there is a concrete reason not to.

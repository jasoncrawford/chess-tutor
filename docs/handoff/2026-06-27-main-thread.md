# Main Thread Handoff - 2026-06-27

November 26 judgment experiment complete: a frozen 12-case eval measured the
unchanged coach first (30/36 useful), then prompt-only (35/36), then prompt plus
Stockfish (34/36, including two failed deliveries). Total conservative accounting
is $9.9870640 under the user-approved $11.50 cap, with unknown reservations retained.
See [the experiment report](../reports/2026-11-25-coaching-judgment.md) for evidence,
judge limitations and next steps. Nothing deployed; production and issue #29 are
unchanged. Broader regressions are needed before promoting the prompt.

November 25 arrow polish: coach arrows use one continuous outlined silhouette
and stop outside the destination ring, including its pulse. See [the arrow report](../reports/2026-11-25-coaching-arrow-polish.md).

November 25 follow-up: the board-answer banner now floats translucently across
the reader's top edge, using the existing gutter instead of shrinking or shifting
the board. Taps pass through it. See [the banner report](../reports/2026-11-25-floating-answer-banner.md).

November 22 follow-up: inline piece icons are restored as baseline-aligned native
text attachments. Show arrow is removed. Ordinary drafts say “Play this move”;
an illustrated alternative hides commit, and closing Help retains the draft.
Visual-v5 prefers descriptive noun-phrase links; eval checks pronoun links and
supplies actual controls to the judge. See [the follow-up report](../reports/2026-11-22-coaching-references-controls.md).
The earlier feedback details below are historical where superseded.

November 22 play-test feedback on PR #28: linked prose now uses native wrapping,
the draft action is “Play my move”, board-answer mode has an explicit banner,
pending answers use centered animated feedback, and replay is named “Show arrow”.
The banner's layout is retained during drag/drop to keep destinations stable.
Visual-v4 pins the matching control-name prompt correction; no paid model calls
or production rollout. See [the feedback report](../reports/2026-11-22-visual-coaching-feedback.md).

November 21 preview: `codex/visual-coaching` adds local tappable coach references,
directional arrows, and an explicit but quiet board-answer interaction. It includes
merged PR #27's debounce/logging. The new client requires the dual v3/v4 server;
do not install it against the production v3-only server. No production or Family
iPad rollout was done here. See [the preview report](../reports/2026-11-21-visual-coaching.md)
for validation, review fixes, and the Coaching Smoke launcher.

November 20 client change: coaching board updates use a tunable 400 ms debounce,
one in-flight call, and one replaceable pending update. Client interaction/timing
events are included in About → Share Diagnostics; see
[the hosted coaching runbook](../hosted-coaching-server.md#client-interaction-timing)
and [design](../superpowers/specs/2026-11-20-coaching-debounce-design.md).

## Latest integration checkpoint — 2026-11-08

November 18 update: PR #25 is merged at `eb15f4a`; the user confirmed coaching
works on Family iPad without a Mac server. An intermittent provider-timeout
investigation and scoped recovery changes are documented in
[the incident report](../reports/2026-11-18-coaching-timeout-investigation.md).

PR #24 merged the coaching branch with main's multiple-game library at
`cc6930b98404bcf90ed4df76f32e43a4cea9b659`. See [the integration report](../reports/2026-11-08-coaching-integration.md)
for the integrated architecture. Hosted family-device deployment is now on main
through PR #25; see [its report](../reports/2026-11-08-hosted-device-play.md)
for the live HTTPS server, verification evidence, and physical-iPad status.
The original MVP notes below are historical, not a description of current scope.

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

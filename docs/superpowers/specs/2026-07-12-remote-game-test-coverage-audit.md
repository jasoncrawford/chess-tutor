# Remote Game Test Coverage Audit

Date: 2026-07-12

## Scope

This audit covers automated test coverage for starting, joining, playing, ending, and restarting remote games.

The product surface has a combinatorial shape:

- A player can start from a fresh local board or from an existing game.
- A new game can stay local or become remote.
- A remote invite can target a known player or someone new.
- The inviter can choose to play White, have the invitee play White, or let the invitee choose.
- The invitee can join by code or link.
- An invite can arrive while the invitee is already in a game.
- Either side can accept, decline, start over, invite the same player again, invite someone else, or return to local play.

## Covered Well

Remote invite flow tests cover the pure invite state machine:

- Opening and canceling the remote play flow.
- Requiring a local player name before sending or joining.
- Creating pending invites for known players and new players.
- Creating pending invites for all three White assignment choices.
- Joining by code.
- Joining by link.
- Rejecting invalid links and unmatched invite links.
- Showing known players after a successful game.
- Keeping the remote play entry point available only before local play begins.

Remote invite transport tests cover the backend invariants:

- Invite creation and lookup.
- Token matching.
- Invite expiration.
- Fixed White assignment.
- Invitee-chosen White assignment.
- Rejection of incompatible chosen colors.
- Fetching accepted invites from the inviter side.
- Preventing double acceptance.
- The same behavior through the CloudKit-backed transport facade.

Remote game start tests cover conversion from an accepted invite into playable game state:

- Inviter and joiner color assignment.
- The inviter sees a start announcement after acceptance.
- The joiner starts directly after accepting.
- Start-announcement copy includes both players and colors.

Remote game session and transport tests cover active play:

- Remote move upload and fetch.
- Retrying local moves after upload failure.
- Restoring an active remote game and fetching missing moves.
- Rejecting local moves for the remote side.
- Allowing inspection of either player's pieces while only legal current-player moves can be committed.
- Locking a locally ended remote game so neither side can keep moving.
- Clearing the ended lock on a new local game.
- Remote game status updates, subscriptions, and presence.

New game confirmation tests cover the current presentation policy:

- No confirmation before any local or remote game exists.
- Confirmation for a local game in progress.
- Confirmation for an active remote game, including before the first move and after checkmate.
- No confirmation for a finished local game.

Diagnostics tests cover the debugging support needed for field reports:

- Stable device identity in exported logs.
- Plain-text export with timestamped events.

## Coverage Added In This Audit

The audit added focused tests for previously under-specified branches:

- Known-player versus new-player invite targets crossed with all three White assignment choices.
- Fixed White assignments accepting either no chosen color or a matching chosen color.
- The same fixed-assignment acceptance behavior through the CloudKit invite transport.
- Explicit new-game confirmation for local games in progress and remote games before the first move.

## Remaining Gaps

The largest remaining gap is not the transport layer. It is the high-level lifecycle orchestration currently embedded in `ContentView`.

The following product cases are only partially covered by lower-level tests or by manual device testing:

- Incoming invite while already in a local game.
- Incoming invite while already in a remote game.
- Declining an invite from the joiner side.
- Inviter canceling or abandoning an outstanding invite.
- Either remote player hitting New Game mid-game.
- Choosing same opponent, different opponent, or local play from the New Game prompt.
- The other player accepting or declining a restart invite.
- The other player seeing the old remote game become severed or locked after one side starts over with someone else.
- Link and code flows at the SwiftUI wiring level, including modal dismissal and popup sequencing.

These behaviors are risky because a single missed state reset can leave the board believing it is still remote while the UI looks local, or vice versa. The lower-level tests catch many invariants, but they cannot prove the view-driven sequence calls the right operations in the right order.

## Recommended Next Test Seam

Extract a small `RemoteGameLifecycleController` or `RemoteGameFlowCoordinator` from `ContentView`.

That object should own the app-level transitions, not chess rules or rendering:

- Present invite flow.
- Create invite.
- Accept invite.
- Decline invite.
- Start remote game.
- End remote game locally.
- Start local new game.
- Start remote new game with same player.
- Start remote new game with someone else.
- React to opponent acceptance, cancellation, or end status.

Once this exists, add table-driven tests for the lifecycle cases above. That will give us fast simulator-independent coverage for the combinatorial start/end matrix, while keeping CloudKit and device testing reserved for transport integration.

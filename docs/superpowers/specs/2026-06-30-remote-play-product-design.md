# Remote Play Product Design

## Purpose

Add private remote chess play so two known players can play together on separate iPads, especially a parent and child playing while apart.

The feature should preserve the app's core product intent: the main screen is still a playable board, learning happens through play, and remote play should feel like the same quiet physical board shared across distance. It should not become a public online chess platform.

## Product Scope

Remote play is private and invitation-based.

Included in the first version:

- One active game at a time, local or remote.
- Private remote games between two players.
- First-time pairing through a short-lived invite link or numeric code.
- Automatic saving of known players after the first accepted invite.
- Quick future games with known players.
- Synchronous-first play, with enough durability to survive sleep, app relaunch, network delay, and temporary offline state.
- Remote move notifications when useful.
- Simple presence for the current player only.

Excluded from the first version:

- Public matchmaking.
- Profile search, browsing, or discoverability.
- Public usernames or global accounts.
- Chat or free-text messaging.
- Multiple simultaneous active games.
- Remote game review, coaching, or social features.
- Sound effects for remote moves.

## Entry Model

The app still opens directly to a fresh playable board.

On a fresh board before any local move is made, the top panel shows a prominent remote-play action. The likely label is `Play Remotely`, though final wording can be refined later.

If the player starts playing locally, the remote-play action disappears and the game becomes a local human-vs-human game on one iPad.

If the player taps the remote-play action, a modal opens over the board. While this modal is open, the board is not playable. This keeps invite setup synchronous and avoids pending invites that might be accepted hours or days later.

The modal supports:

- Starting a game with a known player.
- Inviting someone new.
- Joining with a code.

The modal stays open until the invite is accepted, cancelled, or expires.

## First-Time Invite Flow

A first-time invite both starts a game and pairs the players for future games.

The inviting player chooses:

- Their display name if the app does not know it yet.
- Who plays White and moves first.
- How to share the invite.

The White assignment choices are:

- Me.
- The person I invite.
- Let them choose.

For a new invite, the invitee label can be "the person I invite" because the app does not know their display name yet.

The invite can be shared as:

- A link.
- A short numeric code.

The code should be easy to say over a call and type into another iPad. A six-digit code displayed in two groups, such as `428 913`, is the preferred first design.

Codes are short-lived and only valid while the invite modal is open. This makes random guessing impractical and keeps the product model synchronous.

When the invitee joins by link or code, the inviter's modal shows who wants to join. The game starts only after the inviter approves the join.

When the inviter approves:

- The game starts as a remote game.
- Each device saves the other participant as a known player.
- Each player lands on the board.

## Joining Flow

A player can join by opening a shared link or by entering the short code from the remote-play modal.

The accept screen tells the invitee who invited them and how White will be assigned:

- If the inviter chose themself as White, the invitee sees that the inviter will play White and move first.
- If the inviter chose the invitee as White, the invitee sees that they will play White and move first.
- If the inviter chose "let them choose", the invitee chooses who plays White before accepting.

If the app does not know the invitee's display name yet, it asks for a first name or handle during acceptance.

After the invitee confirms the join, they wait for the inviter to approve. This keeps a guessed or mistyped code from creating a game without the inviter's consent.

## Known Players

Known players are saved automatically after the first accepted invite.

There is no confirmation step for saving the known player. The escape hatch is deletion from the known-player list, likely through a standard swipe-to-delete interaction.

Known players are local/private app records, not public profiles.

Rules:

- No one appears in the known-player list except through a private accepted invite.
- There is no global username uniqueness.
- Two known players can have the same display name locally.
- There is no profile search, browsing, or discovery.
- A known-player relationship is pairwise, not a social graph.
- Deleting a known player removes them from future quick-start remote games.
- Existing finished or severed games do not need to be deleted automatically when a known player is deleted.

## Player Identity

There are no user accounts in the first version.

A game seat is bound to the app install that created or accepted that game. A stable local player identifier is generated on first run and stored in persistent local app storage. It is not a public profile, not searchable, and not meaningful to users.

If the user transfers app data to a new iPad, the local player identifier and known-player list should migrate with that app data so existing remote-play identity remains intact.

The player chooses a first name or handle during first remote use. The app should provide a way to edit this local display name later. Editing the name changes how this player is presented in future remote interactions; it does not create a public profile or searchable account.

Different devices are not treated as the same player unless they are explicitly invited into a game, in which case they are a different participant.

## Starting With Known Players

Starting with a known player should be low friction.

The player opens the remote-play modal, chooses a known player, chooses who plays White, and sends a synchronous game invite.

The invited known player receives a prompt to accept or decline the new game.

## One Active Game

The first version supports one active game at a time.

The app opens to the active board, whether local or remote. There is no game picker or game library in the first version.

This keeps the main screen focused on play and avoids turning the app into a lobby.

Future multi-game management can add a game picker later without changing the core move-log architecture.

## Turn Presentation

The headline remains chess-native:

- `White's turn`
- `Black's turn`

The secondary text is player-relative:

- If it is the local player's turn: `It's your move.`
- If waiting for the remote player: `Waiting for Maya to move.`

If the waiting player tries to move a piece, the app says:

- `It's not your turn.`

## Piece Inspection And Move Affordances

Any piece can be inspected in local and remote games.

Rules:

- Tapping any occupied square selects or highlights that piece.
- The app can show identity and movement guidance for any selected piece.
- Destination dots and capture rings only appear for pieces that can move right now.
- Only the active side, controlled by a local player who is allowed to act, can stage and commit a move.

This lets a child inspect their own or the opponent's pieces without being scolded, while keeping move-taking affordances clear.

## Remote Move Commit

The current `Done` model remains.

On the local player's remote turn:

1. The player moves a piece physically.
2. The board shows the tentative state.
3. `Done` commits the move locally.
4. Only the committed move is uploaded to the remote transport.

Tentative moves, dragging, and piece fiddling are local only. They are not synced.

## Remote Move Arrival

Remote moves should animate.

When the opponent commits a move:

- The receiving device applies the committed move event.
- The piece visibly moves from its source square to its destination square.
- Captures animate into the tray like local captures.
- Castling, promotion, and en passant use the same physical movement language as local play.
- The from and to squares can receive a brief quiet highlight.
- No sound is included in the first version.

The board should not appear to teleport into a new state.

## Sync Status

When sync is healthy, it should be mostly transparent.

After pressing `Done`:

- The move commits locally immediately.
- The turn changes locally to the opponent's turn.
- The app begins uploading in the background.

If upload succeeds quickly, no extra message is needed.

If upload takes longer than a short grace period, the app can show:

- `Sending your move...`

If offline or unable to upload, the app should be clear but calm:

- `Move saved. We'll send it when you're back online.`

While waiting for the opponent, the happy path remains:

- `Waiting for Maya to move.`

If the app cannot confidently receive updates:

- `Trying to check for Maya's move...`

If clearly offline:

- `You're offline. We'll check again when you're connected.`

Sync state is separate from game state. The board should keep the local committed move even if upload is delayed.

## Presence

Presence is shown only for the player whose turn it is.

Presence should describe observable app state only. It should not claim that someone is thinking, looking, or considering a move.

States:

- `activeMoving`: the current player is selecting, dragging, staging, unstaging, or otherwise interacting with movable pieces.
- `foregroundIdle`: the current player has the app open in the foreground but is not currently moving.
- `away`: the current player's app is backgrounded, asleep, or has stopped heartbeating for a grace period.

Displayed from the waiting player's perspective:

- `Maya is moving...`
- `Waiting for Maya to move.`
- `Maya is away from the board.`

The moving state should be debounced so it does not flicker on and off.

Presence is best effort. Move sync remains the source of truth.

## Notifications

Remote move notifications are in scope if they remain straightforward with the chosen transport.

Notifications are not required for correctness. Opening the app always fetches and replays the latest move log.

Notification rules:

- Ask for notification permission during the first remote game flow.
- If permission is denied, remote play still works in-app.
- Notifications only come from accepted games with known or invited players.
- Notifications contain no free text from other users.
- Tapping a notification opens the active board.

Example copy:

- `Maya moved White queen to e4. Your turn.`

The notification payload may include a summary, but the app trusts fetched move events, not the notification body.

## Board Orientation

Board orientation is local-only.

For the White player, board orientation behaves the same way the local board orientation works today.

For the Black player, board orientation is the opposite of the White/local orientation. This keeps the Black player's own pieces closest to them at game start and continues to work consistently in portrait and landscape.

Device rotation can change the local viewing angle. Orientation is never synced between devices.

Move coordinates remain canonical internally, and remote move animations map canonical squares into the local board orientation.

## New Game And Ending Remote Games

Exact button labels can be refined later, but the concepts are:

- Start a replacement game with the same remote player.
- Leave the current remote game and return to a fresh inviteable local board.
- Cancel and keep playing the current game.

When starting a replacement game with the same remote player:

- The current game remains intact while the replacement invite is pending.
- If the opponent accepts, both boards reset into the new remote game.
- If the opponent declines, neither board resets and the current game remains.

When leaving the remote game to start a fresh local/inviteable board:

- The local board resets immediately.
- The remote link is severed.
- The opponent's board does not reset automatically.
- The opponent is notified that the other player ended the game.
- The opponent can no longer move pieces in that ended remote game.
- The opponent must start a new game to play more.

## Game Over

Checkmate and stalemate still use normal game result copy.

After a remote game ends naturally, a simple play-again path with the same known player should be available. The play-again request follows the same accept/decline replacement-game behavior as starting a new game with the same opponent.

## Conflict And Error Handling

Chess is naturally close to conflict-free because only one seat can legally move at a time.

If the app detects that a remote game cannot be synced safely, the user-facing conflict path should be rare and plain:

- `Something went wrong syncing this game.`

The app should stop the affected remote game rather than trying to improvise a repair in the UI. Technical validation, retry, deduping, and versioning details belong in the technical architecture design.

## Technical Direction To Finish Next

These product decisions assume a transport abstraction so CloudKit can be replaced by a custom server later.

The technical architecture still needs a follow-up design covering:

- CloudKit data model.
- App-managed invite records.
- Known-player record shape.
- Remote game and move event schema.
- Presence channel.
- Notification subscription approach.
- Local persistence and outbox.
- Local player identifier persistence and migration with app data.
- Move validation, retry, deduping, missing-event recovery, and protocol version handling.
- `RemoteGameTransport` interface.
- How `GameSession` consumes remote state without duplicating chess rules in SwiftUI.

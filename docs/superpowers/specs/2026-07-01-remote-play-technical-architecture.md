# Remote Play Technical Architecture

## Purpose

Define the technical architecture for private remote chess play, building on the product decisions in `2026-06-30-remote-play-product-design.md`.

The architecture should make remote play feel synchronous when both players are present, remain durable through sleep or network interruptions, and keep CloudKit replaceable by a future custom server.

## Design Principles

- Keep chess rules in `Core`.
- Keep SwiftUI focused on presentation and interaction.
- Keep `GameSession` focused on game flow and board presentation state.
- Treat remote sync as an additive layer over local play.
- Persist committed local moves before attempting upload.
- Sync immutable move events, not mutable board state.
- Do not expose CloudKit types outside the transport implementation.
- Keep public CloudKit data minimal and temporary.
- Treat notifications and presence as convenience channels, not correctness mechanisms.

## Module Layout

Add a new `Remote` area:

```text
ChessTutor/
  Core/
  Game/
  Remote/
    RemoteGameCoordinator.swift
    RemoteGameTransport.swift
    RemoteModels.swift
    RemotePersistence.swift
    RemoteMoveCodec.swift
    RemoteSyncState.swift
    CloudKit/
      CloudKitRemoteGameTransport.swift
      CloudKitRecordCodec.swift
```

`Core` remains pure chess logic. It knows nothing about remote play, CloudKit, persistence, notifications, or presence.

`Game` remains the app-facing game model. It may expose remote-aware presentation inputs such as player seats and turn permissions, but it should not perform CloudKit work.

`Remote` owns remote game lifecycle, local remote-play persistence, move event encoding, sync state, outbox processing, invite flow state, presence, notifications, and transport abstraction.

`Remote/CloudKit` is the only area that imports CloudKit.

## Runtime Ownership

Use three cooperating objects:

```text
GameSession
  Owns current GameState, tentative moves, committed local play flow,
  captured pieces, guidance text, and board-facing presentation state.

RemoteGameCoordinator
  Owns remote lifecycle, active remote game metadata, local move log,
  outbox, sync state, presence, notifications, and transport calls.

RemoteGameTransport
  Owns the concrete network/backend implementation.
```

The app root wires `GameSession` and `RemoteGameCoordinator` together.

`GameSession` emits committed local moves. `RemoteGameCoordinator` persists and uploads those moves when the active game is remote.

`RemoteGameCoordinator` receives remote moves from the transport, validates/replays them through `Core`, and asks `GameSession` to apply accepted committed remote moves through an explicit remote-commit path.

`GameSession` should not know whether the transport is CloudKit or a custom server.

## Local-First State

Remote play should work as a local-first move log with sync layered on top.

Local persistence stores:

- local player profile:
  - `localPlayerID`
  - display name
- known players:
  - known player ID
  - display name
  - transport address/reference
  - last played metadata
- active game reference:
  - game ID
  - local seat color
  - remote player display name
  - remote game status
- local move log:
  - all committed moves for the active game
  - sequence numbers
  - sender IDs
  - sync status
- outbox:
  - committed local moves not yet confirmed by transport
- sync status:
  - last successful fetch
  - last successful upload
  - receive health
  - send health

For V1, prefer a small Codable file store in Application Support for active game state, known players, move log, and outbox. Use `UserDefaults` only for tiny settings or bootstrapping values when appropriate. The data size is small, one active game is supported, and a file-backed repository is straightforward to test.

The local player ID is generated on first run and stored in persistent app data. It should migrate with normal app data transfer/backup.

## Remote Game Transport Interface

The transport protocol should expose product concepts, not CloudKit concepts.

Suggested shape:

```swift
protocol RemoteGameTransport {
    func createInvite(_ request: CreateInviteRequest) async throws -> PendingInvite
    func observeInvite(_ inviteID: RemoteInviteID) -> AsyncStream<InviteUpdate>
    func joinInvite(using code: InviteCode, joiner: JoinerInfo) async throws -> JoinInviteResult
    func joinInvite(using token: InviteToken, joiner: JoinerInfo) async throws -> JoinInviteResult
    func approveJoin(_ approval: JoinApproval) async throws -> RemoteGameDescriptor
    func declineJoin(_ inviteID: RemoteInviteID) async throws
    func cancelInvite(_ inviteID: RemoteInviteID) async throws

    func createReplacementGame(_ request: ReplacementGameRequest) async throws -> RemoteGameDescriptor
    func respondToReplacementGame(_ response: ReplacementGameResponse) async throws -> RemoteGameDescriptor?
    func endGame(_ gameID: RemoteGameID, reason: RemoteGameEndReason) async throws

    func sendMove(_ event: RemoteMoveEvent) async throws -> RemoteMoveAck
    func fetchMoves(gameID: RemoteGameID, after sequence: Int) async throws -> [RemoteMoveEvent]
    func observeGame(_ gameID: RemoteGameID) -> AsyncStream<RemoteGameUpdate>

    func updatePresence(_ presence: PresenceUpdate) async throws
}
```

Concrete implementation names and method grouping can change during implementation, but the boundary should remain app-shaped.

No caller outside `Remote/CloudKit` should see `CKRecord`, `CKShare`, `CKDatabase`, or CloudKit errors directly.

## Invite Rendezvous

Use app-managed invites.

First-time and known-player invites use a short-lived pending invite. The invite is synchronous: the inviter keeps the modal open until the invite is accepted, cancelled, declined, or expired.

CloudKit implementation direction:

- Store `PendingInvite` as a minimal public-database rendezvous record if native CloudKit permissions support the required lookup flow.
- Use native CloudKit only.
- Do not create CloudKit Web Services tokens.
- Do not ship a server-to-server key in the app.
- Keep pending invite data minimal and non-sensitive.

`PendingInvite` fields:

```text
inviteID
shortCode
linkToken
expiresAt
inviterPlayerID
inviterDisplayName
whiteAssignment
protocolVersion
status
joinerDisplayName?
joinerPlayerID?
```

The short code can be six numeric digits displayed in two groups. It is valid only while the inviter's modal remains open and until `expiresAt`.

The link carries a longer random token. Link-based joining should use the token, not only the short code.

No manual code-attempt throttling is required in V1. The safety model is short expiry, minimal data, native app access, and inviter approval before the game is created.

## Accepted Game Storage

Preferred direction: use `CKShare` for accepted game records if a spike confirms it can support the desired UX.

CloudKit storage split:

```text
PendingInvite
  Minimal app-managed rendezvous data.

Shared RemoteGame records
  Private to the accepted participants through CKShare if viable.

Local storage
  Resume cache, known players, local identity, move log, outbox.
```

The app should never store actual move history or durable player relationships in public invite records.

If `CKShare` cannot support the intended flow without intrusive UI or permission limitations, revisit the backend choice before implementing remote play. Do not silently fall back to public game records without an explicit design decision.

## CKShare Spike Requirements

Before implementation planning, build a small spike to answer:

- Can the app create and accept the share through the app-managed invite flow?
- Does the user see generic iCloud sharing UI?
- Can the invitee join via code/link without receiving a separate Apple share invitation?
- Can both participants create `MoveEvent` records under the accepted game?
- Do record-change notifications/subscriptions work for the shared records?
- Can the app observe or poll shared game changes reliably after app relaunch?
- Can the CloudKit-specific identifiers be hidden behind `RemoteGameTransport`?
- What CloudKit account/sign-in errors must the product handle?

The spike should not implement the full chess feature. It only needs enough records and UI scaffolding to validate sharing, writes, reads, subscriptions, and relaunch behavior.

## Remote Game Records

The logical remote game model should be independent of CloudKit.

`RemoteGame`:

```text
gameID
protocolVersion
createdAt
status: pending | active | ended | error
whitePlayerID
blackPlayerID
whiteDisplayName
blackDisplayName
createdByPlayerID
lastAppliedSequence
endedReason?
```

`RemoteMoveEvent`:

```text
eventID
gameID
sequenceNumber
actorPlayerID
move
createdAt
protocolVersion
previousPositionFingerprint
resultingPositionFingerprint
notificationSummary
```

`move` should encode the canonical `Move` data:

```text
from
to
special: none | castleKingside | castleQueenside | enPassant | promotion(kind)
```

`PositionFingerprint` is a deterministic consistency check, not a security primitive. It should be derived from canonical chess state, including board contents, side to move, castling rights, en passant target, result, and move history length or sequence.

## Move Sequencing And Idempotency

Move sequence starts at 1 and increments by 1 for each committed move.

Only the player whose turn it is can create the next move event.

The local sender computes:

- expected next sequence
- previous position fingerprint
- resulting position fingerprint

Send retries are idempotent by `gameID + sequenceNumber + actorPlayerID`. If the same event is observed twice and the payload matches, treat it as already accepted.

If the same identity attempts a different payload for an already accepted sequence, treat it as a serious sync error.

## Validation And Recovery

Sender path:

1. `GameSession` validates and commits the move locally.
2. `RemoteGameCoordinator` appends the move to the local log.
3. The move enters the outbox.
4. The outbox uploads through the transport.
5. On acknowledgment, the move is marked uploaded.

Receiver path:

1. Fetch or observe remote move events after the last applied sequence.
2. Sort by sequence.
3. If the next event is missing, fetch the missing range.
4. Validate actor, sequence, previous fingerprint, and legal move from projected state.
5. Apply the move through `Core`.
6. Verify resulting fingerprint.
7. Deliver accepted remote move to `GameSession` for board animation/presentation.

If recovery fetches cannot produce a valid contiguous log, stop the affected remote game and surface the product error:

```text
Something went wrong syncing this game.
```

Do not merge divergent board states.

## Outbox And Sync State

Outbox states:

```text
pendingUpload
uploading
uploaded
failedRetrying
offlineQueued
```

Receive states:

```text
current
checking
stale
offline
failed
```

The coordinator maps these states to the product copy defined in the product design.

Upload retry uses backoff and resumes on app foreground, network availability, and new local commits. Exact retry timing can be tuned during implementation.

The UI should not show a sync warning until a grace period has elapsed or an explicit offline/error state is known.

## Presence

Presence is separate from move correctness.

`PresenceUpdate`:

```text
gameID
playerID
state: activeMoving | foregroundIdle | away
updatedAt
expiresAt
```

Presence updates may be lost, stale, or delayed. The UI should fall back to ordinary waiting copy if presence is unavailable.

`activeMoving` should be debounced locally before publishing so the waiting player's display does not flicker.

Presence should only be displayed for the player whose turn it is.

## Notifications

Notifications are hints, not source of truth.

Remote move notifications should include enough copy to be useful, but tapping or receiving a notification should trigger a fetch from the canonical move log before applying anything.

Suggested notification source:

- A `notificationSummary` field on `RemoteMoveEvent`, generated by the sender from local move context.

Notification body example:

```text
Maya moved White queen to e4. Your turn.
```

If CloudKit record notifications cannot use the exact desired copy, prefer correctness and quiet fallback over adding server infrastructure solely for notification wording.

## GameSession Integration

`GameSession` needs remote-aware capabilities without depending on remote infrastructure.

Likely additions:

- player seats that can represent local human or remote human.
- a way to ask whether the local user can act for the current side.
- a remote-commit path for accepted remote moves.
- presentation inputs for remote status text.
- inspection behavior that allows any piece to be selected while only movable active-side pieces show destination affordances.

`GameSession` should continue to use `LegalMoveGenerator` and `GameState` for rule decisions.

Remote move application should use the same core move semantics as local commits, while allowing the UI to animate a move that originated remotely.

## Persistence Technology Decision

Use repository protocols so implementation can change without affecting game flow:

```text
LocalPlayerStore
KnownPlayerStore
ActiveRemoteGameStore
RemoteMoveLogStore
RemoteOutboxStore
```

V1 implementation:

- `UserDefaults` for small local profile/settings values when sufficient.
- Codable JSON files in Application Support for known players, active game, move log, and outbox.

Do not introduce Core Data or SwiftData solely for one active game unless implementation proves JSON files are inadequate.

## Testing Strategy

Core tests remain the highest priority for chess rules.

Add focused tests for:

- move event encoding/decoding.
- position fingerprint determinism.
- outbox retry/idempotency behavior.
- receiver validation and missing-event recovery.
- invalid remote move stopping the game.
- known-player persistence.
- invite state machine.
- `GameSession` turn permissions for local and remote seats.
- inspection without move affordances for non-acting pieces.

Use an in-memory `RemoteGameTransport` fake for coordinator tests.

CloudKit tests should be limited to integration/spike coverage because they require Apple services and entitlements.

## Open Risks

- CKShare may force UX or permission flows that conflict with the product design.
- CloudKit shared-record subscriptions may not provide the notification behavior we want.
- iCloud account availability and parental device settings may need product handling.
- JSON persistence may need migration support once remote game history expands beyond one active game.

## Decisions To Revisit After CKShare Spike

- Whether CKShare is viable for accepted game records.
- Whether notifications need a different mechanism.
- Whether invite records need a different CloudKit location or a small custom server.
- Whether known-player transport references are stable enough across reinstall/data transfer.
- Whether the transport interface needs separate invite and game transports.

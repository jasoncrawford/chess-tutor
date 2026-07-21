# Remote Game Coordinator Design

## Purpose

Build the next remote-play slice without making CloudKit part of daily iteration. The coordinator should connect the existing remote move models, move-log validator, outbox, and fake transport so sync behavior can be tested quickly in XCTest and Simulator.

## Testing Strategy

Most remote-play work should stay testable without iCloud:

- Pure unit tests cover move encoding, fingerprints, validation, and outbox behavior.
- Coordinator tests use `InMemoryRemoteGameTransport` to simulate two players and transport acknowledgments.
- Simulator/manual testing can later use a DEBUG-only fake remote lab.
- CloudKit testing remains a thin adapter smoke test on physical devices.

CloudKit should not be imported by this slice. If trying remote behavior becomes slow or annoying, stop and reassess before adding more CloudKit-dependent workflow.

## Coordinator Scope

Add `RemoteGameCoordinator` as a headless remote-play state owner. It should not update SwiftUI directly, persist files, create invites, or call CloudKit. Its job is to:

- hold the active `RemoteGameDescriptor`;
- hold the projected `GameState`;
- hold accepted move events;
- hold a `RemoteOutbox`;
- track the last applied sequence;
- convert a committed local `Move` into a `RemoteMoveEvent`;
- upload pending local events through `RemoteGameTransport`;
- fetch remote events and validate them through `RemoteMoveLog`.

The coordinator owns remote sync state. `GameSession` remains the board-facing model and still owns tentative local interactions. Later slices can wire the coordinator to `GameSession` and persistence once the sync contract is stable.

## Data Flow

### Local move

1. `GameSession` commits a legal local move and returns the `Move`.
2. The app calls `RemoteGameCoordinator.recordLocalMove`.
3. The coordinator computes the previous and resulting position fingerprints.
4. The coordinator creates a `RemoteMoveEvent` for the local player and next sequence.
5. The event is appended to accepted events and queued in the outbox.
6. `uploadPendingMoves` sends queued events and marks exact acknowledgments uploaded.

### Remote move

1. `fetchAndApplyRemoteMoves` asks the transport for events after `lastAppliedSequence`.
2. `RemoteMoveLog` validates ordering, game ID, protocol version, actor, fingerprints, and move legality from the current projected state.
3. On success, the coordinator appends accepted events, updates projected state, and advances `lastAppliedSequence`.
4. On failure, the coordinator preserves its previous state and records a sync error.

## Errors

Use a small coordinator-owned error enum:

- `transportFailed`
- `moveLogRejected`
- `localMoveRejected`

This keeps tests deterministic and avoids leaking transport-specific errors. Later product UI can map these states to user-facing sync messages.

## Out Of Scope

- CloudKit adapter.
- Invite or short-code UI.
- Local JSON persistence.
- Notifications and presence.
- Remote move animation in `GameSession`.
- App-root wiring.

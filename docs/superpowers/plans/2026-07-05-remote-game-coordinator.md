# Remote Game Coordinator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a headless `RemoteGameCoordinator` that can record local committed moves, upload them through the fake transport, and fetch validated remote moves without CloudKit.

**Architecture:** Keep the coordinator in `ChessTutor/Remote`, depending only on existing core/game value types and the `RemoteGameTransport` protocol. The coordinator owns projected remote state, accepted events, outbox, last applied sequence, and deterministic sync status. UI wiring, persistence, invites, notifications, presence, and CloudKit stay out of this slice.

**Tech Stack:** Swift 6, XCTest, XcodeGen source autodiscovery, native iOS target.

---

## Scope

Included:

- `RemoteGameCoordinator`.
- Coordinator-owned sync status and deterministic error state.
- Tests using `InMemoryRemoteGameTransport`.
- A small transport test helper for injecting remote events.

Not included:

- CloudKit adapter.
- Invite UI or debug remote lab UI.
- Local file persistence.
- App-root wiring.
- Remote move animation path in `GameSession`.

## File Structure

- Create `ChessTutor/Remote/RemoteGameCoordinator.swift`
  - Owns active remote game sync state and coordinates local move recording, outbox upload, and remote fetch validation.
- Modify `ChessTutor/Remote/RemoteGameTransport.swift`
  - Add a DEBUG/test-friendly helper on `InMemoryRemoteGameTransport` for seeding remote events through the same storage path.
- Create `ChessTutorTests/Remote/RemoteGameCoordinatorTests.swift`
  - Covers local event creation, outbox upload, remote fetch projection, and invalid remote event handling.

## Task 1: Coordinator Local Move Recording

**Files:**
- Create: `ChessTutor/Remote/RemoteGameCoordinator.swift`
- Test: `ChessTutorTests/Remote/RemoteGameCoordinatorTests.swift`
- Modify: `ChessTutor.xcodeproj/project.pbxproj` via `xcodegen generate`

- [ ] **Step 1: Write failing local move coordinator tests**

Create `ChessTutorTests/Remote/RemoteGameCoordinatorTests.swift`:

```swift
import XCTest
@testable import ChessTutor

final class RemoteGameCoordinatorTests: XCTestCase {
    private let gameID = RemoteGameID(rawValue: "game-1")
    private let whiteID = RemotePlayerID(rawValue: "white")
    private let blackID = RemotePlayerID(rawValue: "black")

    func testRecordLocalMoveCreatesAcceptedEventAndQueuesOutbox() throws {
        var coordinator = makeCoordinator(localPlayerID: whiteID)
        let move = Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4))

        let event = try coordinator.recordLocalMove(move, createdAt: Date(timeIntervalSince1970: 10))

        XCTAssertEqual(event.gameID, gameID)
        XCTAssertEqual(event.sequenceNumber, 1)
        XCTAssertEqual(event.actorPlayerID, whiteID)
        XCTAssertEqual(event.move, RemoteMoveCodec.encode(move))
        XCTAssertEqual(event.previousPositionFingerprint, PositionFingerprinting.fingerprint(for: .startingPosition()))
        XCTAssertEqual(coordinator.lastAppliedSequence, 1)
        XCTAssertEqual(coordinator.acceptedEvents, [event])
        XCTAssertEqual(coordinator.outbox.items, [RemoteOutboxItem(event: event, state: .pendingUpload)])
        XCTAssertEqual(coordinator.projectedState.board[Square(file: .e, rank: 4)], Piece(kind: .pawn, color: .white))
    }

    func testRejectsLocalMoveFromRemoteSide() {
        var coordinator = makeCoordinator(localPlayerID: blackID)
        let move = Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4))

        XCTAssertThrowsError(try coordinator.recordLocalMove(move, createdAt: Date(timeIntervalSince1970: 10))) { error in
            XCTAssertEqual(error as? RemoteGameCoordinator.Error, .localMoveRejected)
        }
        XCTAssertEqual(coordinator.lastAppliedSequence, 0)
        XCTAssertTrue(coordinator.acceptedEvents.isEmpty)
        XCTAssertTrue(coordinator.outbox.items.isEmpty)
        XCTAssertEqual(coordinator.syncStatus, .failed(.localMoveRejected))
    }

    private func makeCoordinator(localPlayerID: RemotePlayerID) -> RemoteGameCoordinator {
        RemoteGameCoordinator(
            descriptor: RemoteGameDescriptor(
                id: gameID,
                protocolVersion: 1,
                status: .active,
                whitePlayer: RemotePlayerRef(id: whiteID, displayName: "White"),
                blackPlayer: RemotePlayerRef(id: blackID, displayName: "Black"),
                localPlayerID: localPlayerID
            ),
            transport: InMemoryRemoteGameTransport(),
            initialState: .startingPosition()
        )
    }
}
```

- [ ] **Step 2: Run coordinator tests and verify they fail**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/RemoteGameCoordinatorTests
```

Expected: fails because `RemoteGameCoordinator` does not exist.

- [ ] **Step 3: Add coordinator implementation for local moves**

Create `ChessTutor/Remote/RemoteGameCoordinator.swift`:

```swift
import Foundation

struct RemoteGameCoordinator {
    enum Error: Swift.Error, Equatable {
        case transportFailed
        case moveLogRejected
        case localMoveRejected
    }

    enum SyncStatus: Equatable {
        case current
        case uploading
        case fetching
        case failed(Error)
    }

    private let descriptor: RemoteGameDescriptor
    private let transport: any RemoteGameTransport
    private(set) var projectedState: GameState
    private(set) var acceptedEvents: [RemoteMoveEvent]
    private(set) var outbox: RemoteOutbox
    private(set) var lastAppliedSequence: Int
    private(set) var syncStatus: SyncStatus

    init(
        descriptor: RemoteGameDescriptor,
        transport: any RemoteGameTransport,
        initialState: GameState,
        acceptedEvents: [RemoteMoveEvent] = [],
        outbox: RemoteOutbox = RemoteOutbox(),
        lastAppliedSequence: Int = 0
    ) {
        self.descriptor = descriptor
        self.transport = transport
        self.projectedState = initialState
        self.acceptedEvents = acceptedEvents
        self.outbox = outbox
        self.lastAppliedSequence = lastAppliedSequence
        self.syncStatus = .current
    }

    @discardableResult
    mutating func recordLocalMove(
        _ move: Move,
        createdAt: Date = Date()
    ) throws -> RemoteMoveEvent {
        let localPlayerID = descriptor.localPlayerID
        guard localPlayerID == expectedActor(for: projectedState.sideToMove),
              LegalMoveGenerator.allLegalMoves(in: projectedState).contains(move) else {
            syncStatus = .failed(.localMoveRejected)
            throw Error.localMoveRejected
        }

        let previousFingerprint = PositionFingerprinting.fingerprint(for: projectedState)
        var resultingState = projectedState
        resultingState.apply(move)
        let resultingFingerprint = PositionFingerprinting.fingerprint(for: resultingState)

        let event = RemoteMoveEvent(
            id: RemoteMoveEventID(rawValue: "\(descriptor.id.rawValue)-\(lastAppliedSequence + 1)-\(localPlayerID.rawValue)"),
            gameID: descriptor.id,
            sequenceNumber: lastAppliedSequence + 1,
            actorPlayerID: localPlayerID,
            move: RemoteMoveCodec.encode(move),
            createdAt: createdAt,
            protocolVersion: descriptor.protocolVersion,
            previousPositionFingerprint: previousFingerprint,
            resultingPositionFingerprint: resultingFingerprint,
            notificationSummary: notificationSummary(for: move, in: projectedState)
        )

        projectedState = resultingState
        acceptedEvents.append(event)
        outbox.append(event)
        lastAppliedSequence = event.sequenceNumber
        syncStatus = .current
        return event
    }

    private func expectedActor(for color: PieceColor) -> RemotePlayerID {
        switch color {
        case .white:
            return descriptor.whitePlayer.id
        case .black:
            return descriptor.blackPlayer.id
        }
    }

    private func notificationSummary(for move: Move, in state: GameState) -> String {
        guard let piece = state.board[move.from] else {
            return "Move"
        }
        return "\(piece.color.rawValue.capitalized) \(piece.kind.rawValue) to \(RemoteMoveCodec.encodeSquare(move.to))"
    }
}
```

- [ ] **Step 4: Regenerate the Xcode project**

Run:

```bash
xcodegen generate
```

Expected: `ChessTutor.xcodeproj/project.pbxproj` changes to include the new coordinator and tests.

- [ ] **Step 5: Run coordinator tests and verify they pass**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/RemoteGameCoordinatorTests
```

Expected: `RemoteGameCoordinatorTests` executes 2 tests with 0 failures.

- [ ] **Step 6: Commit**

```bash
git add ChessTutor/Remote/RemoteGameCoordinator.swift ChessTutorTests/Remote/RemoteGameCoordinatorTests.swift ChessTutor.xcodeproj/project.pbxproj
git commit -m "Add remote game coordinator local moves"
```

## Task 2: Coordinator Outbox Upload

**Files:**
- Modify: `ChessTutor/Remote/RemoteGameCoordinator.swift`
- Modify: `ChessTutorTests/Remote/RemoteGameCoordinatorTests.swift`

- [ ] **Step 1: Add failing upload test**

Append this test to `RemoteGameCoordinatorTests`:

```swift
func testUploadPendingMovesMarksAcknowledgedEventUploaded() async throws {
    var coordinator = makeCoordinator(localPlayerID: whiteID)
    let move = Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4))
    let event = try coordinator.recordLocalMove(move, createdAt: Date(timeIntervalSince1970: 10))

    try await coordinator.uploadPendingMoves()

    XCTAssertEqual(coordinator.outbox.items, [RemoteOutboxItem(event: event, state: .uploaded)])
    XCTAssertEqual(coordinator.syncStatus, .current)
}
```

- [ ] **Step 2: Run coordinator tests and verify they fail**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/RemoteGameCoordinatorTests
```

Expected: fails because `uploadPendingMoves` does not exist.

- [ ] **Step 3: Implement upload**

Add this method to `RemoteGameCoordinator`:

```swift
mutating func uploadPendingMoves() async throws {
    syncStatus = .uploading

    do {
        for event in outbox.pendingEvents {
            try outbox.markUploading(event.id)
            let ack = try await transport.sendMove(event)
            try outbox.markUploaded(ack)
        }
        syncStatus = .current
    } catch {
        syncStatus = .failed(.transportFailed)
        throw Error.transportFailed
    }
}
```

- [ ] **Step 4: Run coordinator tests and verify they pass**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/RemoteGameCoordinatorTests
```

Expected: `RemoteGameCoordinatorTests` executes 3 tests with 0 failures.

- [ ] **Step 5: Commit**

```bash
git add ChessTutor/Remote/RemoteGameCoordinator.swift ChessTutorTests/Remote/RemoteGameCoordinatorTests.swift
git commit -m "Upload remote coordinator outbox"
```

## Task 3: Coordinator Remote Fetch

**Files:**
- Modify: `ChessTutor/Remote/RemoteGameCoordinator.swift`
- Modify: `ChessTutor/Remote/RemoteGameTransport.swift`
- Modify: `ChessTutorTests/Remote/RemoteGameCoordinatorTests.swift`

- [ ] **Step 1: Add failing remote fetch tests**

Append these helpers and tests to `RemoteGameCoordinatorTests`:

```swift
func testFetchAndApplyRemoteMoveAdvancesProjectedState() async throws {
    let transport = InMemoryRemoteGameTransport()
    var coordinator = RemoteGameCoordinator(
        descriptor: descriptor(localPlayerID: whiteID),
        transport: transport,
        initialState: .startingPosition()
    )
    let localMove = Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4))
    _ = try coordinator.recordLocalMove(localMove, createdAt: Date(timeIntervalSince1970: 10))
    let remoteMove = Move(from: Square(file: .e, rank: 7), to: Square(file: .e, rank: 5))
    let remoteEvent = makeEvent(
        sequence: 2,
        actor: blackID,
        move: remoteMove,
        from: coordinator.projectedState
    )
    await transport.storeForTesting(remoteEvent)

    let fetched = try await coordinator.fetchAndApplyRemoteMoves()

    XCTAssertEqual(fetched, [remoteEvent])
    XCTAssertEqual(coordinator.lastAppliedSequence, 2)
    XCTAssertEqual(coordinator.acceptedEvents.last, remoteEvent)
    XCTAssertEqual(coordinator.projectedState.board[Square(file: .e, rank: 5)], Piece(kind: .pawn, color: .black))
    XCTAssertEqual(coordinator.syncStatus, .current)
}

func testInvalidFetchedMoveDoesNotMutateCoordinatorState() async throws {
    let transport = InMemoryRemoteGameTransport()
    var coordinator = RemoteGameCoordinator(
        descriptor: descriptor(localPlayerID: whiteID),
        transport: transport,
        initialState: .startingPosition()
    )
    let invalidEvent = makeEvent(
        sequence: 2,
        actor: blackID,
        move: Move(from: Square(file: .e, rank: 7), to: Square(file: .e, rank: 5)),
        from: coordinator.projectedState
    )
    await transport.storeForTesting(invalidEvent)

    do {
        _ = try await coordinator.fetchAndApplyRemoteMoves()
        XCTFail("Expected fetch to reject the non-contiguous event.")
    } catch {
        XCTAssertEqual(error as? RemoteGameCoordinator.Error, .moveLogRejected)
    }

    XCTAssertEqual(coordinator.lastAppliedSequence, 0)
    XCTAssertTrue(coordinator.acceptedEvents.isEmpty)
    XCTAssertEqual(coordinator.projectedState, GameState.startingPosition())
    XCTAssertEqual(coordinator.syncStatus, .failed(.moveLogRejected))
}

private func descriptor(localPlayerID: RemotePlayerID) -> RemoteGameDescriptor {
    RemoteGameDescriptor(
        id: gameID,
        protocolVersion: 1,
        status: .active,
        whitePlayer: RemotePlayerRef(id: whiteID, displayName: "White"),
        blackPlayer: RemotePlayerRef(id: blackID, displayName: "Black"),
        localPlayerID: localPlayerID
    )
}

private func makeEvent(
    sequence: Int,
    actor: RemotePlayerID,
    move: Move,
    from state: GameState
) -> RemoteMoveEvent {
    var next = state
    next.apply(move)
    return RemoteMoveEvent(
        id: RemoteMoveEventID(rawValue: "event-\(sequence)"),
        gameID: gameID,
        sequenceNumber: sequence,
        actorPlayerID: actor,
        move: RemoteMoveCodec.encode(move),
        createdAt: Date(timeIntervalSince1970: Double(sequence)),
        protocolVersion: 1,
        previousPositionFingerprint: PositionFingerprinting.fingerprint(for: state),
        resultingPositionFingerprint: PositionFingerprinting.fingerprint(for: next),
        notificationSummary: "Move \(sequence)"
    )
}
```

Update `makeCoordinator(localPlayerID:)` to call `descriptor(localPlayerID:)`:

```swift
private func makeCoordinator(localPlayerID: RemotePlayerID) -> RemoteGameCoordinator {
    RemoteGameCoordinator(
        descriptor: descriptor(localPlayerID: localPlayerID),
        transport: InMemoryRemoteGameTransport(),
        initialState: .startingPosition()
    )
}
```

- [ ] **Step 2: Run coordinator tests and verify they fail**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/RemoteGameCoordinatorTests
```

Expected: fails because `storeForTesting` and `fetchAndApplyRemoteMoves` do not exist.

- [ ] **Step 3: Add fake transport test seeding helper**

Add this method to `InMemoryRemoteGameTransport`:

```swift
#if DEBUG
func storeForTesting(_ event: RemoteMoveEvent) {
    var events = eventsByGame[event.gameID, default: []]
    events.removeAll { $0.sequenceNumber == event.sequenceNumber }
    events.append(event)
    events.sort { $0.sequenceNumber < $1.sequenceNumber }
    eventsByGame[event.gameID] = events
}
#endif
```

- [ ] **Step 4: Add coordinator fetch implementation**

Add this method to `RemoteGameCoordinator`:

```swift
@discardableResult
mutating func fetchAndApplyRemoteMoves() async throws -> [RemoteMoveEvent] {
    syncStatus = .fetching

    let fetchedEvents: [RemoteMoveEvent]
    do {
        fetchedEvents = try await transport.fetchMoves(
            gameID: descriptor.id,
            after: lastAppliedSequence
        )
    } catch {
        syncStatus = .failed(.transportFailed)
        throw Error.transportFailed
    }

    guard !fetchedEvents.isEmpty else {
        syncStatus = .current
        return []
    }

    do {
        let result = try RemoteMoveLog.apply(
            events: fetchedEvents,
            to: projectedState,
            gameID: descriptor.id,
            protocolVersion: descriptor.protocolVersion,
            whitePlayerID: descriptor.whitePlayer.id,
            blackPlayerID: descriptor.blackPlayer.id,
            startingAfter: lastAppliedSequence
        )

        acceptedEvents.append(contentsOf: fetchedEvents.sorted { $0.sequenceNumber < $1.sequenceNumber })
        projectedState = result.state
        lastAppliedSequence = result.lastAppliedSequence
        syncStatus = .current
        return fetchedEvents
    } catch {
        syncStatus = .failed(.moveLogRejected)
        throw Error.moveLogRejected
    }
}
```

- [ ] **Step 5: Run coordinator tests and verify they pass**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/RemoteGameCoordinatorTests
```

Expected: `RemoteGameCoordinatorTests` executes 5 tests with 0 failures.

- [ ] **Step 6: Commit**

```bash
git add ChessTutor/Remote/RemoteGameCoordinator.swift ChessTutor/Remote/RemoteGameTransport.swift ChessTutorTests/Remote/RemoteGameCoordinatorTests.swift
git commit -m "Fetch remote coordinator moves"
```

## Task 4: Verification

**Files:**
- No new files.

- [ ] **Step 1: Run focused remote tests**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/RemoteGameCoordinatorTests -only-testing:ChessTutorTests/InMemoryRemoteGameTransportTests -only-testing:ChessTutorTests/RemoteMoveLogTests
```

Expected: all focused remote tests pass.

- [ ] **Step 2: Run full test suite**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Expected: all tests pass with zero failures.

- [ ] **Step 3: Check architecture boundaries**

Run:

```bash
rg "import CloudKit|CKRecord|CKShare|CKContainer" ChessTutor/Remote ChessTutor/Game ChessTutor/Core
rg "import SwiftUI|import UIKit" ChessTutor/Remote
```

Expected: no matches from either command.

- [ ] **Step 4: Check git hygiene**

Run:

```bash
git diff --check
git status --short
```

Expected: `git diff --check` exits 0. `git status --short` is clean after commits.

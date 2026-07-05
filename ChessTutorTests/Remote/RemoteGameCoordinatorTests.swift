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

    func testUploadPendingMovesMarksAcknowledgedEventUploaded() async throws {
        var coordinator = makeCoordinator(localPlayerID: whiteID)
        let move = Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4))
        let event = try coordinator.recordLocalMove(move, createdAt: Date(timeIntervalSince1970: 10))

        try await coordinator.uploadPendingMoves()

        XCTAssertEqual(coordinator.outbox.items, [RemoteOutboxItem(event: event, state: .uploaded)])
        XCTAssertEqual(coordinator.syncStatus, .current)
    }

    func testUploadPendingMoveFailureLeavesEventRetryableForLaterUpload() async throws {
        let transport = FailOnceRemoteGameTransport()
        var coordinator = makeCoordinator(localPlayerID: whiteID, transport: transport)
        let move = Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4))
        let event = try coordinator.recordLocalMove(move, createdAt: Date(timeIntervalSince1970: 10))

        do {
            try await coordinator.uploadPendingMoves()
            XCTFail("Expected first upload to fail.")
        } catch {
            XCTAssertEqual(error as? RemoteGameCoordinator.Error, .transportFailed)
        }

        XCTAssertEqual(coordinator.outbox.items, [RemoteOutboxItem(event: event, state: .failedRetrying)])
        XCTAssertEqual(coordinator.syncStatus, .failed(.transportFailed))

        try await coordinator.uploadPendingMoves()

        XCTAssertEqual(coordinator.outbox.items, [RemoteOutboxItem(event: event, state: .uploaded)])
        XCTAssertEqual(coordinator.syncStatus, .current)
    }

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

    private func makeCoordinator(
        localPlayerID: RemotePlayerID,
        transport: any RemoteGameTransport = InMemoryRemoteGameTransport()
    ) -> RemoteGameCoordinator {
        RemoteGameCoordinator(
            descriptor: descriptor(localPlayerID: localPlayerID),
            transport: transport,
            initialState: .startingPosition()
        )
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
}

private actor FailOnceRemoteGameTransport: RemoteGameTransport {
    private let backing = InMemoryRemoteGameTransport()
    private var shouldFailNextSend = true

    func sendMove(_ event: RemoteMoveEvent) async throws -> RemoteMoveAck {
        if shouldFailNextSend {
            shouldFailNextSend = false
            throw Error.intentionalFailure
        }
        return try await backing.sendMove(event)
    }

    func fetchMoves(gameID: RemoteGameID, after sequenceNumber: Int) async throws -> [RemoteMoveEvent] {
        try await backing.fetchMoves(gameID: gameID, after: sequenceNumber)
    }

    enum Error: Swift.Error {
        case intentionalFailure
    }
}

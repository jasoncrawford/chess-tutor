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

import XCTest
@testable import ChessTutor

final class InMemoryRemoteGameTransportTests: XCTestCase {
    func testSendMoveStoresMoveAndReturnsAck() async throws {
        let transport = InMemoryRemoteGameTransport()
        let event = makeEvent(sequence: 1)

        let ack = try await transport.sendMove(event)
        let fetched = try await transport.fetchMoves(gameID: event.gameID, after: 0)

        XCTAssertEqual(ack, RemoteMoveAck(eventID: event.id, gameID: event.gameID, sequenceNumber: 1))
        XCTAssertEqual(fetched, [event])
    }

    func testFetchMovesOnlyReturnsEventsAfterSequence() async throws {
        let transport = InMemoryRemoteGameTransport()
        let first = makeEvent(sequence: 1)
        let second = makeEvent(sequence: 2)
        _ = try await transport.sendMove(first)
        _ = try await transport.sendMove(second)

        let fetched = try await transport.fetchMoves(gameID: first.gameID, after: 1)

        XCTAssertEqual(fetched, [second])
    }

    func testUpdateGameStatusCanBeFetched() async throws {
        let transport = InMemoryRemoteGameTransport()
        let status = RemoteGameStatusUpdate(
            gameID: RemoteGameID(rawValue: "game"),
            status: .ended,
            updatedByPlayerID: RemotePlayerID(rawValue: "player"),
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        try await transport.updateGameStatus(status)

        let fetchedStatus = try await transport.fetchGameStatus(gameID: RemoteGameID(rawValue: "game"))
        XCTAssertEqual(fetchedStatus, status)
    }

    func testUpdatePresenceCanBeFetchedForCurrentPlayer() async throws {
        let transport = InMemoryRemoteGameTransport()
        let presence = RemotePresenceUpdate(
            gameID: RemoteGameID(rawValue: "game"),
            playerID: RemotePlayerID(rawValue: "maya"),
            state: .activeMoving,
            updatedAt: Date(timeIntervalSince1970: 40),
            expiresAt: Date(timeIntervalSince1970: 45)
        )

        try await transport.updatePresence(presence)

        let fetchedPresence = try await transport.fetchPresence(
            gameID: RemoteGameID(rawValue: "game"),
            playerID: RemotePlayerID(rawValue: "maya")
        )
        XCTAssertEqual(fetchedPresence, presence)
    }

    func testOlderPresenceDoesNotOverwriteNewerPresence() async throws {
        let transport = InMemoryRemoteGameTransport()
        let newerPresence = RemotePresenceUpdate(
            gameID: RemoteGameID(rawValue: "game"),
            playerID: RemotePlayerID(rawValue: "maya"),
            state: .foregroundIdle,
            updatedAt: Date(timeIntervalSince1970: 50),
            expiresAt: Date(timeIntervalSince1970: 60)
        )
        let olderPresence = RemotePresenceUpdate(
            gameID: RemoteGameID(rawValue: "game"),
            playerID: RemotePlayerID(rawValue: "maya"),
            state: .activeMoving,
            updatedAt: Date(timeIntervalSince1970: 40),
            expiresAt: Date(timeIntervalSince1970: 45)
        )

        try await transport.updatePresence(newerPresence)
        try await transport.updatePresence(olderPresence)

        let fetchedPresence = try await transport.fetchPresence(
            gameID: RemoteGameID(rawValue: "game"),
            playerID: RemotePlayerID(rawValue: "maya")
        )
        XCTAssertEqual(fetchedPresence, newerPresence)
    }

    private func makeEvent(sequence: Int) -> RemoteMoveEvent {
        RemoteMoveEvent(
            id: RemoteMoveEventID(rawValue: "event-\(sequence)"),
            gameID: RemoteGameID(rawValue: "game"),
            sequenceNumber: sequence,
            actorPlayerID: RemotePlayerID(rawValue: "player"),
            move: RemoteMoveCodec.encode(Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4))),
            createdAt: Date(timeIntervalSince1970: Double(sequence)),
            protocolVersion: 1,
            previousPositionFingerprint: PositionFingerprint(rawValue: "before-\(sequence)"),
            resultingPositionFingerprint: PositionFingerprint(rawValue: "after-\(sequence)"),
            notificationSummary: "Move \(sequence)"
        )
    }
}

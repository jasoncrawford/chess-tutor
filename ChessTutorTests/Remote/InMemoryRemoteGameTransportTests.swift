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

import XCTest
@testable import ChessTutor

final class RemoteOutboxTests: XCTestCase {
    func testStartsWithPendingEvent() {
        let event = makeEvent(sequence: 1)
        let outbox = RemoteOutbox(events: [event])

        XCTAssertEqual(outbox.items, [RemoteOutboxItem(event: event, state: .pendingUpload)])
    }

    func testMarksMatchingAckUploaded() throws {
        let event = makeEvent(sequence: 1)
        var outbox = RemoteOutbox(events: [event])

        try outbox.markUploaded(RemoteMoveAck(eventID: event.id, gameID: event.gameID, sequenceNumber: event.sequenceNumber))

        XCTAssertEqual(outbox.items.first?.state, .uploaded)
    }

    func testRejectsMismatchedAck() {
        let event = makeEvent(sequence: 1)
        var outbox = RemoteOutbox(events: [event])

        XCTAssertThrowsError(try outbox.markUploaded(RemoteMoveAck(
            eventID: RemoteMoveEventID(rawValue: "other"),
            gameID: event.gameID,
            sequenceNumber: event.sequenceNumber
        ))) { error in
            XCTAssertEqual(error as? RemoteOutbox.Error, .missingEvent(RemoteMoveEventID(rawValue: "other")))
        }
    }

    private func makeEvent(sequence: Int) -> RemoteMoveEvent {
        RemoteMoveEvent(
            id: RemoteMoveEventID(rawValue: "event-\(sequence)"),
            gameID: RemoteGameID(rawValue: "game"),
            sequenceNumber: sequence,
            actorPlayerID: RemotePlayerID(rawValue: "white"),
            move: RemoteMoveCodec.encode(Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4))),
            createdAt: Date(timeIntervalSince1970: Double(sequence)),
            protocolVersion: 1,
            previousPositionFingerprint: PositionFingerprint(rawValue: "before"),
            resultingPositionFingerprint: PositionFingerprint(rawValue: "after"),
            notificationSummary: "White pawn to e4"
        )
    }
}

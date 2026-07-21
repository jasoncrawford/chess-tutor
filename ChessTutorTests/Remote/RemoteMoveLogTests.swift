import XCTest
@testable import ChessTutor

final class RemoteMoveLogTests: XCTestCase {
    private let gameID = RemoteGameID(rawValue: "game-1")
    private let whiteID = RemotePlayerID(rawValue: "white")
    private let blackID = RemotePlayerID(rawValue: "black")

    func testAppliesValidMoveEvent() throws {
        let state = GameState.startingPosition()
        let move = Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4))
        let event = makeEvent(sequence: 1, actor: whiteID, move: move, from: state)

        let result = try RemoteMoveLog.apply(
            events: [event],
            to: state,
            gameID: gameID,
            protocolVersion: 1,
            whitePlayerID: whiteID,
            blackPlayerID: blackID
        )

        XCTAssertEqual(result.state.board[Square(file: .e, rank: 4)], Piece(kind: .pawn, color: .white))
        XCTAssertEqual(result.lastAppliedSequence, 1)
    }

    func testRejectsMissingSequence() {
        let state = GameState.startingPosition()
        let move = Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4))
        let event = makeEvent(sequence: 2, actor: whiteID, move: move, from: state)

        XCTAssertThrowsError(try RemoteMoveLog.apply(
            events: [event],
            to: state,
            gameID: gameID,
            protocolVersion: 1,
            whitePlayerID: whiteID,
            blackPlayerID: blackID
        )) { error in
            XCTAssertEqual(error as? RemoteMoveLog.Error, .unexpectedSequence(expected: 1, actual: 2))
        }
    }

    func testRejectsWrongActorForTurn() {
        let state = GameState.startingPosition()
        let move = Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4))
        let event = makeEvent(sequence: 1, actor: blackID, move: move, from: state)

        XCTAssertThrowsError(try RemoteMoveLog.apply(
            events: [event],
            to: state,
            gameID: gameID,
            protocolVersion: 1,
            whitePlayerID: whiteID,
            blackPlayerID: blackID
        )) { error in
            XCTAssertEqual(error as? RemoteMoveLog.Error, .wrongActor(expected: whiteID, actual: blackID))
        }
    }

    func testRejectsWrongGame() {
        let state = GameState.startingPosition()
        let move = Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4))
        let otherGameID = RemoteGameID(rawValue: "game-2")
        let event = makeEvent(sequence: 1, actor: whiteID, move: move, from: state, gameID: otherGameID)

        XCTAssertThrowsError(try RemoteMoveLog.apply(
            events: [event],
            to: state,
            gameID: gameID,
            protocolVersion: 1,
            whitePlayerID: whiteID,
            blackPlayerID: blackID
        )) { error in
            XCTAssertEqual(error as? RemoteMoveLog.Error, .wrongGame(expected: gameID, actual: otherGameID))
        }
    }

    func testRejectsUnsupportedProtocolVersion() {
        let state = GameState.startingPosition()
        let move = Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4))
        let event = makeEvent(sequence: 1, actor: whiteID, move: move, from: state, protocolVersion: 2)

        XCTAssertThrowsError(try RemoteMoveLog.apply(
            events: [event],
            to: state,
            gameID: gameID,
            protocolVersion: 1,
            whitePlayerID: whiteID,
            blackPlayerID: blackID
        )) { error in
            XCTAssertEqual(error as? RemoteMoveLog.Error, .unsupportedProtocolVersion(2))
        }
    }

    private func makeEvent(
        sequence: Int,
        actor: RemotePlayerID,
        move: Move,
        from state: GameState,
        gameID: RemoteGameID? = nil,
        protocolVersion: Int = 1
    ) -> RemoteMoveEvent {
        var next = state
        next.apply(move)
        return RemoteMoveEvent(
            id: RemoteMoveEventID(rawValue: "event-\(sequence)"),
            gameID: gameID ?? self.gameID,
            sequenceNumber: sequence,
            actorPlayerID: actor,
            move: RemoteMoveCodec.encode(move),
            createdAt: Date(timeIntervalSince1970: Double(sequence)),
            protocolVersion: protocolVersion,
            previousPositionFingerprint: PositionFingerprinting.fingerprint(for: state),
            resultingPositionFingerprint: PositionFingerprinting.fingerprint(for: next),
            notificationSummary: "Test move"
        )
    }
}

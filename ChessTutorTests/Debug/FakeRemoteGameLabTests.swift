import XCTest
@testable import ChessTutor

#if DEBUG
@MainActor
final class FakeRemoteGameLabTests: XCTestCase {
    func testStartConfiguresRemoteSeats() {
        let session = GameSession()
        let lab = FakeRemoteGameLab()

        lab.start(session: session)

        XCTAssertTrue(lab.isActive)
        XCTAssertEqual(session.whitePlayer, .humanLocal)
        XCTAssertEqual(session.blackPlayer, .remote(playerID: "maya"))
        XCTAssertEqual(lab.statusText, "Fake remote game")
    }

    func testStartCanMakeRemotePlayerWhite() {
        let session = GameSession()
        let lab = FakeRemoteGameLab()

        lab.start(session: session, localPlayerColor: .black)

        XCTAssertTrue(lab.isActive)
        XCTAssertEqual(session.whitePlayer, .remote(playerID: "maya"))
        XCTAssertEqual(session.blackPlayer, .humanLocal)
        XCTAssertTrue(lab.canRemotePlay)
    }

    func testRemotePlaysNextMoveAfterLocalCommit() async throws {
        let session = GameSession()
        let lab = FakeRemoteGameLab()
        lab.start(session: session)

        session.select(Square(file: .e, rank: 2))
        _ = session.moveSelectedPiece(to: Square(file: .e, rank: 4))
        guard let committedMove = session.finishTurn() else {
            XCTFail("Expected the local move to commit.")
            return
        }
        try await lab.recordCommittedLocalMove(committedMove)

        let didMove = try await lab.remotePlaysNextMove(session: session)

        XCTAssertTrue(didMove)
        XCTAssertEqual(session.state.sideToMove, .white)
        XCTAssertEqual(lab.statusText, "Maya moved")
        XCTAssertEqual(lab.lastRemoteMove, Move(from: Square(file: .e, rank: 7), to: Square(file: .e, rank: 5)))
        XCTAssertEqual(session.state.board[Square(file: .e, rank: 5)], Piece(kind: .pawn, color: .black))
    }

    func testRestartingFakeGameDoesNotReplayMovesFromPreviousFakeGame() async throws {
        let session = GameSession()
        let lab = FakeRemoteGameLab()
        lab.start(session: session)

        session.select(Square(file: .e, rank: 2))
        _ = session.moveSelectedPiece(to: Square(file: .e, rank: 4))
        guard let committedMove = session.finishTurn() else {
            XCTFail("Expected the local move to commit.")
            return
        }
        try await lab.recordCommittedLocalMove(committedMove)
        _ = try await lab.remotePlaysNextMove(session: session)
        lab.stop(session: session)

        lab.start(session: session, localPlayerColor: .black)
        let didMove = try await lab.remotePlaysNextMove(session: session)

        XCTAssertTrue(didMove)
        XCTAssertEqual(session.state.sideToMove, .black)
        XCTAssertEqual(lab.statusText, "Maya moved")
        XCTAssertEqual(lab.lastRemoteMove, Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4)))
        XCTAssertEqual(session.state.board[Square(file: .e, rank: 4)], Piece(kind: .pawn, color: .white))
        XCTAssertNil(session.state.board[Square(file: .e, rank: 2)])
    }
}
#endif

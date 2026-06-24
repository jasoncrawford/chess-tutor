import XCTest
@testable import ChessTutor

final class GameSessionTests: XCTestCase {
    func testSelectingCurrentPlayersPieceExposesLegalDestinations() {
        let session = GameSession()

        session.select(Square(file: .e, rank: 2))

        XCTAssertEqual(session.selectedSquare, Square(file: .e, rank: 2))
        XCTAssertTrue(session.legalDestinations.contains(Square(file: .e, rank: 3)))
        XCTAssertTrue(session.legalDestinations.contains(Square(file: .e, rank: 4)))
    }

    func testIllegalMoveReturnsFriendlyMessage() {
        let session = GameSession()

        session.select(Square(file: .e, rank: 2))
        let result = session.moveSelectedPiece(to: Square(file: .e, rank: 5))

        XCTAssertEqual(result, .illegal("That piece can't move there."))
        XCTAssertEqual(session.state.sideToMove, .white)
    }

    func testLegalMoveAdvancesTurn() {
        let session = GameSession()

        session.select(Square(file: .e, rank: 2))
        let result = session.moveSelectedPiece(to: Square(file: .e, rank: 4))

        XCTAssertEqual(result, .moved)
        XCTAssertEqual(session.state.sideToMove, .black)
    }
}

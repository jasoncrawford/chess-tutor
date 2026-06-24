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
        XCTAssertEqual(session.message, "That piece can't move there.")
        XCTAssertEqual(session.state.sideToMove, .white)
    }

    func testPromotionRequestClearsStaleIllegalMoveMessage() {
        let promotionFrom = Square(file: .e, rank: 7)
        let promotionTo = Square(file: .e, rank: 8)
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        promotionFrom: Piece(kind: .pawn, color: .white),
                        Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                        Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white
            )
        )

        session.select(promotionFrom)
        _ = session.moveSelectedPiece(to: Square(file: .e, rank: 6))
        let result = session.moveSelectedPiece(to: promotionTo)

        XCTAssertEqual(result, .needsPromotion(from: promotionFrom, to: promotionTo))
        XCTAssertNil(session.message)
    }

    func testLegalMoveAdvancesTurn() {
        let session = GameSession()

        session.select(Square(file: .e, rank: 2))
        let result = session.moveSelectedPiece(to: Square(file: .e, rank: 4))

        XCTAssertEqual(result, .moved)
        XCTAssertEqual(session.state.sideToMove, .black)
    }
}

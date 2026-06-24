import XCTest
@testable import ChessTutor

final class LegalMoveGeneratorTests: XCTestCase {
    func testWhitePawnCanMoveOneOrTwoFromStartingRank() {
        let state = GameState.startingPosition()
        let moves = LegalMoveGenerator.legalMoves(for: Square(file: .e, rank: 2), in: state)

        XCTAssertTrue(moves.contains(Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 3))))
        XCTAssertTrue(moves.contains(Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4))))
    }

    func testKnightCanJumpFromStartingPosition() {
        let state = GameState.startingPosition()
        let moves = LegalMoveGenerator.legalMoves(for: Square(file: .g, rank: 1), in: state)

        XCTAssertEqual(Set(moves.map(\.to)), [
            Square(file: .f, rank: 3),
            Square(file: .h, rank: 3)
        ])
    }

    func testSlidingPieceStopsAtFriendlyPiece() {
        let state = GameState.startingPosition()
        let moves = LegalMoveGenerator.legalMoves(for: Square(file: .c, rank: 1), in: state)

        XCTAssertTrue(moves.isEmpty)
    }

    func testCannotCaptureOwnPiece() {
        let state = GameState.startingPosition()
        let moves = LegalMoveGenerator.legalMoves(for: Square(file: .e, rank: 1), in: state)

        XCTAssertFalse(moves.contains(Move(from: Square(file: .e, rank: 1), to: Square(file: .e, rank: 2))))
    }
}

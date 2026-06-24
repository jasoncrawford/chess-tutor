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

    func testMoveThatExposesOwnKingIsIllegal() {
        var board = Board()
        board[Square(file: .e, rank: 1)] = Piece(kind: .king, color: .white)
        board[Square(file: .e, rank: 2)] = Piece(kind: .rook, color: .white)
        board[Square(file: .e, rank: 8)] = Piece(kind: .rook, color: .black)
        board[Square(file: .a, rank: 8)] = Piece(kind: .king, color: .black)
        let state = GameState(board: board, sideToMove: .white)

        let moves = LegalMoveGenerator.legalMoves(for: Square(file: .e, rank: 2), in: state)

        XCTAssertFalse(moves.contains(Move(from: Square(file: .e, rank: 2), to: Square(file: .d, rank: 2))))
    }

    func testKingInCheckCanCaptureCheckingPiece() {
        var board = Board()
        board[Square(file: .e, rank: 1)] = Piece(kind: .king, color: .white)
        board[Square(file: .e, rank: 2)] = Piece(kind: .rook, color: .black)
        board[Square(file: .a, rank: 8)] = Piece(kind: .king, color: .black)
        let state = GameState(board: board, sideToMove: .white)

        let moves = LegalMoveGenerator.legalMoves(for: Square(file: .e, rank: 1), in: state)

        XCTAssertTrue(moves.contains(Move(from: Square(file: .e, rank: 1), to: Square(file: .e, rank: 2))))
    }

    func testCheckmateResultAfterMove() {
        var board = Board()
        board[Square(file: .h, rank: 1)] = Piece(kind: .king, color: .white)
        board[Square(file: .f, rank: 2)] = Piece(kind: .queen, color: .black)
        board[Square(file: .a, rank: 8)] = Piece(kind: .king, color: .black)
        board[Square(file: .h, rank: 7)] = Piece(kind: .rook, color: .black)
        var state = GameState(board: board, sideToMove: .black)

        state.apply(Move(from: Square(file: .h, rank: 7), to: Square(file: .h, rank: 2)))

        XCTAssertEqual(state.result, .checkmate(winner: .black))
    }
}

import XCTest
@testable import ChessTutor

final class GameStateTests: XCTestCase {
    func testApplySetsCheckmateForBlackWin() {
        var state = GameState(
            board: Board(
                pieces: [
                    Square(file: .h, rank: 1): Piece(kind: .king, color: .white),
                    Square(file: .g, rank: 1): Piece(kind: .rook, color: .white),
                    Square(file: .f, rank: 2): Piece(kind: .queen, color: .black),
                    Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                    Square(file: .h, rank: 7): Piece(kind: .rook, color: .black),
                ]
            ),
            sideToMove: .black
        )

        state.apply(Move(from: Square(file: .h, rank: 7), to: Square(file: .h, rank: 2)))

        XCTAssertEqual(state.result, .checkmate(winner: .black))
        XCTAssertEqual(state.sideToMove, .white)
    }

    func testApplySetsStalemateWhenNextPlayerHasNoLegalMovesAndIsNotInCheck() {
        var state = GameState(
            board: Board(
                pieces: [
                    Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
                    Square(file: .g, rank: 6): Piece(kind: .king, color: .white),
                    Square(file: .f, rank: 6): Piece(kind: .queen, color: .white),
                ]
            ),
            sideToMove: .white
        )

        state.apply(Move(from: Square(file: .f, rank: 6), to: Square(file: .f, rank: 7)))

        XCTAssertEqual(state.result, .stalemate)
        XCTAssertEqual(state.sideToMove, .black)
    }
}

import XCTest
@testable import ChessTutor

final class BoardTests: XCTestCase {
    func testStartingPositionHasExpectedPieces() {
        let board = Board.startingPosition()

        XCTAssertEqual(board[Square(file: .e, rank: 1)]?.kind, .king)
        XCTAssertEqual(board[Square(file: .e, rank: 1)]?.color, .white)
        XCTAssertEqual(board[Square(file: .d, rank: 8)]?.kind, .queen)
        XCTAssertEqual(board[Square(file: .d, rank: 8)]?.color, .black)
        XCTAssertEqual(board.pieces.count, 32)
    }

    func testSquareOffsetsRejectBoardEdges() {
        let a1 = Square(file: .a, rank: 1)

        XCTAssertNil(a1.offset(fileDelta: -1, rankDelta: 0))
        XCTAssertNil(a1.offset(fileDelta: 0, rankDelta: -1))
        XCTAssertEqual(a1.offset(fileDelta: 1, rankDelta: 1), Square(file: .b, rank: 2))
    }
}

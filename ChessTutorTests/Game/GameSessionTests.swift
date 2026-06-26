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

    func testPromotionMoveRequestsPromotionChoice() {
        var board = Board()
        board[Square(file: .e, rank: 7)] = Piece(kind: .pawn, color: .white)
        board[Square(file: .e, rank: 1)] = Piece(kind: .king, color: .white)
        board[Square(file: .a, rank: 8)] = Piece(kind: .king, color: .black)
        let session = GameSession(state: GameState(board: board, sideToMove: .white))

        session.select(Square(file: .e, rank: 7))
        let result = session.moveSelectedPiece(to: Square(file: .e, rank: 8))

        XCTAssertEqual(result, .needsPromotion(from: Square(file: .e, rank: 7), to: Square(file: .e, rank: 8)))
    }

    func testPromoteAppliesPromotionChoiceAndClearsSelection() {
        let promotionFrom = Square(file: .e, rank: 7)
        let promotionTo = Square(file: .e, rank: 8)
        var board = Board()
        board[promotionFrom] = Piece(kind: .pawn, color: .white)
        board[Square(file: .e, rank: 1)] = Piece(kind: .king, color: .white)
        board[Square(file: .a, rank: 8)] = Piece(kind: .king, color: .black)
        let session = GameSession(state: GameState(board: board, sideToMove: .white))

        session.select(promotionFrom)
        session.message = "Choose a promotion piece."
        session.promote(from: promotionFrom, to: promotionTo, to: .knight)

        XCTAssertEqual(session.state.board[promotionTo], Piece(kind: .knight, color: .white))
        XCTAssertNil(session.state.board[promotionFrom])
        XCTAssertEqual(session.state.sideToMove, .black)
        XCTAssertNil(session.selectedSquare)
        XCTAssertTrue(session.legalMovesForSelection.isEmpty)
        XCTAssertNil(session.message)
    }

    func testLegalMoveAdvancesTurn() {
        let session = GameSession()

        session.select(Square(file: .e, rank: 2))
        let result = session.moveSelectedPiece(to: Square(file: .e, rank: 4))

        XCTAssertEqual(result, .moved)
        XCTAssertEqual(session.state.sideToMove, .black)
    }

    func testHiddenLegalMoveHintsDoNotBlockLegalMoveExecution() {
        let session = GameSession()
        session.assistSettings.showLegalMovesOnSelection = false

        session.select(Square(file: .e, rank: 2))

        XCTAssertTrue(session.legalDestinations.isEmpty)

        let result = session.moveSelectedPiece(to: Square(file: .e, rank: 4))

        XCTAssertEqual(result, .moved)
        XCTAssertEqual(session.state.board[Square(file: .e, rank: 4)], Piece(kind: .pawn, color: .white))
        XCTAssertNil(session.state.board[Square(file: .e, rank: 2)])
    }

    func testCheckmateMoveShowsGameOverMessageAndBlocksFurtherSelection() {
        var board = Board()
        board[Square(file: .h, rank: 1)] = Piece(kind: .king, color: .white)
        board[Square(file: .g, rank: 1)] = Piece(kind: .rook, color: .white)
        board[Square(file: .f, rank: 2)] = Piece(kind: .queen, color: .black)
        board[Square(file: .a, rank: 8)] = Piece(kind: .king, color: .black)
        board[Square(file: .h, rank: 7)] = Piece(kind: .rook, color: .black)
        let session = GameSession(state: GameState(board: board, sideToMove: .black))

        session.select(Square(file: .h, rank: 7))
        let result = session.moveSelectedPiece(to: Square(file: .h, rank: 2))

        XCTAssertEqual(result, .moved)
        XCTAssertEqual(session.state.result, .checkmate(winner: .black))
        XCTAssertEqual(session.message, "Checkmate. Black wins.")

        session.select(Square(file: .g, rank: 1))

        XCTAssertNil(session.selectedSquare)
        XCTAssertEqual(session.message, "Checkmate. Black wins.")
    }

    func testMoveAttemptAfterCheckmateKeepsGameOverMessage() {
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        Square(file: .h, rank: 1): Piece(kind: .king, color: .white),
                        Square(file: .g, rank: 1): Piece(kind: .rook, color: .white),
                        Square(file: .f, rank: 2): Piece(kind: .queen, color: .black),
                        Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white,
                result: .checkmate(winner: .black)
            )
        )

        session.select(Square(file: .g, rank: 1))
        let result = session.moveSelectedPiece(to: Square(file: .g, rank: 2))

        XCTAssertEqual(result, .illegal("Checkmate. Black wins."))
        XCTAssertNil(session.selectedSquare)
        XCTAssertTrue(session.legalMovesForSelection.isEmpty)
        XCTAssertEqual(session.message, "Checkmate. Black wins.")
    }

    func testStalemateStatusAndSelectionAreTerminal() {
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
                        Square(file: .g, rank: 6): Piece(kind: .king, color: .white),
                        Square(file: .f, rank: 7): Piece(kind: .queen, color: .white),
                    ]
                ),
                sideToMove: .black,
                result: .stalemate
            )
        )

        XCTAssertEqual(session.statusText, "Stalemate.")

        session.select(Square(file: .h, rank: 8))
        let result = session.moveSelectedPiece(to: Square(file: .g, rank: 8))

        XCTAssertEqual(result, .illegal("Stalemate."))
        XCTAssertNil(session.selectedSquare)
        XCTAssertTrue(session.legalMovesForSelection.isEmpty)
        XCTAssertEqual(session.message, "Stalemate.")
    }
}

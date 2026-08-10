import XCTest
@testable import ChessTutor

final class SpecialMoveTests: XCTestCase {
    func testKingsideCastlingWhenPathIsClear() {
        var board = Board()
        board[Square(file: .e, rank: 1)] = Piece(kind: .king, color: .white)
        board[Square(file: .h, rank: 1)] = Piece(kind: .rook, color: .white)
        board[Square(file: .e, rank: 8)] = Piece(kind: .king, color: .black)
        let state = GameState(
            board: board,
            sideToMove: .white,
            castlingRights: CastlingRights(
                whiteKingside: true,
                whiteQueenside: true,
                blackKingside: true,
                blackQueenside: true
            )
        )

        let moves = LegalMoveGenerator.legalMoves(for: Square(file: .e, rank: 1), in: state)

        XCTAssertTrue(moves.contains(Move(from: Square(file: .e, rank: 1), to: Square(file: .g, rank: 1), special: .castleKingside)))
    }

    func testCustomBoardDoesNotCastleWithoutExplicitRights() {
        var board = Board()
        board[Square(file: .e, rank: 1)] = Piece(kind: .king, color: .white)
        board[Square(file: .h, rank: 1)] = Piece(kind: .rook, color: .white)
        board[Square(file: .e, rank: 8)] = Piece(kind: .king, color: .black)
        let state = GameState(board: board, sideToMove: .white)

        let moves = LegalMoveGenerator.legalMoves(for: Square(file: .e, rank: 1), in: state)

        XCTAssertFalse(moves.contains(Move(from: Square(file: .e, rank: 1), to: Square(file: .g, rank: 1), special: .castleKingside)))
    }

    func testPromotionMoveIncludesQueenChoice() {
        var board = Board()
        board[Square(file: .e, rank: 7)] = Piece(kind: .pawn, color: .white)
        board[Square(file: .e, rank: 1)] = Piece(kind: .king, color: .white)
        board[Square(file: .a, rank: 8)] = Piece(kind: .king, color: .black)
        let state = GameState(board: board, sideToMove: .white)

        let moves = LegalMoveGenerator.legalMoves(for: Square(file: .e, rank: 7), in: state)

        XCTAssertTrue(moves.contains(Move(from: Square(file: .e, rank: 7), to: Square(file: .e, rank: 8), special: .promotion(.queen))))
    }

    func testEnPassantAfterDoublePawnMove() {
        var board = Board()
        board[Square(file: .e, rank: 5)] = Piece(kind: .pawn, color: .white)
        board[Square(file: .d, rank: 7)] = Piece(kind: .pawn, color: .black)
        board[Square(file: .e, rank: 1)] = Piece(kind: .king, color: .white)
        board[Square(file: .a, rank: 8)] = Piece(kind: .king, color: .black)
        var state = GameState(board: board, sideToMove: .black)
        state.apply(Move(from: Square(file: .d, rank: 7), to: Square(file: .d, rank: 5)))

        let moves = LegalMoveGenerator.legalMoves(for: Square(file: .e, rank: 5), in: state)

        XCTAssertTrue(moves.contains(Move(from: Square(file: .e, rank: 5), to: Square(file: .d, rank: 6), special: .enPassant)))
    }

    func testBlackCanCaptureEnPassantAfterWhiteDoublePawnMove() {
        var board = Board()
        board[Square(file: .d, rank: 4)] = Piece(kind: .pawn, color: .black)
        board[Square(file: .e, rank: 2)] = Piece(kind: .pawn, color: .white)
        board[Square(file: .e, rank: 1)] = Piece(kind: .king, color: .white)
        board[Square(file: .a, rank: 8)] = Piece(kind: .king, color: .black)
        var state = GameState(board: board, sideToMove: .white)
        state.apply(Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4)))

        let moves = LegalMoveGenerator.legalMoves(for: Square(file: .d, rank: 4), in: state)

        XCTAssertTrue(moves.contains(Move(from: Square(file: .d, rank: 4), to: Square(file: .e, rank: 3), special: .enPassant)))
    }

    func testEnPassantCaptureRemovesPawnFromAdjacentSquare() {
        var board = Board()
        board[Square(file: .e, rank: 5)] = Piece(kind: .pawn, color: .white)
        board[Square(file: .d, rank: 5)] = Piece(kind: .pawn, color: .black)
        board[Square(file: .e, rank: 1)] = Piece(kind: .king, color: .white)
        board[Square(file: .a, rank: 8)] = Piece(kind: .king, color: .black)
        var state = GameState(
            board: board,
            sideToMove: .white,
            enPassantTarget: Square(file: .d, rank: 6)
        )

        state.apply(Move(from: Square(file: .e, rank: 5), to: Square(file: .d, rank: 6), special: .enPassant))

        XCTAssertEqual(state.board[Square(file: .d, rank: 6)], Piece(kind: .pawn, color: .white))
        XCTAssertNil(state.board[Square(file: .e, rank: 5)])
        XCTAssertNil(state.board[Square(file: .d, rank: 5)])
    }

    func testEnPassantExpiresAfterOneReplyMove() {
        var board = Board()
        board[Square(file: .e, rank: 5)] = Piece(kind: .pawn, color: .white)
        board[Square(file: .d, rank: 7)] = Piece(kind: .pawn, color: .black)
        board[Square(file: .a, rank: 2)] = Piece(kind: .pawn, color: .white)
        board[Square(file: .e, rank: 1)] = Piece(kind: .king, color: .white)
        board[Square(file: .a, rank: 8)] = Piece(kind: .king, color: .black)
        var state = GameState(board: board, sideToMove: .black)
        state.apply(Move(from: Square(file: .d, rank: 7), to: Square(file: .d, rank: 5)))
        state.apply(Move(from: Square(file: .a, rank: 2), to: Square(file: .a, rank: 3)))

        let moves = LegalMoveGenerator.legalMoves(for: Square(file: .e, rank: 5), in: state)

        XCTAssertFalse(moves.contains(Move(from: Square(file: .e, rank: 5), to: Square(file: .d, rank: 6), special: .enPassant)))
    }

    func testEnPassantIsIllegalWhenItExposesOwnKingOnRank() {
        var board = Board()
        board[Square(file: .e, rank: 5)] = Piece(kind: .king, color: .white)
        board[Square(file: .f, rank: 5)] = Piece(kind: .pawn, color: .white)
        board[Square(file: .g, rank: 5)] = Piece(kind: .pawn, color: .black)
        board[Square(file: .h, rank: 5)] = Piece(kind: .rook, color: .black)
        board[Square(file: .a, rank: 8)] = Piece(kind: .king, color: .black)
        let state = GameState(
            board: board,
            sideToMove: .white,
            enPassantTarget: Square(file: .g, rank: 6)
        )

        let moves = LegalMoveGenerator.legalMoves(for: Square(file: .f, rank: 5), in: state)

        XCTAssertFalse(moves.contains(Move(from: Square(file: .f, rank: 5), to: Square(file: .g, rank: 6), special: .enPassant)))
    }

    func testEnPassantRequiresOpposingCapturedPawn() {
        var board = Board()
        board[Square(file: .e, rank: 5)] = Piece(kind: .pawn, color: .white)
        board[Square(file: .e, rank: 1)] = Piece(kind: .king, color: .white)
        board[Square(file: .a, rank: 8)] = Piece(kind: .king, color: .black)
        let state = GameState(
            board: board,
            sideToMove: .white,
            enPassantTarget: Square(file: .d, rank: 6)
        )

        let moves = LegalMoveGenerator.legalMoves(for: Square(file: .e, rank: 5), in: state)

        XCTAssertFalse(moves.contains(Move(from: Square(file: .e, rank: 5), to: Square(file: .d, rank: 6), special: .enPassant)))
    }

    func testCaptureResolutionReturnsDestinationForOrdinaryCapture() {
        let target = Square(file: .d, rank: 5)
        let blackPawn = Piece(kind: .pawn, color: .black)
        let state = GameState(
            board: Board(
                pieces: [
                    Square(file: .e, rank: 4): Piece(kind: .pawn, color: .white),
                    target: blackPawn,
                    Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                    Square(file: .e, rank: 8): Piece(kind: .king, color: .black),
                ]
            ),
            sideToMove: .white
        )
        let move = Move(from: Square(file: .e, rank: 4), to: target)

        XCTAssertEqual(
            LegalMoveGenerator.capture(for: move, in: state),
            MoveCapture(square: target, piece: blackPawn)
        )
    }

    func testCaptureResolutionReturnsAdjacentPawnForEnPassant() {
        let capturedSquare = Square(file: .d, rank: 5)
        let blackPawn = Piece(kind: .pawn, color: .black)
        let state = GameState(
            board: Board(
                pieces: [
                    Square(file: .e, rank: 5): Piece(kind: .pawn, color: .white),
                    capturedSquare: blackPawn,
                    Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                    Square(file: .e, rank: 8): Piece(kind: .king, color: .black),
                ]
            ),
            sideToMove: .white,
            enPassantTarget: Square(file: .d, rank: 6)
        )
        let move = Move(
            from: Square(file: .e, rank: 5),
            to: Square(file: .d, rank: 6),
            special: .enPassant
        )

        XCTAssertEqual(
            LegalMoveGenerator.capture(for: move, in: state),
            MoveCapture(square: capturedSquare, piece: blackPawn)
        )
    }
}

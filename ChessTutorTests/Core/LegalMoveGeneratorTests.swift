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

    func testCannotCaptureOpposingKing() {
        var board = Board()
        board[Square(file: .e, rank: 1)] = Piece(kind: .king, color: .white)
        board[Square(file: .e, rank: 7)] = Piece(kind: .queen, color: .white)
        board[Square(file: .e, rank: 8)] = Piece(kind: .king, color: .black)
        let state = GameState(board: board, sideToMove: .white)

        let moves = LegalMoveGenerator.legalMoves(for: Square(file: .e, rank: 7), in: state)

        XCTAssertFalse(moves.contains(Move(from: Square(file: .e, rank: 7), to: Square(file: .e, rank: 8))))
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

    func testKingSquareReturnsNilWhenKingIsMissing() {
        var board = Board()
        board[Square(file: .a, rank: 8)] = Piece(kind: .king, color: .black)

        XCTAssertNil(LegalMoveGenerator.kingSquare(for: .white, in: board))
    }

    func testLegalMovesCanAnalyzePieceWhoseColorIsNotSideToMove() {
        let state = GameState.startingPosition()
        let before = state

        let moves = LegalMoveGenerator.legalMoves(
            for: Square(file: .g, rank: 8),
            by: .black,
            in: state
        )

        XCTAssertEqual(Set(moves.map(\.to)), [
            Square(file: .f, rank: 6),
            Square(file: .h, rank: 6),
        ])
        XCTAssertEqual(state, before)
    }

    func testTurnScopedLegalMovesStillRejectOtherColor() {
        let state = GameState.startingPosition()

        XCTAssertTrue(
            LegalMoveGenerator.legalMoves(
                for: Square(file: .g, rank: 8),
                in: state
            ).isEmpty
        )
    }

    func testPawnControlsDiagonalsButNotForwardSquare() {
        let state = GameState.startingPosition()

        XCTAssertEqual(
            LegalMoveGenerator.controlledSquares(
                for: Square(file: .e, rank: 2),
                by: .white,
                in: state
            ),
            [Square(file: .d, rank: 3), Square(file: .f, rank: 3)]
        )
    }

    func testSlidingControlIncludesFriendlyBlockerButStopsBeyondIt() {
        let bishop = Square(file: .c, rank: 1)
        let blocker = Square(file: .e, rank: 3)
        let state = GameState(
            board: Board(
                pieces: [
                    bishop: Piece(kind: .bishop, color: .white),
                    blocker: Piece(kind: .pawn, color: .white),
                    Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                    Square(file: .e, rank: 8): Piece(kind: .king, color: .black),
                ]
            ),
            sideToMove: .white
        )

        let controlled = LegalMoveGenerator.controlledSquares(for: bishop, by: .white, in: state)

        XCTAssertTrue(controlled.contains(Square(file: .d, rank: 2)))
        XCTAssertTrue(controlled.contains(blocker))
        XCTAssertFalse(controlled.contains(Square(file: .f, rank: 4)))
    }

    func testPinnedKnightDoesNotLegallySupportFriendlyPiece() {
        let knight = Square(file: .e, rank: 2)
        let target = Square(file: .f, rank: 4)
        let state = GameState(
            board: Board(
                pieces: [
                    Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                    knight: Piece(kind: .knight, color: .white),
                    target: Piece(kind: .pawn, color: .white),
                    Square(file: .e, rank: 8): Piece(kind: .rook, color: .black),
                    Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                ]
            ),
            sideToMove: .white
        )

        XCTAssertFalse(
            LegalMoveGenerator.legalSupportTargets(for: knight, by: .white, in: state).contains(target)
        )
    }

    func testPinnedRookLegallySupportsAlongPinLine() {
        let rook = Square(file: .e, rank: 2)
        let target = Square(file: .e, rank: 4)
        let state = GameState(
            board: Board(
                pieces: [
                    Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                    rook: Piece(kind: .rook, color: .white),
                    target: Piece(kind: .pawn, color: .white),
                    Square(file: .e, rank: 8): Piece(kind: .rook, color: .black),
                    Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                ]
            ),
            sideToMove: .white
        )

        XCTAssertTrue(
            LegalMoveGenerator.legalSupportTargets(for: rook, by: .white, in: state).contains(target)
        )
    }

    func testCheckingPieceSquaresReturnsEveryCheckingSource() {
        let rook = Square(file: .e, rank: 8)
        let bishop = Square(file: .b, rank: 4)
        let board = Board(
            pieces: [
                Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                rook: Piece(kind: .rook, color: .black),
                bishop: Piece(kind: .bishop, color: .black),
                Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
            ]
        )

        XCTAssertEqual(
            LegalMoveGenerator.checkingPieceSquares(against: .white, in: board),
            [rook, bishop]
        )
    }

    func testEnPassantIsNotOfferedToColorThatIsNotSideToMove() {
        let blackPawn = Square(file: .e, rank: 4)
        let target = Square(file: .d, rank: 3)
        let state = GameState(
            board: Board(
                pieces: [
                    Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                    Square(file: .e, rank: 8): Piece(kind: .king, color: .black),
                    blackPawn: Piece(kind: .pawn, color: .black),
                    Square(file: .d, rank: 4): Piece(kind: .pawn, color: .white),
                ]
            ),
            sideToMove: .white,
            enPassantTarget: target
        )

        XCTAssertFalse(
            LegalMoveGenerator.allowedMoves(for: blackPawn, by: .black, in: state).contains(
                Move(from: blackPawn, to: target, special: .enPassant)
            )
        )
    }
}

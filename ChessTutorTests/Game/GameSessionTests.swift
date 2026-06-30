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

    func testSelectedPieceInfoNamesSelectedPiece() {
        let session = GameSession()

        session.select(Square(file: .g, rank: 1))

        XCTAssertEqual(
            session.selectedPieceInfo,
            SelectedPieceInfo(
                piece: Piece(kind: .knight, color: .white),
                square: Square(file: .g, rank: 1),
                squareID: "g1",
                title: "White knight",
                movementSummary: "Moves in an L shape."
            )
        )
    }

    func testSelectedPieceInfoClearsWhenSelectionClears() {
        let session = GameSession()

        session.select(Square(file: .g, rank: 1))
        session.select(Square(file: .a, rank: 6))

        XCTAssertNil(session.selectedPieceInfo)
    }

    func testSelectedPieceInfoIncludesSquareCoordinates() {
        let session = GameSession()

        session.select(Square(file: .e, rank: 2))

        XCTAssertEqual(session.selectedPieceInfo?.squareID, "e2")
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

    func testPromoteStagesPromotionChoiceAndClearsSelection() {
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
        XCTAssertEqual(session.state.sideToMove, .white)
        XCTAssertTrue(session.canFinishTurn)
        XCTAssertNil(session.selectedSquare)
        XCTAssertTrue(session.legalMovesForSelection.isEmpty)
        XCTAssertNil(session.message)
    }

    func testLegalMoveWaitsForDoneBeforeAdvancingTurn() {
        let session = GameSession()

        session.select(Square(file: .e, rank: 2))
        let result = session.moveSelectedPiece(to: Square(file: .e, rank: 4))

        XCTAssertEqual(result, .moved)
        XCTAssertEqual(session.state.board[Square(file: .e, rank: 4)], Piece(kind: .pawn, color: .white))
        XCTAssertNil(session.state.board[Square(file: .e, rank: 2)])
        XCTAssertEqual(session.state.sideToMove, .white)
        XCTAssertEqual(session.statusText, "White's turn")
        XCTAssertNil(session.guidanceText)
        XCTAssertTrue(session.canFinishTurn)

        session.finishTurn()

        XCTAssertEqual(session.state.sideToMove, .black)
        XCTAssertEqual(session.statusText, "Black's turn")
        XCTAssertFalse(session.canFinishTurn)
    }

    func testTentativeMoveCanBePutBackBeforeDone() {
        let session = GameSession()

        session.select(Square(file: .e, rank: 2))
        _ = session.moveSelectedPiece(to: Square(file: .e, rank: 4))
        session.select(Square(file: .e, rank: 4))
        let result = session.moveSelectedPiece(to: Square(file: .e, rank: 2))

        XCTAssertEqual(result, .moved)
        XCTAssertEqual(session.state.board[Square(file: .e, rank: 2)], Piece(kind: .pawn, color: .white))
        XCTAssertNil(session.state.board[Square(file: .e, rank: 4)])
        XCTAssertEqual(session.state.sideToMove, .white)
        XCTAssertFalse(session.canFinishTurn)
        XCTAssertNil(session.guidanceText)
    }

    func testGameInProgressReflectsTentativeAndCommittedMoves() {
        let session = GameSession()

        XCTAssertFalse(session.hasGameInProgress)

        session.select(Square(file: .e, rank: 2))
        _ = session.moveSelectedPiece(to: Square(file: .e, rank: 4))

        XCTAssertTrue(session.hasGameInProgress)

        session.finishTurn()

        XCTAssertTrue(session.hasGameInProgress)

        session.newGame()

        XCTAssertFalse(session.hasGameInProgress)
    }

    func testTentativeCaptureMovesCapturedPieceToTrayUntilPutBack() {
        let whitePawn = Square(file: .e, rank: 4)
        let blackPawn = Square(file: .d, rank: 5)
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        whitePawn: Piece(kind: .pawn, color: .white),
                        blackPawn: Piece(kind: .pawn, color: .black),
                        Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                        Square(file: .e, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white
            )
        )

        XCTAssertTrue(session.capturedPieces.isEmpty)

        session.select(whitePawn)
        _ = session.moveSelectedPiece(to: blackPawn)

        XCTAssertEqual(session.capturedPieces.map(\.piece), [Piece(kind: .pawn, color: .black)])
        XCTAssertEqual(session.capturedPieces.map(\.state), [.tentative])

        session.select(blackPawn)
        _ = session.moveSelectedPiece(to: whitePawn)

        XCTAssertTrue(session.capturedPieces.isEmpty)
    }

    func testCaptureBecomesCommittedWhenTurnFinishesAndClearsOnNewGame() {
        let whitePawn = Square(file: .e, rank: 4)
        let blackPawn = Square(file: .d, rank: 5)
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        whitePawn: Piece(kind: .pawn, color: .white),
                        blackPawn: Piece(kind: .pawn, color: .black),
                        Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                        Square(file: .e, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white
            )
        )

        session.select(whitePawn)
        _ = session.moveSelectedPiece(to: blackPawn)
        session.finishTurn()

        XCTAssertEqual(session.capturedPieces.map(\.piece), [Piece(kind: .pawn, color: .black)])
        XCTAssertEqual(session.capturedPieces.map(\.state), [.committed])

        session.newGame()

        XCTAssertTrue(session.capturedPieces.isEmpty)
    }

    #if DEBUG
    func testCaptureForTestingRemovesPieceFromBoardAndAddsCommittedCapture() {
        let session = GameSession()
        let square = Square(file: .a, rank: 7)

        session.captureForTesting(at: square)

        XCTAssertNil(session.state.board[square])
        XCTAssertEqual(session.capturedPieces.map(\.piece), [Piece(kind: .pawn, color: .black)])
        XCTAssertEqual(session.capturedPieces.map(\.capturedAt), [square])
        XCTAssertEqual(session.capturedPieces.map(\.state), [.committed])
    }

    func testCaptureForTestingClearsTentativeMoveAndSelection() {
        let session = GameSession()
        let movedPawn = Square(file: .e, rank: 4)

        session.select(Square(file: .e, rank: 2))
        _ = session.moveSelectedPiece(to: movedPawn)
        session.select(movedPawn)

        session.captureForTesting(at: movedPawn)

        XCTAssertNil(session.state.board[movedPawn])
        XCTAssertFalse(session.canFinishTurn)
        XCTAssertNil(session.selectedSquare)
        XCTAssertTrue(session.legalMovesForSelection.isEmpty)
        XCTAssertNil(session.message)
    }

    func testPromoteForTestingReplacesPawnOnItsCurrentSquare() {
        let session = GameSession()
        let square = Square(file: .e, rank: 2)

        session.promoteForTesting(at: square, to: .queen)

        XCTAssertEqual(session.state.board[square], Piece(kind: .queen, color: .white))
    }

    func testPromoteForTestingIgnoresNonPawns() {
        let session = GameSession()
        let square = Square(file: .a, rank: 1)

        session.promoteForTesting(at: square, to: .queen)

        XCTAssertEqual(session.state.board[square], Piece(kind: .rook, color: .white))
    }
    #endif

    func testCapturedPieceAnimationIDDiffersFromCapturingPieceOnSameSquare() {
        let whitePawn = Square(file: .e, rank: 4)
        let blackPawn = Square(file: .d, rank: 5)
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        whitePawn: Piece(kind: .pawn, color: .white),
                        blackPawn: Piece(kind: .pawn, color: .black),
                        Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                        Square(file: .e, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white
            )
        )

        session.select(whitePawn)
        _ = session.moveSelectedPiece(to: blackPawn)

        guard let capturedPieceID = session.capturedPieces.first?.id else {
            XCTFail("Expected the captured pawn to appear in the captured-piece tray.")
            return
        }
        let capturingPieceID = session.pieceAnimationID(for: Piece(kind: .pawn, color: .white), at: blackPawn)

        XCTAssertNotEqual(capturedPieceID, capturingPieceID)
    }

    func testPawnCaptureThroughNormalOpeningKeepsCapturedPieceInTrayAfterDone() {
        let session = GameSession()

        session.select(Square(file: .e, rank: 2))
        _ = session.moveSelectedPiece(to: Square(file: .e, rank: 4))
        session.finishTurn()
        session.select(Square(file: .d, rank: 7))
        _ = session.moveSelectedPiece(to: Square(file: .d, rank: 5))
        session.finishTurn()

        session.select(Square(file: .e, rank: 4))
        _ = session.moveSelectedPiece(to: Square(file: .d, rank: 5))

        XCTAssertEqual(session.state.board[Square(file: .d, rank: 5)], Piece(kind: .pawn, color: .white))
        XCTAssertNil(session.state.board[Square(file: .e, rank: 4)])
        XCTAssertEqual(session.capturedPieces.map(\.piece), [Piece(kind: .pawn, color: .black)])
        XCTAssertEqual(session.capturedPieces.map(\.state), [.tentative])

        session.finishTurn()

        XCTAssertEqual(session.state.board[Square(file: .d, rank: 5)], Piece(kind: .pawn, color: .white))
        XCTAssertNil(session.state.board[Square(file: .e, rank: 4)])
        XCTAssertEqual(session.capturedPieces.map(\.piece), [Piece(kind: .pawn, color: .black)])
        XCTAssertEqual(session.capturedPieces.map(\.state), [.committed])
    }

    func testTentativeEnPassantMovesCapturedPawnToTrayUntilDone() {
        let whitePawn = Square(file: .e, rank: 5)
        let blackPawn = Square(file: .d, rank: 5)
        let enPassantDestination = Square(file: .d, rank: 6)
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        whitePawn: Piece(kind: .pawn, color: .white),
                        blackPawn: Piece(kind: .pawn, color: .black),
                        Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                        Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white,
                enPassantTarget: enPassantDestination
            )
        )

        session.select(whitePawn)
        let result = session.moveSelectedPiece(to: enPassantDestination)

        XCTAssertEqual(result, .moved)
        XCTAssertEqual(session.state.board[enPassantDestination], Piece(kind: .pawn, color: .white))
        XCTAssertNil(session.state.board[whitePawn])
        XCTAssertNil(session.state.board[blackPawn])
        XCTAssertEqual(session.capturedPieces.map(\.piece), [Piece(kind: .pawn, color: .black)])
        XCTAssertEqual(session.capturedPieces.map(\.capturedAt), [blackPawn])
        XCTAssertEqual(session.capturedPieces.map(\.state), [.tentative])

        session.finishTurn()

        XCTAssertEqual(session.capturedPieces.map(\.piece), [Piece(kind: .pawn, color: .black)])
        XCTAssertEqual(session.capturedPieces.map(\.capturedAt), [blackPawn])
        XCTAssertEqual(session.capturedPieces.map(\.state), [.committed])
    }

    func testEnPassantSelectionMarksCapturedPawnSeparatelyFromDestination() {
        let whitePawn = Square(file: .e, rank: 5)
        let blackPawn = Square(file: .d, rank: 5)
        let enPassantDestination = Square(file: .d, rank: 6)
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        whitePawn: Piece(kind: .pawn, color: .white),
                        blackPawn: Piece(kind: .pawn, color: .black),
                        Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                        Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white,
                enPassantTarget: enPassantDestination
            )
        )

        session.select(whitePawn)

        XCTAssertTrue(session.legalDestinations.contains(enPassantDestination))
        XCTAssertFalse(session.captureIndicatorSquares.contains(enPassantDestination))
        XCTAssertEqual(session.captureIndicatorSquares, [blackPawn])
    }

    func testNormalCaptureSelectionMarksDestinationAsCapturedPiece() {
        let whitePawn = Square(file: .e, rank: 4)
        let blackPawn = Square(file: .d, rank: 5)
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        whitePawn: Piece(kind: .pawn, color: .white),
                        blackPawn: Piece(kind: .pawn, color: .black),
                        Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                        Square(file: .e, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white
            )
        )

        session.select(whitePawn)

        XCTAssertTrue(session.legalDestinations.contains(blackPawn))
        XCTAssertEqual(session.captureIndicatorSquares, [blackPawn])
    }

    func testTentativeEnPassantCanBePutBackBeforeDone() {
        let whitePawn = Square(file: .e, rank: 5)
        let blackPawn = Square(file: .d, rank: 5)
        let enPassantDestination = Square(file: .d, rank: 6)
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        whitePawn: Piece(kind: .pawn, color: .white),
                        blackPawn: Piece(kind: .pawn, color: .black),
                        Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                        Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white,
                enPassantTarget: enPassantDestination
            )
        )

        session.select(whitePawn)
        _ = session.moveSelectedPiece(to: enPassantDestination)
        session.select(enPassantDestination)
        let result = session.moveSelectedPiece(to: whitePawn)

        XCTAssertEqual(result, .moved)
        XCTAssertEqual(session.state.board[whitePawn], Piece(kind: .pawn, color: .white))
        XCTAssertEqual(session.state.board[blackPawn], Piece(kind: .pawn, color: .black))
        XCTAssertNil(session.state.board[enPassantDestination])
        XCTAssertFalse(session.canFinishTurn)
        XCTAssertTrue(session.capturedPieces.isEmpty)
    }

    func testCheckKeepsTurnStatusAndShowsGuidance() {
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                        Square(file: .e, rank: 8): Piece(kind: .rook, color: .black),
                        Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white
            )
        )

        XCTAssertEqual(session.statusText, "White's turn")
        XCTAssertEqual(session.guidanceText, "Check! You must move to defend.")
    }

    func testSelectionGuidanceShowsAllowedMovesEvenWhenOnlySomeResolveCheck() {
        let whiteKing = Square(file: .e, rank: 1)
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        whiteKing: Piece(kind: .king, color: .white),
                        Square(file: .e, rank: 8): Piece(kind: .rook, color: .black),
                        Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white
            )
        )

        session.select(whiteKing)

        XCTAssertTrue(session.legalDestinations.contains(Square(file: .d, rank: 1)))
        XCTAssertTrue(session.legalDestinations.contains(Square(file: .e, rank: 2)))
    }

    func testCheckRuleViolationCanBeStagedButCannotFinishTurn() {
        let whiteKing = Square(file: .e, rank: 1)
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        whiteKing: Piece(kind: .king, color: .white),
                        Square(file: .e, rank: 8): Piece(kind: .rook, color: .black),
                        Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white
            )
        )

        session.select(whiteKing)
        let result = session.moveSelectedPiece(to: Square(file: .e, rank: 2))

        XCTAssertEqual(result, .moved)
        XCTAssertEqual(session.state.board[Square(file: .e, rank: 2)], Piece(kind: .king, color: .white))
        XCTAssertNil(session.state.board[whiteKing])
        XCTAssertFalse(session.canFinishTurn)
        XCTAssertEqual(session.guidanceText, "Your king would still be in check. Move to defend your king.")

        session.finishTurn()

        XCTAssertEqual(session.state.sideToMove, .white)
        XCTAssertFalse(session.canFinishTurn)
        XCTAssertEqual(session.guidanceText, "Your king would still be in check. Move to defend your king.")
    }

    func testMoveThatExposesKingCanBeStagedButCannotFinishTurn() {
        let whiteKing = Square(file: .e, rank: 1)
        let whiteRook = Square(file: .e, rank: 2)
        let session = GameSession(
            state: GameState(
                board: Board(
                    pieces: [
                        whiteKing: Piece(kind: .king, color: .white),
                        whiteRook: Piece(kind: .rook, color: .white),
                        Square(file: .e, rank: 8): Piece(kind: .rook, color: .black),
                        Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                    ]
                ),
                sideToMove: .white
            )
        )

        session.select(whiteRook)
        let result = session.moveSelectedPiece(to: Square(file: .a, rank: 2))

        XCTAssertEqual(result, .moved)
        XCTAssertFalse(session.canFinishTurn)
        XCTAssertEqual(session.guidanceText, "That move would put your king in check.")
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
        XCTAssertEqual(session.state.result, .ongoing)
        XCTAssertTrue(session.canFinishTurn)

        session.finishTurn()

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

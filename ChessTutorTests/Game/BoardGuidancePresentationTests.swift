import XCTest
@testable import ChessTutor

final class BoardGuidancePresentationTests: XCTestCase {
    func testSelectedOpponentUsesOpponentOutgoingAndCurrentPlayerIncomingPaths() {
        let blackRook = Square(file: .d, rank: 6)
        let whiteBishop = Square(file: .b, rank: 4)
        let state = inspectionPosition()

        let presentation = BoardGuidancePresentation.make(
            state: state,
            analysis: PositionAnalyzer.analyze(state),
            selectedSquare: blackRook,
            showsSelectedReach: true,
            showsCoverage: false,
            keepsOnlyCheckmateKingThreat: false
        )

        XCTAssertTrue(
            presentation.selectedPaths.contains {
                $0.source == blackRook && $0.role == .allowed && $0.color == .black
            }
        )
        XCTAssertTrue(
            presentation.selectedPaths.contains {
                $0.source == whiteBishop
                    && $0.destination == blackRook
                    && $0.captureSquare == blackRook
                    && $0.role == .attacker
                    && $0.color == .white
            }
        )
    }

    func testSelectedPieceShowsSupporterAsEchoWithoutAddingDefenderPath() {
        let selected = Square(file: .d, rank: 4)
        let supporter = Square(file: .d, rank: 1)
        let state = GameState(
            board: Board(
                pieces: [
                    Square(file: .a, rank: 1): Piece(kind: .king, color: .white),
                    selected: Piece(kind: .bishop, color: .white),
                    supporter: Piece(kind: .rook, color: .white),
                    Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
                ]
            ),
            sideToMove: .white
        )

        let presentation = BoardGuidancePresentation.make(
            state: state,
            analysis: PositionAnalyzer.analyze(state),
            selectedSquare: selected,
            showsSelectedReach: true,
            showsCoverage: false,
            keepsOnlyCheckmateKingThreat: false
        )

        XCTAssertEqual(presentation.supporterSquares, [supporter])
        XCTAssertFalse(
            presentation.selectedPaths.contains {
                $0.source == supporter && $0.destination == selected
            }
        )
    }

    func testEnPassantAttackerPathKeepsCaptureAndLandingSquaresDistinct() {
        let whitePawn = Square(file: .e, rank: 5)
        let blackPawn = Square(file: .d, rank: 5)
        let landing = Square(file: .d, rank: 6)
        let state = GameState(
            board: Board(
                pieces: [
                    Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                    whitePawn: Piece(kind: .pawn, color: .white),
                    blackPawn: Piece(kind: .pawn, color: .black),
                    Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                ]
            ),
            sideToMove: .white,
            enPassantTarget: landing
        )

        let presentation = BoardGuidancePresentation.make(
            state: state,
            analysis: PositionAnalyzer.analyze(state),
            selectedSquare: blackPawn,
            showsSelectedReach: true,
            showsCoverage: false,
            keepsOnlyCheckmateKingThreat: false
        )

        XCTAssertTrue(
            presentation.selectedPaths.contains(
                BoardGuidancePath(
                    source: whitePawn,
                    destination: landing,
                    captureSquare: blackPawn,
                    color: .white,
                    role: .attacker
                )
            )
        )
    }

    func testSelectionQuietsOnlyUnrelatedAmbientMarkers() {
        let selected = Square(file: .d, rank: 4)
        let relatedAttacker = Square(file: .b, rank: 6)
        let unrelatedThreat = Square(file: .h, rank: 2)
        let state = GameState(
            board: Board(
                pieces: [
                    Square(file: .a, rank: 1): Piece(kind: .king, color: .white),
                    selected: Piece(kind: .bishop, color: .white),
                    unrelatedThreat: Piece(kind: .pawn, color: .white),
                    Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
                    relatedAttacker: Piece(kind: .bishop, color: .black),
                    Square(file: .f, rank: 3): Piece(kind: .knight, color: .black),
                ]
            ),
            sideToMove: .white
        )

        let presentation = BoardGuidancePresentation.make(
            state: state,
            analysis: PositionAnalyzer.analyze(state),
            selectedSquare: selected,
            showsSelectedReach: true,
            showsCoverage: false,
            keepsOnlyCheckmateKingThreat: false
        )

        XCTAssertEqual(presentation.markerOpacity(at: selected), 1)
        XCTAssertEqual(presentation.markerOpacity(at: relatedAttacker), 1)
        XCTAssertEqual(presentation.markerOpacity(at: unrelatedThreat), 0.20)
    }

    func testCoverageSeparatesSideToMoveFromOtherSide() {
        let state = inspectionPosition()
        let analysis = PositionAnalyzer.analyze(state)

        let presentation = BoardGuidancePresentation.make(
            state: state,
            analysis: analysis,
            selectedSquare: nil,
            showsSelectedReach: true,
            showsCoverage: true,
            keepsOnlyCheckmateKingThreat: false
        )

        XCTAssertEqual(presentation.coverage?.sideToMove, .white)
        XCTAssertEqual(presentation.coverage?.sideToMoveSquares, analysis.coverage(for: .white))
        XCTAssertEqual(presentation.coverage?.otherSideSquares, analysis.coverage(for: .black))
    }

    func testCheckmateGuidanceKeepsOnlyLosingKingDanger() {
        let losingKing = Square(file: .h, rank: 1)
        let state = GameState(
            board: Board(
                pieces: [
                    losingKing: Piece(kind: .king, color: .white),
                    Square(file: .f, rank: 2): Piece(kind: .queen, color: .black),
                    Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                ]
            ),
            sideToMove: .white,
            result: .checkmate(winner: .black)
        )

        let presentation = BoardGuidancePresentation.make(
            state: state,
            analysis: PositionAnalyzer.analyze(state),
            selectedSquare: Square(file: .f, rank: 2),
            showsSelectedReach: true,
            showsCoverage: true,
            keepsOnlyCheckmateKingThreat: true
        )

        XCTAssertEqual(presentation.threatenedSquares, [losingKing])
        XCTAssertTrue(presentation.defendedSquares.isEmpty)
        XCTAssertTrue(presentation.selectedPaths.isEmpty)
        XCTAssertTrue(presentation.supporterSquares.isEmpty)
        XCTAssertNil(presentation.coverage)
    }

    private func inspectionPosition() -> GameState {
        GameState(
            board: Board(
                pieces: [
                    Square(file: .a, rank: 1): Piece(kind: .king, color: .white),
                    Square(file: .b, rank: 4): Piece(kind: .bishop, color: .white),
                    Square(file: .d, rank: 1): Piece(kind: .rook, color: .white),
                    Square(file: .d, rank: 6): Piece(kind: .rook, color: .black),
                    Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
                ]
            ),
            sideToMove: .white
        )
    }
}

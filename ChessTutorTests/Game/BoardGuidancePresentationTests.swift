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

    func testSelectedCheckingPieceShowsItsThreatToTheKing() {
        let whiteKing = Square(file: .e, rank: 1)
        let blackRook = Square(file: .e, rank: 8)
        let state = GameState(
            board: Board(
                pieces: [
                    whiteKing: Piece(kind: .king, color: .white),
                    blackRook: Piece(kind: .rook, color: .black),
                    Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                ]
            ),
            sideToMove: .white
        )

        let presentation = BoardGuidancePresentation.make(
            state: state,
            analysis: PositionAnalyzer.analyze(state),
            selectedSquare: blackRook,
            showsSelectedReach: true,
            showsCoverage: false,
            keepsOnlyCheckmateKingThreat: false
        )

        XCTAssertTrue(
            presentation.selectedPaths.contains(
                BoardGuidancePath(
                    source: blackRook,
                    destination: whiteKing,
                    captureSquare: whiteKing,
                    color: .black,
                    role: .allowed
                )
            )
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

    func testEnPassantCapturePromotesCapturedPawnRatherThanLandingSquare() {
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
            selectedSquare: whitePawn,
            showsSelectedReach: true,
            showsCoverage: false,
            keepsOnlyCheckmateKingThreat: false
        )

        XCTAssertEqual(presentation.prominentThreatSquares, [blackPawn])
        XCTAssertFalse(presentation.prominentThreatSquares.contains(landing))
    }

    func testSelectionPromotesOnlyThreatenedSelectionAndLegalCaptureTargets() {
        let selected = Square(file: .d, rank: 4)
        let captureTarget = Square(file: .f, rank: 6)
        let unrelatedThreat = Square(file: .h, rank: 2)
        let presentation = markerRelevancePresentation(selectedSquare: selected)

        XCTAssertTrue(presentation.threatenedSquares.isSuperset(of: [
            selected, captureTarget, unrelatedThreat,
        ]))
        XCTAssertEqual(presentation.prominentThreatSquares, [selected, captureTarget])
        XCTAssertFalse(presentation.prominentThreatSquares.contains(unrelatedThreat))
    }

    func testSelectionShowsDefenseOnlyForSelectionAndLegalCaptureTargets() {
        let selected = Square(file: .d, rank: 4)
        let captureTarget = Square(file: .f, rank: 6)
        let unrelatedDefendedPiece = Square(file: .h, rank: 2)
        let presentation = markerRelevancePresentation(selectedSquare: selected)

        XCTAssertTrue(presentation.defendedSquares.isSuperset(of: [
            selected, captureTarget, unrelatedDefendedPiece,
        ]))
        XCTAssertEqual(presentation.visibleDefenseSquares, [selected, captureTarget])
    }

    func testNoSelectionKeepsAllFactsButHasNoProminentThreatsOrVisibleDefense() {
        let presentation = markerRelevancePresentation(selectedSquare: nil)

        XCTAssertFalse(presentation.threatenedSquares.isEmpty)
        XCTAssertFalse(presentation.defendedSquares.isEmpty)
        XCTAssertTrue(presentation.prominentThreatSquares.isEmpty)
        XCTAssertTrue(presentation.visibleDefenseSquares.isEmpty)
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
        XCTAssertEqual(presentation.prominentThreatSquares, [losingKing])
        XCTAssertTrue(presentation.defendedSquares.isEmpty)
        XCTAssertTrue(presentation.visibleDefenseSquares.isEmpty)
        XCTAssertTrue(presentation.selectedPaths.isEmpty)
        XCTAssertTrue(presentation.supporterSquares.isEmpty)
        XCTAssertNil(presentation.coverage)
    }

    func testPieceAccessibilityIncludesThreatAndDefenseStatus() {
        let target = Square(file: .d, rank: 4)
        let presentation = BoardGuidancePresentation(
            sideToMove: .white,
            threatenedSquares: [target],
            prominentThreatSquares: [],
            defendedSquares: [target],
            visibleDefenseSquares: [],
            selectedSquare: nil,
            selectedPaths: [],
            supporterSquares: [],
            coverage: nil
        )

        XCTAssertEqual(
            presentation.accessibilityLabel(
                for: target,
                piece: Piece(kind: .bishop, color: .white)
            ),
            "White bishop on d4, threatened and defended"
        )
    }

    func testPieceAccessibilityNamesSingleAndAbsentStatuses() {
        let threatened = Square(file: .a, rank: 2)
        let defended = Square(file: .b, rank: 2)
        let quiet = Square(file: .c, rank: 2)
        let presentation = BoardGuidancePresentation(
            sideToMove: .white,
            threatenedSquares: [threatened],
            prominentThreatSquares: [],
            defendedSquares: [defended],
            visibleDefenseSquares: [],
            selectedSquare: nil,
            selectedPaths: [],
            supporterSquares: [],
            coverage: nil
        )

        XCTAssertEqual(
            presentation.accessibilityLabel(
                for: threatened,
                piece: Piece(kind: .pawn, color: .white)
            ),
            "White pawn on a2, threatened"
        )
        XCTAssertEqual(
            presentation.accessibilityLabel(
                for: defended,
                piece: Piece(kind: .knight, color: .white)
            ),
            "White knight on b2, defended"
        )
        XCTAssertEqual(
            presentation.accessibilityLabel(
                for: quiet,
                piece: Piece(kind: .rook, color: .white)
            ),
            "White rook on c2"
        )
    }

    func testCoverageAccessibilityNamesBothSidesOnContestedSquare() {
        let contested = Square(file: .d, rank: 5)
        let presentation = BoardGuidancePresentation(
            sideToMove: .white,
            threatenedSquares: [],
            prominentThreatSquares: [],
            defendedSquares: [],
            visibleDefenseSquares: [],
            selectedSquare: nil,
            selectedPaths: [],
            supporterSquares: [],
            coverage: BoardCoveragePresentation(
                sideToMove: .white,
                sideToMoveSquares: [contested],
                otherSideSquares: [contested]
            )
        )

        XCTAssertEqual(
            presentation.coverageAccessibilityLabel(for: contested),
            "d5, covered by White and Black"
        )
    }

    func testCoverageAccessibilityNamesOneSideOrBareSquare() {
        let blackOnly = Square(file: .f, rank: 6)
        let uncovered = Square(file: .g, rank: 6)
        let presentation = BoardGuidancePresentation(
            sideToMove: .black,
            threatenedSquares: [],
            prominentThreatSquares: [],
            defendedSquares: [],
            visibleDefenseSquares: [],
            selectedSquare: nil,
            selectedPaths: [],
            supporterSquares: [],
            coverage: BoardCoveragePresentation(
                sideToMove: .black,
                sideToMoveSquares: [blackOnly],
                otherSideSquares: []
            )
        )

        XCTAssertEqual(
            presentation.coverageAccessibilityLabel(for: blackOnly),
            "f6, covered by Black"
        )
        XCTAssertEqual(
            presentation.coverageAccessibilityLabel(for: uncovered),
            "g6"
        )
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

    private func markerRelevancePresentation(
        selectedSquare: Square?
    ) -> BoardGuidancePresentation {
        let state = GameState(
            board: Board(
                pieces: [
                    Square(file: .a, rank: 1): Piece(kind: .king, color: .white),
                    Square(file: .d, rank: 4): Piece(kind: .bishop, color: .white),
                    Square(file: .d, rank: 1): Piece(kind: .rook, color: .white),
                    Square(file: .h, rank: 2): Piece(kind: .pawn, color: .white),
                    Square(file: .h, rank: 1): Piece(kind: .rook, color: .white),
                    Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
                    Square(file: .d, rank: 8): Piece(kind: .rook, color: .black),
                    Square(file: .f, rank: 6): Piece(kind: .knight, color: .black),
                    Square(file: .f, rank: 8): Piece(kind: .rook, color: .black),
                    Square(file: .f, rank: 3): Piece(kind: .knight, color: .black),
                ]
            ),
            sideToMove: .white
        )
        return BoardGuidancePresentation.make(
            state: state,
            analysis: PositionAnalyzer.analyze(state),
            selectedSquare: selectedSquare,
            showsSelectedReach: true,
            showsCoverage: false,
            keepsOnlyCheckmateKingThreat: false
        )
    }
}

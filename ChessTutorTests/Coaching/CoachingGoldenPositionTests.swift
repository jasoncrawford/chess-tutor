import XCTest
@testable import ChessTutor

final class CoachingGoldenPositionTests: XCTestCase {
    func testAllFixturesContainOneKingPerColor() {
        for fixture in CoachingGoldenPosition.allCases {
            let pieces = fixture.state.board.pieces.values
            XCTAssertEqual(pieces.filter { $0 == Piece(kind: .king, color: .white) }.count, 1, fixture.rawValue)
            XCTAssertEqual(pieces.filter { $0 == Piece(kind: .king, color: .black) }.count, 1, fixture.rawValue)
        }
    }

    func testReadyToCastleFixtureAllowsKingsideCastling() {
        let state = CoachingGoldenPosition.readyToCastle.state
        XCTAssertTrue(LegalMoveGenerator.legalMoves(for: sq("e1"), in: state).contains(CoachingGoldenMoves.castle))
    }

    func testReadyToCastleFixtureProtectsE4ThroughTheOpponentReplyScan() async throws {
        let state = CoachingGoldenPosition.readyToCastle.state
        let request = CoachingRequest(
            committedState: state,
            tentativeMove: CoachingGoldenMoves.castle,
            learner: .white,
            positionRevision: 1,
            context: .tentativeMove(origin: .wake)
        )

        let advice = try await LocalCoachingAdvisor().advice(for: request)
        let assessment = try XCTUnwrap(advice.moveAssessments[CoachingGoldenMoves.castle])

        XCTAssertTrue(assessment.opponentIssues.isEmpty)
        XCTAssertTrue(assessment.isAcceptable)
    }

    func testDangerFixturesContainTheSpecifiedCaptures() {
        assertLegal(CoachingGoldenMoves.knightTaken, by: .black, in: .endangeredKnight)
        assertLegal(CoachingGoldenMoves.pawnTaken, by: .black, in: .twoDangerPriorities)
        assertLegal(CoachingGoldenMoves.knightTaken, by: .black, in: .twoDangerPriorities)
        assertLegal(Move(from: sq("b6"), to: sq("e3")), by: .black, in: .endangeredPawn)
        assertLegal(CoachingGoldenMoves.pawnEscapes, by: .white, in: .endangeredPawn)
    }

    func testCaptureFixturesContainWinningAndLosingLines() {
        assertLegal(CoachingGoldenMoves.bishopWinsRook, by: .white, in: .winningCapture)
        let afterBishopTakes = CoachingGoldenPosition.losingCapture.state
            .applyingUnchecked(CoachingGoldenMoves.bishopTakesPawn)
        XCTAssertTrue(LegalMoveGenerator.legalMoves(for: sq("g8"), in: afterBishopTakes).contains(CoachingGoldenMoves.kingTakesBishop))
    }

    func testProtectionFixtureContainsRecaptureLine() {
        let afterH3 = CoachingGoldenPosition.protectPawn.state
            .applyingUnchecked(CoachingGoldenMoves.addsPawnDefender)
        let afterKnightTakes = afterH3.applyingUnchecked(CoachingGoldenMoves.knightTakesPawn)
        XCTAssertTrue(LegalMoveGenerator.legalMoves(for: sq("h3"), in: afterKnightTakes).contains(CoachingGoldenMoves.pawnRecapturesKnight))
    }

    func testCornerKnightMobilityRisesFromTwoToSix() {
        let before = CoachingGoldenPosition.cornerKnight.state
        XCTAssertEqual(LegalMoveGenerator.legalMoves(for: sq("a1"), in: before).count, 2)
        for move in [CoachingGoldenMoves.knightThreatB3, CoachingGoldenMoves.knightThreatC2] {
            let after = before.applyingUnchecked(move)
            XCTAssertEqual(LegalMoveGenerator.legalMoves(for: move.to, by: .white, in: after).count, 6)
        }
    }

    func testOpponentAndCheckFixturesContainTheSpecifiedLines() {
        let queenState = CoachingGoldenPosition.exposedQueen.state.applyingUnchecked(CoachingGoldenMoves.exposesQueen)
        XCTAssertTrue(LegalMoveGenerator.legalMoves(for: sq("d8"), in: queenState).contains(CoachingGoldenMoves.rookTakesQueen))

        let checkingState = CoachingGoldenPosition.harmlessCheck.state
            .applyingUnchecked(CoachingGoldenMoves.developsKnight)
            .applyingUnchecked(CoachingGoldenMoves.rookChecks)
        XCTAssertTrue(LegalMoveGenerator.isKingInCheck(.white, in: checkingState.board))
        XCTAssertFalse(LegalMoveGenerator.allLegalMoves(in: checkingState).isEmpty)

        let forced = CoachingGoldenPosition.forcedCheck.state
        XCTAssertTrue(LegalMoveGenerator.isKingInCheck(.white, in: forced.board))
        XCTAssertTrue(LegalMoveGenerator.legalMoves(for: sq("b5"), in: forced).contains(CoachingGoldenMoves.capturesChecker))
        XCTAssertTrue(LegalMoveGenerator.legalMoves(for: sq("b5"), in: forced).contains(CoachingGoldenMoves.blocksChecker))
    }

    func testOpponentActivityFixturesContainTheSpecifiedLines() throws {
        let afterBishopToA6 = CoachingGoldenPosition.openingBishopCanBeTaken.state
            .applyingUnchecked(CoachingGoldenMoves.bishopToA6)
        XCTAssertTrue(
            LegalMoveGenerator.legalMoves(for: sq("b7"), in: afterBishopToA6)
                .contains(Move(from: sq("b7"), to: sq("a6")))
        )

        let afterBlackPawnToE6 = CoachingGoldenPosition.protectedPawnUnderBishopAttack.state
            .applyingUnchecked(CoachingGoldenMoves.blackPawnToE6)
        XCTAssertTrue(
            LegalMoveGenerator.legalMoves(for: sq("c4"), in: afterBlackPawnToE6)
                .contains(CoachingGoldenMoves.bishopTakesE6)
        )
        let estimate = try XCTUnwrap(
            MaterialTacticalEvaluator().captureEstimate(
                for: CoachingGoldenMoves.bishopTakesE6,
                in: afterBlackPawnToE6
            )
        )
        XCTAssertLessThan(estimate.netGainForMover, 0)
    }

    private func assertLegal(
        _ move: Move,
        by color: PieceColor,
        in fixture: CoachingGoldenPosition,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var state = fixture.state
        state.sideToMove = color
        XCTAssertTrue(
            LegalMoveGenerator.legalMoves(for: move.from, in: state).contains(move),
            "Expected \(move) to be legal in \(fixture.rawValue)",
            file: file,
            line: line
        )
    }
}

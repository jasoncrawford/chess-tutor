import XCTest
@testable import ChessTutor

final class LocalCoachingAdvisorTests: XCTestCase {
    private let advisor = LocalCoachingAdvisor()

    func testCheckRanksBeforeMaterialDanger() async throws {
        let checkingRook = Square(file: .e, rank: 8)
        let looseQueen = Square(file: .b, rank: 3)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                looseQueen: Piece(kind: .queen, color: .white),
                checkingRook: Piece(kind: .rook, color: .black),
                Square(file: .a, rank: 4): Piece(kind: .bishop, color: .black),
                Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
            ]
        )

        let advice = try await advisor.advice(for: request(for: state))

        XCTAssertEqual(advice.insights.first?.concept, .kingInCheck)
        XCTAssertEqual(advice.checkingPieces, [checkingRook])
    }

    func testAnyUrgentPieceRemainsAValidSafeAnswer() async throws {
        let earlierBishop = Square(file: .b, rank: 3)
        let laterRook = Square(file: .f, rank: 4)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .h, rank: 1): Piece(kind: .king, color: .white),
                earlierBishop: Piece(kind: .bishop, color: .white),
                laterRook: Piece(kind: .rook, color: .white),
                Square(file: .a, rank: 4): Piece(kind: .pawn, color: .black),
                Square(file: .f, rank: 8): Piece(kind: .rook, color: .black),
                Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
            ]
        )

        let advice = try await advisor.advice(for: request(for: state))

        XCTAssertEqual(Set(advice.urgentProblems.map(\.target)), [earlierBishop, laterRook])
    }

    func testSafeInsightsOrderCheckFactsBeforeMaterialDangerFacts() async throws {
        let checkingRook = Square(file: .e, rank: 8)
        let looseQueen = Square(file: .b, rank: 3)
        let queenAttacker = Square(file: .a, rank: 4)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                looseQueen: Piece(kind: .queen, color: .white),
                checkingRook: Piece(kind: .rook, color: .black),
                queenAttacker: Piece(kind: .bishop, color: .black),
                Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
            ]
        )

        let advice = try await advisor.advice(for: request(for: state))
        let safeConcepts = advice.insights.map(\.concept).filter {
            [.kingInCheck, .checkingPiece, .pieceNeedsHelp, .profitableAttacker].contains($0)
        }

        XCTAssertEqual(
            safeConcepts,
            [.kingInCheck, .checkingPiece, .pieceNeedsHelp, .profitableAttacker]
        )
        XCTAssertEqual(
            insight(.checkingPiece, subject: checkingRook, in: advice)?.evidence,
            .check(attackers: [checkingRook])
        )
        XCTAssertEqual(
            insight(.profitableAttacker, subject: queenAttacker, in: advice)?.candidateMoves,
            [Move(from: queenAttacker, to: looseQueen)]
        )
    }

    func testCheckInsightIncludesEvasionsThatLeaveSeparateMaterialDanger() async throws {
        let checkingRook = Square(file: .e, rank: 8)
        let looseBishop = Square(file: .c, rank: 2)
        let materialAttacker = Square(file: .c, rank: 8)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                looseBishop: Piece(kind: .bishop, color: .white),
                checkingRook: Piece(kind: .rook, color: .black),
                materialAttacker: Piece(kind: .rook, color: .black),
                Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
            ]
        )

        let advice = try await advisor.advice(for: request(for: state))
        let checkInsight = try XCTUnwrap(
            advice.insights.first { $0.concept == .kingInCheck }
        )
        let allLegalEvasions = Set(LegalMoveGenerator.allLegalMoves(in: state))
        let materialResolvingMoves = Set(
            advice.evaluation.moveAssessments.values
                .filter { $0.isLegal && $0.resolvesRequiredDanger }
                .map(\.move)
        )

        XCTAssertGreaterThan(allLegalEvasions.count, materialResolvingMoves.count)
        XCTAssertEqual(Set(checkInsight.candidateMoves), allLegalEvasions)
    }

    func testPieceNeedsHelpIncludesMovingDefendingAndExchangingMoves() async throws {
        let target = Square(file: .d, rank: 4)
        let attacker = Square(file: .b, rank: 6)
        let defender = Square(file: .c, rank: 2)
        let movingMove = Move(from: target, to: Square(file: .e, rank: 5))
        let defendingMove = Move(from: defender, to: Square(file: .c, rank: 3))
        let exchange = Move(from: target, to: attacker)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .h, rank: 1): Piece(kind: .king, color: .white),
                target: Piece(kind: .bishop, color: .white),
                defender: Piece(kind: .pawn, color: .white),
                attacker: Piece(kind: .bishop, color: .black),
                Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
            ]
        )

        let advice = try await advisor.advice(for: request(for: state))
        let candidates = try XCTUnwrap(
            insight(.pieceNeedsHelp, subject: target, in: advice)?.candidateMoves
        )

        XCTAssertTrue(candidates.contains(movingMove))
        XCTAssertTrue(candidates.contains(defendingMove))
        XCTAssertTrue(candidates.contains(exchange))
    }

    func testProfitableCapturesRankByGainThenStableBoardOrder() async throws {
        let best = Move(
            from: Square(file: .c, rank: 1),
            to: Square(file: .g, rank: 5)
        )
        let earlierTie = Move(
            from: Square(file: .a, rank: 2),
            to: Square(file: .a, rank: 7)
        )
        let laterTie = Move(
            from: Square(file: .b, rank: 2),
            to: Square(file: .b, rank: 7)
        )
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .d, rank: 1): Piece(kind: .king, color: .white),
                best.from: Piece(kind: .bishop, color: .white),
                earlierTie.from: Piece(kind: .rook, color: .white),
                laterTie.from: Piece(kind: .rook, color: .white),
                best.to: Piece(kind: .rook, color: .black),
                earlierTie.to: Piece(kind: .bishop, color: .black),
                laterTie.to: Piece(kind: .bishop, color: .black),
                Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
            ]
        )

        let advice = try await advisor.advice(for: request(for: state))

        XCTAssertEqual(
            advice.takeOpportunities.flatMap(\.moves),
            [best, earlierTie, laterTie]
        )
        XCTAssertEqual(
            advice.takeOpportunities.map(\.concept),
            [.profitableCapture, .profitableCapture, .profitableCapture]
        )
    }

    func testBadProfitableCaptureRemainsFactualButIsNotATakeAnswer() async throws {
        let badCapture = Move(
            from: Square(file: .b, rank: 2),
            to: Square(file: .a, rank: 3)
        )
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .h, rank: 1): Piece(kind: .king, color: .white),
                badCapture.from: Piece(kind: .pawn, color: .white),
                badCapture.to: Piece(kind: .pawn, color: .black),
                Square(file: .f, rank: 3): Piece(kind: .king, color: .black),
                Square(file: .g, rank: 3): Piece(kind: .queen, color: .black),
            ]
        )

        let advice = try await advisor.advice(for: request(for: state))
        let assessment = try XCTUnwrap(advice.moveAssessments[badCapture])
        let mateIssue = try XCTUnwrap(
            assessment.opponentIssues.first { $0.kind == .mateInOne }
        )

        XCTAssertTrue(assessment.concepts.contains(.profitableCapture))
        XCTAssertTrue(assessment.concepts.contains(.allowsMateInOne))
        XCTAssertEqual(
            moveInsight(.allowsMateInOne, move: badCapture, in: advice)?.evidence,
            .opponentReply(mateIssue)
        )
        XCTAssertFalse(advice.takeOpportunities.flatMap(\.moves).contains(badCapture))
        XCTAssertFalse(assessment.isAcceptable)
    }

    func testResolvingEqualExchangeIsAcceptedWithoutWinningConcept() async throws {
        let learnerBishop = Square(file: .d, rank: 4)
        let attacker = Square(file: .b, rank: 6)
        let exchange = Move(from: learnerBishop, to: attacker)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .h, rank: 1): Piece(kind: .king, color: .white),
                learnerBishop: Piece(kind: .bishop, color: .white),
                Square(file: .a, rank: 5): Piece(kind: .pawn, color: .white),
                attacker: Piece(kind: .bishop, color: .black),
                Square(file: .d, rank: 7): Piece(kind: .knight, color: .black),
                Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
            ]
        )

        let advice = try await advisor.advice(for: request(for: state))
        let assessment = try XCTUnwrap(advice.moveAssessments[exchange])

        XCTAssertEqual(
            advice.evaluation.learnerCaptureEstimates.first { $0.move == exchange }?.netGainForMover,
            0
        )
        XCTAssertTrue(assessment.concepts.contains(.captureResolvesDanger))
        XCTAssertFalse(assessment.concepts.contains(.profitableCapture))
        XCTAssertTrue(advice.takeOpportunities.contains {
            $0.concept == .captureResolvesDanger && $0.moves == [exchange]
        })
        XCTAssertTrue(assessment.isAcceptable)
    }

    func testMateInOneIsATakeOpportunityAndAcceptablePurpose() async throws {
        let matingMove = Move(
            from: Square(file: .g, rank: 6),
            to: Square(file: .g, rank: 7)
        )
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .f, rank: 6): Piece(kind: .king, color: .white),
                matingMove.from: Piece(kind: .queen, color: .white),
                Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
            ]
        )

        let advice = try await advisor.advice(for: request(for: state))
        let assessment = try XCTUnwrap(advice.moveAssessments[matingMove])
        let opportunity = try XCTUnwrap(
            advice.takeOpportunities.first { $0.concept == .mateInOne }
        )

        XCTAssertEqual(advice.takeOpportunities.first?.concept, .mateInOne)
        XCTAssertEqual(opportunity.moves, [matingMove])
        XCTAssertEqual(opportunity.evidence, .check(attackers: [matingMove.to]))
        XCTAssertTrue(assessment.concepts.contains(.mateInOne))
        XCTAssertTrue(assessment.isAcceptable)
    }

    func testHarmlessReplyCheckProducesAllowsCheckAndVerifiedSafeFacts() async throws {
        let learnerMove = Move(
            from: Square(file: .h, rank: 2),
            to: Square(file: .h, rank: 3)
        )
        let checkingReply = Move(
            from: Square(file: .a, rank: 8),
            to: Square(file: .a, rank: 1)
        )
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                learnerMove.from: Piece(kind: .pawn, color: .white),
                Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
                checkingReply.from: Piece(kind: .rook, color: .black),
            ]
        )

        let advice = try await advisor.advice(for: request(for: state))
        let assessment = try XCTUnwrap(advice.moveAssessments[learnerMove])
        let issue = try XCTUnwrap(
            assessment.opponentIssues.first { $0.reply == checkingReply && $0.kind == .check }
        )

        XCTAssertEqual(
            moveInsight(.allowsCheck, move: learnerMove, in: advice)?.evidence,
            .opponentReply(issue)
        )
        XCTAssertEqual(
            moveInsight(.safeAfterReplyCheck, move: learnerMove, in: advice)?.evidence,
            .verifiedSafe
        )
    }

    func testClearReplyLossProducesMaterialLossFactButNotVerifiedSafe() async throws {
        let learnerMove = Move(
            from: Square(file: .c, rank: 3),
            to: Square(file: .d, rank: 4)
        )
        let reply = Move(
            from: Square(file: .c, rank: 5),
            to: Square(file: .d, rank: 4)
        )
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .h, rank: 1): Piece(kind: .king, color: .white),
                learnerMove.from: Piece(kind: .bishop, color: .white),
                Square(file: .e, rank: 3): Piece(kind: .pawn, color: .white),
                reply.from: Piece(kind: .pawn, color: .black),
                Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
            ]
        )

        let advice = try await advisor.advice(for: request(for: state))
        let assessment = try XCTUnwrap(advice.moveAssessments[learnerMove])
        let issue = try XCTUnwrap(
            assessment.opponentIssues.first {
                $0.reply == reply && $0.kind == .materialLoss(points: 2)
            }
        )

        XCTAssertEqual(
            moveInsight(.allowsMaterialLoss, move: learnerMove, in: advice)?.evidence,
            .opponentReply(issue)
        )
        XCTAssertNil(moveInsight(.safeAfterReplyCheck, move: learnerMove, in: advice))
    }

    func testSafeButPurposelessMoveStaysUnacceptableOutsideFallback() async throws {
        let quietMove = Move(
            from: Square(file: .a, rank: 2),
            to: Square(file: .a, rank: 3)
        )
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .h, rank: 1): Piece(kind: .king, color: .white),
                quietMove.from: Piece(kind: .pawn, color: .white),
                Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
            ]
        )

        let advice = try await advisor.advice(for: request(for: state))
        let assessment = try XCTUnwrap(advice.moveAssessments[quietMove])

        XCTAssertTrue(assessment.concepts.contains(.safeAfterReplyCheck))
        XCTAssertFalse(assessment.isAcceptable)
        XCTAssertEqual(advice.confidence, .high)
    }

    func testCheckInsightCarriesEveryLegalCheckResolvingMove() async throws {
        let checkingRook = Square(file: .e, rank: 8)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                Square(file: .d, rank: 2): Piece(kind: .bishop, color: .white),
                checkingRook: Piece(kind: .rook, color: .black),
                Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
            ]
        )
        let expected = Set(LegalMoveGenerator.allLegalMoves(in: state))

        let advice = try await advisor.advice(for: request(for: state))
        let checkInsight = try XCTUnwrap(
            advice.insights.first { $0.concept == .kingInCheck }
        )

        XCTAssertEqual(Set(checkInsight.candidateMoves), expected)
        XCTAssertEqual(checkInsight.candidateMoves.count, expected.count)
    }

    func testSameRequestReturnsDeterministicallyEqualAdvice() async throws {
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .d, rank: 1): Piece(kind: .king, color: .white),
                Square(file: .c, rank: 1): Piece(kind: .bishop, color: .white),
                Square(file: .a, rank: 2): Piece(kind: .rook, color: .white),
                Square(file: .b, rank: 2): Piece(kind: .rook, color: .white),
                Square(file: .g, rank: 5): Piece(kind: .rook, color: .black),
                Square(file: .a, rank: 7): Piece(kind: .bishop, color: .black),
                Square(file: .b, rank: 7): Piece(kind: .bishop, color: .black),
                Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
            ]
        )
        let request = request(for: state)

        let first = try await advisor.advice(for: request)
        for _ in 0..<10 {
            let repeated = try await advisor.advice(for: request)
            XCTAssertEqual(repeated, first)
        }
    }

    private func request(for state: GameState) -> CoachingRequest {
        CoachingRequest(
            committedState: state,
            tentativeMove: nil,
            learner: state.sideToMove,
            positionRevision: 1,
            context: .start
        )
    }

    private func insight(
        _ concept: CoachingConcept,
        subject: Square,
        in advice: CoachingAdvice
    ) -> CoachingInsight? {
        advice.insights.first {
            $0.concept == concept && $0.subjectSquares.contains(subject)
        }
    }

    private func moveInsight(
        _ concept: CoachingConcept,
        move: Move,
        in advice: CoachingAdvice
    ) -> CoachingInsight? {
        advice.insights.first {
            $0.concept == concept && $0.candidateMoves == [move]
        }
    }
}

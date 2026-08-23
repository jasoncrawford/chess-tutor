import XCTest
@testable import ChessTutor

final class MaterialTacticalEvaluatorTests: XCTestCase {
    private let evaluator = MaterialTacticalEvaluator()

    func testMaterialIssueUsesOpponentSourceAsAnswer() throws {
        let assessment = try assessment(
            position: .exposedQueen,
            tentativeMove: CoachingGoldenMoves.exposesQueen
        )
        let issue = try XCTUnwrap(assessment.opponentIssues.first {
            $0.reply == CoachingGoldenMoves.rookTakesQueen
                && $0.kind == .materialLoss(points: 9)
        })

        XCTAssertEqual(issue.reply, CoachingGoldenMoves.rookTakesQueen)
        XCTAssertEqual(issue.answerSquares, [sq("d8")])
        XCTAssertEqual(issue.affectedSquare, sq("d4"))
        XCTAssertEqual(issue.checkingSquares, [])
    }

    func testHarmlessCheckPreservesReplyAffectedKingAndVisibleChecker() throws {
        let assessment = try assessment(
            position: .harmlessCheck,
            tentativeMove: CoachingGoldenMoves.developsKnight
        )
        let issue = try XCTUnwrap(assessment.opponentIssues.first {
            $0.reply == CoachingGoldenMoves.rookChecks && $0.kind == .check
        })

        XCTAssertEqual(issue.answerSquares, [sq("a8")])
        XCTAssertEqual(issue.affectedSquare, sq("g1"))
        XCTAssertEqual(issue.checkingSquares, [sq("a8")])
    }

    func testCheckResolutionClassifiesCaptureBlockAndKingMoveAfterSafetyProof() {
        let state = CoachingGoldenPosition.forcedCheck.state
        let kingMove = Move(from: sq("e1"), to: sq("d1"))

        XCTAssertEqual(
            evaluator.checkResolution(
                for: CoachingGoldenMoves.capturesChecker,
                in: state,
                learner: .white,
                checkingSquares: [sq("e8")]
            ),
            .capturedChecker(checker: .rook, capturer: .bishop)
        )
        XCTAssertEqual(
            evaluator.checkResolution(
                for: CoachingGoldenMoves.blocksChecker,
                in: state,
                learner: .white,
                checkingSquares: [sq("e8")]
            ),
            .blocked(attacker: .rook, blocker: .bishop)
        )
        XCTAssertEqual(
            evaluator.checkResolution(
                for: kingMove,
                in: state,
                learner: .white,
                checkingSquares: [sq("e8")]
            ),
            .movedKing
        )
        XCTAssertNil(evaluator.checkResolution(
            for: Move(from: sq("b5"), to: sq("c4")),
            in: state,
            learner: .white,
            checkingSquares: [sq("e8")]
        ))
    }

    func testOnePawnLossIsADangerProblem() {
        let evaluation = evaluator.evaluate(request(for: CoachingGoldenPosition.endangeredPawn.state))

        XCTAssertEqual(evaluation.dangerProblems.map(\.target), [sq("e3")])
        XCTAssertEqual(evaluation.dangerProblems.first?.worstEstimatedLoss, 1)
    }

    func testProtectedAttackIsNotPositiveLoss() throws {
        let evaluation = evaluator.evaluate(request(for: CoachingGoldenPosition.protectedPawn.state))

        XCTAssertTrue(evaluation.dangerProblems.isEmpty)
        let attack = try XCTUnwrap(
            evaluation.opponentCaptureEstimates.first { $0.capturedSquare == sq("g4") }
        )
        XCTAssertEqual(attack.immediateRecapture, Move(from: sq("h3"), to: sq("g4")))
        XCTAssertLessThanOrEqual(attack.netGainForMover, 0)
    }

    func testUnrelatedMoveDoesNotResolveOnePointDanger() throws {
        let move = Move(from: sq("h1"), to: sq("g1"))

        let evaluation = evaluator.evaluate(request(for: CoachingGoldenPosition.endangeredPawn.state))
        let assessment = try XCTUnwrap(evaluation.moveAssessments[move])

        XCTAssertFalse(assessment.resolvesRequiredDanger)
    }

    func testAddingDefenderResolvesOnePointDanger() throws {
        let evaluation = evaluator.evaluate(request(for: CoachingGoldenPosition.protectPawn.state))
        let assessment = try XCTUnwrap(
            evaluation.moveAssessments[CoachingGoldenMoves.addsPawnDefender]
        )

        XCTAssertTrue(assessment.resolvesRequiredDanger)
    }

    func testIncludesEveryPositiveLossAsDanger() {
        let state = CoachingGoldenPosition.twoDangerPriorities.state

        let evaluation = evaluator.evaluate(
            CoachingRequest(
                committedState: state,
                tentativeMove: nil,
                learner: .white,
                positionRevision: 7,
                context: .start
            )
        )

        XCTAssertEqual(evaluation.dangerProblems.map(\.target), [sq("f3"), sq("a3")])
        XCTAssertEqual(evaluation.dangerProblems.map(\.worstEstimatedLoss), [3, 1])
    }

    func testCheckIsDangerWithoutAssigningMaterialValueToKing() {
        let whiteKing = Square(file: .e, rank: 1)
        let checkingRook = Square(file: .e, rank: 8)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                whiteKing: Piece(kind: .king, color: .white),
                checkingRook: Piece(kind: .rook, color: .black),
                Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
            ]
        )

        let evaluation = evaluator.evaluate(request(for: state))

        XCTAssertEqual(evaluation.checkingPieces, [checkingRook])
        XCTAssertTrue(evaluation.dangerProblems.isEmpty)
    }

    func testOrdersDangerProblemsByGreatestEstimatedLoss() {
        let queen = Square(file: .d, rank: 4)
        let rook = Square(file: .h, rank: 2)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .a, rank: 1): Piece(kind: .king, color: .white),
                Square(file: .b, rank: 8): Piece(kind: .king, color: .black),
                queen: Piece(kind: .queen, color: .white),
                rook: Piece(kind: .rook, color: .white),
                Square(file: .d, rank: 8): Piece(kind: .rook, color: .black),
                Square(file: .e, rank: 5): Piece(kind: .bishop, color: .black),
            ]
        )

        let evaluation = evaluator.evaluate(request(for: state))

        XCTAssertEqual(evaluation.dangerProblems.map(\.target), [queen, rook])
        XCTAssertEqual(evaluation.dangerProblems.map(\.worstEstimatedLoss), [9, 5])
    }

    func testOrdersEqualDangerProblemsByStableSquareOrder() {
        let earlierBishop = Square(file: .b, rank: 2)
        let laterBishop = Square(file: .g, rank: 5)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .h, rank: 1): Piece(kind: .king, color: .white),
                Square(file: .e, rank: 8): Piece(kind: .king, color: .black),
                earlierBishop: Piece(kind: .bishop, color: .white),
                laterBishop: Piece(kind: .bishop, color: .white),
                Square(file: .a, rank: 3): Piece(kind: .pawn, color: .black),
                Square(file: .h, rank: 6): Piece(kind: .pawn, color: .black),
            ]
        )

        let evaluation = evaluator.evaluate(request(for: state))

        XCTAssertEqual(evaluation.dangerProblems.map(\.target), [earlierBishop, laterBishop])
        XCTAssertEqual(evaluation.dangerProblems.map(\.worstEstimatedLoss), [3, 3])
    }

    func testOrdersEqualLossByThreatenedPieceValueBeforeSquareOrder() {
        let bishop = Square(file: .b, rank: 2)
        let rook = Square(file: .g, rank: 5)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .a, rank: 1): Piece(kind: .king, color: .white),
                Square(file: .e, rank: 8): Piece(kind: .king, color: .black),
                bishop: Piece(kind: .bishop, color: .white),
                rook: Piece(kind: .rook, color: .white),
                Square(file: .h, rank: 4): Piece(kind: .pawn, color: .white),
                Square(file: .a, rank: 3): Piece(kind: .pawn, color: .black),
                Square(file: .h, rank: 6): Piece(kind: .bishop, color: .black),
            ]
        )

        let evaluation = evaluator.evaluate(request(for: state))

        XCTAssertEqual(evaluation.dangerProblems.map(\.target), [rook, bishop])
        XCTAssertEqual(evaluation.dangerProblems.map(\.worstEstimatedLoss), [2, 2])
    }

    func testOpponentPromotionCapturesRetainStableLegalMoveIdentities() {
        let attacker = Square(file: .b, rank: 2)
        let target = Square(file: .c, rank: 1)
        let expectedCaptures = [
            Move(from: attacker, to: target, special: .promotion(.queen)),
            Move(from: attacker, to: target, special: .promotion(.rook)),
            Move(from: attacker, to: target, special: .promotion(.bishop)),
            Move(from: attacker, to: target, special: .promotion(.knight)),
        ]
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .h, rank: 8): Piece(kind: .king, color: .white),
                Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                attacker: Piece(kind: .pawn, color: .black),
                target: Piece(kind: .queen, color: .white),
            ]
        )
        var opponentState = state
        opponentState.sideToMove = .black

        XCTAssertEqual(
            LegalMoveGenerator.legalMoves(for: attacker, in: opponentState)
                .filter { $0.to == target },
            expectedCaptures
        )

        let evaluation = evaluator.evaluate(request(for: state))

        XCTAssertTrue(evaluation.opponentHasAnyLegalCapture)
        XCTAssertEqual(evaluation.opponentCaptureEstimates.map(\.move), expectedCaptures)
    }

    func testOpponentPromotionCaptureCreatesSingleDangerSafeTarget() throws {
        let attacker = Square(file: .b, rank: 2)
        let target = Square(file: .c, rank: 1)
        let expectedCaptures = [
            Move(from: attacker, to: target, special: .promotion(.queen)),
            Move(from: attacker, to: target, special: .promotion(.rook)),
            Move(from: attacker, to: target, special: .promotion(.bishop)),
            Move(from: attacker, to: target, special: .promotion(.knight)),
        ]
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .h, rank: 8): Piece(kind: .king, color: .white),
                Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                attacker: Piece(kind: .pawn, color: .black),
                target: Piece(kind: .queen, color: .white),
            ]
        )

        let evaluation = evaluator.evaluate(request(for: state))
        let problem = try XCTUnwrap(evaluation.dangerProblems.first)

        XCTAssertEqual(evaluation.dangerProblems.map(\.target), [target])
        XCTAssertEqual(problem.captures.map(\.move), expectedCaptures)
        XCTAssertEqual(problem.worstEstimatedLoss, 9)
    }

    func testIncludesGainOneLearnerCaptureForTakePolicy() throws {
        let attacker = Square(file: .c, rank: 4)
        let target = Square(file: .d, rank: 5)
        let capture = Move(from: attacker, to: target)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                attacker: Piece(kind: .pawn, color: .white),
                target: Piece(kind: .pawn, color: .black),
            ]
        )

        let evaluation = evaluator.evaluate(request(for: state))
        let estimate = try XCTUnwrap(
            evaluation.learnerCaptureEstimates.first { $0.move == capture }
        )

        XCTAssertTrue(evaluation.learnerHasAnyLegalCapture)
        XCTAssertEqual(estimate.netGainForMover, 1)
    }

    func testWinningCaptureFactNamesMoverTargetAndNoRecapture() throws {
        let evaluation = evaluator.evaluate(
            request(for: CoachingGoldenPosition.winningCapture.state)
        )

        let fact = try XCTUnwrap(
            evaluation.exchangeFacts[CoachingGoldenMoves.bishopWinsRook]
        )

        XCTAssertEqual(fact.mover, .bishop)
        XCTAssertEqual(fact.captured, .rook)
        XCTAssertNil(fact.immediateRecapturer)
        XCTAssertEqual(fact.netGainForLearner, 5)
    }

    func testLosingCaptureFactNamesKingRecapture() throws {
        let move = CoachingGoldenMoves.bishopTakesPawn
        let state = CoachingGoldenPosition.losingCapture.state
        let evaluation = evaluator.evaluate(CoachingRequest(
            committedState: state,
            tentativeMove: move,
            learner: .white,
            positionRevision: 1,
            context: .tentativeMove(origin: .take)
        ))

        let fact = try XCTUnwrap(evaluation.exchangeFacts[move])

        XCTAssertEqual(fact.mover, .bishop)
        XCTAssertEqual(fact.captured, .pawn)
        XCTAssertEqual(fact.immediateRecapturer, .king)
        XCTAssertEqual(fact.netGainForLearner, -2)
    }

    func testRetainsEqualExchangeAtZeroGainForTakeExclusion() throws {
        let attacker = Square(file: .c, rank: 4)
        let target = Square(file: .d, rank: 5)
        let recapturer = Square(file: .e, rank: 6)
        let exchange = Move(from: attacker, to: target)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                attacker: Piece(kind: .bishop, color: .white),
                target: Piece(kind: .bishop, color: .black),
                recapturer: Piece(kind: .pawn, color: .black),
            ]
        )

        let evaluation = evaluator.evaluate(request(for: state))
        let estimate = try XCTUnwrap(
            evaluation.learnerCaptureEstimates.first { $0.move == exchange }
        )

        XCTAssertEqual(estimate.netGainForMover, 0)
        XCTAssertFalse(
            evaluation.learnerCaptureEstimates
                .filter { $0.netGainForMover >= 1 }
                .contains { $0.move == exchange }
        )
    }

    func testCaptureThatResolvesDangerIsIncludedForSafePolicy() throws {
        let bishop = Square(file: .d, rank: 4)
        let attacker = Square(file: .c, rank: 5)
        let resolvingCapture = Move(from: bishop, to: attacker)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                bishop: Piece(kind: .bishop, color: .white),
                attacker: Piece(kind: .pawn, color: .black),
            ]
        )

        let evaluation = evaluator.evaluate(request(for: state))
        let assessment = try XCTUnwrap(evaluation.moveAssessments[resolvingCapture])

        XCTAssertEqual(evaluation.dangerProblems.map(\.target), [bishop])
        XCTAssertTrue(assessment.isLegal)
        XCTAssertTrue(assessment.resolvesRequiredDanger)
    }

    func testIncludesLegalMateInOneMove() {
        let matingMove = Move(
            from: Square(file: .g, rank: 6),
            to: Square(file: .g, rank: 7)
        )
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .f, rank: 6): Piece(kind: .king, color: .white),
                Square(file: .g, rank: 6): Piece(kind: .queen, color: .white),
                Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
            ]
        )

        let evaluation = evaluator.evaluate(request(for: state))

        XCTAssertTrue(evaluation.mateInOneMoves.contains(matingMove))
        XCTAssertEqual(evaluation.moveAssessments[matingMove]?.isLegal, true)
    }

    func testRejectsMoveThatAllowsImmediateMate() throws {
        let learnerMove = Move(
            from: Square(file: .a, rank: 2),
            to: Square(file: .a, rank: 3)
        )
        let matingReply = Move(
            from: Square(file: .g, rank: 3),
            to: Square(file: .g, rank: 2)
        )
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .h, rank: 1): Piece(kind: .king, color: .white),
                Square(file: .a, rank: 2): Piece(kind: .pawn, color: .white),
                Square(file: .f, rank: 3): Piece(kind: .king, color: .black),
                Square(file: .g, rank: 3): Piece(kind: .queen, color: .black),
            ]
        )

        let evaluation = evaluator.evaluate(request(for: state))
        let assessment = try XCTUnwrap(evaluation.moveAssessments[learnerMove])

        XCTAssertTrue(assessment.opponentIssues.contains {
            $0.reply == matingReply
                && $0.kind == .mateInOne
                && $0.severity == .reviseMove
                && $0.answerSquares == [matingReply.from]
                && $0.affectedSquare == sq("h1")
                && $0.checkingSquares == [matingReply.from]
        })
        XCTAssertFalse(assessment.opponentIssues.contains {
            $0.reply == matingReply && $0.kind == .check
        })
    }

    func testRejectsNewOpponentMaterialLossOfTwo() throws {
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
                Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                Square(file: .c, rank: 3): Piece(kind: .bishop, color: .white),
                Square(file: .e, rank: 3): Piece(kind: .pawn, color: .white),
                Square(file: .c, rank: 5): Piece(kind: .pawn, color: .black),
            ]
        )

        let evaluation = evaluator.evaluate(request(for: state))
        let assessment = try XCTUnwrap(evaluation.moveAssessments[learnerMove])

        XCTAssertTrue(assessment.opponentIssues.contains {
            $0.reply == reply
                && $0.kind == .materialLoss(points: 2)
                && $0.severity == .reviseMove
                && $0.answerSquares == [reply.from]
                && $0.affectedSquare == learnerMove.to
                && $0.checkingSquares.isEmpty
        })
    }

    func testHarmlessOpponentCheckHasNoticeSeverity() throws {
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
                Square(file: .h, rank: 2): Piece(kind: .pawn, color: .white),
                Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
                Square(file: .a, rank: 8): Piece(kind: .rook, color: .black),
            ]
        )

        let evaluation = evaluator.evaluate(request(for: state))
        let assessment = try XCTUnwrap(evaluation.moveAssessments[learnerMove])

        XCTAssertTrue(assessment.opponentIssues.contains {
            $0.reply == checkingReply
                && $0.kind == .check
                && $0.severity == .notice
                && $0.answerSquares == [checkingReply.from]
                && $0.affectedSquare == sq("e1")
                && $0.checkingSquares == [checkingReply.from]
        })
        XCTAssertFalse(assessment.opponentIssues.contains {
            $0.reply == checkingReply && $0.kind == .mateInOne
        })
    }

    func testDiscoveredCheckMapsUnchangedCheckerRatherThanMovedBlocker() throws {
        let learnerMove = Move(
            from: Square(file: .a, rank: 2),
            to: Square(file: .a, rank: 3)
        )
        let checker = Square(file: .e, rank: 8)
        let blocker = Square(file: .e, rank: 7)
        let reply = Move(from: blocker, to: Square(file: .d, rank: 6))
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                learnerMove.from: Piece(kind: .pawn, color: .white),
                checker: Piece(kind: .rook, color: .black),
                blocker: Piece(kind: .bishop, color: .black),
                Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
            ]
        )

        let evaluation = evaluator.evaluate(request(for: state))
        let assessment = try XCTUnwrap(evaluation.moveAssessments[learnerMove])
        let issue = try XCTUnwrap(assessment.opponentIssues.first {
            $0.reply == reply && $0.kind == .check
        })

        XCTAssertEqual(issue, CoachingOpponentIssue(
            reply: reply,
            kind: .check,
            severity: .notice,
            affectedSquare: sq("e1"),
            checkingSquares: [checker]
        ))
        XCTAssertEqual(issue.answerSquares, [blocker])
    }

    func testDoubleCheckMapsMovedAndUnchangedCheckersToTheirVisibleSquares() throws {
        let learnerMove = Move(
            from: Square(file: .a, rank: 2),
            to: Square(file: .a, rank: 3)
        )
        let unchangedChecker = Square(file: .e, rank: 8)
        let movedChecker = Square(file: .e, rank: 7)
        let reply = Move(from: movedChecker, to: Square(file: .b, rank: 4))
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                learnerMove.from: Piece(kind: .pawn, color: .white),
                unchangedChecker: Piece(kind: .rook, color: .black),
                movedChecker: Piece(kind: .bishop, color: .black),
                Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
            ]
        )

        let evaluation = evaluator.evaluate(request(for: state))
        let assessment = try XCTUnwrap(evaluation.moveAssessments[learnerMove])
        let issue = try XCTUnwrap(assessment.opponentIssues.first {
            $0.reply == reply && $0.kind == .check
        })

        XCTAssertEqual(issue, CoachingOpponentIssue(
            reply: reply,
            kind: .check,
            severity: .notice,
            affectedSquare: sq("e1"),
            checkingSquares: [unchangedChecker, movedChecker]
        ))
        XCTAssertEqual(issue.answerSquares, [movedChecker])
    }

    func testCastlingCheckMapsRookToItsVisiblePreCastleSquare() throws {
        let learnerMove = Move(
            from: Square(file: .a, rank: 2),
            to: Square(file: .a, rank: 3)
        )
        let king = Square(file: .e, rank: 8)
        let rook = Square(file: .h, rank: 8)
        let reply = Move(
            from: king,
            to: Square(file: .g, rank: 8),
            special: .castleKingside
        )
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .f, rank: 1): Piece(kind: .king, color: .white),
                learnerMove.from: Piece(kind: .pawn, color: .white),
                king: Piece(kind: .king, color: .black),
                rook: Piece(kind: .rook, color: .black),
            ],
            castlingRights: CastlingRights(blackKingside: true)
        )

        let evaluation = evaluator.evaluate(request(for: state))
        let assessment = try XCTUnwrap(evaluation.moveAssessments[learnerMove])
        let issue = try XCTUnwrap(assessment.opponentIssues.first {
            $0.reply == reply && $0.kind == .check
        })

        XCTAssertEqual(issue, CoachingOpponentIssue(
            reply: reply,
            kind: .check,
            severity: .notice,
            affectedSquare: sq("f1"),
            checkingSquares: [rook]
        ))
        XCTAssertEqual(issue.answerSquares, [king])
        XCTAssertFalse(issue.answerSquares.contains(Square(file: .f, rank: 8)))
    }

    func testIncludesPinnedAllowedMoveAsIllegalAssessment() throws {
        let pinnedMove = Move(
            from: Square(file: .e, rank: 2),
            to: Square(file: .f, rank: 2)
        )
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                Square(file: .e, rank: 2): Piece(kind: .rook, color: .white),
                Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
                Square(file: .e, rank: 8): Piece(kind: .rook, color: .black),
            ]
        )

        let evaluation = evaluator.evaluate(request(for: state))
        let assessment = try XCTUnwrap(evaluation.moveAssessments[pinnedMove])

        XCTAssertFalse(assessment.isLegal)
        XCTAssertFalse(assessment.resolvesRequiredDanger)
        XCTAssertTrue(assessment.opponentIssues.isEmpty)
    }

    func testAcceptsBestUnavoidableWorstCaseDefenseAndDowngradesItsLoss() throws {
        let queen = Square(file: .a, rank: 2)
        let bishop = Square(file: .g, rank: 2)
        let bestDefense = Move(from: queen, to: Square(file: .a, rank: 8))
        let worseDefense = Move(from: bishop, to: Square(file: .h, rank: 3))
        let unavoidableReply = Move(
            from: Square(file: .g, rank: 8),
            to: bishop
        )
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .a, rank: 1): Piece(kind: .king, color: .white),
                queen: Piece(kind: .queen, color: .white),
                bishop: Piece(kind: .bishop, color: .white),
                Square(file: .c, rank: 4): Piece(kind: .pawn, color: .white),
                Square(file: .e, rank: 2): Piece(kind: .pawn, color: .white),
                Square(file: .e, rank: 4): Piece(kind: .pawn, color: .white),
                Square(file: .h, rank: 7): Piece(kind: .king, color: .black),
                Square(file: .a, rank: 8): Piece(kind: .rook, color: .black),
                Square(file: .d, rank: 8): Piece(kind: .knight, color: .black),
                Square(file: .g, rank: 8): Piece(kind: .rook, color: .black),
                Square(file: .b, rank: 3): Piece(kind: .bishop, color: .black),
            ]
        )

        let evaluation = evaluator.evaluate(request(for: state))
        let bestAssessment = try XCTUnwrap(evaluation.moveAssessments[bestDefense])
        let worseAssessment = try XCTUnwrap(evaluation.moveAssessments[worseDefense])

        XCTAssertTrue(bestAssessment.resolvesRequiredDanger)
        XCTAssertTrue(bestAssessment.opponentIssues.contains {
            $0.reply == unavoidableReply
                && $0.kind == .materialLoss(points: 3)
                && $0.severity == .notice
        })
        XCTAssertFalse(worseAssessment.resolvesRequiredDanger)
        XCTAssertTrue(worseAssessment.opponentIssues.contains {
            $0.kind == .materialLoss(points: 9)
                && $0.severity == .reviseMove
        })
    }

    func testUsesBeginnerPieceValues() {
        XCTAssertEqual(evaluator.pieceValue(.pawn), 1)
        XCTAssertEqual(evaluator.pieceValue(.knight), 3)
        XCTAssertEqual(evaluator.pieceValue(.bishop), 3)
        XCTAssertEqual(evaluator.pieceValue(.rook), 5)
        XCTAssertEqual(evaluator.pieceValue(.queen), 9)
        XCTAssertNil(evaluator.pieceValue(.king))
    }

    func testPawnTakingDefendedBishopHasNetGainTwo() throws {
        let attacker = Square(file: .c, rank: 4)
        let target = Square(file: .d, rank: 5)
        let recapturer = Square(file: .e, rank: 6)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                attacker: Piece(kind: .pawn, color: .white),
                target: Piece(kind: .bishop, color: .black),
                recapturer: Piece(kind: .pawn, color: .black),
            ]
        )

        let estimate = try XCTUnwrap(
            evaluator.captureEstimate(
                for: Move(from: attacker, to: target),
                in: state
            )
        )

        XCTAssertEqual(estimate.capturedSquare, target)
        XCTAssertEqual(estimate.netGainForMover, 2)
        XCTAssertEqual(estimate.immediateRecapture?.from, recapturer)
        XCTAssertEqual(estimate.immediateRecapture?.to, target)
    }

    func testUndefendedCaptureKeepsCapturedPieceValue() throws {
        let attacker = Square(file: .a, rank: 2)
        let target = Square(file: .a, rank: 7)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                attacker: Piece(kind: .rook, color: .white),
                target: Piece(kind: .knight, color: .black),
            ]
        )

        let estimate = try XCTUnwrap(
            evaluator.captureEstimate(for: Move(from: attacker, to: target), in: state)
        )

        XCTAssertNil(estimate.immediateRecapture)
        XCTAssertEqual(estimate.netGainForMover, 3)
    }

    func testQueenTakingPawnAndBeingRecapturedHasNetLossEight() throws {
        let attacker = Square(file: .c, rank: 4)
        let target = Square(file: .d, rank: 5)
        let recapturer = Square(file: .f, rank: 6)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                attacker: Piece(kind: .queen, color: .white),
                target: Piece(kind: .pawn, color: .black),
                recapturer: Piece(kind: .knight, color: .black),
            ]
        )

        let estimate = try XCTUnwrap(
            evaluator.captureEstimate(for: Move(from: attacker, to: target), in: state)
        )

        XCTAssertEqual(estimate.immediateRecapture, Move(from: recapturer, to: target))
        XCTAssertEqual(estimate.netGainForMover, -8)
    }

    func testMultipleLegalRecapturesUseStableMoveOrdering() throws {
        let attacker = Square(file: .c, rank: 4)
        let target = Square(file: .d, rank: 5)
        let earlierRecapturer = Square(file: .f, rank: 6)
        let laterRecapturer = Square(file: .d, rank: 8)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                attacker: Piece(kind: .bishop, color: .white),
                target: Piece(kind: .pawn, color: .black),
                earlierRecapturer: Piece(kind: .knight, color: .black),
                laterRecapturer: Piece(kind: .queen, color: .black),
            ]
        )

        let estimate = try XCTUnwrap(
            evaluator.captureEstimate(for: Move(from: attacker, to: target), in: state)
        )

        XCTAssertEqual(estimate.immediateRecapture, Move(from: earlierRecapturer, to: target))
    }

    func testPinnedRecapturerDoesNotReduceEstimatedGain() throws {
        let attacker = Square(file: .c, rank: 4)
        let target = Square(file: .d, rank: 5)
        let pinnedRecapturer = Square(file: .f, rank: 6)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .a, rank: 1): Piece(kind: .king, color: .white),
                Square(file: .f, rank: 1): Piece(kind: .rook, color: .white),
                attacker: Piece(kind: .bishop, color: .white),
                target: Piece(kind: .pawn, color: .black),
                pinnedRecapturer: Piece(kind: .knight, color: .black),
                Square(file: .f, rank: 8): Piece(kind: .king, color: .black),
            ]
        )

        let estimate = try XCTUnwrap(
            evaluator.captureEstimate(for: Move(from: attacker, to: target), in: state)
        )

        XCTAssertNil(estimate.immediateRecapture)
        XCTAssertEqual(estimate.netGainForMover, 1)
    }

    func testEnPassantReportsPawnSquareInsteadOfLandingSquare() throws {
        let attacker = Square(file: .e, rank: 5)
        let capturedPawn = Square(file: .d, rank: 5)
        let landingSquare = Square(file: .d, rank: 6)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                attacker: Piece(kind: .pawn, color: .white),
                capturedPawn: Piece(kind: .pawn, color: .black),
            ],
            enPassantTarget: landingSquare
        )

        let estimate = try XCTUnwrap(
            evaluator.captureEstimate(
                for: Move(from: attacker, to: landingSquare, special: .enPassant),
                in: state
            )
        )

        XCTAssertEqual(estimate.capturedSquare, capturedPawn)
        XCTAssertNotEqual(estimate.capturedSquare, estimate.move.to)
        XCTAssertEqual(estimate.netGainForMover, 1)
    }

    func testPromotionCaptureUsesPromotedPieceValueWhenRecaptured() throws {
        let attacker = Square(file: .c, rank: 7)
        let target = Square(file: .d, rank: 8)
        let recapturer = Square(file: .d, rank: 7)
        let promotion = Move(from: attacker, to: target, special: .promotion(.queen))
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                attacker: Piece(kind: .pawn, color: .white),
                target: Piece(kind: .bishop, color: .black),
                recapturer: Piece(kind: .rook, color: .black),
            ]
        )

        let estimate = try XCTUnwrap(evaluator.captureEstimate(for: promotion, in: state))
        let fact = try XCTUnwrap(
            evaluator.exchangeFact(for: estimate, in: state, opponentIssue: nil)
        )

        XCTAssertEqual(estimate.immediateRecapture, Move(from: recapturer, to: target))
        XCTAssertEqual(estimate.netGainForMover, -6)
        XCTAssertEqual(fact.mover, .queen)
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

    private func assessment(
        position: CoachingGoldenPosition,
        tentativeMove: Move
    ) throws -> CoachingMoveAssessment {
        let evaluation = evaluator.evaluate(request(for: position.state))
        return try XCTUnwrap(evaluation.moveAssessments[tentativeMove])
    }
}

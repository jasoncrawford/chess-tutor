import XCTest
@testable import ChessTutor

final class LocalCoachingAdvisorTests: XCTestCase {
    private let advisor = LocalCoachingAdvisor()

    func testStartingKnightMovesHavePreferredAndAcceptableGrades() async throws {
        let advice = try await advisor.advice(
            for: request(for: CoachingGoldenPosition.starting.state)
        )

        XCTAssertEqual(advice.grade(for: Move(from: sq("g1"), to: sq("f3"))), .preferred)
        XCTAssertEqual(advice.grade(for: Move(from: sq("g1"), to: sq("h3"))), .acceptable)
        XCTAssertEqual(advice.grade(for: Move(from: sq("b1"), to: sq("c3"))), .preferred)
        XCTAssertEqual(advice.grade(for: Move(from: sq("b1"), to: sq("a3"))), .acceptable)

        let opening = try XCTUnwrap(advice.wakeTasks.first)
        let candidates = opening.candidates
        XCTAssertEqual(
            candidates.first { $0.move == Move(from: sq("b1"), to: sq("a3")) }?
                .centralityComparison,
            .fartherWithLessMobility(
                alternative: Move(from: sq("b1"), to: sq("c3")),
                candidateMobility: 3,
                alternativeMobility: 5
            )
        )
        XCTAssertEqual(
            candidates.first { $0.move == Move(from: sq("b1"), to: sq("c3")) }?
                .centralityComparison,
            .closerWithMoreMobility(
                alternative: Move(from: sq("b1"), to: sq("a3")),
                candidateMobility: 5,
                alternativeMobility: 3
            )
        )
    }

    func testOpeningTaskCarriesWhetherCastlingIsAnExplicitAlternative() async throws {
        let castleAdvice = try await advisor.advice(
            for: request(for: CoachingGoldenPosition.readyToCastle.state)
        )
        let castleOpening = try XCTUnwrap(castleAdvice.wakeTasks.first {
            if case .opening = $0 { return true }
            return false
        })
        guard case let .opening(firstMove, castleIsAlternative, _) = castleOpening else {
            return XCTFail("Expected canonical opening task")
        }
        XCTAssertFalse(firstMove)
        XCTAssertTrue(castleIsAlternative)

        let nonFirstState = GameState.startingPosition()
            .applyingUnchecked(Move(from: sq("e2"), to: sq("e3")))
            .applyingUnchecked(Move(from: sq("a7"), to: sq("a6")))
        let ordinaryAdvice = try await advisor.advice(for: request(for: nonFirstState))
        let ordinaryOpening = try XCTUnwrap(ordinaryAdvice.wakeTasks.first {
            if case .opening = $0 { return true }
            return false
        })
        guard case let .opening(nonFirst, ordinaryCastleIsAlternative, _) = ordinaryOpening else {
            return XCTFail("Expected ordinary opening task")
        }
        XCTAssertFalse(nonFirst)
        XCTAssertFalse(ordinaryCastleIsAlternative)
    }

    func testStartingTaskCandidatesUseLiteralRankMajorMoveOrder() async throws {
        let advice = try await advisor.advice(
            for: request(for: CoachingGoldenPosition.starting.state)
        )
        let opening = try XCTUnwrap(advice.wakeTasks.first)

        XCTAssertEqual(opening.candidates.map(\.move), [
            Move(from: sq("b1"), to: sq("a3")),
            Move(from: sq("b1"), to: sq("c3")),
            Move(from: sq("g1"), to: sq("f3")),
            Move(from: sq("g1"), to: sq("h3")),
            Move(from: sq("d2"), to: sq("d3")),
            Move(from: sq("d2"), to: sq("d4")),
            Move(from: sq("e2"), to: sq("e3")),
            Move(from: sq("e2"), to: sq("e4")),
        ])
    }

    func testThreatTaskNamesKnightAndRook() async throws {
        let advice = try await advisor.advice(
            for: request(for: CoachingGoldenPosition.createRookThreat.state)
        )
        let task = try XCTUnwrap(advice.wakeTasks.first)

        XCTAssertEqual(
            task,
            .createThreat(
                source: sq("a1"),
                sourcePiece: .knight,
                target: sq("d4"),
                targetPiece: .rook,
                candidates: [
                    .init(
                        move: CoachingGoldenMoves.knightThreatC2,
                        grade: .acceptable
                    ),
                    .init(
                        move: CoachingGoldenMoves.knightThreatB3,
                        grade: .acceptable
                    ),
                ]
            )
        )
    }

    func testMobilityTaskKeepsBeforeAndAfterCounts() async throws {
        let advice = try await advisor.advice(
            for: request(for: CoachingGoldenPosition.cornerKnight.state)
        )

        XCTAssertTrue(advice.wakeTasks.contains(.improveMobility(
            source: sq("a1"),
            piece: .knight,
            sourceIsCorner: true,
            before: 2,
            candidates: [
                .init(
                    move: CoachingGoldenMoves.knightThreatC2,
                    grade: .acceptable,
                    resultingMobility: 6
                ),
                .init(
                    move: CoachingGoldenMoves.knightThreatB3,
                    grade: .acceptable,
                    resultingMobility: 6
                ),
            ]
        )))
    }

    func testStartingPositionOffersMinorAndCenterPawnWakeMoves() async throws {
        let request = CoachingRequest(
            committedState: .startingPosition(),
            tentativeMove: nil,
            learner: .white,
            positionRevision: 0,
            context: .start
        )

        let advice = try await advisor.advice(for: request)
        let wakeMoves = Set(advice.wakeOpportunities.flatMap(\.moves))

        XCTAssertTrue(advice.openingDevelopmentIsRelevant)
        XCTAssertTrue(wakeMoves.contains(Move(
            from: Square(file: .g, rank: 1),
            to: Square(file: .f, rank: 3)
        )))
        XCTAssertTrue(wakeMoves.contains(Move(
            from: Square(file: .e, rank: 2),
            to: Square(file: .e, rank: 4)
        )))
        XCTAssertFalse(wakeMoves.contains(Move(
            from: Square(file: .a, rank: 2),
            to: Square(file: .a, rank: 3)
        )))
    }

    func testUnsupportedQuietPositionUsesFallbackConfidence() async throws {
        let advice = try await advisor.advice(for: CoachingTestFixtures.noRecognizedPurposeRequest)

        XCTAssertTrue(advice.dangerProblems.isEmpty)
        XCTAssertTrue(advice.takeOpportunities.isEmpty)
        XCTAssertTrue(advice.wakeOpportunities.isEmpty)
        XCTAssertEqual(advice.confidence, .unsupported)
    }

    func testBlackOpeningUsesBlackHomeSquaresAndForwardDirection() async throws {
        var state = GameState.startingPosition()
        state.sideToMove = .black

        let advice = try await advisor.advice(for: request(for: state))
        let wakeMoves = Set(advice.wakeOpportunities.flatMap(\.moves))

        XCTAssertTrue(advice.openingDevelopmentIsRelevant)
        XCTAssertTrue(wakeMoves.contains(Move(
            from: Square(file: .g, rank: 8),
            to: Square(file: .f, rank: 6)
        )))
        XCTAssertTrue(wakeMoves.contains(Move(
            from: Square(file: .e, rank: 7),
            to: Square(file: .e, rank: 5)
        )))
        XCTAssertFalse(wakeMoves.contains(Move(
            from: Square(file: .a, rank: 7),
            to: Square(file: .a, rank: 6)
        )))
    }

    func testOpeningDevelopmentUsesThePiecesTrueOriginalHomeSquares() async throws {
        var state = GameState.startingPosition()
        state.board[Square(file: .b, rank: 1)] = Piece(kind: .bishop, color: .white)
        state.board[Square(file: .c, rank: 1)] = Piece(kind: .knight, color: .white)
        state.board[Square(file: .a, rank: 2)] = nil

        let advice = try await advisor.advice(for: request(for: state))
        let developmentMoves = advice.wakeOpportunities
            .filter { $0.concept == .developsKnightOrBishop }
            .flatMap(\.moves)

        XCTAssertTrue(advice.openingDevelopmentIsRelevant)
        XCTAssertFalse(developmentMoves.contains { $0.from == Square(file: .b, rank: 1) })
        XCTAssertFalse(developmentMoves.contains { $0.from == Square(file: .c, rank: 1) })
    }

    func testOpeningContextRequiresEveryPositionEvidenceCondition() async throws {
        let starting = GameState.startingPosition()
        let startingAdvice = try await advisor.advice(for: request(for: starting))
        XCTAssertTrue(startingAdvice.openingDevelopmentIsRelevant)

        var noLearnerMinorAtHome = starting
        for file in [Square.File.b, .c, .f, .g] {
            noLearnerMinorAtHome.board[Square(file: file, rank: 1)] = nil
        }
        let noLearnerMinorAdvice = try await advisor.advice(
            for: request(for: noLearnerMinorAtHome)
        )
        XCTAssertFalse(noLearnerMinorAdvice.openingDevelopmentIsRelevant)

        var missingOpponentQueen = starting
        missingOpponentQueen.board[Square(file: .d, rank: 8)] = nil
        let missingOpponentQueenAdvice = try await advisor.advice(
            for: request(for: missingOpponentQueen)
        )
        XCTAssertFalse(missingOpponentQueenAdvice.openingDevelopmentIsRelevant)

        var tooFewOpponentPieces = starting
        for file in [Square.File.b, .c, .f, .g, .h] {
            tooFewOpponentPieces.board[Square(file: file, rank: 8)] = nil
        }
        let tooFewOpponentPiecesAdvice = try await advisor.advice(
            for: request(for: tooFewOpponentPieces)
        )
        XCTAssertFalse(tooFewOpponentPiecesAdvice.openingDevelopmentIsRelevant)
    }

    func testLegalCastleIsAGeneralWakeOpportunity() async throws {
        let castle = Move(
            from: Square(file: .e, rank: 1),
            to: Square(file: .g, rank: 1),
            special: .castleKingside
        )
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                castle.from: Piece(kind: .king, color: .white),
                Square(file: .h, rank: 1): Piece(kind: .rook, color: .white),
                Square(file: .e, rank: 8): Piece(kind: .king, color: .black),
            ],
            castlingRights: CastlingRights(whiteKingside: true)
        )

        let advice = try await advisor.advice(for: request(for: state))
        let opportunity = advice.wakeOpportunities.first { $0.moves == [castle] }

        XCTAssertFalse(advice.openingDevelopmentIsRelevant)
        XCTAssertEqual(opportunity?.concept, .castlesForKingSafety)
        XCTAssertEqual(opportunity?.evidence, .castle(castle))
    }

    func testCanonicalCastleIsVerifiedWakeEvidenceWhenEPawnIsProtected() async throws {
        let advice = try await advisor.advice(
            for: request(for: CoachingGoldenPosition.readyToCastle.state)
        )

        XCTAssertTrue(advice.wakeTasks.contains(.castle(move: CoachingGoldenMoves.castle)))
        XCTAssertTrue(advice.wakeOpportunities.contains { opportunity in
            opportunity.moves.contains(CoachingGoldenMoves.castle)
        })
        XCTAssertTrue(advice.insights.contains { insight in
            insight.concept == .castlesForKingSafety
                && insight.candidateMoves.contains(CoachingGoldenMoves.castle)
        })
    }

    func testMovedPieceCanAddANewLegalDefenderToCapturablePiece() async throws {
        let defendingMove = Move(
            from: Square(file: .b, rank: 1),
            to: Square(file: .c, rank: 3)
        )
        let target = Square(file: .e, rank: 4)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .h, rank: 1): Piece(kind: .king, color: .white),
                defendingMove.from: Piece(kind: .knight, color: .white),
                target: Piece(kind: .bishop, color: .white),
                Square(file: .b, rank: 7): Piece(kind: .bishop, color: .black),
                Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
            ]
        )

        let advice = try await advisor.advice(for: request(for: state))
        let opportunity = advice.wakeOpportunities.first { $0.moves == [defendingMove] }

        XCTAssertFalse(advice.openingDevelopmentIsRelevant)
        XCTAssertEqual(opportunity?.concept, .addsUsefulDefender)
        XCTAssertEqual(
            opportunity?.evidence,
            .defender(source: defendingMove.from, target: target)
        )
    }

    func testMovedPieceCanCreateSafeThreatAgainstUndefendedPiece() async throws {
        let threateningMove = Move(
            from: Square(file: .b, rank: 1),
            to: Square(file: .c, rank: 3)
        )
        let target = Square(file: .d, rank: 5)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .h, rank: 1): Piece(kind: .king, color: .white),
                threateningMove.from: Piece(kind: .knight, color: .white),
                target: Piece(kind: .pawn, color: .black),
                Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
            ]
        )

        let advice = try await advisor.advice(for: request(for: state))
        let opportunity = advice.wakeOpportunities.first {
            $0.concept == .createsSafeImmediateThreat && $0.moves == [threateningMove]
        }

        XCTAssertEqual(
            opportunity?.evidence,
            .threat(source: threateningMove.from, target: target)
        )
    }

    func testMovedPieceCanCreateSafeThreatAgainstMoreValuableDefendedPiece() async throws {
        let threateningMove = Move(
            from: Square(file: .b, rank: 1),
            to: Square(file: .c, rank: 3)
        )
        let target = Square(file: .d, rank: 5)
        let defender = Square(file: .e, rank: 6)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .h, rank: 1): Piece(kind: .king, color: .white),
                threateningMove.from: Piece(kind: .knight, color: .white),
                target: Piece(kind: .rook, color: .black),
                defender: Piece(kind: .pawn, color: .black),
                Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
            ]
        )
        let after = state.applyingUnchecked(threateningMove)
        XCTAssertTrue(PositionAnalyzer.analyze(after).supporters(of: target).contains(defender))

        let advice = try await advisor.advice(for: request(for: state))
        let opportunity = advice.wakeOpportunities.first {
            $0.concept == .createsSafeImmediateThreat && $0.moves == [threateningMove]
        }

        XCTAssertEqual(
            opportunity?.evidence,
            .threat(source: threateningMove.from, target: target)
        )
    }

    func testNonPawnMovingTowardCentralSixteenWithTwoMoreMovesImprovesActivity() async throws {
        let activityMove = Move(
            from: Square(file: .a, rank: 1),
            to: Square(file: .b, rank: 2)
        )
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .h, rank: 1): Piece(kind: .king, color: .white),
                activityMove.from: Piece(kind: .bishop, color: .white),
                Square(file: .h, rank: 7): Piece(kind: .king, color: .black),
            ]
        )
        let beforeMobility = LegalMoveGenerator.legalMoves(
            for: activityMove.from,
            by: .white,
            in: state
        ).count
        let after = state.applyingUnchecked(activityMove)
        let afterMobility = LegalMoveGenerator.legalMoves(
            for: activityMove.to,
            by: .white,
            in: after
        ).count
        XCTAssertEqual(afterMobility, beforeMobility + 2)

        let advice = try await advisor.advice(for: request(for: state))
        let opportunity = advice.wakeOpportunities.first {
            $0.concept == .improvesCentralActivity && $0.moves == [activityMove]
        }

        XCTAssertEqual(
            opportunity?.evidence,
            .mobility(
                source: activityMove.from,
                destination: activityMove.to,
                before: beforeMobility,
                after: afterMobility
            )
        )
    }

    func testMovingCloserToCenterWithoutTwoMoreMovesDoesNotImproveActivity() async throws {
        let quietMove = Move(
            from: Square(file: .a, rank: 1),
            to: Square(file: .b, rank: 1)
        )
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                quietMove.from: Piece(kind: .rook, color: .white),
                Square(file: .h, rank: 1): Piece(kind: .king, color: .white),
                Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
            ]
        )
        let beforeMobility = LegalMoveGenerator.legalMoves(
            for: quietMove.from,
            by: .white,
            in: state
        ).count
        let after = state.applyingUnchecked(quietMove)
        let afterMobility = LegalMoveGenerator.legalMoves(
            for: quietMove.to,
            by: .white,
            in: after
        ).count
        XCTAssertLessThan(afterMobility, beforeMobility + 2)

        let advice = try await advisor.advice(for: request(for: state))

        XCTAssertFalse(advice.wakeOpportunities.contains {
            $0.concept == .improvesCentralActivity && $0.moves == [quietMove]
        })
    }

    func testPurposefulOpeningMoveThatLeavesRequiredDangerIsExcluded() async throws {
        let unsafeDevelopment = Move(
            from: Square(file: .g, rank: 1),
            to: Square(file: .f, rank: 3)
        )
        var state = GameState.startingPosition()
        state.board[Square(file: .d, rank: 1)] = nil
        state.board[Square(file: .b, rank: 3)] = Piece(kind: .queen, color: .white)
        state.board[Square(file: .c, rank: 8)] = nil
        state.board[Square(file: .a, rank: 4)] = Piece(kind: .bishop, color: .black)

        let advice = try await advisor.advice(for: request(for: state))
        let assessment = try XCTUnwrap(advice.moveAssessments[unsafeDevelopment])

        XCTAssertTrue(advice.openingDevelopmentIsRelevant)
        XCTAssertTrue(assessment.isLegal)
        XCTAssertFalse(assessment.resolvesRequiredDanger)
        XCTAssertFalse(advice.wakeOpportunities.contains {
            $0.moves.contains(unsafeDevelopment)
        })
    }

    func testOtherwiseDevelopingMoveThatIsIllegalIsExcluded() async throws {
        let pinnedDevelopment = Move(
            from: Square(file: .g, rank: 1),
            to: Square(file: .f, rank: 3)
        )
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .h, rank: 1): Piece(kind: .king, color: .white),
                pinnedDevelopment.from: Piece(kind: .knight, color: .white),
                Square(file: .d, rank: 2): Piece(kind: .queen, color: .white),
                Square(file: .c, rank: 2): Piece(kind: .bishop, color: .white),
                Square(file: .e, rank: 2): Piece(kind: .rook, color: .white),
                Square(file: .a, rank: 1): Piece(kind: .rook, color: .black),
                Square(file: .d, rank: 8): Piece(kind: .queen, color: .black),
                Square(file: .c, rank: 8): Piece(kind: .bishop, color: .black),
                Square(file: .b, rank: 8): Piece(kind: .knight, color: .black),
                Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
            ]
        )

        let advice = try await advisor.advice(for: request(for: state))
        let assessment = try XCTUnwrap(advice.moveAssessments[pinnedDevelopment])

        XCTAssertTrue(advice.openingDevelopmentIsRelevant)
        XCTAssertFalse(assessment.isLegal)
        XCTAssertFalse(advice.wakeOpportunities.contains {
            $0.moves.contains(pinnedDevelopment)
        })
    }

    func testPurposefulMoveWithReviseLevelReplyIsExcluded() async throws {
        let unsafeActivity = Move(
            from: Square(file: .a, rank: 1),
            to: Square(file: .b, rank: 2)
        )
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .h, rank: 1): Piece(kind: .king, color: .white),
                unsafeActivity.from: Piece(kind: .bishop, color: .white),
                Square(file: .b, rank: 8): Piece(kind: .rook, color: .black),
                Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
            ]
        )

        let advice = try await advisor.advice(for: request(for: state))
        let assessment = try XCTUnwrap(advice.moveAssessments[unsafeActivity])

        XCTAssertTrue(assessment.isLegal)
        XCTAssertTrue(assessment.resolvesRequiredDanger)
        XCTAssertTrue(assessment.opponentIssues.contains { $0.severity == .reviseMove })
        XCTAssertFalse(advice.wakeOpportunities.contains {
            $0.moves.contains(unsafeActivity)
        })
    }

    func testWakeOrdersPurposeBeforeStableSourceAndRetainsEveryAlternative() async throws {
        let startingAdvice = try await advisor.advice(for: CoachingRequest(
            committedState: .startingPosition(),
            tentativeMove: nil,
            learner: .white,
            positionRevision: 0,
            context: .start
        ))
        let expectedOpeningMoves: Set<Move> = [
            Move(from: Square(file: .b, rank: 1), to: Square(file: .a, rank: 3)),
            Move(from: Square(file: .b, rank: 1), to: Square(file: .c, rank: 3)),
            Move(from: Square(file: .d, rank: 2), to: Square(file: .d, rank: 3)),
            Move(from: Square(file: .d, rank: 2), to: Square(file: .d, rank: 4)),
            Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 3)),
            Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4)),
            Move(from: Square(file: .g, rank: 1), to: Square(file: .f, rank: 3)),
            Move(from: Square(file: .g, rank: 1), to: Square(file: .h, rank: 3)),
        ]
        let retainedOpeningMoves = Set(
            startingAdvice.wakeOpportunities
                .filter {
                    $0.concept == .developsKnightOrBishop
                        || $0.concept == .advancesCenterPawn
                }
                .flatMap(\.moves)
        )

        XCTAssertEqual(retainedOpeningMoves, expectedOpeningMoves)
        XCTAssertEqual(
            startingAdvice.wakeOpportunities.first?.moves.first?.from,
            Square(file: .b, rank: 1)
        )
        for move in expectedOpeningMoves {
            XCTAssertTrue(try XCTUnwrap(startingAdvice.moveAssessments[move]).isAcceptable)
        }

        let multiPurposeMove = Move(
            from: Square(file: .b, rank: 1),
            to: Square(file: .c, rank: 3)
        )
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .h, rank: 1): Piece(kind: .king, color: .white),
                multiPurposeMove.from: Piece(kind: .knight, color: .white),
                Square(file: .e, rank: 2): Piece(kind: .bishop, color: .white),
                Square(file: .e, rank: 8): Piece(kind: .rook, color: .black),
                Square(file: .d, rank: 5): Piece(kind: .pawn, color: .black),
                Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
            ]
        )

        let multiPurposeAdvice = try await advisor.advice(for: request(for: state))
        let orderedConcepts = multiPurposeAdvice.wakeOpportunities
            .filter { $0.moves == [multiPurposeMove] }
            .map(\.concept)

        XCTAssertEqual(
            orderedConcepts,
            [.addsUsefulDefender, .createsSafeImmediateThreat, .improvesCentralActivity]
        )
        let assessmentWakeConcepts = try XCTUnwrap(
            multiPurposeAdvice.moveAssessments[multiPurposeMove]
        ).concepts.filter {
            [
                CoachingConcept.addsUsefulDefender,
                .createsSafeImmediateThreat,
                .improvesCentralActivity,
            ].contains($0)
        }
        XCTAssertEqual(
            assessmentWakeConcepts,
            [.addsUsefulDefender, .createsSafeImmediateThreat, .improvesCentralActivity]
        )
    }

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

    func testEqualLossUsesPieceValueToChoosePrimaryDanger() async throws {
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

        let advice = try await advisor.advice(for: request(for: state))

        XCTAssertEqual(advice.dangerProblems.map(\.worstEstimatedLoss), [2, 2])
        XCTAssertEqual(advice.primaryDangerProblems.map(\.target), [rook])
    }

    func testEqualLossAndPieceValueKeepBothDangersPrimary() async throws {
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

        let advice = try await advisor.advice(for: request(for: state))

        XCTAssertEqual(advice.primaryDangerProblems.map(\.target), [earlierBishop, laterBishop])
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

        XCTAssertEqual(mateIssue.answerSquares, [Square(file: .g, rank: 3)])
        XCTAssertTrue(assessment.concepts.contains(.profitableCapture))
        XCTAssertTrue(assessment.concepts.contains(.allowsMateInOne))
        XCTAssertEqual(
            moveInsight(.allowsMateInOne, move: badCapture, in: advice)?.evidence,
            .opponentReply(mateIssue)
        )
        XCTAssertFalse(advice.takeOpportunities.flatMap(\.moves).contains(badCapture))
        XCTAssertFalse(assessment.isAcceptable)
    }

    func testResolvingEqualExchangeIsAcceptedForSafeButExcludedFromTake() async throws {
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
        XCTAssertFalse(advice.takeOpportunities.contains {
            $0.concept == .captureResolvesDanger && $0.moves == [exchange]
        })
        XCTAssertTrue(assessment.isAcceptable)
    }

    func testNonCaptureMateIsAcceptedButNotOfferedAsASafeCapture() async throws {
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
        XCTAssertFalse(advice.takeOpportunities.contains {
            $0.concept == .mateInOne && $0.moves == [matingMove]
        })
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

        XCTAssertEqual(issue.answerSquares, [checkingReply.from])
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

private extension CoachingTestFixtures {
    static var noRecognizedPurposeRequest: CoachingRequest {
        CoachingRequest(
            committedState: state(
                sideToMove: .white,
                pieces: [
                    Square(file: .d, rank: 4): Piece(kind: .king, color: .white),
                    Square(file: .a, rank: 2): Piece(kind: .pawn, color: .white),
                    Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
                ]
            ),
            tentativeMove: nil,
            learner: .white,
            positionRevision: 1,
            context: .start
        )
    }
}

import XCTest
@testable import ChessTutor

final class CoachingReconcilerTests: XCTestCase {
    func testWakeStepIsDerivedFromCurrentSelection() {
        let purpose = CoachingWakePurpose.openingDevelopment(firstMove: true)
        let cases: [(
            name: String,
            selectedSquare: Square?,
            expectedStage: CoachingStage,
            expectedQuestionID: CoachingQuestionID,
            expectedFeedback: CoachingFeedback?
        )] = [
            (
                "cleared selection",
                nil,
                .wakeChoosePiece(purpose: purpose),
                .wakeSource(purpose: purpose),
                nil
            ),
            (
                "recommended knight",
                CoachingTestFixtures.openingKnight,
                .wakeChooseMove(piece: CoachingTestFixtures.openingKnight, purpose: purpose),
                .wakeMove(source: CoachingTestFixtures.openingKnight, purpose: purpose),
                nil
            ),
            (
                "different recommended knight",
                CoachingTestFixtures.alternateKnight,
                .wakeChooseMove(piece: CoachingTestFixtures.alternateKnight, purpose: purpose),
                .wakeMove(source: CoachingTestFixtures.alternateKnight, purpose: purpose),
                nil
            ),
            (
                "blocked learner rook",
                Square(file: .a, rank: 1),
                .wakeChoosePiece(purpose: purpose),
                .wakeSource(purpose: purpose),
                .blockedWakePiece(piece: .rook, blocker: .pawn)
            ),
            (
                "movable noncandidate learner pawn",
                Square(file: .e, rank: 2),
                .wakeChoosePiece(purpose: purpose),
                .wakeSource(purpose: purpose),
                .notWakeCandidate(piece: .pawn, purpose: purpose)
            ),
            (
                "opponent knight",
                Square(file: .b, rank: 8),
                .wakeChoosePiece(purpose: purpose),
                .wakeSource(purpose: purpose),
                .expectedLearnerPiece
            ),
        ]

        for testCase in cases {
            let result = CoachingReconciler().derive(
                learner: .white,
                episode: episode(
                    advice: CoachingTestFixtures.startingPositionAdvice,
                    selectedSquare: testCase.selectedSquare
                )
            )

            XCTAssertEqual(result.stage, testCase.expectedStage, testCase.name)
            XCTAssertEqual(result.questionID, testCase.expectedQuestionID, testCase.name)
            XCTAssertEqual(result.derivedFeedback, testCase.expectedFeedback, testCase.name)
        }
    }

    func testSafeEvidenceIsUsedOnlyWhileItsPrerequisitesRemainValid() {
        var episode = episode(advice: CoachingTestFixtures.multipleDangerAdvice)
        episode.evidence.safeTarget = CoachingTestFixtures.whiteQueen
        episode.evidence.safeAttacker = CoachingTestFixtures.blackBishop
        XCTAssertEqual(
            CoachingReconciler().derive(learner: .white, episode: episode).questionID,
            .safeResolve(
                target: CoachingTestFixtures.whiteQueen,
                attacker: CoachingTestFixtures.blackBishop
            )
        )

        episode.evidence.safeTarget = CoachingTestFixtures.whiteRook
        let changedTarget = CoachingReconciler().derive(learner: .white, episode: episode)
        XCTAssertEqual(changedTarget.stage, .safeLocate)
        XCTAssertEqual(changedTarget.questionID, .safeLocate)
    }

    func testCheckingPieceEvidenceMustMatchCurrentAdvice() {
        let advice = CoachingTestFixtures.advice(
            checking: [CoachingTestFixtures.blackBishop],
            opponentHasCapture: true,
            learnerHasCapture: false
        )
        var episode = episode(advice: advice)
        episode.evidence.checkingPiece = CoachingTestFixtures.blackRook

        let invalid = CoachingReconciler().derive(learner: .white, episode: episode)
        XCTAssertEqual(invalid.stage, .checkLocate)
        XCTAssertEqual(invalid.questionID, .checkLocate)

        episode.evidence.checkingPiece = CoachingTestFixtures.blackBishop
        let valid = CoachingReconciler().derive(learner: .white, episode: episode)
        XCTAssertEqual(valid.stage, .checkResolve)
        XCTAssertEqual(
            valid.questionID,
            .checkResolve(checker: CoachingTestFixtures.blackBishop)
        )
    }

    func testAbsenceEvidenceCannotSkipAnExistingSafeOrTakeAnswer() {
        var safeEpisode = episode(advice: CoachingTestFixtures.multipleDangerAdvice)
        safeEpisode.evidence.confirmedSafeAbsence = true
        let safe = CoachingReconciler().derive(learner: .white, episode: safeEpisode)
        XCTAssertEqual(safe.stage, .safeLocate)
        XCTAssertEqual(safe.questionID, .safeLocate)

        var takeEpisode = episode(advice: CoachingTestFixtures.takeAdvice)
        takeEpisode.evidence.confirmedTakeAbsence = true
        let take = CoachingReconciler().derive(learner: .white, episode: takeEpisode)
        XCTAssertEqual(take.stage, .takeChooseMove)
        XCTAssertEqual(take.questionID, .take)
    }

    func testReplyEvidenceForDifferentTentativeMoveIsIgnored() {
        let move = CoachingTestFixtures.openingKnightMove
        let staleMove = CoachingTestFixtures.alternateKnightMove
        let issue = CoachingTestFixtures.issue(
            reply: Move(from: CoachingTestFixtures.blackBishop, to: move.to),
            kind: .materialLoss(points: 3),
            severity: .reviseMove,
            answers: [CoachingTestFixtures.blackBishop]
        )
        var episode = episode(
            advice: CoachingTestFixtures.startingPositionAdvice,
            selectedSquare: move.to,
            tentativeMove: move
        )
        episode.evidence.tentativeOrigin = .wake
        episode.evidence.replyAnswer = .issue(move: staleMove, issue: issue)
        episode.knowledge.tentativeAdvice = CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: .wake,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                issues: [issue],
                opponentActivities: [CoachingTestFixtures.opponentActivity(
                    reply: issue.reply,
                    opponentPiece: .knight,
                    capturedSquare: move.to,
                    capturedPiece: .knight,
                    netGainForOpponent: 3
                )],
                concepts: [.developsKnightOrBishop],
                isTacticallyAcceptable: false
            )
        )

        let result = CoachingReconciler().derive(learner: .white, episode: episode)
        XCTAssertEqual(result.stage, .opponentCheck(move: move, origin: .wake))
        XCTAssertEqual(result.questionID, .opponentReply(move: move, origin: .wake))
        XCTAssertNil(result.derivedFeedback)
    }

    func testTentativeMoveWithoutApplicableAdviceAwaitsAndRequestsExactContext() {
        let move = CoachingTestFixtures.openingKnightMove
        var episode = episode(
            advice: CoachingTestFixtures.startingPositionAdvice,
            selectedSquare: move.to,
            tentativeMove: move
        )
        episode.evidence.tentativeOrigin = .wake

        let result = CoachingReconciler().derive(learner: .white, episode: episode)
        XCTAssertEqual(result.stage, .awaitingAdvice(origin: .wake))
        XCTAssertNil(result.questionID)
        XCTAssertEqual(result.requestedAdvice, .tentativeMove(origin: .wake))
    }

    func testExactQuietTentativeAssessmentCompletesWithoutOpponentReply() {
        let move = CoachingTestFixtures.openingKnightMove
        var episode = episode(
            advice: CoachingTestFixtures.startingPositionAdvice,
            selectedSquare: move.to,
            tentativeMove: move
        )
        episode.evidence.tentativeOrigin = .wake
        episode.knowledge.tentativeAdvice = CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: .wake,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                concepts: [.developsKnightOrBishop]
            )
        )

        let result = CoachingReconciler().derive(learner: .white, episode: episode)
        XCTAssertEqual(
            result.stage,
            .complete(
                move: move,
                origin: .wake,
                concepts: [.developsKnightOrBishop]
            )
        )
        XCTAssertEqual(result.questionID, .complete(move: move, origin: .wake))
        XCTAssertNil(result.promptOverride)
        XCTAssertNil(result.derivedFeedback)
        XCTAssertNil(result.requestedAdvice)
    }

    func testTentativeAdviceRequiresExactEvaluatorAssessment() {
        let move = CoachingTestFixtures.openingKnightMove
        let alternateMove = CoachingTestFixtures.alternateKnightMove
        let source = CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: .wake,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                concepts: [.developsKnightOrBishop]
            )
        )
        let invalid = replacingEvaluationAssessments(
            in: source,
            with: [move: CoachingTestFixtures.acceptableAssessment(
                alternateMove,
                concepts: [.developsKnightOrBishop]
            )]
        )
        var episode = episode(
            advice: CoachingTestFixtures.startingPositionAdvice,
            selectedSquare: move.to,
            tentativeMove: move
        )
        episode.evidence.tentativeOrigin = .wake
        episode.knowledge.tentativeAdvice = invalid

        let result = CoachingReconciler().derive(learner: .white, episode: episode)

        XCTAssertEqual(result.stage, .awaitingAdvice(origin: .wake))
        XCTAssertNil(result.questionID)
        XCTAssertEqual(result.requestedAdvice, .tentativeMove(origin: .wake))
    }

    func testTentativeAdviceRequiresRetainedPositionAdviceAtExactRevision() {
        let move = CoachingTestFixtures.openingKnightMove
        let request = CoachingRequest(
            committedState: .startingPosition(),
            tentativeMove: move,
            learner: .white,
            positionRevision: 8,
            context: .tentativeMove(origin: .wake)
        )
        var episode = episode(
            advice: CoachingTestFixtures.startingPositionAdvice,
            selectedSquare: move.to,
            tentativeMove: move
        )
        episode.interaction = CoachingInteractionSnapshot(
            selectedSquare: move.to,
            tentativeMove: move,
            positionRevision: 8
        )
        episode.evidence.tentativeOrigin = .wake
        episode.knowledge.tentativeAdvice = CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: .wake,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                concepts: [.developsKnightOrBishop]
            )
        ).replacingRequest(with: request)

        let result = CoachingReconciler().derive(learner: .white, episode: episode)

        XCTAssertEqual(result.stage, .awaitingAdvice(origin: .wake))
        XCTAssertNil(result.questionID)
        XCTAssertEqual(result.requestedAdvice, .tentativeMove(origin: .wake))
    }

    func testTentativeMoveNeverReturnsToPositionLevelQuestion() {
        let move = CoachingTestFixtures.fallbackMove
        var episode = episode(
            advice: CoachingTestFixtures.nontrivialTakeClearAdvice,
            selectedSquare: move.to,
            tentativeMove: move
        )
        episode.evidence.tentativeOrigin = .take
        episode.knowledge.tentativeAdvice = CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: .take,
            assessment: CoachingTestFixtures.acceptableAssessment(move)
        )

        let result = CoachingReconciler().derive(learner: .white, episode: episode)

        XCTAssertEqual(
            result.stage,
            .complete(move: move, origin: .take, concepts: [])
        )
        XCTAssertEqual(result.questionID, .complete(move: move, origin: .take))
        XCTAssertNil(result.derivedFeedback)
    }

    func testIllegalTentativeMoveDerivesMoveSpecificRevision() {
        let move = CoachingTestFixtures.openingKnightMove
        let illegal = CoachingMoveAssessment(
            move: move,
            isLegal: false,
            resolvesRequiredDanger: false,
            opponentIssues: [],
            opponentActivities: [],
            concepts: [],
            isTacticallyAcceptable: false
        )
        var episode = episode(
            advice: CoachingTestFixtures.startingPositionAdvice,
            selectedSquare: move.to,
            tentativeMove: move
        )
        episode.evidence.tentativeOrigin = .wake
        episode.knowledge.tentativeAdvice = CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: .wake,
            assessment: illegal
        )

        let result = CoachingReconciler().derive(learner: .white, episode: episode)
        XCTAssertEqual(result.stage, .reviseMove(origin: .wake))
        XCTAssertEqual(result.questionID, .revise(move: move, origin: .wake))
        XCTAssertEqual(result.promptOverride, .illegalKingSafety)
        XCTAssertNil(result.derivedFeedback)
    }

    func testUnresolvedSafeMoveDerivesMoveSpecificRevision() {
        let move = CoachingTestFixtures.safeMove
        var episode = episode(
            advice: CoachingTestFixtures.multipleDangerAdvice,
            selectedSquare: move.to,
            tentativeMove: move
        )
        episode.evidence.safeTarget = CoachingTestFixtures.whiteQueen
        episode.evidence.safeAttacker = CoachingTestFixtures.blackBishop
        episode.evidence.tentativeOrigin = .safe
        episode.knowledge.tentativeAdvice = CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: .safe,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                resolvesRequiredDanger: false,
                isTacticallyAcceptable: false
            ),
            danger: CoachingTestFixtures.multipleDangerAdvice.dangerProblems
        )

        let result = CoachingReconciler().derive(learner: .white, episode: episode)
        XCTAssertEqual(result.stage, .reviseMove(origin: .safe))
        XCTAssertEqual(result.questionID, .revise(move: move, origin: .safe))
        XCTAssertEqual(
            result.derivedFeedback,
            .dangerStillPresent(attacker: .bishop, target: .queen)
        )
    }

    func testUnresolvedSafeFeedbackUsesOnlyEvidenceValidForRederivedQuestion() {
        let move = CoachingTestFixtures.safeMove
        var episode = episode(
            advice: CoachingTestFixtures.multipleDangerAdvice,
            selectedSquare: move.to,
            tentativeMove: move
        )
        episode.evidence.safeTarget = CoachingTestFixtures.whiteRook
        episode.evidence.safeAttacker = CoachingTestFixtures.blackBishop
        episode.evidence.tentativeOrigin = .safe
        episode.knowledge.tentativeAdvice = CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: .safe,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                resolvesRequiredDanger: false,
                isTacticallyAcceptable: false
            ),
            danger: CoachingTestFixtures.multipleDangerAdvice.dangerProblems
        )

        let result = CoachingReconciler().derive(learner: .white, episode: episode)
        XCTAssertEqual(result.stage, .reviseMove(origin: .safe))
        XCTAssertEqual(result.questionID, .revise(move: move, origin: .safe))
        XCTAssertEqual(
            result.derivedFeedback,
            .dangerStillPresent(attacker: nil, target: .queen)
        )

        episode.evidence.safeTarget = CoachingTestFixtures.openingKnight
        let invalidTarget = CoachingReconciler().derive(learner: .white, episode: episode)
        XCTAssertEqual(invalidTarget.stage, .reviseMove(origin: .safe))
        XCTAssertEqual(invalidTarget.questionID, .revise(move: move, origin: .safe))
        XCTAssertEqual(
            invalidTarget.derivedFeedback,
            .dangerStillPresent(attacker: nil, target: .queen)
        )
    }

    func testTacticallySafeUnpurposefulWakeMoveCompletesWithoutInventedPurpose() {
        let move = CoachingTestFixtures.alternateKnightMove
        var episode = episode(
            advice: CoachingTestFixtures.startingPositionAdvice,
            selectedSquare: move.to,
            tentativeMove: move
        )
        episode.evidence.tentativeOrigin = .wake
        episode.knowledge.tentativeAdvice = CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: .wake,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                concepts: []
            )
        )

        let result = CoachingReconciler().derive(learner: .white, episode: episode)
        XCTAssertEqual(
            result.stage,
            .complete(move: move, origin: .wake, concepts: [])
        )
        XCTAssertEqual(result.questionID, .complete(move: move, origin: .wake))
        XCTAssertNil(result.derivedFeedback)
    }

    func testCorrectReplyAnswerCompletesExactAcceptableMove() {
        let move = CoachingTestFixtures.openingKnightMove
        let concepts = [CoachingConcept.developsKnightOrBishop]
        var episode = episode(
            advice: CoachingTestFixtures.startingPositionAdvice,
            selectedSquare: move.to,
            tentativeMove: move
        )
        episode.evidence.tentativeOrigin = .wake
        episode.evidence.replyAnswer = .looksSafe(move: move)
        episode.knowledge.tentativeAdvice = CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: .wake,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                opponentActivities: [CoachingTestFixtures.opponentActivity(
                    reply: Move(
                        from: CoachingTestFixtures.blackBishop,
                        to: move.to
                    ),
                    opponentPiece: .knight,
                    capturedSquare: move.to,
                    capturedPiece: .knight,
                    netGainForOpponent: 0
                )],
                concepts: concepts
            )
        )

        let result = CoachingReconciler().derive(learner: .white, episode: episode)
        XCTAssertEqual(
            result.stage,
            .complete(move: move, origin: .wake, concepts: concepts)
        )
        XCTAssertEqual(result.questionID, .complete(move: move, origin: .wake))
        XCTAssertEqual(result.derivedFeedback, .opponentReplyLooksSafe)
    }

    func testTentativeAdviceMustMatchExactCurrentMoveAndOrigin() {
        let currentMove = CoachingTestFixtures.openingKnightMove
        let staleMove = CoachingTestFixtures.alternateKnightMove
        let staleAdvice = CoachingTestFixtures.adviceForTentativeMove(
            staleMove,
            origin: .wake,
            assessment: CoachingTestFixtures.acceptableAssessment(
                staleMove,
                concepts: [.developsKnightOrBishop]
            )
        )
        let wrongOriginAdvice = CoachingTestFixtures.adviceForTentativeMove(
            currentMove,
            origin: .take,
            assessment: CoachingTestFixtures.acceptableAssessment(
                currentMove,
                concepts: [.profitableCapture]
            )
        )

        for (name, advice) in [
            ("stale move", staleAdvice),
            ("wrong origin", wrongOriginAdvice),
        ] {
            var episode = episode(
                advice: CoachingTestFixtures.startingPositionAdvice,
                selectedSquare: currentMove.to,
                tentativeMove: currentMove
            )
            episode.evidence.tentativeOrigin = .wake
            episode.knowledge.tentativeAdvice = advice

            let result = CoachingReconciler().derive(learner: .white, episode: episode)
            XCTAssertEqual(result.stage, .awaitingAdvice(origin: .wake), name)
            XCTAssertNil(result.questionID, name)
            XCTAssertEqual(result.requestedAdvice, .tentativeMove(origin: .wake), name)
        }
    }

    private func episode(
        advice: CoachingAdvice,
        selectedSquare: Square? = nil,
        tentativeMove: Move? = nil
    ) -> CoachingEpisodeState {
        CoachingEpisodeState(
            knowledge: CoachingKnowledge(
                positionAdvice: advice,
                tentativeAdvice: nil,
                unsupportedContext: nil,
                pendingContext: nil
            ),
            evidence: .empty,
            progress: CoachingQuestionProgress(
                questionID: nil,
                hintLevel: 0,
                missesAtCurrentLevel: 0,
                feedback: nil,
                feedbackAnchor: nil,
                pulseID: 0
            ),
            interaction: CoachingInteractionSnapshot(
                selectedSquare: selectedSquare,
                tentativeMove: tentativeMove,
                positionRevision: advice.evaluation.request.positionRevision
            )
        )
    }

    private func replacingEvaluationAssessments(
        in advice: CoachingAdvice,
        with moveAssessments: [Move: CoachingMoveAssessment]
    ) -> CoachingAdvice {
        let source = advice.evaluation
        let evaluation = CoachingEvaluation(
            request: source.request,
            checkingPieces: source.checkingPieces,
            opponentHasAnyLegalCapture: source.opponentHasAnyLegalCapture,
            learnerHasAnyLegalCapture: source.learnerHasAnyLegalCapture,
            opponentCaptureEstimates: source.opponentCaptureEstimates,
            dangerProblems: source.dangerProblems,
            learnerCaptureEstimates: source.learnerCaptureEstimates,
            mateInOneMoves: source.mateInOneMoves,
            moveAssessments: moveAssessments
        )
        return CoachingAdvice(
            evaluation: evaluation,
            insights: advice.insights,
            dangerProblems: advice.dangerProblems,
            takeOpportunities: advice.takeOpportunities,
            wakeOpportunities: advice.wakeOpportunities,
            wakeTasks: advice.wakeTasks,
            moveAssessments: advice.moveAssessments,
            openingDevelopmentIsRelevant: advice.openingDevelopmentIsRelevant,
            confidence: advice.confidence
        )
    }
}

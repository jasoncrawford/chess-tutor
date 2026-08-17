import XCTest
@testable import ChessTutor

final class CoachingPresentationProjectorTests: XCTestCase {
    func testQuestionChangeResetsHintMissAndFeedbackTogether() {
        var progress = CoachingQuestionProgress(
            questionID: .wakeSource(purpose: .openingDevelopment(firstMove: true)),
            hintLevel: 1,
            missesAtCurrentLevel: 2,
            feedback: .blockedWakePiece(piece: .rook),
            feedbackAnchor: .selection(square: Square(file: .a, rank: 1)),
            pulseID: 4
        )

        progress.enter(.wakeMove(
            source: CoachingTestFixtures.openingKnight,
            purpose: .openingDevelopment(firstMove: true)
        ))

        XCTAssertEqual(progress.hintLevel, 0)
        XCTAssertEqual(progress.missesAtCurrentLevel, 0)
        XCTAssertNil(progress.feedback)
        XCTAssertNil(progress.feedbackAnchor)
        XCTAssertEqual(progress.pulseID, 4)
    }

    func testEnteringSameQuestionPreservesHintMissAndFeedbackProgress() {
        let question = CoachingQuestionID.safeAttacker(
            target: CoachingTestFixtures.whiteQueen
        )
        var progress = CoachingQuestionProgress(
            questionID: question,
            hintLevel: 1,
            missesAtCurrentLevel: 2,
            feedback: .expectedAttacker(target: .queen),
            feedbackAnchor: .identification(square: CoachingTestFixtures.whiteRook),
            pulseID: 4
        )

        progress.enter(question)

        XCTAssertEqual(progress.questionID, question)
        XCTAssertEqual(progress.hintLevel, 1)
        XCTAssertEqual(progress.missesAtCurrentLevel, 2)
        XCTAssertEqual(progress.feedback, .expectedAttacker(target: .queen))
        XCTAssertEqual(
            progress.feedbackAnchor,
            .identification(square: CoachingTestFixtures.whiteRook)
        )
        XCTAssertEqual(progress.pulseID, 4)
    }

    func testSelectionFeedbackDisappearsWhenSelectionChangesOrClears() {
        let selected = CoachingTestFixtures.openingKnight
        var changed = progress(
            feedback: .blockedWakePiece(piece: .rook),
            anchor: .selection(square: selected)
        )

        changed.discardFeedbackInvalidated(by: interaction(
            selectedSquare: CoachingTestFixtures.alternateKnight
        ))

        XCTAssertNil(changed.feedback)
        XCTAssertNil(changed.feedbackAnchor)

        var cleared = progress(
            feedback: .blockedWakePiece(piece: .rook),
            anchor: .selection(square: selected)
        )
        cleared.discardFeedbackInvalidated(by: interaction(selectedSquare: nil))

        XCTAssertNil(cleared.feedback)
        XCTAssertNil(cleared.feedbackAnchor)
    }

    func testSelectionAndTentativeMoveFeedbackSurviveOnlyTheirExactInteraction() {
        let move = CoachingTestFixtures.openingKnightMove
        var selection = progress(
            feedback: .notWakeCandidate(
                piece: .knight,
                purpose: .openingDevelopment(firstMove: true)
            ),
            anchor: .selection(square: move.from)
        )
        selection.discardFeedbackInvalidated(by: interaction(selectedSquare: move.from))
        XCTAssertNotNil(selection.feedback)

        var tentative = progress(
            feedback: .noRecognizedPurpose(
                purpose: .openingDevelopment(firstMove: true)
            ),
            anchor: .tentativeMove(move)
        )
        tentative.discardFeedbackInvalidated(by: interaction(
            selectedSquare: move.to,
            tentativeMove: move
        ))
        XCTAssertNotNil(tentative.feedback)

        tentative.discardFeedbackInvalidated(by: interaction(
            selectedSquare: CoachingTestFixtures.alternateKnightMove.to,
            tentativeMove: CoachingTestFixtures.alternateKnightMove
        ))
        XCTAssertNil(tentative.feedback)
        XCTAssertNil(tentative.feedbackAnchor)
    }

    func testIdentificationFeedbackSurvivesRebuildAndNextAttemptReplacesIt() {
        var progress = CoachingQuestionProgress(
            questionID: .safeLocate,
            hintLevel: 0,
            missesAtCurrentLevel: 0,
            feedback: nil,
            feedbackAnchor: nil,
            pulseID: 0
        )
        progress.recordMiss(
            .safePiece(piece: .knight),
            anchor: .identification(square: CoachingTestFixtures.openingKnight)
        )

        progress.enter(.safeLocate)
        progress.discardFeedbackInvalidated(by: interaction(selectedSquare: nil))

        XCTAssertEqual(progress.feedback, .safePiece(piece: .knight))
        XCTAssertEqual(
            progress.feedbackAnchor,
            .identification(square: CoachingTestFixtures.openingKnight)
        )

        progress.recordMiss(
            .nonurgentThreat(piece: .rook),
            anchor: .identification(square: CoachingTestFixtures.whiteRook)
        )

        XCTAssertEqual(progress.missesAtCurrentLevel, 2)
        XCTAssertEqual(progress.feedback, .nonurgentThreat(piece: .rook))
        XCTAssertEqual(
            progress.feedbackAnchor,
            .identification(square: CoachingTestFixtures.whiteRook)
        )
    }

    func testActionFeedbackIsDiscardedAtTheNextInteractionReconciliation() {
        var progress = CoachingQuestionProgress(
            questionID: .take,
            hintLevel: 0,
            missesAtCurrentLevel: 1,
            feedback: .correctAbsence,
            feedbackAnchor: .action(.noAnswer),
            pulseID: 0
        )

        progress.discardFeedbackInvalidated(by: interaction(selectedSquare: nil))

        XCTAssertNil(progress.feedback)
        XCTAssertNil(progress.feedbackAnchor)
    }

    func testRevealNextHintCapsAtAvailableLadderAndClearsAttemptFeedback() {
        var progress = CoachingQuestionProgress(
            questionID: .safeLocate,
            hintLevel: 0,
            missesAtCurrentLevel: 2,
            feedback: .missedExistingAnswer,
            feedbackAnchor: .action(.noAnswer),
            pulseID: 7
        )

        progress.revealNextHint(available: [.dangerMarker])
        progress.revealNextHint(available: [.dangerMarker])

        XCTAssertEqual(progress.hintLevel, 1)
        XCTAssertEqual(progress.missesAtCurrentLevel, 0)
        XCTAssertNil(progress.feedback)
        XCTAssertNil(progress.feedbackAnchor)
        XCTAssertEqual(progress.pulseID, 8)
    }

    func testProjectionProducesOneCoherentContextForEveryRepresentativeStage() throws {
        let projector = CoachingPresentationProjector()
        let purpose = CoachingWakePurpose.openingDevelopment(firstMove: true)
        let checker = CoachingTestFixtures.blackBishop
        let checkAdvice = CoachingTestFixtures.advice(
            checking: [checker],
            opponentHasCapture: true,
            learnerHasCapture: false
        )
        let replyMove = CoachingTestFixtures.openingKnightMove
        let replyIssue = CoachingTestFixtures.issue(
            reply: Move(from: CoachingTestFixtures.blackRook, to: replyMove.to),
            kind: .materialLoss(points: 3),
            severity: .reviseMove,
            answers: [replyMove.to]
        )
        let replyAdvice = CoachingTestFixtures.adviceForTentativeMove(
            replyMove,
            origin: .wake,
            assessment: CoachingTestFixtures.acceptableAssessment(
                replyMove,
                issues: [replyIssue],
                concepts: [.developsKnightOrBishop],
                isAcceptable: false
            )
        )
        let captureMove = CoachingTestFixtures.profitableCapture
        let captureEstimate = CoachingTestFixtures.capture(
            move: captureMove,
            captured: Piece(kind: .rook, color: .black),
            capturedSquare: CoachingTestFixtures.blackRook,
            net: 5
        )
        let completeAdvice = CoachingTestFixtures.adviceForTentativeMove(
            captureMove,
            origin: .take,
            assessment: CoachingTestFixtures.acceptableAssessment(
                captureMove,
                concepts: [.profitableCapture]
            ),
            learnerCaptures: [captureEstimate]
        )
        let safeAttackerPath = CoachFocusPath(
            source: CoachingTestFixtures.blackBishop,
            destination: CoachingTestFixtures.whiteQueen,
            role: .attacker
        )

        let cases = [
            ProjectionCase(
                name: "check locate",
                derived: derived(.checkLocate, questionID: .checkLocate),
                episode: episode(
                    advice: checkAdvice,
                    progress: progress(questionID: .checkLocate, hintLevel: 2, pulseID: 1)
                ),
                prompt: .checkLocate,
                boardTask: .identify(allowsMoveRevision: false),
                actions: [.stop],
                routine: [],
                hint: .candidatePieces,
                focus: CoachFocusPresentation(
                    emphasizedSquares: [],
                    candidateSquares: [checker],
                    paths: [],
                    pulseID: 1
                )
            ),
            ProjectionCase(
                name: "safe attacker",
                derived: derived(
                    .safeIdentifyAttacker(target: CoachingTestFixtures.whiteQueen),
                    questionID: .safeAttacker(target: CoachingTestFixtures.whiteQueen)
                ),
                episode: episode(
                    advice: CoachingTestFixtures.multipleDangerAdvice,
                    evidence: evidence(
                        safeTarget: CoachingTestFixtures.whiteQueen
                    ),
                    progress: progress(
                        questionID: .safeAttacker(target: CoachingTestFixtures.whiteQueen),
                        hintLevel: 1,
                        pulseID: 2
                    )
                ),
                prompt: .safeIdentifyAttacker(piece: .queen),
                boardTask: .identify(allowsMoveRevision: false),
                actions: [.hint, .stop],
                routine: [.safeCurrent, .takePending, .wakePending],
                hint: .attackerRelationship,
                focus: CoachFocusPresentation(
                    emphasizedSquares: [CoachingTestFixtures.whiteQueen],
                    candidateSquares: [CoachingTestFixtures.blackBishop],
                    paths: [safeAttackerPath],
                    pulseID: 2
                )
            ),
            ProjectionCase(
                name: "safe resolve",
                derived: derived(
                    .safeResolve(target: CoachingTestFixtures.whiteQueen),
                    questionID: .safeResolve(
                        target: CoachingTestFixtures.whiteQueen,
                        attacker: CoachingTestFixtures.blackBishop
                    )
                ),
                episode: episode(
                    advice: CoachingTestFixtures.multipleDangerAdvice,
                    evidence: evidence(
                        safeTarget: CoachingTestFixtures.whiteQueen,
                        safeAttacker: CoachingTestFixtures.blackBishop
                    ),
                    progress: progress(
                        questionID: .safeResolve(
                            target: CoachingTestFixtures.whiteQueen,
                            attacker: CoachingTestFixtures.blackBishop
                        ),
                        hintLevel: 1,
                        pulseID: 3
                    )
                ),
                prompt: .safeResolve(target: .queen, attacker: .bishop),
                boardTask: .move,
                actions: [.hint, .stop],
                routine: [.safeCurrent, .takePending, .wakePending],
                hint: .safeResponseIdeas,
                focus: CoachFocusPresentation(
                    emphasizedSquares: [
                        CoachingTestFixtures.whiteQueen,
                        CoachingTestFixtures.blackBishop,
                    ],
                    candidateSquares: [],
                    paths: [safeAttackerPath],
                    pulseID: 3
                )
            ),
            ProjectionCase(
                name: "take",
                derived: derived(.takeChooseMove, questionID: .take),
                episode: episode(
                    advice: CoachingTestFixtures.takeAdvice,
                    progress: progress(questionID: .take, hintLevel: 2, pulseID: 4)
                ),
                prompt: .takeChooseMove,
                boardTask: .move,
                actions: [.noAnswer, .stop],
                routine: [.safeCleared, .takeCurrent, .wakePending],
                hint: .candidateMoves,
                focus: CoachFocusPresentation(
                    emphasizedSquares: [],
                    candidateSquares: [captureMove.to],
                    paths: [CoachFocusPath(
                        source: captureMove.from,
                        destination: captureMove.to,
                        role: .candidate
                    )],
                    pulseID: 4
                )
            ),
            ProjectionCase(
                name: "wake source",
                derived: derived(
                    .wakeChoosePiece(purpose: purpose),
                    questionID: .wakeSource(purpose: purpose)
                ),
                episode: episode(
                    advice: CoachingTestFixtures.startingPositionAdvice,
                    progress: progress(
                        questionID: .wakeSource(purpose: purpose),
                        hintLevel: 1,
                        pulseID: 5
                    )
                ),
                prompt: .wakeChoosePiece(purpose: purpose),
                boardTask: .move,
                actions: [.hint, .stop],
                routine: [.safeCleared, .takeCleared, .wakeCurrent],
                hint: .candidatePieces,
                focus: CoachFocusPresentation(
                    emphasizedSquares: [],
                    candidateSquares: [
                        CoachingTestFixtures.openingKnight,
                        CoachingTestFixtures.alternateKnight,
                    ],
                    paths: [],
                    pulseID: 5
                )
            ),
            ProjectionCase(
                name: "wake move",
                derived: derived(
                    .wakeChooseMove(
                        piece: CoachingTestFixtures.openingKnight,
                        purpose: purpose
                    ),
                    questionID: .wakeMove(
                        source: CoachingTestFixtures.openingKnight,
                        purpose: purpose
                    )
                ),
                episode: episode(
                    advice: CoachingTestFixtures.startingPositionAdvice,
                    evidence: evidence(),
                    progress: progress(
                        questionID: .wakeMove(
                            source: CoachingTestFixtures.openingKnight,
                            purpose: purpose
                        ),
                        hintLevel: 2,
                        pulseID: 6
                    ),
                    selectedSquare: CoachingTestFixtures.openingKnight
                ),
                prompt: .wakeChooseMove(piece: .knight, purpose: purpose),
                boardTask: .move,
                actions: [.stop],
                routine: [.safeCleared, .takeCleared, .wakeCurrent],
                hint: .candidateMoves,
                focus: CoachFocusPresentation(
                    emphasizedSquares: [],
                    candidateSquares: [CoachingTestFixtures.openingKnightMove.to],
                    paths: [CoachFocusPath(
                        source: CoachingTestFixtures.openingKnight,
                        destination: CoachingTestFixtures.openingKnightMove.to,
                        role: .candidate
                    )],
                    pulseID: 6
                )
            ),
            ProjectionCase(
                name: "opponent reply",
                derived: derived(
                    .opponentCheck(move: replyMove, origin: .wake),
                    questionID: .opponentReply(move: replyMove, origin: .wake)
                ),
                episode: episode(
                    tentativeAdvice: replyAdvice,
                    evidence: evidence(tentativeOrigin: .wake),
                    progress: progress(
                        questionID: .opponentReply(move: replyMove, origin: .wake),
                        hintLevel: 2,
                        pulseID: 7
                    ),
                    selectedSquare: replyMove.to,
                    tentativeMove: replyMove
                ),
                prompt: .opponentReply(opponent: .black),
                boardTask: .identify(allowsMoveRevision: true),
                actions: [.looksSafe, .stop],
                routine: [],
                hint: .attackerRelationship,
                focus: CoachFocusPresentation(
                    emphasizedSquares: [],
                    candidateSquares: [replyMove.to],
                    paths: [CoachFocusPath(
                        source: CoachingTestFixtures.blackRook,
                        destination: replyMove.to,
                        role: .attacker
                    )],
                    pulseID: 7
                )
            ),
            ProjectionCase(
                name: "revise",
                derived: derived(
                    .reviseMove(origin: .fallback),
                    questionID: .revise(move: nil, origin: .fallback)
                ),
                episode: episode(
                    advice: CoachingTestFixtures.fallbackAdvice,
                    progress: progress(
                        questionID: .revise(move: nil, origin: .fallback),
                        pulseID: 8
                    )
                ),
                prompt: .reviseMove,
                boardTask: .move,
                actions: [.stop],
                routine: [],
                hint: nil,
                focus: CoachFocusPresentation(
                    emphasizedSquares: [],
                    candidateSquares: [],
                    paths: [],
                    pulseID: 8
                )
            ),
            ProjectionCase(
                name: "complete",
                derived: derived(
                    .complete(
                        move: captureMove,
                        origin: .take,
                        concepts: [.profitableCapture]
                    ),
                    questionID: .complete(move: captureMove, origin: .take)
                ),
                episode: episode(
                    tentativeAdvice: completeAdvice,
                    evidence: evidence(tentativeOrigin: .take),
                    progress: progress(
                        questionID: .complete(move: captureMove, origin: .take),
                        pulseID: 9
                    ),
                    selectedSquare: captureMove.to,
                    tentativeMove: captureMove
                ),
                prompt: .complete(
                    origin: .take,
                    idea: .profitableCapture(captured: .rook)
                ),
                boardTask: .none,
                actions: [.done, .keepLooking, .stop],
                routine: [],
                hint: nil,
                focus: CoachFocusPresentation(
                    emphasizedSquares: [],
                    candidateSquares: [],
                    paths: [],
                    pulseID: 9
                )
            ),
        ]

        for testCase in cases {
            let context = try XCTUnwrap(projector.context(
                learner: .white,
                derived: testCase.derived,
                episode: testCase.episode
            ), testCase.name)

            XCTAssertEqual(context.prompt, testCase.prompt, testCase.name)
            XCTAssertEqual(context.boardTask, testCase.boardTask, testCase.name)
            XCTAssertEqual(context.actions, testCase.actions, testCase.name)
            XCTAssertEqual(context.routine, testCase.routine, testCase.name)
            XCTAssertEqual(context.hint, testCase.hint, testCase.name)
            XCTAssertEqual(context.focus, testCase.focus, testCase.name)
        }
    }

    func testSafeTargetAttackerFocusRequiresBothValuesToMatchCurrentAdvice() throws {
        let validTarget = CoachingTestFixtures.whiteQueen
        let invalidAttacker = CoachingTestFixtures.blackRook
        let question = CoachingQuestionID.safeResolve(
            target: validTarget,
            attacker: invalidAttacker
        )
        let context = try XCTUnwrap(CoachingPresentationProjector().context(
            learner: .white,
            derived: derived(
                .safeResolve(target: validTarget),
                questionID: question
            ),
            episode: episode(
                advice: CoachingTestFixtures.multipleDangerAdvice,
                evidence: evidence(
                    safeTarget: validTarget,
                    safeAttacker: invalidAttacker
                ),
                progress: progress(questionID: question, pulseID: 13)
            )
        ))

        XCTAssertTrue(context.focus.emphasizedSquares.isEmpty)
        XCTAssertTrue(context.focus.paths.isEmpty)
    }

    func testProjectionIgnoresTentativeAdviceWhenNoMatchingMoveIsStaged() throws {
        let target = CoachingTestFixtures.whiteQueen
        let attacker = CoachingTestFixtures.blackBishop
        let staleAttacker = CoachingTestFixtures.blackRook
        let staleCapture = CoachingTestFixtures.capture(
            move: Move(from: staleAttacker, to: target),
            captured: Piece(kind: .queen, color: .white),
            capturedSquare: target,
            net: 9
        )
        let staleMove = CoachingTestFixtures.alternateKnightMove
        let staleAdvice = CoachingTestFixtures.adviceForTentativeMove(
            staleMove,
            origin: .wake,
            assessment: CoachingTestFixtures.acceptableAssessment(staleMove),
            urgent: [CoachingUrgentProblem(
                target: target,
                piece: Piece(kind: .queen, color: .white),
                captures: [staleCapture],
                worstEstimatedLoss: 9
            )]
        )
        let question = CoachingQuestionID.safeResolve(
            target: target,
            attacker: attacker
        )
        let context = try XCTUnwrap(CoachingPresentationProjector().context(
            learner: .white,
            derived: derived(
                .safeResolve(target: target),
                questionID: question
            ),
            episode: episode(
                advice: CoachingTestFixtures.multipleDangerAdvice,
                tentativeAdvice: staleAdvice,
                evidence: evidence(safeTarget: target, safeAttacker: attacker),
                progress: progress(questionID: question, pulseID: 14)
            )
        ))

        XCTAssertEqual(context.prompt, .safeResolve(target: .queen, attacker: .bishop))
        XCTAssertEqual(context.focus.emphasizedSquares, [target, attacker])
        XCTAssertEqual(context.focus.paths, [CoachFocusPath(
            source: attacker,
            destination: target,
            role: .attacker
        )])
    }

    func testPositionAdviceMustMatchLearnerRevisionAndStartRequestContext() throws {
        let source = CoachingTestFixtures.multipleDangerAdvice
        let request = source.evaluation.request
        let target = CoachingTestFixtures.whiteQueen
        let attacker = CoachingTestFixtures.blackBishop
        let question = CoachingQuestionID.safeResolve(
            target: target,
            attacker: attacker
        )
        let invalidCases: [(String, CoachingAdvice)] = [
            (
                "learner",
                replacing(source, request: CoachingRequest(
                    committedState: request.committedState,
                    tentativeMove: nil,
                    learner: .black,
                    positionRevision: request.positionRevision,
                    context: .start
                ))
            ),
            (
                "revision",
                replacing(source, request: CoachingRequest(
                    committedState: request.committedState,
                    tentativeMove: nil,
                    learner: request.learner,
                    positionRevision: request.positionRevision + 1,
                    context: .start
                ))
            ),
            (
                "request context",
                replacing(source, request: CoachingRequest(
                    committedState: request.committedState,
                    tentativeMove: CoachingTestFixtures.safeMove,
                    learner: request.learner,
                    positionRevision: request.positionRevision,
                    context: .tentativeMove(origin: .safe)
                ))
            ),
        ]

        for (name, advice) in invalidCases {
            let context = try XCTUnwrap(CoachingPresentationProjector().context(
                learner: .white,
                derived: derived(
                    .safeResolve(target: target),
                    questionID: question
                ),
                episode: episode(
                    advice: advice,
                    evidence: evidence(safeTarget: target, safeAttacker: attacker),
                    progress: progress(questionID: question, pulseID: 21),
                    positionRevision: request.positionRevision
                )
            ), name)

            XCTAssertEqual(
                context.prompt,
                .safeResolve(target: .pawn, attacker: .pawn),
                name
            )
            XCTAssertTrue(context.focus.emphasizedSquares.isEmpty, name)
            XCTAssertTrue(context.focus.paths.isEmpty, name)
        }
    }

    func testTentativeAdviceMustMatchExactRequestAndMoveAssessment() throws {
        let move = CoachingTestFixtures.profitableCapture
        let alternateMove = CoachingTestFixtures.openingKnightMove
        let assessment = CoachingTestFixtures.acceptableAssessment(
            move,
            concepts: [.profitableCapture]
        )
        let estimate = CoachingTestFixtures.capture(
            move: move,
            captured: Piece(kind: .rook, color: .black),
            capturedSquare: CoachingTestFixtures.blackRook,
            net: 5
        )
        let source = CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: .take,
            assessment: assessment,
            learnerCaptures: [estimate]
        )
        let request = source.evaluation.request
        let wrongAssessment = CoachingTestFixtures.acceptableAssessment(
            alternateMove,
            concepts: [.developsKnightOrBishop]
        )
        let invalidCases: [(String, CoachingAdvice)] = [
            (
                "learner",
                replacing(source, request: CoachingRequest(
                    committedState: request.committedState,
                    tentativeMove: move,
                    learner: .black,
                    positionRevision: request.positionRevision,
                    context: .tentativeMove(origin: .take)
                ))
            ),
            (
                "revision",
                replacing(source, request: CoachingRequest(
                    committedState: request.committedState,
                    tentativeMove: move,
                    learner: request.learner,
                    positionRevision: request.positionRevision + 1,
                    context: .tentativeMove(origin: .take)
                ))
            ),
            (
                "move",
                replacing(source, request: CoachingRequest(
                    committedState: request.committedState,
                    tentativeMove: alternateMove,
                    learner: request.learner,
                    positionRevision: request.positionRevision,
                    context: .tentativeMove(origin: .take)
                ))
            ),
            (
                "origin",
                replacing(source, request: CoachingRequest(
                    committedState: request.committedState,
                    tentativeMove: move,
                    learner: request.learner,
                    positionRevision: request.positionRevision,
                    context: .tentativeMove(origin: .wake)
                ))
            ),
            (
                "evaluation assessment",
                replacing(source, evaluationMoveAssessments: [move: wrongAssessment])
            ),
            (
                "advice assessment",
                replacing(source, moveAssessments: [move: wrongAssessment])
            ),
        ]
        let question = CoachingQuestionID.complete(move: move, origin: .take)

        for (name, advice) in invalidCases {
            let context = try XCTUnwrap(CoachingPresentationProjector().context(
                learner: .white,
                derived: derived(
                    .complete(
                        move: move,
                        origin: .take,
                        concepts: [.profitableCapture]
                    ),
                    questionID: question
                ),
                episode: episode(
                    advice: CoachingTestFixtures.takeAdvice,
                    tentativeAdvice: advice,
                    evidence: evidence(tentativeOrigin: .take),
                    progress: progress(questionID: question),
                    selectedSquare: move.to,
                    tentativeMove: move,
                    positionRevision: request.positionRevision
                )
            ), name)

            XCTAssertEqual(
                context.prompt,
                .complete(
                    origin: .take,
                    idea: .profitableCapture(captured: .pawn)
                ),
                name
            )
        }
    }

    private struct ProjectionCase {
        let name: String
        let derived: CoachingDerivedState
        let episode: CoachingEpisodeState
        let prompt: CoachingPrompt
        let boardTask: CoachingBoardTask
        let actions: [CoachingAction]
        let routine: [CoachingRoutineState]
        let hint: CoachingHint?
        let focus: CoachFocusPresentation
    }

    private func derived(
        _ stage: CoachingStage,
        questionID: CoachingQuestionID
    ) -> CoachingDerivedState {
        CoachingDerivedState(
            stage: stage,
            questionID: questionID,
            promptOverride: nil,
            derivedFeedback: nil,
            requestedAdvice: nil
        )
    }

    private func episode(
        advice: CoachingAdvice? = nil,
        tentativeAdvice: CoachingAdvice? = nil,
        evidence: CoachingPedagogicalEvidence = .empty,
        progress: CoachingQuestionProgress,
        selectedSquare: Square? = nil,
        tentativeMove: Move? = nil,
        positionRevision: Int? = nil
    ) -> CoachingEpisodeState {
        let revision = positionRevision
            ?? advice?.evaluation.request.positionRevision
            ?? tentativeAdvice?.evaluation.request.positionRevision
            ?? 0
        return CoachingEpisodeState(
            knowledge: CoachingKnowledge(
                positionAdvice: advice,
                tentativeAdvice: tentativeAdvice,
                unsupportedContext: nil,
                pendingContext: nil
            ),
            evidence: evidence,
            progress: progress,
            interaction: interaction(
                selectedSquare: selectedSquare,
                tentativeMove: tentativeMove,
                positionRevision: revision
            )
        )
    }

    private func replacing(
        _ advice: CoachingAdvice,
        request: CoachingRequest? = nil,
        evaluationMoveAssessments: [Move: CoachingMoveAssessment]? = nil,
        moveAssessments: [Move: CoachingMoveAssessment]? = nil
    ) -> CoachingAdvice {
        let source = advice.evaluation
        let evaluation = CoachingEvaluation(
            request: request ?? source.request,
            checkingPieces: source.checkingPieces,
            opponentHasAnyLegalCapture: source.opponentHasAnyLegalCapture,
            learnerHasAnyLegalCapture: source.learnerHasAnyLegalCapture,
            opponentCaptureEstimates: source.opponentCaptureEstimates,
            urgentProblems: source.urgentProblems,
            learnerCaptureEstimates: source.learnerCaptureEstimates,
            mateInOneMoves: source.mateInOneMoves,
            moveAssessments: evaluationMoveAssessments ?? source.moveAssessments
        )
        return CoachingAdvice(
            evaluation: evaluation,
            insights: advice.insights,
            urgentProblems: advice.urgentProblems,
            takeOpportunities: advice.takeOpportunities,
            wakeOpportunities: advice.wakeOpportunities,
            moveAssessments: moveAssessments ?? advice.moveAssessments,
            openingDevelopmentIsRelevant: advice.openingDevelopmentIsRelevant,
            confidence: advice.confidence
        )
    }

    private func evidence(
        safeTarget: Square? = nil,
        safeAttacker: Square? = nil,
        tentativeOrigin: CoachingMoveOrigin? = nil
    ) -> CoachingPedagogicalEvidence {
        CoachingPedagogicalEvidence(
            checkingPiece: nil,
            safeTarget: safeTarget,
            safeAttacker: safeAttacker,
            confirmedSafeAbsence: false,
            confirmedTakeAbsence: false,
            tentativeOrigin: tentativeOrigin,
            replyAnswer: nil
        )
    }

    private func progress(
        questionID: CoachingQuestionID? = .safeLocate,
        hintLevel: Int = 0,
        pulseID: Int = 0
    ) -> CoachingQuestionProgress {
        CoachingQuestionProgress(
            questionID: questionID,
            hintLevel: hintLevel,
            missesAtCurrentLevel: 0,
            feedback: nil,
            feedbackAnchor: nil,
            pulseID: pulseID
        )
    }

    private func progress(
        feedback: CoachingFeedback,
        anchor: CoachingFeedbackAnchor
    ) -> CoachingQuestionProgress {
        CoachingQuestionProgress(
            questionID: .wakeSource(purpose: .openingDevelopment(firstMove: true)),
            hintLevel: 0,
            missesAtCurrentLevel: 1,
            feedback: feedback,
            feedbackAnchor: anchor,
            pulseID: 0
        )
    }

    private func interaction(
        selectedSquare: Square?,
        tentativeMove: Move? = nil,
        positionRevision: Int = 7
    ) -> CoachingInteractionSnapshot {
        CoachingInteractionSnapshot(
            selectedSquare: selectedSquare,
            tentativeMove: tentativeMove,
            positionRevision: positionRevision
        )
    }
}

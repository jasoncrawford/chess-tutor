import XCTest
@testable import ChessTutor

final class CoachingSessionTests: XCTestCase {
    func testStartingPositionCompressesSafeAndTakeIntoOpeningWake() {
        var session = CoachingSession(learner: .white)

        XCTAssertTrue(session.receive(CoachingTestFixtures.startingPositionAdvice).isEmpty)

        XCTAssertEqual(session.stage, .wakeChoosePiece(opening: true))
        XCTAssertEqual(session.presentation?.routine, [
            .safeCleared, .takeCleared, .wakeCurrent,
        ])
        XCTAssertEqual(
            session.presentation?.headline,
            "Nothing is in danger yet. Can you help the center or wake up a piece?"
        )
    }

    func testSafeTranscriptAcceptsAnyUrgentPieceThenItsAttacker() {
        var session = CoachingSession(learner: .white)
        session.receive(CoachingTestFixtures.multipleDangerAdvice)

        let chosenTarget = CoachingTestFixtures.whiteRook
        XCTAssertTrue(session.handle(.squareTapped(chosenTarget)).isEmpty)
        XCTAssertEqual(session.stage, .safeIdentifyAttacker(target: chosenTarget))

        let attacker = CoachingTestFixtures.blackRook
        XCTAssertTrue(session.handle(.squareTapped(attacker)).isEmpty)
        XCTAssertEqual(session.stage, .safeResolve(target: chosenTarget))
        XCTAssertEqual(session.presentation?.boardTask, .move)
    }

    func testCheckAndDoubleCheckAcceptEveryCheckingPieceWithoutSelectingIt() {
        for checkingPiece in [CoachingTestFixtures.blackBishop, CoachingTestFixtures.blackRook] {
            var session = CoachingSession(learner: .white)
            let advice = CoachingTestFixtures.advice(
                checking: [CoachingTestFixtures.blackBishop, CoachingTestFixtures.blackRook],
                opponentHasCapture: true,
                learnerHasCapture: false
            )
            session.receive(advice)

            XCTAssertEqual(session.stage, .checkLocate)
            XCTAssertEqual(
                session.presentation?.routine,
                [.safeCurrent, .takePending, .wakePending]
            )
            XCTAssertTrue(session.handle(.squareTapped(checkingPiece)).isEmpty)
            XCTAssertEqual(session.stage, .checkResolve)
            XCTAssertEqual(session.presentation?.boardTask, .move)
        }
    }

    func testNontrivialSafeRequiresCorrectAbsenceAndRejectsIncorrectAbsence() {
        var clearSession = CoachingSession(learner: .white)
        clearSession.receive(CoachingTestFixtures.nontrivialSafeClearAdvice)
        XCTAssertEqual(clearSession.stage, .safeLocate)
        clearSession.handle(.actionChosen(.noAnswer))
        XCTAssertEqual(clearSession.stage, .wakeChoosePiece(opening: false))
        XCTAssertEqual(clearSession.presentation?.headline, "Right—there isn’t one.")
        XCTAssertEqual(clearSession.presentation?.instruction, "Tap that piece.")
        XCTAssertEqual(clearSession.presentation?.routine, [
            .safeCleared, .takeCleared, .wakeCurrent,
        ])

        var dangerSession = CoachingSession(learner: .white)
        dangerSession.receive(CoachingTestFixtures.multipleDangerAdvice)
        dangerSession.handle(.actionChosen(.noAnswer))
        XCTAssertEqual(dangerSession.stage, .safeLocate)
        XCTAssertEqual(dangerSession.presentation?.headline, "There is one to find.")
        XCTAssertEqual(dangerSession.missesAtCurrentLevel, 1)
    }

    func testSafeRejectsUnrelatedTapAndResolutionThatLeavesDanger() {
        var session = CoachingSession(learner: .white)
        session.receive(CoachingTestFixtures.multipleDangerAdvice)
        session.handle(.squareTapped(CoachingTestFixtures.whiteQueen))
        session.handle(.squareTapped(CoachingTestFixtures.blackBishop))

        XCTAssertEqual(
            session.handle(.moveStaged(CoachingTestFixtures.safeMove)),
            [.requestAdvice(context: .tentativeMove(origin: .safe))]
        )
        let rejected = CoachingMoveAssessment(
            move: CoachingTestFixtures.safeMove,
            isLegal: true,
            resolvesRequiredDanger: false,
            opponentIssues: [],
            concepts: [],
            isAcceptable: false
        )
        session.receive(CoachingTestFixtures.adviceForTentativeMove(
            CoachingTestFixtures.safeMove,
            origin: .safe,
            assessment: rejected,
            urgent: CoachingTestFixtures.multipleDangerAdvice.urgentProblems
        ))

        XCTAssertEqual(session.stage, .safeResolve(target: CoachingTestFixtures.whiteQueen))
        XCTAssertEqual(session.presentation?.headline, "Your queen would still need help.")
    }

    func testTakeRequiresCorrectAbsenceAndStagesCapturesForAdvice() {
        var emptySession = CoachingSession(learner: .white)
        emptySession.receive(CoachingTestFixtures.nontrivialTakeClearAdvice)
        XCTAssertEqual(emptySession.stage, .takeChooseMove)
        emptySession.handle(.actionChosen(.noAnswer))
        XCTAssertEqual(emptySession.stage, .wakeChoosePiece(opening: false))
        XCTAssertEqual(emptySession.presentation?.headline, "Right—there isn’t one.")

        var takeSession = CoachingSession(learner: .white)
        takeSession.receive(CoachingTestFixtures.takeAdvice)
        takeSession.handle(.actionChosen(.noAnswer))
        XCTAssertEqual(takeSession.presentation?.headline, "There is one to find.")
        XCTAssertEqual(
            takeSession.handle(.moveStaged(CoachingTestFixtures.profitableCapture)),
            [.requestAdvice(context: .tentativeMove(origin: .take))]
        )
    }

    func testMateInOneKeepsTakeNontrivialWithoutALegalCapture() {
        let mate = Move(
            from: CoachingTestFixtures.whiteQueen,
            to: Square(file: .h, rank: 4)
        )
        let advice = CoachingTestFixtures.advice(
            opponentHasCapture: false,
            learnerHasCapture: false,
            mateInOne: [mate]
        )
        var session = CoachingSession(learner: .white)

        session.receive(advice)

        XCTAssertEqual(session.stage, .takeChooseMove)
        XCTAssertEqual(
            session.presentation?.routine,
            [.safeCleared, .takeCurrent, .wakePending]
        )
    }

    func testUnprofitableCaptureExplainsImmediateRecaptureAndReturnsToTake() {
        let capture = CoachingTestFixtures.profitableCapture
        let recapture = Move(from: CoachingTestFixtures.blackKing, to: capture.to)
        let estimate = CoachingTestFixtures.capture(
            move: capture,
            captured: Piece(kind: .rook, color: .black),
            capturedSquare: capture.to,
            recapture: recapture,
            net: -4
        )
        let assessment = CoachingTestFixtures.acceptableAssessment(
            capture,
            concepts: [],
            isAcceptable: false
        )
        var session = CoachingSession(learner: .white)
        session.receive(CoachingTestFixtures.takeAdvice)
        session.handle(.moveStaged(capture))

        session.receive(CoachingTestFixtures.adviceForTentativeMove(
            capture,
            origin: .take,
            assessment: assessment,
            learnerCaptures: [estimate]
        ))

        XCTAssertEqual(session.stage, .takeChooseMove)
        XCTAssertEqual(session.presentation?.headline, "Black could take your queen.")
    }

    func testEveryWakeSourceAlternativeSelectsExactlyThatPiece() {
        for source in [CoachingTestFixtures.openingKnight, CoachingTestFixtures.alternateKnight] {
            var session = CoachingSession(learner: .white)
            session.receive(CoachingTestFixtures.startingPositionAdvice)

            XCTAssertEqual(session.handle(.squareTapped(source)), [.selectSquare(source)])
            XCTAssertEqual(session.stage, .wakeChooseMove(piece: source, opening: true))
            XCTAssertEqual(session.presentation?.boardTask, .move)
        }
    }

    func testWakeAcceptsEveryQualifyingMoveAndRejectsMoveWithoutWakePurpose() {
        for move in [CoachingTestFixtures.openingKnightMove, CoachingTestFixtures.alternateKnightMove] {
            var session = CoachingSession(learner: .white)
            session.receive(CoachingTestFixtures.startingPositionAdvice)
            session.handle(.squareTapped(move.from))
            session.handle(.moveStaged(move))
            session.receive(CoachingTestFixtures.adviceForTentativeMove(
                move,
                origin: .wake,
                assessment: CoachingTestFixtures.acceptableAssessment(
                    move,
                    concepts: [.developsKnightOrBishop]
                )
            ))
            XCTAssertEqual(session.stage, .opponentCheck(move: move, origin: .wake))
        }

        var rejected = CoachingSession(learner: .white)
        rejected.receive(CoachingTestFixtures.startingPositionAdvice)
        rejected.handle(.squareTapped(CoachingTestFixtures.openingKnight))
        rejected.handle(.moveStaged(CoachingTestFixtures.openingKnightMove))
        rejected.receive(CoachingTestFixtures.adviceForTentativeMove(
            CoachingTestFixtures.openingKnightMove,
            origin: .wake,
            assessment: CoachingTestFixtures.acceptableAssessment(
                CoachingTestFixtures.openingKnightMove,
                concepts: [],
                isAcceptable: false
            )
        ))
        XCTAssertEqual(
            rejected.stage,
            .wakeChooseMove(piece: CoachingTestFixtures.openingKnight, opening: true)
        )
        XCTAssertEqual(
            rejected.presentation?.headline,
            "That move looks safe, but give the piece a clear job."
        )
    }

    func testUnsupportedAdviceAndExplicitUnsupportedPositionUseGenericFallback() {
        var fromAdvice = CoachingSession(learner: .white)
        fromAdvice.receive(CoachingTestFixtures.fallbackAdvice)
        XCTAssertEqual(fromAdvice.stage, .fallbackChooseMove)
        XCTAssertEqual(fromAdvice.presentation?.routine, [])

        var explicit = CoachingSession(learner: .white)
        explicit.receiveUnsupportedPosition()
        XCTAssertEqual(explicit.stage, .fallbackChooseMove)
        XCTAssertEqual(
            explicit.presentation?.headline,
            "Nothing urgent stands out. Try a move you like, and we’ll check it together."
        )
        XCTAssertEqual(explicit.presentation?.routine, [])
    }

    func testReviseIssueAnswersAcceptAnyAnswerSquareAndNeverSelectIt() {
        let move = CoachingTestFixtures.fallbackMove
        let reply = Move(from: CoachingTestFixtures.blackRook, to: move.to)
        let answers: Set<Square> = [reply.from, move.to]
        let issue = CoachingTestFixtures.issue(
            reply: reply,
            kind: .materialLoss(points: 3),
            severity: .reviseMove,
            answers: answers
        )
        var session = opponentCheckSession(
            move: move,
            origin: .fallback,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                issues: [issue],
                isAcceptable: false
            )
        )

        XCTAssertTrue(session.handle(.squareTapped(move.to)).isEmpty)
        XCTAssertEqual(session.stage, .reviseMove(origin: .fallback))
        XCTAssertEqual(session.presentation?.boardTask, .move)
        XCTAssertEqual(session.presentation?.headline, "Black could take your pawn.")
    }

    func testHarmlessCheckCanBeFoundAndCompletesAnAcceptableMove() {
        let move = CoachingTestFixtures.openingKnightMove
        let reply = Move(from: CoachingTestFixtures.blackBishop, to: CoachingTestFixtures.whiteKing)
        let issue = CoachingTestFixtures.issue(
            reply: reply,
            kind: .check,
            severity: .notice,
            answers: [reply.from]
        )
        var session = opponentCheckSession(
            move: move,
            origin: .wake,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                issues: [issue],
                concepts: [.developsKnightOrBishop]
            )
        )

        XCTAssertTrue(session.handle(.squareTapped(reply.from)).isEmpty)
        XCTAssertEqual(
            session.stage,
            .complete(move: move, origin: .wake, concepts: [.developsKnightOrBishop])
        )
        XCTAssertEqual(
            session.presentation?.headline,
            "Yes. Black could check your king, but your move still works."
        )
    }

    func testNoticeLevelBestCaseMaterialLossCanBeFoundAndAccepted() {
        let move = CoachingTestFixtures.fallbackMove
        let reply = Move(from: CoachingTestFixtures.blackRook, to: move.to)
        let issue = CoachingTestFixtures.issue(
            reply: reply,
            kind: .materialLoss(points: 1),
            severity: .notice,
            answers: [reply.from, reply.to]
        )
        var session = opponentCheckSession(
            move: move,
            origin: .fallback,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                issues: [issue]
            )
        )

        XCTAssertTrue(session.handle(.squareTapped(reply.from)).isEmpty)
        XCTAssertEqual(
            session.stage,
            .complete(move: move, origin: .fallback, concepts: [])
        )
        XCTAssertEqual(session.presentation?.headline, "Black could take your pawn.")
    }

    func testLooksSafeMissesAnExistingReplyIssueWithoutChangingStage() {
        let move = CoachingTestFixtures.fallbackMove
        let issue = CoachingTestFixtures.issue(
            reply: Move(from: CoachingTestFixtures.blackRook, to: move.to),
            kind: .materialLoss(points: 3),
            severity: .reviseMove,
            answers: [CoachingTestFixtures.blackRook]
        )
        var session = opponentCheckSession(
            move: move,
            origin: .fallback,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                issues: [issue],
                isAcceptable: false
            )
        )

        session.handle(.actionChosen(.looksSafe))

        XCTAssertEqual(session.stage, .opponentCheck(move: move, origin: .fallback))
        XCTAssertEqual(session.presentation?.headline, "There is one to find.")
        XCTAssertEqual(session.missesAtCurrentLevel, 1)
    }

    func testLooksSafeCompletesAcceptableMoveWithoutCommitting() {
        let move = CoachingTestFixtures.openingKnightMove
        var session = opponentCheckSession(
            move: move,
            origin: .wake,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                concepts: [.developsKnightOrBishop]
            )
        )

        XCTAssertTrue(session.handle(.actionChosen(.looksSafe)).isEmpty)
        XCTAssertEqual(
            session.stage,
            .complete(move: move, origin: .wake, concepts: [.developsKnightOrBishop])
        )
        XCTAssertEqual(
            session.presentation?.headline,
            "That works. Your knight joined the game and helps in the center."
        )
        XCTAssertEqual(session.presentation?.actions.map(\.action), [.done, .keepLooking, .stop])
        XCTAssertEqual(
            session.handle(.actionChosen(.done)),
            [.commitWithExistingDonePath]
        )
    }

    func testLooksSafeRejectsMoveWithoutPurposeAndReturnsToOrigin() {
        let move = CoachingTestFixtures.fallbackMove
        var session = opponentCheckSession(
            move: move,
            origin: .fallback,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                isAcceptable: false
            )
        )

        XCTAssertTrue(session.handle(.actionChosen(.looksSafe)).isEmpty)
        XCTAssertEqual(session.stage, .fallbackChooseMove)
        XCTAssertEqual(
            session.presentation?.headline,
            "That move looks safe, but give the piece a clear job."
        )
    }

    func testChangingMoveInvalidatesReplyAdviceButPreservesOrigin() {
        let move = CoachingTestFixtures.safeMove
        var session = opponentCheckSession(
            move: move,
            origin: .safe,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                concepts: [.pieceNeedsHelp]
            )
        )

        XCTAssertTrue(session.handle(.positionChanged(revision: 8)).isEmpty)
        XCTAssertEqual(session.stage, .reviseMove(origin: .safe))
        XCTAssertEqual(
            session.handle(.moveStaged(move)),
            [.requestAdvice(context: .tentativeMove(origin: .safe))]
        )
    }

    func testRemovingMoveWhileAdviceIsPendingPreservesOriginForReplacement() {
        var session = CoachingSession(learner: .white)
        session.receive(CoachingTestFixtures.takeAdvice)
        session.handle(.moveStaged(CoachingTestFixtures.profitableCapture))

        XCTAssertTrue(session.handle(.positionChanged(revision: 8)).isEmpty)
        XCTAssertEqual(session.stage, .reviseMove(origin: .take))
        XCTAssertEqual(
            session.handle(.moveStaged(CoachingTestFixtures.profitableCapture)),
            [.requestAdvice(context: .tentativeMove(origin: .take))]
        )
    }

    func testSafeSubjectSurvivesMoveRevisionAndReplacementAdvice() {
        let move = CoachingTestFixtures.safeMove
        var session = CoachingSession(learner: .white)
        session.receive(CoachingTestFixtures.multipleDangerAdvice)
        session.handle(.squareTapped(CoachingTestFixtures.whiteRook))
        session.handle(.squareTapped(CoachingTestFixtures.blackRook))
        session.handle(.moveStaged(move))
        session.receive(CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: .safe,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                concepts: [.pieceNeedsHelp]
            ),
            urgent: CoachingTestFixtures.multipleDangerAdvice.urgentProblems
        ))
        session.handle(.positionChanged(revision: 8))
        session.handle(.moveStaged(move))

        session.receive(CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: .safe,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                resolvesRequiredDanger: false,
                isAcceptable: false
            ),
            urgent: CoachingTestFixtures.multipleDangerAdvice.urgentProblems
        ))

        XCTAssertEqual(
            session.stage,
            .safeResolve(target: CoachingTestFixtures.whiteRook)
        )
        XCTAssertEqual(session.presentation?.headline, "Your rook would still need help.")
    }

    func testWakeSubjectSurvivesMoveRevisionAndReplacementAdvice() {
        let move = CoachingTestFixtures.alternateKnightMove
        var session = CoachingSession(learner: .white)
        session.receive(CoachingTestFixtures.startingPositionAdvice)
        session.handle(.squareTapped(CoachingTestFixtures.alternateKnight))
        session.handle(.moveStaged(move))
        session.receive(CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: .wake,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                concepts: [.developsKnightOrBishop]
            )
        ))
        session.handle(.positionChanged(revision: 8))
        session.handle(.moveStaged(move))

        session.receive(CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: .wake,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                concepts: [],
                isAcceptable: false
            )
        ))

        XCTAssertEqual(
            session.stage,
            .wakeChooseMove(
                piece: CoachingTestFixtures.alternateKnight,
                opening: true
            )
        )
    }

    func testCheckMoveThatDoesNotResolveCheckReturnsToCheckResolution() {
        let move = CoachingTestFixtures.safeMove
        var session = preparedSession(for: .check)
        session.handle(.moveStaged(move))
        session.receive(CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: .check,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                resolvesRequiredDanger: false,
                isAcceptable: false
            )
        ))

        XCTAssertEqual(session.stage, .checkResolve)
        XCTAssertEqual(session.presentation?.headline, "Your king would still need help.")
    }

    func testPreexistingMoveWithoutPurposeReturnsToRevisionAfterReplyCheck() {
        let move = CoachingTestFixtures.fallbackMove
        var session = opponentCheckSession(
            move: move,
            origin: .preexisting,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                isAcceptable: false
            )
        )

        session.handle(.actionChosen(.looksSafe))

        XCTAssertEqual(session.stage, .reviseMove(origin: .preexisting))
        XCTAssertEqual(
            session.presentation?.headline,
            "That move looks safe, but give the piece a clear job."
        )
    }

    func testStopAndKeepLookingPreserveTentativeMove() {
        var active = CoachingSession(learner: .white)
        active.receive(CoachingTestFixtures.fallbackAdvice)
        XCTAssertEqual(
            active.handle(.actionChosen(.stop)),
            [.stop(preservingTentativeMove: true)]
        )

        var complete = opponentCheckSession(
            move: CoachingTestFixtures.fallbackMove,
            origin: .fallback,
            assessment: CoachingTestFixtures.acceptableAssessment(
                CoachingTestFixtures.fallbackMove
            )
        )
        complete.handle(.actionChosen(.looksSafe))
        XCTAssertEqual(
            complete.handle(.actionChosen(.keepLooking)),
            [.stop(preservingTentativeMove: true)]
        )
    }

    func testHintAdvancesOneLevelOnlyAfterActionAndTwoMissesOfferIt() {
        var session = CoachingSession(learner: .white)
        session.receive(CoachingTestFixtures.multipleDangerAdvice)

        let unrelated = Square(file: .a, rank: 2)
        session.handle(.squareTapped(unrelated))
        session.handle(.squareTapped(unrelated))
        XCTAssertEqual(session.hintLevel, 0)
        XCTAssertEqual(session.missesAtCurrentLevel, 2)
        XCTAssertTrue(session.presentation?.instruction?.contains("Want a hint?") == true)
        XCTAssertEqual(
            session.presentation?.actions.first(where: { $0.action == .hint })?.prominence,
            .primary
        )

        let oldPulse = session.presentation?.focus.pulseID
        XCTAssertTrue(session.handle(.actionChosen(.hint)).isEmpty)
        XCTAssertEqual(session.hintLevel, 1)
        XCTAssertEqual(session.missesAtCurrentLevel, 0)
        XCTAssertEqual(session.presentation?.focus.pulseID, (oldPulse ?? 0) + 1)
        session.handle(.actionChosen(.hint))
        session.handle(.actionChosen(.hint))
        session.handle(.actionChosen(.hint))
        session.handle(.actionChosen(.hint))
        XCTAssertEqual(session.hintLevel, 4)
    }

    func testIllegalMoveReturnsToEveryOriginSpecificMoveStage() {
        let move = CoachingTestFixtures.safeMove
        let illegal = CoachingMoveAssessment(
            move: move,
            isLegal: false,
            resolvesRequiredDanger: false,
            opponentIssues: [],
            concepts: [],
            isAcceptable: false
        )

        let expected: [(CoachingMoveOrigin, CoachingStage)] = [
            (.preexisting, .reviseMove(origin: .preexisting)),
            (.check, .checkResolve),
            (.safe, .safeResolve(target: CoachingTestFixtures.whiteQueen)),
            (.take, .takeChooseMove),
            (
                .wake,
                .wakeChooseMove(piece: CoachingTestFixtures.openingKnight, opening: true)
            ),
            (.fallback, .fallbackChooseMove),
        ]

        for (origin, expectedStage) in expected {
            var session = preparedSession(for: origin)
            session.handle(.moveStaged(move))
            session.receive(CoachingTestFixtures.adviceForTentativeMove(
                move,
                origin: origin,
                assessment: illegal
            ))
            XCTAssertEqual(session.stage, expectedStage, "Wrong return stage for \(origin)")
            XCTAssertEqual(
                session.presentation?.headline,
                "This move leaves your king in check. Try another move."
            )
            XCTAssertEqual(session.presentation?.boardTask, .move)
        }
    }

    func testEveryOriginCanReachOpponentCheckAndCompletion() {
        let move = CoachingTestFixtures.safeMove
        for origin in [
            CoachingMoveOrigin.preexisting, .check, .safe, .take, .wake, .fallback,
        ] {
            var session = preparedSession(for: origin)
            session.handle(.moveStaged(move))
            let concept: CoachingConcept = origin == .wake
                ? .developsKnightOrBishop
                : (origin == .take ? .profitableCapture : .pieceNeedsHelp)
            session.receive(CoachingTestFixtures.adviceForTentativeMove(
                move,
                origin: origin,
                assessment: CoachingTestFixtures.acceptableAssessment(
                    move,
                    concepts: [concept]
                ),
                confidence: origin == .fallback ? .unsupported : .high
            ))
            XCTAssertEqual(session.stage, .opponentCheck(move: move, origin: origin))
            XCTAssertTrue(session.handle(.actionChosen(.looksSafe)).isEmpty)
            XCTAssertEqual(
                session.stage,
                .complete(move: move, origin: origin, concepts: [concept])
            )
        }
    }

    private func opponentCheckSession(
        move: Move,
        origin: CoachingMoveOrigin,
        assessment: CoachingMoveAssessment
    ) -> CoachingSession {
        var session = preparedSession(for: origin)
        session.handle(.moveStaged(move))
        session.receive(CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: origin,
            assessment: assessment,
            confidence: origin == .fallback ? .unsupported : .high
        ))
        return session
    }

    private func preparedSession(for origin: CoachingMoveOrigin) -> CoachingSession {
        var session = CoachingSession(learner: .white)
        switch origin {
        case .preexisting:
            break
        case .check:
            session.receive(CoachingTestFixtures.advice(
                checking: [CoachingTestFixtures.blackBishop],
                opponentHasCapture: true,
                learnerHasCapture: false
            ))
            session.handle(.squareTapped(CoachingTestFixtures.blackBishop))
        case .safe:
            session.receive(CoachingTestFixtures.multipleDangerAdvice)
            session.handle(.squareTapped(CoachingTestFixtures.whiteQueen))
            session.handle(.squareTapped(CoachingTestFixtures.blackBishop))
        case .take:
            session.receive(CoachingTestFixtures.takeAdvice)
        case .wake:
            session.receive(CoachingTestFixtures.startingPositionAdvice)
            session.handle(.squareTapped(CoachingTestFixtures.openingKnight))
        case .fallback:
            session.receive(CoachingTestFixtures.fallbackAdvice)
        }
        return session
    }
}

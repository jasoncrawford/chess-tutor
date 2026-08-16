import XCTest
@testable import ChessTutor

final class CoachingSessionTests: XCTestCase {
    private let advisor = LocalCoachingAdvisor()

    func testStartingPositionSkipsEmptyScansAndAsksConcreteOpeningQuestion() {
        var session = CoachingSession(learner: .white)

        XCTAssertTrue(session.receive(CoachingTestFixtures.startingPositionAdvice).isEmpty)

        XCTAssertEqual(session.stage, .wakeChoosePiece(purpose: .openingDevelopment(firstMove: true)))
        XCTAssertEqual(session.presentation?.routine, [
            .safeCleared, .takeCleared, .wakeCurrent,
        ])
        XCTAssertEqual(
            session.presentation?.headline,
            "A good first step is to move a center pawn or bring out a knight. Which would you like to try?"
        )
        XCTAssertTrue(session.presentation?.focus.candidateSquares.isEmpty == true)
    }

    func testSafeTranscriptAcceptsAnyUrgentPieceThenItsAttacker() {
        var session = CoachingSession(learner: .white)
        session.receive(CoachingTestFixtures.multipleDangerAdvice)

        let chosenTarget = CoachingTestFixtures.whiteRook
        XCTAssertTrue(session.handle(.squareTapped(chosenTarget)).isEmpty)
        XCTAssertEqual(session.stage, .safeIdentifyAttacker(target: chosenTarget))
        XCTAssertEqual(
            session.presentation?.headline,
            "You found the rook. What black piece is attacking it?"
        )

        let attacker = CoachingTestFixtures.blackRook
        XCTAssertTrue(session.handle(.squareTapped(attacker)).isEmpty)
        XCTAssertEqual(session.stage, .safeResolve(target: chosenTarget))
        XCTAssertEqual(
            session.presentation?.headline,
            "Yes—that rook is attacking your rook. How could you help your rook?"
        )
        XCTAssertEqual(session.presentation?.instruction, "Make a move that gets it safe.")
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

    func testRealCheckEvasionAdvancesEvenWhenSeparateMaterialDangerRemains() async throws {
        let king = Square(file: .e, rank: 1)
        let checkingRook = Square(file: .e, rank: 8)
        let looseBishop = Square(file: .c, rank: 2)
        let materialAttacker = Square(file: .c, rank: 8)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                king: Piece(kind: .king, color: .white),
                looseBishop: Piece(kind: .bishop, color: .white),
                checkingRook: Piece(kind: .rook, color: .black),
                materialAttacker: Piece(kind: .rook, color: .black),
                Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
            ]
        )
        let startAdvice = try await advisor.advice(for: CoachingRequest(
            committedState: state,
            tentativeMove: nil,
            learner: .white,
            positionRevision: 1,
            context: .start
        ))
        let allLegalEvasions = Set(LegalMoveGenerator.allLegalMoves(in: state))
        let assessment = try XCTUnwrap(startAdvice.moveAssessments.values.first {
            $0.isLegal
                && !$0.resolvesRequiredDanger
                && $0.opponentIssues.contains {
                    $0.kind == .materialLoss(points: 3)
                        && $0.severity == .reviseMove
                        && $0.answerSquares.contains(looseBishop)
                }
        })
        let evasion = assessment.move
        let materialIssue = try XCTUnwrap(assessment.opponentIssues.first {
            $0.kind == .materialLoss(points: 3) && $0.severity == .reviseMove
        })
        XCTAssertTrue(allLegalEvasions.contains(evasion))
        XCTAssertTrue(materialIssue.answerSquares.contains(looseBishop))

        var session = CoachingSession(learner: .white)
        session.receive(startAdvice)
        session.handle(.squareTapped(checkingRook))
        session.handle(.actionChosen(.hint))
        session.handle(.actionChosen(.hint))
        XCTAssertEqual(
            session.presentation?.focus.candidateSquares,
            Set(allLegalEvasions.map(\.to))
        )

        XCTAssertEqual(
            session.handle(.moveStaged(evasion)),
            [.requestAdvice(context: .tentativeMove(origin: .check))]
        )
        let moveAdvice = try await advisor.advice(for: CoachingRequest(
            committedState: state,
            tentativeMove: evasion,
            learner: .white,
            positionRevision: 2,
            context: .tentativeMove(origin: .check)
        ))
        session.receive(moveAdvice)

        XCTAssertEqual(session.stage, .opponentCheck(move: evasion, origin: .check))
        XCTAssertFalse(session.presentation?.headline.contains("king would still need help") == true)
        XCTAssertTrue(session.handle(.squareTapped(looseBishop)).isEmpty)
        XCTAssertEqual(session.stage, .reviseMove(origin: .check))
        XCTAssertEqual(session.presentation?.headline, "Black could take your bishop.")
    }

    func testNontrivialSafeRequiresCorrectAbsenceAndRejectsIncorrectAbsence() {
        var clearSession = CoachingSession(learner: .white)
        clearSession.receive(CoachingTestFixtures.nontrivialSafeClearAdvice)
        XCTAssertEqual(clearSession.stage, .safeLocate)
        clearSession.handle(.actionChosen(.noAnswer))
        XCTAssertEqual(clearSession.stage, .fallbackChooseMove)
        XCTAssertEqual(clearSession.presentation?.headline, "Right—there isn’t one.")
        XCTAssertEqual(clearSession.presentation?.instruction, "Make a move on the board.")
        XCTAssertEqual(clearSession.presentation?.routine, [])

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
        XCTAssertEqual(emptySession.stage, .fallbackChooseMove)
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

    func testRepeatedUnprofitableCapturesPreserveHintLevelAtAvailableFocusCap() {
        let move = CoachingTestFixtures.profitableCapture
        let estimate = CoachingTestFixtures.capture(
            move: move,
            captured: Piece(kind: .rook, color: .black),
            capturedSquare: move.to,
            recapture: Move(from: CoachingTestFixtures.blackKing, to: move.to),
            net: -4
        )
        let advice = CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: .take,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                concepts: [],
                isAcceptable: false
            ),
            learnerCaptures: [estimate]
        )
        var session = CoachingSession(learner: .white)
        session.receive(CoachingTestFixtures.takeAdvice)
        session.handle(.actionChosen(.hint))

        for expectedMisses in 1...2 {
            session.handle(.moveStaged(move))
            session.receive(advice)
            XCTAssertEqual(session.stage, .takeChooseMove)
            XCTAssertEqual(session.hintLevel, 1)
            XCTAssertEqual(session.missesAtCurrentLevel, expectedMisses)
        }
        XCTAssertFalse(session.presentation?.instruction?.contains("Want a hint?") == true)
        XCTAssertFalse(session.presentation?.actions.map(\.action).contains(.hint) == true)
    }

    func testEveryWakeSourceAlternativeSelectsExactlyThatPiece() {
        for source in [CoachingTestFixtures.openingKnight, CoachingTestFixtures.alternateKnight] {
            var session = CoachingSession(learner: .white)
            session.receive(CoachingTestFixtures.startingPositionAdvice)

            XCTAssertEqual(session.handle(.squareTapped(source)), [.selectSquare(source)])
            XCTAssertEqual(
                session.stage,
                .wakeChooseMove(piece: source, purpose: .openingDevelopment(firstMove: true))
            )
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
            .wakeChooseMove(
                piece: CoachingTestFixtures.openingKnight,
                purpose: .openingDevelopment(firstMove: true)
            )
        )
        XCTAssertEqual(
            rejected.presentation?.headline,
            "That move looks safe, but give the piece a clear job."
        )
    }

    func testRepeatedPurposelessWakeMovesPreserveHintLevelAtAvailableFocusCap() {
        let move = CoachingTestFixtures.openingKnightMove
        let advice = CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: .wake,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                concepts: [],
                isAcceptable: false
            )
        )
        var session = CoachingSession(learner: .white)
        session.receive(CoachingTestFixtures.startingPositionAdvice)
        session.handle(.squareTapped(CoachingTestFixtures.openingKnight))
        session.handle(.actionChosen(.hint))

        for expectedMisses in 1...2 {
            session.handle(.moveStaged(move))
            session.receive(advice)
            XCTAssertEqual(
                session.stage,
                .wakeChooseMove(
                    piece: CoachingTestFixtures.openingKnight,
                    purpose: .openingDevelopment(firstMove: true)
                )
            )
            XCTAssertEqual(session.hintLevel, 1)
            XCTAssertEqual(session.missesAtCurrentLevel, expectedMisses)
        }
        XCTAssertFalse(session.presentation?.instruction?.contains("Want a hint?") == true)
        XCTAssertFalse(session.presentation?.actions.map(\.action).contains(.hint) == true)
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

    func testFallbackHintsCapAtMarkerLevelWithoutPromisingMissingFocus() {
        var session = CoachingSession(learner: .white)
        session.receiveUnsupportedPosition()

        session.handle(.actionChosen(.hint))
        session.handle(.actionChosen(.hint))

        XCTAssertEqual(session.hintLevel, 1)
        XCTAssertEqual(
            session.presentation?.instruction,
            "Use the movement markers, then make a move on the board."
        )
        XCTAssertEqual(session.presentation?.focus, CoachFocusPresentation(
            emphasizedSquares: [],
            candidateSquares: [],
            paths: [],
            pulseID: 1
        ))
        XCTAssertFalse(session.presentation?.actions.map(\.action).contains(.hint) == true)
    }

    func testReviseHintsCapAtMarkerLevelWithoutPromisingMissingFocus() {
        var session = CoachingSession(learner: .white)
        session.receive(CoachingTestFixtures.fallbackAdvice)
        session.handle(.moveStaged(CoachingTestFixtures.fallbackMove))
        session.handle(.positionChanged(revision: 8))
        XCTAssertEqual(session.stage, .reviseMove(origin: .fallback))

        session.handle(.actionChosen(.hint))
        session.handle(.actionChosen(.hint))

        XCTAssertEqual(session.hintLevel, 1)
        XCTAssertEqual(
            session.presentation?.instruction,
            "Use the movement markers, then make a move on the board."
        )
        XCTAssertTrue(session.presentation?.focus.candidateSquares.isEmpty == true)
        XCTAssertTrue(session.presentation?.focus.emphasizedSquares.isEmpty == true)
        XCTAssertTrue(session.presentation?.focus.paths.isEmpty == true)
        XCTAssertFalse(session.presentation?.actions.map(\.action).contains(.hint) == true)
    }

    func testCheckLocateHintsCapAtSuppliedCandidateSquares() {
        let checker = CoachingTestFixtures.blackRook
        var session = CoachingSession(learner: .white)
        session.receive(CoachingTestFixtures.advice(
            checking: [checker],
            opponentHasCapture: true,
            learnerHasCapture: false
        ))

        for _ in 0..<4 { session.handle(.actionChosen(.hint)) }

        XCTAssertEqual(session.hintLevel, 2)
        XCTAssertEqual(
            session.presentation?.instruction,
            "Look at the highlighted choices. Tap the piece giving check."
        )
        XCTAssertEqual(session.presentation?.focus.candidateSquares, [checker])
        XCTAssertTrue(session.presentation?.focus.emphasizedSquares.isEmpty == true)
        XCTAssertTrue(session.presentation?.focus.paths.isEmpty == true)
        XCTAssertFalse(session.presentation?.actions.map(\.action).contains(.hint) == true)
    }

    func testSafeLocateHintsCapAtSuppliedCandidateSquares() {
        var session = CoachingSession(learner: .white)
        session.receive(CoachingTestFixtures.multipleDangerAdvice)

        for _ in 0..<4 { session.handle(.actionChosen(.hint)) }

        XCTAssertEqual(session.hintLevel, 2)
        XCTAssertEqual(
            session.presentation?.instruction,
            "Look at the highlighted choices. Tap your piece, or choose I don’t see one."
        )
        XCTAssertEqual(
            session.presentation?.focus.candidateSquares,
            [CoachingTestFixtures.whiteQueen, CoachingTestFixtures.whiteRook]
        )
        XCTAssertTrue(session.presentation?.focus.emphasizedSquares.isEmpty == true)
        XCTAssertTrue(session.presentation?.focus.paths.isEmpty == true)
        XCTAssertFalse(session.presentation?.actions.map(\.action).contains(.hint) == true)
    }

    func testWakePieceHintsCapAtSuppliedCandidateSquares() {
        var session = CoachingSession(learner: .white)
        session.receive(CoachingTestFixtures.startingPositionAdvice)

        for _ in 0..<4 { session.handle(.actionChosen(.hint)) }

        XCTAssertEqual(session.hintLevel, 2)
        XCTAssertEqual(
            session.presentation?.instruction,
            "Look at the highlighted choices. Tap the piece you want to move."
        )
        XCTAssertEqual(
            session.presentation?.focus.candidateSquares,
            [CoachingTestFixtures.openingKnight, CoachingTestFixtures.alternateKnight]
        )
        XCTAssertTrue(session.presentation?.focus.emphasizedSquares.isEmpty == true)
        XCTAssertTrue(session.presentation?.focus.paths.isEmpty == true)
        XCTAssertFalse(session.presentation?.actions.map(\.action).contains(.hint) == true)
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

    func testReviseIssueWinsWhenTappedSquareAlsoMatchesNoticeIssue() {
        let move = CoachingTestFixtures.openingKnightMove
        let reply = Move(from: CoachingTestFixtures.blackBishop, to: move.to)
        let sharedAnswer = reply.from
        let notice = CoachingTestFixtures.issue(
            reply: reply,
            kind: .check,
            severity: .notice,
            answers: [sharedAnswer]
        )
        let revise = CoachingTestFixtures.issue(
            reply: reply,
            kind: .materialLoss(points: 3),
            severity: .reviseMove,
            answers: [sharedAnswer, reply.to]
        )
        var session = opponentCheckSession(
            move: move,
            origin: .wake,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                issues: [notice, revise],
                concepts: [.developsKnightOrBishop],
                isAcceptable: false
            )
        )

        XCTAssertTrue(session.handle(.squareTapped(sharedAnswer)).isEmpty)
        XCTAssertEqual(session.stage, .reviseMove(origin: .wake))
        XCTAssertEqual(session.presentation?.headline, "Black could take your knight.")
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
            "Yes. Black could check your king, but your move still works. "
                + "Your knight came into the game. Chess players call that developing a piece."
        )
    }

    func testRealHarmlessCheckerDoesNotClaimMoveWorksWhileSeriousIssueRemains() async throws {
        let king = Square(file: .e, rank: 1)
        let move = CoachingTestFixtures.openingKnightMove
        let harmlessChecker = Square(file: .a, rank: 8)
        let looseQueen = Square(file: .b, rank: 3)
        let materialAttacker = Square(file: .a, rank: 4)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                king: Piece(kind: .king, color: .white),
                move.from: Piece(kind: .knight, color: .white),
                looseQueen: Piece(kind: .queen, color: .white),
                harmlessChecker: Piece(kind: .rook, color: .black),
                materialAttacker: Piece(kind: .bishop, color: .black),
                Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
            ]
        )
        let advice = try await advisor.advice(for: CoachingRequest(
            committedState: state,
            tentativeMove: move,
            learner: .white,
            positionRevision: 1,
            context: .tentativeMove(origin: .preexisting)
        ))
        let assessment = try XCTUnwrap(advice.moveAssessments[move])
        XCTAssertTrue(assessment.opponentIssues.contains {
            $0.kind == .check && $0.severity == .notice
        })
        XCTAssertTrue(assessment.opponentIssues.contains {
            $0.kind == .materialLoss(points: 9) && $0.severity == .reviseMove
        })

        var session = CoachingSession(learner: .white)
        session.handle(.moveStaged(move))
        session.receive(advice)
        XCTAssertEqual(session.stage, .opponentCheck(move: move, origin: .preexisting))

        XCTAssertTrue(session.handle(.squareTapped(harmlessChecker)).isEmpty)
        XCTAssertEqual(session.stage, .opponentCheck(move: move, origin: .preexisting))
        XCTAssertEqual(session.presentation?.headline, "Yes.")
        XCTAssertFalse(session.presentation?.headline.contains("move still works") == true)

        XCTAssertTrue(session.handle(.squareTapped(looseQueen)).isEmpty)
        XCTAssertEqual(session.stage, .reviseMove(origin: .preexisting))
        XCTAssertEqual(session.presentation?.headline, "Black could take your queen.")
    }

    func testNoticeLevelBestCaseMaterialLossCanBeFoundAndAccepted() {
        let move = CoachingTestFixtures.openingKnightMove
        let reply = Move(from: CoachingTestFixtures.blackBishop, to: move.to)
        let issue = CoachingTestFixtures.issue(
            reply: reply,
            kind: .materialLoss(points: 1),
            severity: .notice,
            answers: [reply.from, reply.to]
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
            "Black could take your knight. Your move still works. "
                + "Your knight came into the game. Chess players call that developing a piece."
        )
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
            "That works. Your knight came into the game. Chess players call that developing a piece."
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
                purpose: .openingDevelopment(firstMove: true)
            )
        )
    }

    func testLegalCheckMoveAdvancesEvenWhenSeparateDangerIsUnresolved() {
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

        XCTAssertEqual(session.stage, .opponentCheck(move: move, origin: .check))
    }

    func testRepeatedUnresolvedSafeMovesPreserveHintLevelAtAvailableFocusCap() {
        let move = CoachingTestFixtures.safeMove
        let advice = CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: .safe,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                resolvesRequiredDanger: false,
                isAcceptable: false
            ),
            urgent: CoachingTestFixtures.multipleDangerAdvice.urgentProblems
        )
        var session = preparedSession(for: .safe)
        session.handle(.actionChosen(.hint))

        for expectedMisses in 1...2 {
            session.handle(.moveStaged(move))
            session.receive(advice)
            XCTAssertEqual(
                session.stage,
                .safeResolve(target: CoachingTestFixtures.whiteQueen)
            )
            XCTAssertEqual(session.hintLevel, 1)
            XCTAssertEqual(session.missesAtCurrentLevel, expectedMisses)
        }
        XCTAssertFalse(session.presentation?.instruction?.contains("Want a hint?") == true)
        XCTAssertFalse(session.presentation?.actions.map(\.action).contains(.hint) == true)
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

    func testHintAdvancesOneLevelOnlyAfterActionAndCapsAtStrongestFocusLevel() {
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
        XCTAssertEqual(session.hintLevel, 2)
        XCTAssertFalse(session.presentation?.actions.map(\.action).contains(.hint) == true)
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
                .wakeChooseMove(
                    piece: CoachingTestFixtures.openingKnight,
                    purpose: .openingDevelopment(firstMove: true)
                )
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

    func testRepeatedIllegalMovesPreserveHintLevelAndCountMisses() {
        let move = CoachingTestFixtures.fallbackMove
        let illegal = CoachingMoveAssessment(
            move: move,
            isLegal: false,
            resolvesRequiredDanger: false,
            opponentIssues: [],
            concepts: [],
            isAcceptable: false
        )
        let advice = CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: .fallback,
            assessment: illegal,
            confidence: .unsupported
        )
        var session = preparedSession(for: .fallback)
        session.handle(.actionChosen(.hint))

        for expectedMisses in 1...2 {
            session.handle(.moveStaged(move))
            session.receive(advice)
            XCTAssertEqual(session.stage, .fallbackChooseMove)
            XCTAssertEqual(session.hintLevel, 1)
            XCTAssertEqual(session.missesAtCurrentLevel, expectedMisses)
        }
        XCTAssertFalse(session.presentation?.instruction?.contains("Want a hint?") == true)
        XCTAssertFalse(session.presentation?.actions.map(\.action).contains(.hint) == true)
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

    func testLevelThreeFocusShowsRelationshipWithoutCandidatePath() {
        var session = CoachingSession(learner: .white)
        session.receive(CoachingTestFixtures.multipleDangerAdvice)
        session.handle(.squareTapped(CoachingTestFixtures.whiteQueen))

        session.handle(.actionChosen(.hint))
        session.handle(.actionChosen(.hint))
        session.handle(.actionChosen(.hint))

        XCTAssertEqual(session.hintLevel, 3)
        XCTAssertEqual(
            session.presentation?.focus.candidateSquares,
            [CoachingTestFixtures.blackBishop]
        )
        XCTAssertEqual(
            session.presentation?.focus.emphasizedSquares,
            [CoachingTestFixtures.blackBishop, CoachingTestFixtures.whiteQueen]
        )
        XCTAssertEqual(session.presentation?.focus.paths, [])

        session.handle(.actionChosen(.hint))

        XCTAssertEqual(session.hintLevel, 4)
        XCTAssertEqual(session.presentation?.focus.paths, [CoachFocusPath(
            source: CoachingTestFixtures.blackBishop,
            destination: CoachingTestFixtures.whiteQueen,
            role: .attacker
        )])
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

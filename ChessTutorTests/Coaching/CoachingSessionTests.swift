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

    func testRoutineIsHiddenOutsideSafeTakeWakeDecisionStages() {
        var session = CoachingSession(learner: .white)
        let wakeMove = Move(
            from: CoachingTestFixtures.openingKnight,
            to: Square(file: .c, rank: 3)
        )
        session.receive(CoachingTestFixtures.startingPositionAdvice)
        XCTAssertEqual(session.presentation?.routine, [
            .safeCleared, .takeCleared, .wakeCurrent,
        ])

        session.handle(.squareTapped(CoachingTestFixtures.openingKnight))
        session.handle(.moveStaged(wakeMove))
        session.receive(CoachingTestFixtures.adviceForTentativeMove(
            wakeMove,
            origin: .wake,
            assessment: CoachingTestFixtures.acceptableAssessment(
                wakeMove,
                concepts: [.developsKnightOrBishop]
            )
        ))

        XCTAssertEqual(session.presentation?.routine, [])
        session.handle(.actionChosen(.looksSafe))
        XCTAssertEqual(session.presentation?.routine, [])
    }

    func testRoutineIsHiddenDuringCheckFallbackAndRevisionStages() {
        var check = CoachingSession(learner: .white)
        check.receive(CoachingTestFixtures.advice(
            checking: [CoachingTestFixtures.blackBishop],
            opponentHasCapture: true,
            learnerHasCapture: false
        ))
        XCTAssertEqual(check.presentation?.routine, [])

        var fallback = CoachingSession(learner: .white)
        fallback.receive(CoachingTestFixtures.fallbackAdvice)
        XCTAssertEqual(fallback.presentation?.routine, [])

        let move = CoachingTestFixtures.fallbackMove
        var revise = opponentCheckSession(
            move: move,
            origin: .preexisting,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                isAcceptable: false
            )
        )
        revise.handle(.actionChosen(.looksSafe))
        XCTAssertEqual(revise.presentation?.routine, [])
    }

    func testOpeningStartsWithoutCandidatesAndFirstHintRevealsSourcePieces() {
        var session = CoachingSession(learner: .white)
        session.receive(CoachingTestFixtures.startingPositionAdvice)

        XCTAssertNil(session.presentation?.hint)
        XCTAssertTrue(session.presentation?.focus.candidateSquares.isEmpty == true)

        session.handle(.actionChosen(.hint))

        XCTAssertEqual(session.presentation?.hint, .candidatePieces)
        XCTAssertEqual(
            session.presentation?.focus.candidateSquares,
            Set(CoachingTestFixtures.startingPositionAdvice.wakeOpportunities
                .flatMap(\.moves).map(\.from))
        )
    }

    func testSafeContextPersistsWithoutARequestedHint() {
        var session = CoachingSession(learner: .white)
        session.receive(CoachingTestFixtures.multipleDangerAdvice)
        session.handle(.squareTapped(CoachingTestFixtures.whiteQueen))

        XCTAssertEqual(
            session.presentation?.focus.emphasizedSquares,
            [CoachingTestFixtures.whiteQueen]
        )

        session.handle(.squareTapped(CoachingTestFixtures.blackBishop))

        XCTAssertEqual(
            session.presentation?.focus.emphasizedSquares,
            [CoachingTestFixtures.whiteQueen, CoachingTestFixtures.blackBishop]
        )
        XCTAssertEqual(session.presentation?.focus.paths, [CoachFocusPath(
            source: CoachingTestFixtures.blackBishop,
            destination: CoachingTestFixtures.whiteQueen,
            role: .attacker
        )])
    }

    func testSemanticHintsAlwaysRevealTheBoardFocusTheyName() {
        var check = CoachingSession(learner: .white)
        check.receive(CoachingTestFixtures.advice(
            checking: [CoachingTestFixtures.blackBishop],
            opponentHasCapture: true,
            learnerHasCapture: false,
            assessments: [CoachingTestFixtures.acceptableAssessment(
                CoachingTestFixtures.safeMove,
                concepts: [.pieceNeedsHelp]
            )]
        ))
        check.handle(.actionChosen(.hint))
        check.handle(.actionChosen(.hint))
        let checkLocateHint = check.presentation?.hint

        var safe = CoachingSession(learner: .white)
        safe.receive(CoachingTestFixtures.multipleDangerAdvice)
        safe.handle(.actionChosen(.hint))
        safe.handle(.actionChosen(.hint))

        var attacker = CoachingSession(learner: .white)
        attacker.receive(CoachingTestFixtures.multipleDangerAdvice)
        attacker.handle(.squareTapped(CoachingTestFixtures.whiteQueen))
        attacker.handle(.actionChosen(.hint))
        attacker.handle(.actionChosen(.hint))
        let safeAttackerHint = attacker.presentation?.hint

        var take = CoachingSession(learner: .white)
        take.receive(CoachingTestFixtures.takeAdvice)
        take.handle(.actionChosen(.hint))

        var wake = CoachingSession(learner: .white)
        wake.receive(CoachingTestFixtures.startingPositionAdvice)
        wake.handle(.actionChosen(.hint))
        let wakeSourceHint = wake.presentation?.hint

        let candidatePiecePresentations: [(String, CoachingPresentation?)] = [
            ("check locate", check.presentation),
            ("safe locate", safe.presentation),
            ("safe attacker", attacker.presentation),
            ("take move", take.presentation),
            ("wake source", wake.presentation),
        ]
        for (name, presentation) in candidatePiecePresentations {
            XCTAssertEqual(presentation?.hint, .candidatePieces, name)
            XCTAssertFalse(presentation?.focus.candidateSquares.isEmpty == true, name)
        }

        check.handle(.squareTapped(CoachingTestFixtures.blackBishop))
        check.handle(.actionChosen(.hint))
        check.handle(.actionChosen(.hint))

        var safeResolve = CoachingSession(learner: .white)
        safeResolve.receive(CoachingTestFixtures.multipleDangerAdvice)
        safeResolve.handle(.squareTapped(CoachingTestFixtures.whiteQueen))
        safeResolve.handle(.squareTapped(CoachingTestFixtures.blackBishop))
        safeResolve.handle(.actionChosen(.hint))
        safeResolve.handle(.actionChosen(.hint))

        take.handle(.actionChosen(.hint))

        wake.handle(.actionChosen(.hint))

        var wakeMove = CoachingSession(learner: .white)
        wakeMove.receive(CoachingTestFixtures.startingPositionAdvice)
        wakeMove.handle(.squareTapped(CoachingTestFixtures.openingKnight))
        wakeMove.handle(.actionChosen(.hint))
        wakeMove.handle(.actionChosen(.hint))

        let candidateMovePresentations: [(String, CoachingPresentation?)] = [
            ("check resolve", check.presentation),
            ("safe resolve", safeResolve.presentation),
            ("take move", take.presentation),
            ("wake source", wake.presentation),
            ("wake move", wakeMove.presentation),
        ]
        for (name, presentation) in candidateMovePresentations {
            XCTAssertEqual(presentation?.hint, .candidateMoves, name)
            XCTAssertFalse(presentation?.focus.paths.isEmpty == true, name)
        }

        var sourceSelectionHints = CoachingSession(learner: .white)
        sourceSelectionHints.receive(CoachingTestFixtures.multipleDangerAdvice)
        sourceSelectionHints.handle(.actionChosen(.hint))
        sourceSelectionHints.handle(.actionChosen(.hint))
        let safeLocateHints = [
            sourceSelectionHints.presentation?.hint,
        ]

        sourceSelectionHints.handle(.squareTapped(CoachingTestFixtures.whiteQueen))
        sourceSelectionHints.handle(.actionChosen(.hint))
        sourceSelectionHints.handle(.actionChosen(.hint))
        let sourceHints = safeLocateHints + [
            sourceSelectionHints.presentation?.hint,
            checkLocateHint,
            safeAttackerHint,
            wakeSourceHint,
        ]
        XCTAssertFalse(sourceHints.contains(.movementMarkers))
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

    func testTapFeedbackClassifiesBoardFactsWithoutChangingCandidateSelection() {
        let pawn = Square(file: .a, rank: 2)
        let pawnCapture = CoachingTestFixtures.capture(
            move: Move(from: CoachingTestFixtures.blackBishop, to: pawn),
            captured: Piece(kind: .pawn, color: .white),
            capturedSquare: pawn,
            net: 1
        )
        let advice = CoachingTestFixtures.advice(
            opponentHasCapture: true,
            learnerHasCapture: false,
            opponentCaptures: [pawnCapture],
            urgent: CoachingTestFixtures.multipleDangerAdvice.urgentProblems
        )
        let urgentPiece = advice.urgentProblems.first!.piece.kind

        var safePieceSession = CoachingSession(learner: .white)
        safePieceSession.receive(CoachingTestFixtures.multipleDangerAdvice)
        safePieceSession.handle(.squareTapped(Square(file: .a, rank: 2)))
        XCTAssertEqual(safePieceSession.presentation?.headline, "That pawn is safe right now.")

        var lowerPrioritySession = CoachingSession(learner: .white)
        lowerPrioritySession.receive(advice)
        lowerPrioritySession.handle(.squareTapped(pawn))
        XCTAssertEqual(
            lowerPrioritySession.presentation?.headline,
            "Yes, that pawn is threatened. Your \(urgentPiece.rawValue) is worth more, so help the \(urgentPiece.rawValue) first."
        )

        var wrongColorSession = CoachingSession(learner: .white)
        wrongColorSession.receive(CoachingTestFixtures.multipleDangerAdvice)
        wrongColorSession.handle(.squareTapped(CoachingTestFixtures.blackBishop))
        XCTAssertEqual(wrongColorSession.presentation?.headline, "Tap one of your pieces.")
        XCTAssertEqual(wrongColorSession.hintLevel, 0)
        XCTAssertEqual(wrongColorSession.missesAtCurrentLevel, 1)
        XCTAssertEqual(
            wrongColorSession.presentation?.actions.first { $0.action == .hint }?.prominence,
            .primary
        )

        var attackerSession = CoachingSession(learner: .white)
        attackerSession.receive(CoachingTestFixtures.multipleDangerAdvice)
        attackerSession.handle(.squareTapped(CoachingTestFixtures.whiteQueen))
        attackerSession.handle(.squareTapped(CoachingTestFixtures.blackRook))
        XCTAssertEqual(attackerSession.presentation?.headline, "That rook isn’t attacking your queen.")

        var blockedWakeSession = CoachingSession(learner: .white)
        blockedWakeSession.receive(CoachingTestFixtures.startingPositionAdvice)
        blockedWakeSession.handle(.squareTapped(Square(file: .a, rank: 1)))
        XCTAssertEqual(
            blockedWakeSession.presentation?.headline,
            "That rook can’t come out yet because other pieces are in the way."
        )

        let move = CoachingTestFixtures.openingKnightMove
        var replySession = opponentCheckSession(
            move: move,
            origin: .wake,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                concepts: [.developsKnightOrBishop]
            )
        )
        let emptySquare = Square(file: .c, rank: 5)
        XCTAssertNil(CoachingTestFixtures.coachingState.board[emptySquare])
        replySession.handle(.squareTapped(emptySquare))
        XCTAssertEqual(
            replySession.presentation?.headline,
            "That square doesn’t show a check or capture after this move."
        )
    }

    func testHigherValueNonurgentThreatDoesNotClaimAnUrgentPieceIsWorthMore() {
        let queenCapture = CoachingTestFixtures.capture(
            move: Move(from: CoachingTestFixtures.blackBishop, to: CoachingTestFixtures.whiteQueen),
            captured: Piece(kind: .queen, color: .white),
            capturedSquare: CoachingTestFixtures.whiteQueen,
            net: 1
        )
        let knightCapture = CoachingTestFixtures.capture(
            move: Move(from: CoachingTestFixtures.blackRook, to: CoachingTestFixtures.openingKnight),
            captured: Piece(kind: .knight, color: .white),
            capturedSquare: CoachingTestFixtures.openingKnight,
            net: 2
        )
        let advice = CoachingTestFixtures.advice(
            opponentHasCapture: true,
            learnerHasCapture: false,
            opponentCaptures: [queenCapture, knightCapture],
            urgent: [CoachingUrgentProblem(
                target: CoachingTestFixtures.openingKnight,
                piece: Piece(kind: .knight, color: .white),
                captures: [knightCapture],
                worstEstimatedLoss: 2
            )]
        )
        var session = CoachingSession(learner: .white)

        session.receive(advice)
        session.handle(.squareTapped(CoachingTestFixtures.whiteQueen))

        XCTAssertEqual(
            session.presentation?.headline,
            "Yes, that queen is threatened. We’re looking for a knight, bishop, rook, or queen Black could win."
        )
    }

    func testUnresolvedRealDangerNamesTheOtherAffectedPieceRatherThanTheSelectedTarget() async throws {
        let queen = Square(file: .d, rank: 4)
        let queenEscape = Move(from: queen, to: Square(file: .d, rank: 2))
        let rook = Square(file: .f, rank: 3)
        let bishop = Square(file: .b, rank: 6)
        let blackRook = Square(file: .f, rank: 7)
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .a, rank: 1): Piece(kind: .king, color: .white),
                queen: Piece(kind: .queen, color: .white),
                rook: Piece(kind: .rook, color: .white),
                bishop: Piece(kind: .bishop, color: .black),
                blackRook: Piece(kind: .rook, color: .black),
                Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
            ]
        )
        let startAdvice = try await advisor.advice(for: CoachingRequest(
            committedState: state,
            tentativeMove: nil,
            learner: .white,
            positionRevision: 1,
            context: .start
        ))
        let queenProblem = try XCTUnwrap(startAdvice.urgentProblems.first { $0.target == queen })
        let queenAttacker = try XCTUnwrap(queenProblem.captures.first?.move.from)
        XCTAssertTrue(startAdvice.urgentProblems.contains { $0.target == rook })

        var session = CoachingSession(learner: .white)
        session.receive(startAdvice)
        session.handle(.squareTapped(queen))
        session.handle(.squareTapped(queenAttacker))
        XCTAssertEqual(session.stage, .safeResolve(target: queen))
        session.handle(.actionChosen(.hint))
        session.handle(.actionChosen(.hint))
        XCTAssertEqual(
            session.handle(.moveStaged(queenEscape)),
            [.requestAdvice(context: .tentativeMove(origin: .safe))]
        )

        let moveAdvice = try await advisor.advice(for: CoachingRequest(
            committedState: state,
            tentativeMove: queenEscape,
            learner: .white,
            positionRevision: 2,
            context: .tentativeMove(origin: .safe)
        ))
        let assessment = try XCTUnwrap(moveAdvice.moveAssessments[queenEscape])
        XCTAssertFalse(assessment.resolvesRequiredDanger)
        XCTAssertTrue(assessment.opponentIssues.contains { issue in
            issue.reply.from == blackRook && issue.answerSquares.contains(rook)
        })

        session.receive(moveAdvice)

        XCTAssertEqual(session.stage, .safeResolve(target: queen))
        XCTAssertEqual(session.presentation?.headline, "The rook could still take your rook after that move.")
        XCTAssertNil(session.presentation?.hint)
        XCTAssertTrue(session.presentation?.focus.emphasizedSquares.isEmpty == true)
        XCTAssertTrue(session.presentation?.focus.candidateSquares.isEmpty == true)
        XCTAssertTrue(session.presentation?.focus.paths.isEmpty == true)
        XCTAssertFalse(session.presentation?.actions.map(\.action).contains(.hint) == true)

        session.handle(.positionChanged(revision: 3))

        XCTAssertEqual(session.stage, .safeResolve(target: queen))
        XCTAssertEqual(session.presentation?.headline, "The rook could still take your rook after that move.")
        XCTAssertEqual(session.presentation?.hint, .candidateMoves)
        XCTAssertEqual(session.presentation?.focus.emphasizedSquares, [queen, queenAttacker])
        XCTAssertFalse(session.presentation?.focus.candidateSquares.isEmpty == true)
        XCTAssertTrue(session.presentation?.focus.paths.contains(CoachFocusPath(
            source: queenAttacker,
            destination: queen,
            role: .attacker
        )) == true)
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
            XCTAssertEqual(session.presentation?.routine, [])
            XCTAssertTrue(session.handle(.squareTapped(checkingPiece)).isEmpty)
            XCTAssertEqual(session.stage, .checkResolve)
            XCTAssertEqual(session.presentation?.routine, [])
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
        XCTAssertEqual(
            clearSession.presentation?.headline,
            "Right—there isn’t one. Nothing urgent stands out. Try a move you like, and we’ll check it together."
        )
        XCTAssertEqual(clearSession.presentation?.instruction, "Make a move on the board.")
        XCTAssertEqual(clearSession.presentation?.routine, [])

        var dangerSession = CoachingSession(learner: .white)
        dangerSession.receive(CoachingTestFixtures.multipleDangerAdvice)
        dangerSession.handle(.actionChosen(.noAnswer))
        XCTAssertEqual(dangerSession.stage, .safeLocate)
        XCTAssertEqual(dangerSession.presentation?.headline, "One of your pieces does need help.")
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
        XCTAssertEqual(session.presentation?.headline, "The bishop could still take your queen after that move.")
    }

    func testTakeRequiresCorrectAbsenceAndStagesCapturesForAdvice() {
        var emptySession = CoachingSession(learner: .white)
        emptySession.receive(CoachingTestFixtures.nontrivialTakeClearAdvice)
        XCTAssertEqual(emptySession.stage, .takeChooseMove)
        emptySession.handle(.actionChosen(.noAnswer))
        XCTAssertEqual(emptySession.stage, .fallbackChooseMove)
        XCTAssertEqual(
            emptySession.presentation?.headline,
            "Right—there isn’t one. Nothing urgent stands out. Try a move you like, and we’ll check it together."
        )

        var takeSession = CoachingSession(learner: .white)
        takeSession.receive(CoachingTestFixtures.takeAdvice)
        takeSession.handle(.actionChosen(.noAnswer))
        XCTAssertEqual(takeSession.presentation?.headline, "There is a useful capture to find.")
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
            "That move is safe, but it doesn’t bring a new piece into the game."
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

    func testFallbackDoesNotOfferHintsWithoutFactualFocus() {
        var session = CoachingSession(learner: .white)
        session.receiveUnsupportedPosition()

        session.handle(.actionChosen(.hint))
        session.handle(.actionChosen(.hint))

        XCTAssertEqual(session.hintLevel, 0)
        XCTAssertEqual(
            session.presentation?.instruction,
            "Make a move on the board."
        )
        XCTAssertEqual(session.presentation?.focus, .empty)
        XCTAssertFalse(session.presentation?.actions.map(\.action).contains(.hint) == true)
    }

    func testRevisionDoesNotOfferHintsWithoutFactualFocus() {
        var session = CoachingSession(learner: .white)
        session.receive(CoachingTestFixtures.fallbackAdvice)
        session.handle(.moveStaged(CoachingTestFixtures.fallbackMove))
        session.handle(.positionChanged(revision: 8))
        XCTAssertEqual(session.stage, .reviseMove(origin: .fallback))

        session.handle(.actionChosen(.hint))
        session.handle(.actionChosen(.hint))

        XCTAssertEqual(session.hintLevel, 0)
        XCTAssertEqual(
            session.presentation?.instruction,
            "Move a piece on the board."
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
            "Try one of the highlighted pieces."
        )
        XCTAssertEqual(session.presentation?.hint, .candidatePieces)
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
            "Try one of the highlighted pieces."
        )
        XCTAssertEqual(session.presentation?.hint, .candidatePieces)
        XCTAssertEqual(
            session.presentation?.focus.candidateSquares,
            [CoachingTestFixtures.whiteQueen, CoachingTestFixtures.whiteRook]
        )
        XCTAssertTrue(session.presentation?.focus.emphasizedSquares.isEmpty == true)
        XCTAssertTrue(session.presentation?.focus.paths.isEmpty == true)
        XCTAssertFalse(session.presentation?.actions.map(\.action).contains(.hint) == true)
    }

    func testSafeLocateWithoutAnUrgentProblemOffersNoHint() {
        var session = CoachingSession(learner: .white)
        session.receive(CoachingTestFixtures.nontrivialSafeClearAdvice)

        XCTAssertEqual(session.stage, .safeLocate)
        XCTAssertFalse(session.presentation?.actions.map(\.action).contains(.hint) == true)
        session.handle(.actionChosen(.hint))

        XCTAssertEqual(session.hintLevel, 0)
        XCTAssertNil(session.presentation?.hint)
        XCTAssertTrue(session.presentation?.focus.candidateSquares.isEmpty == true)
        XCTAssertTrue(session.presentation?.focus.paths.isEmpty == true)
    }

    func testOpponentReplyWithoutAnAnswerableIssueOffersNoHint() {
        let move = CoachingTestFixtures.fallbackMove
        var session = opponentCheckSession(
            move: move,
            origin: .fallback,
            assessment: CoachingTestFixtures.acceptableAssessment(move)
        )

        XCTAssertEqual(session.stage, .opponentCheck(move: move, origin: .fallback))
        XCTAssertFalse(session.presentation?.actions.map(\.action).contains(.hint) == true)

        session.handle(.actionChosen(.hint))

        XCTAssertEqual(session.hintLevel, 0)
        XCTAssertNil(session.presentation?.hint)
        XCTAssertTrue(session.presentation?.focus.candidateSquares.isEmpty == true)
        XCTAssertTrue(session.presentation?.focus.paths.isEmpty == true)
    }

    func testBlackLearnerTranscriptNamesWhiteInSafeAndReplyQuestions() {
        let blackKnight = Square(file: .f, rank: 6)
        let whiteBishop = Square(file: .b, rank: 2)
        let blackMove = Move(from: blackKnight, to: Square(file: .g, rank: 4))
        let state = CoachingTestFixtures.state(
            sideToMove: .black,
            pieces: [
                blackKnight: Piece(kind: .knight, color: .black),
                whiteBishop: Piece(kind: .bishop, color: .white),
            ]
        )
        let capture = CoachingTestFixtures.capture(
            move: Move(from: whiteBishop, to: blackKnight),
            captured: Piece(kind: .knight, color: .black),
            capturedSquare: blackKnight,
            net: 3
        )
        let urgent = CoachingUrgentProblem(
            target: blackKnight,
            piece: Piece(kind: .knight, color: .black),
            captures: [capture],
            worstEstimatedLoss: 3
        )
        var safeSession = CoachingSession(learner: .black)
        safeSession.receive(CoachingTestFixtures.advice(
            state: state,
            learner: .black,
            opponentHasCapture: true,
            learnerHasCapture: false,
            opponentCaptures: [capture],
            urgent: [urgent]
        ))

        safeSession.handle(.squareTapped(blackKnight))

        XCTAssertEqual(
            safeSession.presentation?.headline,
            "You found the knight. What white piece is attacking it?"
        )
        XCTAssertEqual(safeSession.presentation?.instruction, "Tap the white piece.")

        var replySession = CoachingSession(learner: .black)
        replySession.handle(.moveStaged(blackMove))
        replySession.receive(CoachingTestFixtures.advice(
            state: state,
            tentativeMove: blackMove,
            context: .tentativeMove(origin: .preexisting),
            learner: .black,
            opponentHasCapture: false,
            learnerHasCapture: false,
            assessments: [CoachingTestFixtures.acceptableAssessment(blackMove)]
        ))

        XCTAssertEqual(
            replySession.presentation?.instruction,
            "Tap the white checking piece, or tap your piece White could take. Otherwise choose Looks safe."
        )
    }

    func testOpponentMaterialHintPointsToEnPassantCapturedPawnSquare() {
        let whitePawn = Square(file: .d, rank: 2)
        let blackPawn = Square(file: .e, rank: 4)
        let capturedPawn = Square(file: .d, rank: 4)
        let learnerMove = Move(from: whitePawn, to: capturedPawn)
        let reply = Move(
            from: blackPawn,
            to: Square(file: .d, rank: 3),
            special: .enPassant
        )
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                whitePawn: Piece(kind: .pawn, color: .white),
                blackPawn: Piece(kind: .pawn, color: .black),
            ]
        )
        let issue = CoachingTestFixtures.issue(
            reply: reply,
            kind: .materialLoss(points: 1),
            severity: .notice,
            answers: [capturedPawn]
        )
        var session = CoachingSession(learner: .white)
        session.handle(.moveStaged(learnerMove))
        session.receive(CoachingTestFixtures.advice(
            state: state,
            tentativeMove: learnerMove,
            context: .tentativeMove(origin: .preexisting),
            opponentHasCapture: false,
            learnerHasCapture: false,
            assessments: [CoachingTestFixtures.acceptableAssessment(
                learnerMove,
                issues: [issue]
            )]
        ))

        session.handle(.actionChosen(.hint))
        session.handle(.actionChosen(.hint))

        XCTAssertEqual(session.presentation?.hint, .attackerRelationship)
        XCTAssertEqual(session.presentation?.focus.candidateSquares, [capturedPawn])
        XCTAssertEqual(session.presentation?.focus.paths, [CoachFocusPath(
            source: blackPawn,
            destination: capturedPawn,
            role: .attacker
        )])
    }

    func testCastlingRookCheckHintOmitsUnrepresentableKingPath() async throws {
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
        let advice = try await advisor.advice(for: CoachingRequest(
            committedState: state,
            tentativeMove: learnerMove,
            learner: .white,
            positionRevision: 1,
            context: .tentativeMove(origin: .preexisting)
        ))
        let issue = try XCTUnwrap(advice.moveAssessments[learnerMove]?.opponentIssues.first {
            $0.reply == reply && $0.kind == .check
        })
        XCTAssertEqual(issue.answerSquares, [rook])
        let focusedAdvice = CoachingTestFixtures.advice(
            state: state,
            tentativeMove: learnerMove,
            context: .tentativeMove(origin: .preexisting),
            opponentHasCapture: false,
            learnerHasCapture: false,
            assessments: [CoachingTestFixtures.acceptableAssessment(
                learnerMove,
                issues: [issue]
            )]
        )
        var session = CoachingSession(learner: .white)
        session.handle(.moveStaged(learnerMove))
        session.receive(focusedAdvice)

        session.handle(.actionChosen(.hint))
        session.handle(.actionChosen(.hint))

        XCTAssertEqual(session.presentation?.hint, .attackerRelationship)
        XCTAssertEqual(session.presentation?.focus.candidateSquares, [rook])
        XCTAssertTrue(session.presentation?.focus.paths.isEmpty == true)
    }

    func testDiscoveredCheckHintOmitsBlockerPath() async throws {
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
        let advice = try await advisor.advice(for: CoachingRequest(
            committedState: state,
            tentativeMove: learnerMove,
            learner: .white,
            positionRevision: 1,
            context: .tentativeMove(origin: .preexisting)
        ))
        let issue = try XCTUnwrap(advice.moveAssessments[learnerMove]?.opponentIssues.first {
            $0.reply == reply && $0.kind == .check
        })
        XCTAssertEqual(issue.answerSquares, [checker])
        let focusedAdvice = CoachingTestFixtures.advice(
            state: state,
            tentativeMove: learnerMove,
            context: .tentativeMove(origin: .preexisting),
            opponentHasCapture: false,
            learnerHasCapture: false,
            assessments: [CoachingTestFixtures.acceptableAssessment(
                learnerMove,
                issues: [issue]
            )]
        )
        var session = CoachingSession(learner: .white)
        session.handle(.moveStaged(learnerMove))
        session.receive(focusedAdvice)

        session.handle(.actionChosen(.hint))
        session.handle(.actionChosen(.hint))

        XCTAssertEqual(session.presentation?.hint, .attackerRelationship)
        XCTAssertEqual(session.presentation?.focus.candidateSquares, [checker])
        XCTAssertTrue(session.presentation?.focus.paths.isEmpty == true)
    }

    func testWakePieceHintsRevealPurposeFilteredSourcesThenCandidateMoves() {
        var session = CoachingSession(learner: .white)
        session.receive(CoachingTestFixtures.startingPositionAdvice)

        session.handle(.actionChosen(.hint))

        XCTAssertEqual(session.hintLevel, 1)
        XCTAssertEqual(session.presentation?.hint, .candidatePieces)
        XCTAssertEqual(
            session.presentation?.focus.candidateSquares,
            [CoachingTestFixtures.openingKnight, CoachingTestFixtures.alternateKnight]
        )

        session.handle(.actionChosen(.hint))

        XCTAssertEqual(session.hintLevel, 2)
        XCTAssertEqual(
            session.presentation?.instruction,
            "Try one of the highlighted paths, then make the move yourself."
        )
        XCTAssertEqual(session.presentation?.hint, .candidateMoves)
        XCTAssertEqual(
            session.presentation?.focus.candidateSquares,
            [CoachingTestFixtures.openingKnightMove.to, CoachingTestFixtures.alternateKnightMove.to]
        )
        XCTAssertTrue(session.presentation?.focus.emphasizedSquares.isEmpty == true)
        XCTAssertEqual(session.presentation?.focus.paths, [
            CoachFocusPath(
                source: CoachingTestFixtures.openingKnight,
                destination: CoachingTestFixtures.openingKnightMove.to,
                role: .candidate
            ),
            CoachFocusPath(
                source: CoachingTestFixtures.alternateKnight,
                destination: CoachingTestFixtures.alternateKnightMove.to,
                role: .candidate
            ),
        ])
        XCTAssertFalse(session.presentation?.actions.map(\.action).contains(.hint) == true)
    }

    func testWakeHintsFilterCurrentPurposeWithoutRejectingOtherVerifiedSources() {
        var session = CoachingSession(learner: .white)
        session.receive(CoachingTestFixtures.mixedPurposeWakeAdvice)

        XCTAssertEqual(
            session.stage,
            .wakeChoosePiece(purpose: .openingDevelopment(firstMove: false))
        )

        session.handle(.actionChosen(.hint))

        XCTAssertEqual(session.presentation?.hint, .candidatePieces)
        XCTAssertEqual(
            session.presentation?.focus.candidateSquares,
            [CoachingTestFixtures.openingKnight]
        )

        session.handle(.actionChosen(.hint))

        XCTAssertEqual(session.presentation?.hint, .candidateMoves)
        XCTAssertEqual(
            session.presentation?.focus.candidateSquares,
            [CoachingTestFixtures.openingKnightMove.to]
        )
        XCTAssertEqual(session.presentation?.focus.paths, [CoachFocusPath(
            source: CoachingTestFixtures.openingKnight,
            destination: CoachingTestFixtures.openingKnightMove.to,
            role: .candidate
        )])

        XCTAssertEqual(
            session.handle(.squareTapped(CoachingTestFixtures.whiteQueen)),
            [.selectSquare(CoachingTestFixtures.whiteQueen)]
        )
        XCTAssertEqual(
            session.stage,
            .wakeChooseMove(
                piece: CoachingTestFixtures.whiteQueen,
                purpose: .addsDefender
            )
        )
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
            "You found it. Black could check your king, but your move still works. "
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
        XCTAssertEqual(
            session.presentation?.headline,
            "You found the check. There is still another danger after this move."
        )
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
        XCTAssertEqual(session.presentation?.headline, "Black has a reply to notice.")
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
            "That move is safe, but it doesn’t help with a clear plan yet."
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
        XCTAssertEqual(session.presentation?.headline, "The rook could still take your rook after that move.")
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

    func testRejectedTentativeMovesSuppressOriginHintsUntilTheBoardChanges() {
        let alternative = Move(
            from: CoachingTestFixtures.whiteRook,
            to: Square(file: .f, rank: 5)
        )

        let checkMove = CoachingTestFixtures.safeMove
        let illegal = CoachingMoveAssessment(
            move: checkMove,
            isLegal: false,
            resolvesRequiredDanger: false,
            opponentIssues: [],
            concepts: [],
            isAcceptable: false
        )
        var check = preparedSession(for: .check)
        check.handle(.moveStaged(checkMove))
        check.receive(CoachingTestFixtures.advice(
            tentativeMove: checkMove,
            context: .tentativeMove(origin: .check),
            opponentHasCapture: true,
            learnerHasCapture: false,
            assessments: [
                illegal,
                CoachingTestFixtures.acceptableAssessment(alternative),
            ]
        ))

        let capture = CoachingTestFixtures.profitableCapture
        var take = preparedSession(for: .take)
        take.handle(.moveStaged(capture))
        take.receive(CoachingTestFixtures.advice(
            tentativeMove: capture,
            context: .tentativeMove(origin: .take),
            opponentHasCapture: false,
            learnerHasCapture: true,
            take: CoachingTestFixtures.takeAdvice.takeOpportunities,
            assessments: [CoachingTestFixtures.acceptableAssessment(
                capture,
                concepts: [],
                isAcceptable: false
            )]
        ))

        let wakeMove = CoachingTestFixtures.openingKnightMove
        var wake = preparedSession(for: .wake)
        wake.handle(.moveStaged(wakeMove))
        wake.receive(CoachingTestFixtures.advice(
            state: .startingPosition(),
            tentativeMove: wakeMove,
            context: .tentativeMove(origin: .wake),
            opponentHasCapture: false,
            learnerHasCapture: false,
            wake: CoachingTestFixtures.startingPositionAdvice.wakeOpportunities,
            assessments: [CoachingTestFixtures.acceptableAssessment(
                wakeMove,
                concepts: [],
                isAcceptable: false
            )]
        ))

        for (name, session) in [("check", check), ("take", take), ("wake", wake)] {
            XCTAssertNil(session.presentation?.hint, name)
            XCTAssertFalse(
                session.presentation?.actions.map(\.action).contains(.hint) == true,
                name
            )
            XCTAssertTrue(session.presentation?.focus.candidateSquares.isEmpty == true, name)
            XCTAssertTrue(session.presentation?.focus.paths.isEmpty == true, name)
        }

        let checkHeadline = check.presentation?.headline
        check.handle(.positionChanged(revision: 8))
        XCTAssertEqual(check.stage, .checkResolve)
        XCTAssertEqual(check.presentation?.headline, checkHeadline)
        XCTAssertTrue(check.presentation?.actions.map(\.action).contains(.hint) == true)
        check.handle(.actionChosen(.hint))
        XCTAssertEqual(check.presentation?.hint, .candidatePieces)
        XCTAssertEqual(check.presentation?.focus.candidateSquares, [alternative.from])

        let takeHeadline = take.presentation?.headline
        take.handle(.positionChanged(revision: 8))
        XCTAssertEqual(take.stage, .takeChooseMove)
        XCTAssertEqual(take.presentation?.headline, takeHeadline)
        XCTAssertTrue(take.presentation?.actions.map(\.action).contains(.hint) == true)
        take.handle(.actionChosen(.hint))
        XCTAssertEqual(take.presentation?.hint, .candidatePieces)
        XCTAssertEqual(take.presentation?.focus.candidateSquares, [capture.from])

        let wakeHeadline = wake.presentation?.headline
        wake.handle(.positionChanged(revision: 8))
        XCTAssertEqual(
            wake.stage,
            .wakeChooseMove(
                piece: CoachingTestFixtures.openingKnight,
                purpose: .openingDevelopment(firstMove: true)
            )
        )
        XCTAssertEqual(wake.presentation?.headline, wakeHeadline)
        XCTAssertTrue(wake.presentation?.actions.map(\.action).contains(.hint) == true)
        wake.handle(.actionChosen(.hint))
        wake.handle(.actionChosen(.hint))
        XCTAssertEqual(wake.presentation?.hint, .candidateMoves)
        XCTAssertEqual(
            wake.presentation?.focus.candidateSquares,
            [CoachingTestFixtures.openingKnightMove.to]
        )
        XCTAssertEqual(wake.presentation?.focus.paths, [CoachFocusPath(
            source: CoachingTestFixtures.openingKnight,
            destination: CoachingTestFixtures.openingKnightMove.to,
            role: .candidate
        )])
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
            "That move is safe, but it doesn’t help with a clear plan yet."
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
        XCTAssertEqual(
            session.presentation?.actions.first { $0.action == .hint }?.prominence,
            .primary
        )
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

    func testRepeatedIllegalFallbackMovesPreserveZeroHintLevelAndCountMisses() {
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
            XCTAssertEqual(session.hintLevel, 0)
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

    func testSafeAttackerHintsRevealRelationshipThenCandidatesWithoutInventingPersistentPath() {
        var session = CoachingSession(learner: .white)
        session.receive(CoachingTestFixtures.multipleDangerAdvice)
        session.handle(.squareTapped(CoachingTestFixtures.whiteQueen))

        session.handle(.actionChosen(.hint))

        XCTAssertEqual(session.hintLevel, 1)
        XCTAssertEqual(session.presentation?.hint, .attackerRelationship)
        XCTAssertEqual(
            session.presentation?.focus.candidateSquares,
            [CoachingTestFixtures.blackBishop]
        )
        XCTAssertEqual(
            session.presentation?.focus.emphasizedSquares,
            [CoachingTestFixtures.whiteQueen]
        )
        XCTAssertEqual(session.presentation?.focus.paths, [CoachFocusPath(
            source: CoachingTestFixtures.blackBishop,
            destination: CoachingTestFixtures.whiteQueen,
            role: .attacker
        )])

        session.handle(.actionChosen(.hint))

        XCTAssertEqual(session.hintLevel, 2)
        XCTAssertEqual(session.presentation?.hint, .candidatePieces)
        XCTAssertEqual(session.presentation?.focus.paths, [])
        XCTAssertFalse(session.presentation?.actions.map(\.action).contains(.hint) == true)
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

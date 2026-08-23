import XCTest
@testable import ChessTutor

final class CoachingSessionTests: XCTestCase {
    private let advisor = LocalCoachingAdvisor()

    func testStartingPositionSkipsEmptyScansAndAsksConcreteOpeningQuestion() {
        var session = session()

        XCTAssertTrue(session.receive(CoachingTestFixtures.startingPositionAdvice).isEmpty)

        XCTAssertEqual(session.stage, .wakeChoosePiece(purpose: .openingDevelopment(firstMove: true)))
        XCTAssertEqual(session.presentation?.routine, [
            .safeCleared, .takeCleared, .wakeCurrent,
        ])
        XCTAssertEqual(
            session.presentation?.headline,
            "A center pawn or knight is a simple way to start. Which would you like to move?"
        )
        XCTAssertEqual(session.presentation?.boardTask, .move)
        XCTAssertTrue(session.presentation?.focus.candidateSquares.isEmpty == true)
    }

    func testRoutineIsHiddenOutsideSafeTakeWakeDecisionStages() {
        var session = session()
        let wakeMove = Move(
            from: CoachingTestFixtures.openingKnight,
            to: Square(file: .c, rank: 3)
        )
        session.receive(CoachingTestFixtures.startingPositionAdvice)
        XCTAssertEqual(session.presentation?.routine, [
            .safeCleared, .takeCleared, .wakeCurrent,
        ])

        session.handle(.interactionChanged(snapshot(
            selected: CoachingTestFixtures.openingKnight
        )))
        stage(wakeMove, in: &session)
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
        var check = session()
        check.receive(CoachingTestFixtures.advice(
            checking: [CoachingTestFixtures.blackBishop],
            opponentHasCapture: true,
            learnerHasCapture: false
        ))
        XCTAssertEqual(check.presentation?.routine, [])

        var fallback = session()
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
        var session = session()
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
        var session = session()
        session.receive(CoachingTestFixtures.multipleDangerAdvice)
        session.handle(.identificationTapped(CoachingTestFixtures.whiteQueen))

        XCTAssertEqual(
            session.presentation?.focus.emphasizedSquares,
            [CoachingTestFixtures.whiteQueen]
        )

        session.handle(.identificationTapped(CoachingTestFixtures.blackBishop))

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
        var check = session()
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

        var safe = session()
        safe.receive(CoachingTestFixtures.multipleDangerAdvice)
        safe.handle(.actionChosen(.hint))
        safe.handle(.actionChosen(.hint))

        var attacker = session()
        attacker.receive(CoachingTestFixtures.multipleDangerAdvice)
        attacker.handle(.identificationTapped(CoachingTestFixtures.whiteQueen))
        attacker.handle(.actionChosen(.hint))
        attacker.handle(.actionChosen(.hint))
        let safeAttackerHint = attacker.presentation?.hint

        var take = session()
        take.receive(CoachingTestFixtures.takeAdvice)
        take.handle(.actionChosen(.hint))

        var wake = session()
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

        check.handle(.identificationTapped(CoachingTestFixtures.blackBishop))
        check.handle(.actionChosen(.hint))
        check.handle(.actionChosen(.hint))

        var safeResolve = session()
        safeResolve.receive(CoachingTestFixtures.multipleDangerAdvice)
        safeResolve.handle(.identificationTapped(CoachingTestFixtures.whiteQueen))
        safeResolve.handle(.identificationTapped(CoachingTestFixtures.blackBishop))
        safeResolve.handle(.actionChosen(.hint))
        safeResolve.handle(.actionChosen(.hint))

        take.handle(.actionChosen(.hint))

        wake.handle(.actionChosen(.hint))

        var wakeMove = session()
        wakeMove.receive(CoachingTestFixtures.startingPositionAdvice)
        wakeMove.handle(.interactionChanged(snapshot(
            selected: CoachingTestFixtures.openingKnight
        )))
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

        var sourceSelectionHints = session()
        sourceSelectionHints.receive(CoachingTestFixtures.multipleDangerAdvice)
        sourceSelectionHints.handle(.actionChosen(.hint))
        sourceSelectionHints.handle(.actionChosen(.hint))
        let safeLocateHints = [
            sourceSelectionHints.presentation?.hint,
        ]

        sourceSelectionHints.handle(.identificationTapped(CoachingTestFixtures.whiteQueen))
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

    func testSafeTranscriptAcceptsPrimaryDangerThenItsAttacker() {
        var session = session()
        session.receive(CoachingTestFixtures.multipleDangerAdvice)

        let chosenTarget = CoachingTestFixtures.whiteQueen
        XCTAssertTrue(session.handle(.identificationTapped(chosenTarget)).isEmpty)
        XCTAssertEqual(session.stage, .safeIdentifyAttacker(target: chosenTarget))
        XCTAssertEqual(
            session.presentation?.headline,
            "You found the queen. What black piece is attacking it?"
        )

        let attacker = CoachingTestFixtures.blackBishop
        XCTAssertTrue(session.handle(.identificationTapped(attacker)).isEmpty)
        XCTAssertEqual(session.stage, .safeResolve(target: chosenTarget))
        XCTAssertEqual(
            session.presentation?.headline,
            "Yes—that bishop is attacking your queen. How could you help your queen?"
        )
        XCTAssertEqual(session.presentation?.instruction, "Make a move that gets it safe.")
        XCTAssertEqual(session.presentation?.boardTask, .move)
    }

    func testLowerPriorityDangerReturnsToSafeLocateWithConcreteLossComparison() async throws {
        let state = CoachingGoldenPosition.twoDangerPriorities.state
        let advice = try await advisor.advice(for: CoachingRequest(
            committedState: state,
            tentativeMove: nil,
            learner: .white,
            positionRevision: 7,
            context: .start
        ))
        var session = session()
        session.receive(advice)

        session.handle(.identificationTapped(sq("a3")))

        XCTAssertEqual(session.stage, .safeLocate)
        XCTAssertEqual(
            session.presentation?.response,
            "You found a threatened pawn. A knight is worth about three pawns, so losing the knight would cost more."
        )
        XCTAssertEqual(session.presentation?.headline, "Which piece should you help first?")
    }

    func testProtectedAttackAdvancesWithConcreteRecaptureFact() async throws {
        let state = CoachingGoldenPosition.protectedPawn.state
        let advice = try await advisor.advice(for: CoachingRequest(
            committedState: state,
            tentativeMove: nil,
            learner: .white,
            positionRevision: 7,
            context: .start
        ))
        var session = session()
        session.receive(advice)

        session.handle(.identificationTapped(sq("g4")))

        XCTAssertNotEqual(session.stage, .safeLocate)
        XCTAssertEqual(
            session.presentation?.response,
            "The pawn is attacked, but your other pawn protects it. If the knight takes it, your pawn can take the knight back. No piece needs help right now."
        )
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
            danger: CoachingTestFixtures.multipleDangerAdvice.dangerProblems + [
                CoachingDangerProblem(
                    target: pawn,
                    piece: Piece(kind: .pawn, color: .white),
                    pieceValue: 1,
                    captures: [pawnCapture],
                    worstEstimatedLoss: 1
                ),
            ]
        )
        let primaryPiece = advice.dangerProblems.first!.piece.kind

        var safePieceSession = session()
        safePieceSession.receive(CoachingTestFixtures.multipleDangerAdvice)
        safePieceSession.handle(.identificationTapped(Square(file: .a, rank: 2)))
        XCTAssertEqual(safePieceSession.presentation?.response, "That pawn is safe right now.")
        XCTAssertEqual(
            safePieceSession.presentation?.headline,
            "One of your pieces is in danger. Which one?"
        )

        var lowerPrioritySession = session()
        lowerPrioritySession.receive(advice)
        lowerPrioritySession.handle(.identificationTapped(pawn))
        XCTAssertEqual(
            lowerPrioritySession.presentation?.response,
            "You found a threatened pawn. Losing the \(primaryPiece.rawValue) would cost more."
        )

        var wrongColorSession = session()
        wrongColorSession.receive(CoachingTestFixtures.multipleDangerAdvice)
        wrongColorSession.handle(.identificationTapped(CoachingTestFixtures.blackBishop))
        XCTAssertEqual(wrongColorSession.presentation?.response, "Tap one of your pieces.")
        XCTAssertEqual(wrongColorSession.hintLevel, 0)
        XCTAssertEqual(wrongColorSession.missesAtCurrentLevel, 1)
        XCTAssertEqual(
            wrongColorSession.presentation?.actions.first { $0.action == .hint }?.prominence,
            .primary
        )

        var attackerSession = session()
        attackerSession.receive(CoachingTestFixtures.multipleDangerAdvice)
        attackerSession.handle(.identificationTapped(CoachingTestFixtures.whiteQueen))
        attackerSession.handle(.identificationTapped(CoachingTestFixtures.blackRook))
        XCTAssertEqual(attackerSession.presentation?.response, "That rook isn’t attacking your queen.")

        var blockedWakeSession = session()
        blockedWakeSession.receive(CoachingTestFixtures.startingPositionAdvice)
        blockedWakeSession.handle(.interactionChanged(snapshot(
            selected: Square(file: .a, rank: 1)
        )))
        XCTAssertEqual(
            blockedWakeSession.presentation?.response,
            "Your pawn is blocking that rook. Choose a center pawn or knight."
        )
        XCTAssertEqual(
            blockedWakeSession.presentation?.headline,
            "A center pawn or knight is a simple way to start. Which would you like to move?"
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
        replySession.handle(.identificationTapped(emptySquare))
        XCTAssertEqual(
            replySession.presentation?.response,
            "Tap a black piece that could check your king or take one of your pieces."
        )
    }

    func testHigherValueLowerLossDangerUsesActualLossForPriority() {
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
            danger: [
                CoachingDangerProblem(
                    target: CoachingTestFixtures.openingKnight,
                    piece: Piece(kind: .knight, color: .white),
                    pieceValue: 3,
                    captures: [knightCapture],
                    worstEstimatedLoss: 2
                ),
                CoachingDangerProblem(
                    target: CoachingTestFixtures.whiteQueen,
                    piece: Piece(kind: .queen, color: .white),
                    pieceValue: 9,
                    captures: [queenCapture],
                    worstEstimatedLoss: 1
                ),
            ]
        )
        var session = session()

        session.receive(advice)
        session.handle(.identificationTapped(CoachingTestFixtures.whiteQueen))

        XCTAssertEqual(
            session.presentation?.response,
            "You found a threatened queen. Losing the knight would cost more."
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
        let queenProblem = try XCTUnwrap(startAdvice.dangerProblems.first { $0.target == queen })
        let queenAttacker = try XCTUnwrap(queenProblem.captures.first?.move.from)
        XCTAssertTrue(startAdvice.dangerProblems.contains { $0.target == rook })

        var session = session()
        session.receive(startAdvice)
        session.handle(.identificationTapped(queen))
        session.handle(.identificationTapped(queenAttacker))
        XCTAssertEqual(session.stage, .safeResolve(target: queen))
        session.handle(.actionChosen(.hint))
        session.handle(.actionChosen(.hint))
        XCTAssertEqual(
            stage(queenEscape, in: &session, revision: 1),
            [.requestAdvice(context: .tentativeMove(origin: .safe))]
        )

        let moveAdvice = try await advisor.advice(for: CoachingRequest(
            committedState: state,
            tentativeMove: queenEscape,
            learner: .white,
            positionRevision: 1,
            context: .tentativeMove(origin: .safe)
        ))
        let assessment = try XCTUnwrap(moveAdvice.moveAssessments[queenEscape])
        XCTAssertFalse(assessment.resolvesRequiredDanger)
        XCTAssertTrue(assessment.opponentIssues.contains { issue in
            issue.reply.from == blackRook && issue.affectedSquare == rook
        })

        session.receive(moveAdvice)

        XCTAssertEqual(session.stage, .safeResolve(target: queen))
        XCTAssertEqual(
            session.presentation?.response,
            "The rook could still take your rook after that move."
        )
        XCTAssertEqual(
            session.presentation?.headline,
            "Yes—that bishop is attacking your queen. How could you help your queen?"
        )
        XCTAssertNil(session.presentation?.hint)
        XCTAssertTrue(session.presentation?.focus.emphasizedSquares.isEmpty == true)
        XCTAssertTrue(session.presentation?.focus.candidateSquares.isEmpty == true)
        XCTAssertTrue(session.presentation?.focus.paths.isEmpty == true)
        XCTAssertFalse(session.presentation?.actions.map(\.action).contains(.hint) == true)

        session.handle(.interactionChanged(snapshot(revision: 1)))

        XCTAssertEqual(session.stage, .safeResolve(target: queen))
        XCTAssertEqual(
            session.presentation?.headline,
            "Yes—that bishop is attacking your queen. How could you help your queen?"
        )
        XCTAssertEqual(session.presentation?.hint, .candidateMoves)
        XCTAssertEqual(session.presentation?.focus.emphasizedSquares, [queen, queenAttacker])
        XCTAssertFalse(session.presentation?.focus.candidateSquares.isEmpty == true)
        XCTAssertTrue(session.presentation?.focus.paths.contains(CoachFocusPath(
            source: queenAttacker,
            destination: queen,
            role: .attacker
        )) == true)
    }

    func testChangedOnePointDangerNamesTheNewPawnAndAttacker() async throws {
        let target = sq("a3")
        let originalAttacker = sq("b4")
        let newlyExposedPawn = sq("a2")
        let newAttacker = sq("a8")
        let move = Move(from: target, to: sq("c4"))
        let state = CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                sq("h1"): Piece(kind: .king, color: .white),
                target: Piece(kind: .knight, color: .white),
                newlyExposedPawn: Piece(kind: .pawn, color: .white),
                sq("b1"): Piece(kind: .rook, color: .white),
                originalAttacker: Piece(kind: .bishop, color: .black),
                newAttacker: Piece(kind: .rook, color: .black),
                sq("h8"): Piece(kind: .king, color: .black),
            ]
        )
        let startAdvice = try await advisor.advice(for: CoachingRequest(
            committedState: state,
            tentativeMove: nil,
            learner: .white,
            positionRevision: 7,
            context: .start
        ))
        let problem = try XCTUnwrap(startAdvice.dangerProblems.first { $0.target == target })
        XCTAssertTrue(problem.captures.contains { $0.move.from == originalAttacker })

        var session = session()
        session.receive(startAdvice)
        session.handle(.identificationTapped(target))
        session.handle(.identificationTapped(originalAttacker))
        XCTAssertEqual(session.stage, .safeResolve(target: target))
        XCTAssertEqual(
            stage(move, in: &session),
            [.requestAdvice(context: .tentativeMove(origin: .safe))]
        )

        let moveAdvice = try await advisor.advice(for: CoachingRequest(
            committedState: state,
            tentativeMove: move,
            learner: .white,
            positionRevision: 7,
            context: .tentativeMove(origin: .safe)
        ))
        let assessment = try XCTUnwrap(moveAdvice.moveAssessments[move])
        XCTAssertFalse(assessment.resolvesRequiredDanger)
        XCTAssertTrue(assessment.opponentIssues.contains { issue in
            issue.reply.from == newAttacker
                && issue.kind == .materialLoss(points: 1)
                && issue.answerSquares == [newAttacker]
                && issue.affectedSquare == newlyExposedPawn
        })

        session.receive(moveAdvice)

        XCTAssertEqual(session.stage, .safeResolve(target: target))
        XCTAssertEqual(
            session.presentation?.response,
            "The rook could still take your pawn after that move."
        )
    }

    func testCheckAndDoubleCheckAcceptEveryCheckingPieceWithoutSelectingIt() {
        for checkingPiece in [CoachingTestFixtures.blackBishop, CoachingTestFixtures.blackRook] {
            var session = session()
            let advice = CoachingTestFixtures.advice(
                checking: [CoachingTestFixtures.blackBishop, CoachingTestFixtures.blackRook],
                opponentHasCapture: true,
                learnerHasCapture: false
            )
            session.receive(advice)

            XCTAssertEqual(session.stage, .checkLocate)
            XCTAssertEqual(session.presentation?.routine, [])
            XCTAssertTrue(session.handle(.identificationTapped(checkingPiece)).isEmpty)
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
                        && $0.affectedSquare == looseBishop
                }
        })
        let evasion = assessment.move
        let materialIssue = try XCTUnwrap(assessment.opponentIssues.first {
            $0.kind == .materialLoss(points: 3) && $0.severity == .reviseMove
        })
        XCTAssertTrue(allLegalEvasions.contains(evasion))
        XCTAssertEqual(materialIssue.affectedSquare, looseBishop)

        var session = session()
        session.receive(startAdvice)
        session.handle(.identificationTapped(checkingRook))
        session.handle(.actionChosen(.hint))
        session.handle(.actionChosen(.hint))
        XCTAssertEqual(
            session.presentation?.focus.candidateSquares,
            Set(allLegalEvasions.map(\.to))
        )

        XCTAssertEqual(
            stage(evasion, in: &session, revision: 1),
            [.requestAdvice(context: .tentativeMove(origin: .check))]
        )
        let moveAdvice = try await advisor.advice(for: CoachingRequest(
            committedState: state,
            tentativeMove: evasion,
            learner: .white,
            positionRevision: 1,
            context: .tentativeMove(origin: .check)
        ))
        session.receive(moveAdvice)

        XCTAssertEqual(session.stage, .opponentCheck(move: evasion, origin: .check))
        XCTAssertFalse(session.presentation?.headline.contains("king would still need help") == true)
        XCTAssertTrue(session.handle(.identificationTapped(looseBishop)).isEmpty)
        XCTAssertEqual(session.stage, .opponentCheck(move: evasion, origin: .check))
        XCTAssertEqual(
            session.presentation?.response,
            "Tap a black piece that could check your king or take one of your pieces."
        )

        XCTAssertTrue(session.handle(.identificationTapped(materialAttacker)).isEmpty)
        XCTAssertEqual(session.stage, .reviseMove(origin: .check))
        XCTAssertEqual(session.presentation?.response, "Black’s rook could take your bishop.")
        XCTAssertEqual(
            session.presentation?.headline,
            "How can you change your move so the bishop is safe?"
        )
        XCTAssertEqual(
            session.presentation?.instruction,
            "Change your move so the bishop is safe."
        )
    }

    func testNontrivialSafeOffersOnlyValidAbsenceClaim() {
        var clearSession = session()
        clearSession.receive(CoachingTestFixtures.nontrivialSafeClearAdvice)
        XCTAssertEqual(clearSession.stage, .safeLocate)
        clearSession.handle(.actionChosen(.noAnswer))
        XCTAssertEqual(clearSession.stage, .fallbackChooseMove)
        XCTAssertEqual(
            clearSession.presentation?.response,
            "Right—no piece needs help right now."
        )
        XCTAssertEqual(
            clearSession.presentation?.headline,
            "Choose a move you are considering, and I will check it with you."
        )
        XCTAssertEqual(clearSession.presentation?.instruction, "Make a move on the board.")
        XCTAssertEqual(clearSession.presentation?.routine, [])

        var dangerSession = session()
        dangerSession.receive(CoachingTestFixtures.multipleDangerAdvice)
        let presentation = dangerSession.presentation
        XCTAssertFalse(
            dangerSession.presentation?.actions.map(\.action).contains(.noAnswer) == true
        )

        dangerSession.handle(.actionChosen(.noAnswer))

        XCTAssertEqual(dangerSession.stage, .safeLocate)
        XCTAssertEqual(dangerSession.presentation, presentation)
        XCTAssertEqual(dangerSession.missesAtCurrentLevel, 0)
    }

    func testSafeRejectsUnrelatedTapAndResolutionThatLeavesDanger() {
        var session = session()
        session.receive(CoachingTestFixtures.multipleDangerAdvice)
        session.handle(.identificationTapped(CoachingTestFixtures.whiteQueen))
        session.handle(.identificationTapped(CoachingTestFixtures.blackBishop))

        XCTAssertEqual(
            stage(CoachingTestFixtures.safeMove, in: &session),
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
            danger: CoachingTestFixtures.multipleDangerAdvice.dangerProblems
        ))

        XCTAssertEqual(session.stage, .safeResolve(target: CoachingTestFixtures.whiteQueen))
        XCTAssertEqual(
            session.presentation?.response,
            "The bishop could still take your queen after that move."
        )
        XCTAssertEqual(
            session.presentation?.headline,
            "Yes—that bishop is attacking your queen. How could you help your queen?"
        )
    }

    func testTakeRequiresCorrectAbsenceAndStagesCapturesForAdvice() {
        var emptySession = session()
        emptySession.receive(CoachingTestFixtures.nontrivialTakeClearAdvice)
        XCTAssertEqual(emptySession.stage, .takeChooseMove)
        emptySession.handle(.actionChosen(.noAnswer))
        XCTAssertEqual(emptySession.stage, .fallbackChooseMove)
        XCTAssertEqual(
            emptySession.presentation?.response,
            "Right—there is no safe capture here."
        )
        XCTAssertEqual(
            emptySession.presentation?.headline,
            "I can check immediate dangers, but I do not have a confident plan for this position yet."
        )

        var takeSession = session()
        takeSession.receive(CoachingTestFixtures.takeAdvice)
        takeSession.handle(.actionChosen(.noAnswer))
        XCTAssertEqual(takeSession.presentation?.response, "There is a safe capture to find.")
        XCTAssertEqual(
            takeSession.presentation?.headline,
            "Can one of your pieces safely take a black piece?"
        )
        XCTAssertEqual(
            stage(CoachingTestFixtures.profitableCapture, in: &takeSession),
            [.requestAdvice(context: .tentativeMove(origin: .take))]
        )
    }

    func testTakeAbsenceUsesCaptureSpecificResponse() {
        var session = session()
        session.receive(CoachingTestFixtures.nontrivialTakeClearAdvice)

        session.handle(.actionChosen(.noAnswer))

        XCTAssertEqual(
            session.presentation?.response,
            "Right—there is no safe capture here."
        )
    }

    func testNonCaptureMateDoesNotOpenTheSafeCaptureQuestion() {
        let mate = Move(
            from: CoachingTestFixtures.whiteQueen,
            to: Square(file: .h, rank: 4)
        )
        let advice = CoachingTestFixtures.advice(
            opponentHasCapture: false,
            learnerHasCapture: false,
            mateInOne: [mate]
        )
        var session = session()

        session.receive(advice)

        XCTAssertEqual(session.stage, .fallbackChooseMove)
        XCTAssertEqual(session.presentation?.routine, [])
    }

    func testTakeRejectsZeroGainCaptureOutsideActiveSafeCaptureOpportunities() {
        let capture = Move(
            from: CoachingTestFixtures.whiteRook,
            to: CoachingTestFixtures.blackRook
        )
        let recapture = Move(
            from: CoachingTestFixtures.blackKing,
            to: CoachingTestFixtures.blackRook
        )
        let estimate = CoachingTestFixtures.capture(
            move: capture,
            captured: Piece(kind: .rook, color: .black),
            capturedSquare: capture.to,
            recapture: recapture,
            net: 0
        )
        var session = preparedSession(for: .take)
        stage(capture, in: &session)

        session.receive(CoachingTestFixtures.adviceForTentativeMove(
            capture,
            origin: .take,
            assessment: CoachingTestFixtures.acceptableAssessment(
                capture,
                concepts: [.captureResolvesDanger]
            ),
            learnerCaptures: [estimate]
        ))

        XCTAssertEqual(session.stage, .takeChooseMove)
        XCTAssertEqual(
            session.presentation?.response,
            "Black’s king could take your rook. You would lose a rook to take one rook."
        )
        XCTAssertEqual(
            session.presentation?.headline,
            "Can one of your pieces safely take a black piece?"
        )
    }

    func testTakeRejectsNonCaptureMateOutsideActiveSafeCaptureOpportunities() {
        let mate = CoachingTestFixtures.safeMove
        var session = preparedSession(for: .take)
        stage(mate, in: &session)

        session.receive(CoachingTestFixtures.adviceForTentativeMove(
            mate,
            origin: .take,
            assessment: CoachingTestFixtures.acceptableAssessment(
                mate,
                concepts: [.mateInOne]
            )
        ))

        XCTAssertEqual(session.stage, .takeChooseMove)
        XCTAssertEqual(
            session.presentation?.response,
            "That piece has no safe capture here."
        )
        XCTAssertEqual(
            session.presentation?.headline,
            "Can one of your pieces safely take a black piece?"
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
        var session = session()
        session.receive(CoachingTestFixtures.takeAdvice)
        stage(capture, in: &session)

        session.receive(CoachingTestFixtures.adviceForTentativeMove(
            capture,
            origin: .take,
            assessment: assessment,
            learnerCaptures: [estimate]
        ))

        XCTAssertEqual(session.stage, .takeChooseMove)
        XCTAssertEqual(
            session.presentation?.response,
            "Black’s king could take your queen. You would lose a queen to take one rook."
        )
        XCTAssertEqual(
            session.presentation?.headline,
            "Can one of your pieces safely take a black piece?"
        )
    }

    func testRealLosingCaptureExplainsKingRecaptureThenAcceptsNoSafeCapture() async throws {
        let state = CoachingGoldenPosition.losingCapture.state
        let move = CoachingGoldenMoves.bishopTakesPawn
        let advisor = LocalCoachingAdvisor()
        let initial = CoachingInteractionSnapshot(
            selectedSquare: nil,
            tentativeMove: nil,
            positionRevision: 1
        )
        var session = CoachingSession(
            learner: .white,
            interaction: initial,
            initialContext: .start
        )
        session.receive(try await advisor.advice(for: CoachingRequest(
            committedState: state,
            tentativeMove: nil,
            learner: .white,
            positionRevision: 1,
            context: .start
        )), interaction: initial)

        let tentative = CoachingInteractionSnapshot(
            selectedSquare: move.to,
            tentativeMove: move,
            positionRevision: 1
        )
        session.handle(.interactionChanged(tentative))
        session.receive(try await advisor.advice(for: CoachingRequest(
            committedState: state,
            tentativeMove: move,
            learner: .white,
            positionRevision: 1,
            context: .tentativeMove(origin: .take)
        )), interaction: tentative)

        XCTAssertEqual(
            session.presentation?.response,
            "Black’s king could take your bishop. You would lose a bishop to take one pawn."
        )

        session.handle(.interactionChanged(initial))
        session.handle(.actionChosen(.noAnswer))

        XCTAssertEqual(session.presentation?.response, "Right—there is no safe capture here.")
        XCTAssertEqual(
            session.presentation?.headline,
            "I can check immediate dangers, but I do not have a confident plan for this position yet."
        )
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
        var session = session()
        session.receive(CoachingTestFixtures.takeAdvice)
        session.handle(.actionChosen(.hint))

        for expectedMisses in 1...2 {
            stage(move, in: &session)
            session.receive(advice)
            XCTAssertEqual(session.stage, .takeChooseMove)
            XCTAssertEqual(session.hintLevel, 1)
            XCTAssertEqual(session.missesAtCurrentLevel, expectedMisses)
            if expectedMisses < 2 {
                session.handle(.interactionChanged(snapshot()))
            }
        }
        XCTAssertFalse(session.presentation?.instruction?.contains("Want a hint?") == true)
        XCTAssertFalse(session.presentation?.actions.map(\.action).contains(.hint) == true)
    }

    func testEveryWakeSourceAlternativeProjectsExactlyThatPiece() {
        for source in [CoachingTestFixtures.openingKnight, CoachingTestFixtures.alternateKnight] {
            var session = session()
            session.receive(CoachingTestFixtures.startingPositionAdvice)

            XCTAssertTrue(session.handle(.interactionChanged(snapshot(selected: source))).isEmpty)
            XCTAssertEqual(
                session.stage,
                .wakeChooseMove(piece: source, purpose: .openingDevelopment(firstMove: true))
            )
            XCTAssertEqual(session.presentation?.boardTask, .move)
        }
    }

    func testWakeAcceptsEveryQualifyingMoveAndRejectsMoveWithoutWakePurpose() {
        for move in [CoachingTestFixtures.openingKnightMove, CoachingTestFixtures.alternateKnightMove] {
            var session = session()
            session.receive(CoachingTestFixtures.startingPositionAdvice)
            session.handle(.interactionChanged(snapshot(selected: move.from)))
            stage(move, in: &session)
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

        var rejected = session()
        rejected.receive(CoachingTestFixtures.startingPositionAdvice)
        rejected.handle(.interactionChanged(snapshot(
            selected: CoachingTestFixtures.openingKnight
        )))
        stage(CoachingTestFixtures.openingKnightMove, in: &rejected)
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
            rejected.presentation?.response,
            "That move is safe, but it doesn’t bring a new piece into the game."
        )
        XCTAssertEqual(rejected.presentation?.headline, "You can develop this knight.")
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
        var session = session()
        session.receive(CoachingTestFixtures.startingPositionAdvice)
        session.handle(.interactionChanged(snapshot(
            selected: CoachingTestFixtures.openingKnight
        )))
        session.handle(.actionChosen(.hint))

        for expectedMisses in 1...2 {
            stage(move, in: &session)
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
            if expectedMisses < 2 {
                session.handle(.interactionChanged(snapshot(
                    selected: move.from
                )))
            }
        }
        XCTAssertFalse(session.presentation?.instruction?.contains("Want a hint?") == true)
        XCTAssertFalse(session.presentation?.actions.map(\.action).contains(.hint) == true)
    }

    func testUnsupportedAdviceAndExplicitUnsupportedPositionStateTheirBoundary() {
        var fromAdvice = session()
        fromAdvice.receive(CoachingTestFixtures.fallbackAdvice)
        XCTAssertEqual(fromAdvice.stage, .fallbackChooseMove)
        XCTAssertEqual(fromAdvice.presentation?.routine, [])

        var explicit = session()
        explicit.receiveUnsupportedPosition(
            for: .start,
            interaction: snapshot()
        )
        XCTAssertEqual(explicit.stage, .fallbackChooseMove)
        XCTAssertEqual(
            explicit.presentation?.headline,
            "I can check immediate dangers, but I do not have a confident plan for this position yet."
        )
        XCTAssertEqual(explicit.presentation?.routine, [])
    }

    func testFallbackDoesNotOfferHintsWithoutFactualFocus() {
        var session = session()
        session.receiveUnsupportedPosition(
            for: .start,
            interaction: snapshot()
        )

        session.handle(.actionChosen(.hint))
        session.handle(.actionChosen(.hint))

        XCTAssertEqual(session.hintLevel, 0)
        XCTAssertEqual(
            session.presentation?.instruction,
            "Choose a move you are considering, and I will check it with you."
        )
        XCTAssertEqual(session.presentation?.focus, .empty)
        XCTAssertFalse(session.presentation?.actions.map(\.action).contains(.hint) == true)
    }

    func testFallbackStillDoesNotOfferHintsAfterTentativeMoveRemoval() {
        var session = session()
        session.receive(CoachingTestFixtures.fallbackAdvice)
        stage(CoachingTestFixtures.fallbackMove, in: &session)
        session.handle(.interactionChanged(snapshot()))
        XCTAssertEqual(session.stage, .fallbackChooseMove)

        session.handle(.actionChosen(.hint))
        session.handle(.actionChosen(.hint))

        XCTAssertEqual(session.hintLevel, 0)
        XCTAssertEqual(
            session.presentation?.instruction,
            "Choose a move you are considering, and I will check it with you."
        )
        XCTAssertTrue(session.presentation?.focus.candidateSquares.isEmpty == true)
        XCTAssertTrue(session.presentation?.focus.emphasizedSquares.isEmpty == true)
        XCTAssertTrue(session.presentation?.focus.paths.isEmpty == true)
        XCTAssertFalse(session.presentation?.actions.map(\.action).contains(.hint) == true)
    }

    func testCheckLocateHintsCapAtSuppliedCandidateSquares() {
        let checker = CoachingTestFixtures.blackRook
        var session = session()
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
        var session = session()
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
            [CoachingTestFixtures.whiteQueen]
        )
        XCTAssertTrue(session.presentation?.focus.emphasizedSquares.isEmpty == true)
        XCTAssertTrue(session.presentation?.focus.paths.isEmpty == true)
        XCTAssertFalse(session.presentation?.actions.map(\.action).contains(.hint) == true)
    }

    func testSafeLocateWithoutADangerProblemOffersNoHint() {
        var session = session()
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
        let danger = CoachingDangerProblem(
            target: blackKnight,
            piece: Piece(kind: .knight, color: .black),
            pieceValue: 3,
            captures: [capture],
            worstEstimatedLoss: 3
        )
        var safeSession = session(learner: .black)
        safeSession.receive(CoachingTestFixtures.advice(
            state: state,
            learner: .black,
            opponentHasCapture: true,
            learnerHasCapture: false,
            opponentCaptures: [capture],
            danger: [danger]
        ))

        safeSession.handle(.identificationTapped(blackKnight))

        XCTAssertEqual(
            safeSession.presentation?.headline,
            "You found the knight. What white piece is attacking it?"
        )
        XCTAssertEqual(safeSession.presentation?.instruction, "Tap the white piece.")

        var replySession = session(learner: .black)
        stage(blackMove, in: &replySession)
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
            "Tap a white piece that could check your king or take one of your pieces. Otherwise choose Looks safe."
        )
    }

    func testOpponentMaterialHintShowsSourceLandingAndDistinctEnPassantTarget() {
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
        var session = session()
        stage(learnerMove, in: &session)
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

        XCTAssertEqual(session.presentation?.hint, .attackerRelationship)
        XCTAssertEqual(session.presentation?.focus.candidateSquares, [blackPawn])
        XCTAssertEqual(session.presentation?.focus.paths, [
            CoachFocusPath(
                source: blackPawn,
                destination: reply.to,
                role: .attacker
            ),
            CoachFocusPath(
                source: reply.to,
                destination: capturedPawn,
                role: .attacker
            ),
        ])
    }

    func testCastlingCheckHintUsesOpponentMoveSourceAndDestination() async throws {
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
        XCTAssertEqual(issue.answerSquares, [king])
        XCTAssertEqual(issue.checkingSquares, [rook])
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
        var session = session()
        stage(learnerMove, in: &session)
        session.receive(focusedAdvice)

        session.handle(.actionChosen(.hint))

        XCTAssertEqual(session.presentation?.hint, .attackerRelationship)
        XCTAssertEqual(session.presentation?.focus.candidateSquares, [king])
        XCTAssertEqual(session.presentation?.focus.paths, [CoachFocusPath(
            source: king,
            destination: reply.to,
            role: .attacker
        )])
    }

    func testDiscoveredCheckHintUsesOpponentMoveSourceAndDestination() async throws {
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
        XCTAssertEqual(issue.answerSquares, [blocker])
        XCTAssertEqual(issue.checkingSquares, [checker])
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
        var session = session()
        stage(learnerMove, in: &session)
        session.receive(focusedAdvice)

        session.handle(.actionChosen(.hint))

        XCTAssertEqual(session.presentation?.hint, .attackerRelationship)
        XCTAssertEqual(session.presentation?.focus.candidateSquares, [blocker])
        XCTAssertEqual(session.presentation?.focus.paths, [CoachFocusPath(
            source: blocker,
            destination: reply.to,
            role: .attacker
        )])
    }

    func testWakePieceHintsRevealPurposeFilteredSourcesThenCandidateMoves() {
        var session = session()
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
        var session = session()
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

        XCTAssertTrue(session.handle(.interactionChanged(snapshot(
            selected: CoachingTestFixtures.whiteQueen
        ))).isEmpty)
        XCTAssertEqual(
            session.stage,
            .wakeChooseMove(
                piece: CoachingTestFixtures.whiteQueen,
                purpose: .addsDefender
            )
        )
    }

    func testReviseIssueAcceptsOnlyOpponentSourceAndNeverSelectsIt() {
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

        XCTAssertTrue(session.handle(.identificationTapped(move.to)).isEmpty)
        XCTAssertEqual(session.stage, .opponentCheck(move: move, origin: .fallback))
        XCTAssertEqual(
            session.presentation?.response,
            "Tap a black piece that could check your king or take one of your pieces."
        )

        XCTAssertTrue(session.handle(.identificationTapped(reply.from)).isEmpty)
        XCTAssertEqual(session.stage, .reviseMove(origin: .fallback))
        XCTAssertEqual(session.presentation?.boardTask, .move)
        XCTAssertEqual(session.presentation?.response, "Black’s rook could take your pawn.")
        XCTAssertEqual(
            session.presentation?.headline,
            "How can you change your move so the pawn is safe?"
        )
        XCTAssertEqual(
            session.presentation?.instruction,
            "Change your move so the pawn is safe."
        )
        XCTAssertEqual(session.presentation?.actions.map(\.action), [.hint, .stop])
    }

    func testReviseIssueWinsWhenTappedSquareAlsoMatchesNoticeIssue() {
        let move = CoachingTestFixtures.openingKnightMove
        let reply = Move(
            from: Square(file: .c, rank: 8),
            to: move.to
        )
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

        XCTAssertTrue(session.handle(.identificationTapped(sharedAnswer)).isEmpty)
        XCTAssertEqual(session.stage, .reviseMove(origin: .wake))
        XCTAssertEqual(session.presentation?.response, "Black’s bishop could take your knight.")
        XCTAssertEqual(
            session.presentation?.headline,
            "How can you change your move so the knight is safe?"
        )
        XCTAssertEqual(
            session.presentation?.instruction,
            "Change your move so the knight is safe."
        )
    }

    func testHarmlessCheckCanBeFoundAndCompletesAnAcceptableMove() {
        let move = CoachingTestFixtures.openingKnightMove
        let reply = Move(
            from: Square(file: .c, rank: 8),
            to: CoachingTestFixtures.whiteKing
        )
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

        XCTAssertTrue(session.handle(.identificationTapped(reply.from)).isEmpty)
        XCTAssertEqual(
            session.stage,
            .complete(move: move, origin: .wake, concepts: [.developsKnightOrBishop])
        )
        XCTAssertEqual(
            session.presentation?.response,
            "That bishop could check your king. You could answer the check, so your knight move still works."
        )
        XCTAssertEqual(
            session.presentation?.headline,
            "That works. You developed your knight."
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

        var session = session()
        stage(move, in: &session)
        session.receive(advice)
        XCTAssertEqual(session.stage, .opponentCheck(move: move, origin: .preexisting))

        XCTAssertTrue(session.handle(.identificationTapped(harmlessChecker)).isEmpty)
        XCTAssertEqual(session.stage, .opponentCheck(move: move, origin: .preexisting))
        XCTAssertEqual(
            session.presentation?.response,
            "You found the check. There is still another danger after this move."
        )
        XCTAssertFalse(session.presentation?.response?.contains("move still works") == true)
        XCTAssertEqual(
            session.presentation?.headline,
            "What could Black do after your move?"
        )

        XCTAssertTrue(session.handle(.identificationTapped(looseQueen)).isEmpty)
        XCTAssertEqual(
            session.presentation?.response,
            "Tap a black piece that could check your king or take one of your pieces."
        )
        XCTAssertEqual(session.stage, .opponentCheck(move: move, origin: .preexisting))

        XCTAssertTrue(session.handle(.identificationTapped(materialAttacker)).isEmpty)
        XCTAssertEqual(session.stage, .reviseMove(origin: .preexisting))
        XCTAssertEqual(session.presentation?.response, "Black’s bishop could take your queen.")
        XCTAssertEqual(
            session.presentation?.headline,
            "How can you change your move so the queen is safe?"
        )
        XCTAssertEqual(
            session.presentation?.instruction,
            "Change your move so the queen is safe."
        )
    }

    func testNoticeLevelBestCaseMaterialLossCanBeFoundAndAccepted() {
        let move = CoachingTestFixtures.openingKnightMove
        let reply = Move(
            from: Square(file: .c, rank: 8),
            to: move.to
        )
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

        XCTAssertTrue(session.handle(.identificationTapped(reply.from)).isEmpty)
        XCTAssertEqual(
            session.stage,
            .complete(move: move, origin: .wake, concepts: [.developsKnightOrBishop])
        )
        XCTAssertEqual(
            session.presentation?.response,
            "Black’s bishop could take your knight."
        )
        XCTAssertEqual(
            session.presentation?.headline,
            "That works. You developed your knight."
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
        XCTAssertEqual(session.presentation?.response, "Black’s rook could take your pawn.")
        XCTAssertEqual(
            session.presentation?.headline,
            "What could Black do after your move?"
        )
        XCTAssertEqual(session.missesAtCurrentLevel, 1)
        XCTAssertEqual(session.presentation?.actions.map(\.action), [.hint, .stop])
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
            "That works. You developed your knight."
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
            session.presentation?.response,
            "That move is safe, but I cannot name a verified purpose for it."
        )
        XCTAssertEqual(
            session.presentation?.headline,
            "I can check immediate dangers, but I do not have a confident plan for this position yet."
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

        XCTAssertTrue(session.handle(.interactionChanged(snapshot())).isEmpty)
        XCTAssertEqual(
            session.stage,
            .safeResolve(target: CoachingTestFixtures.whiteQueen)
        )
        XCTAssertEqual(
            stage(move, in: &session),
            [.requestAdvice(context: .tentativeMove(origin: .safe))]
        )
    }

    func testRemovingMoveWhileAdviceIsPendingPreservesOriginForReplacement() {
        var session = session()
        session.receive(CoachingTestFixtures.takeAdvice)
        stage(CoachingTestFixtures.profitableCapture, in: &session)

        XCTAssertTrue(session.handle(.interactionChanged(snapshot())).isEmpty)
        XCTAssertEqual(session.stage, .takeChooseMove)
        XCTAssertEqual(
            stage(CoachingTestFixtures.profitableCapture, in: &session),
            [.requestAdvice(context: .tentativeMove(origin: .take))]
        )
    }

    func testSafeSubjectSurvivesMoveRevisionAndReplacementAdvice() {
        let move = CoachingTestFixtures.safeMove
        var session = session()
        session.receive(CoachingTestFixtures.multipleDangerAdvice)
        session.handle(.identificationTapped(CoachingTestFixtures.whiteQueen))
        session.handle(.identificationTapped(CoachingTestFixtures.blackBishop))
        stage(move, in: &session)
        session.receive(CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: .safe,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                concepts: [.pieceNeedsHelp]
            ),
            danger: CoachingTestFixtures.multipleDangerAdvice.dangerProblems
        ))
        session.handle(.interactionChanged(snapshot()))
        session.handle(.interactionChanged(snapshot(selected: move.from)))
        stage(move, in: &session)

        session.receive(CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: .safe,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                resolvesRequiredDanger: false,
                isAcceptable: false
            ),
            danger: CoachingTestFixtures.multipleDangerAdvice.dangerProblems
        ))

        XCTAssertEqual(
            session.stage,
            .safeResolve(target: CoachingTestFixtures.whiteQueen)
        )
        XCTAssertEqual(
            session.presentation?.response,
            "The bishop could still take your queen after that move."
        )
        XCTAssertEqual(
            session.presentation?.headline,
            "Yes—that bishop is attacking your queen. How could you help your queen?"
        )
    }

    func testWakeSubjectSurvivesMoveRevisionAndReplacementAdvice() {
        let move = CoachingTestFixtures.alternateKnightMove
        var session = session()
        session.receive(CoachingTestFixtures.startingPositionAdvice)
        session.handle(.interactionChanged(snapshot(
            selected: CoachingTestFixtures.alternateKnight
        )))
        stage(move, in: &session)
        session.receive(CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: .wake,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                concepts: [.developsKnightOrBishop]
            )
        ))
        session.handle(.interactionChanged(snapshot()))
        session.handle(.interactionChanged(snapshot(selected: move.from)))
        stage(move, in: &session)

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
        stage(checkMove, in: &check)
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
        stage(capture, in: &take)
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
        stage(wakeMove, in: &wake)
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

        check.handle(.interactionChanged(snapshot()))
        XCTAssertEqual(check.stage, .checkResolve)
        XCTAssertEqual(
            check.presentation?.headline,
            "Make a move that gets your king safe."
        )
        XCTAssertFalse(check.presentation?.actions.map(\.action).contains(.hint) == true)
        check.handle(.actionChosen(.hint))
        XCTAssertNil(check.presentation?.hint)
        XCTAssertTrue(check.presentation?.focus.candidateSquares.isEmpty == true)

        take.handle(.interactionChanged(snapshot()))
        XCTAssertEqual(take.stage, .takeChooseMove)
        XCTAssertEqual(
            take.presentation?.headline,
            "Can one of your pieces safely take a black piece?"
        )
        XCTAssertTrue(take.presentation?.actions.map(\.action).contains(.hint) == true)
        take.handle(.actionChosen(.hint))
        XCTAssertEqual(take.presentation?.hint, .candidatePieces)
        XCTAssertEqual(take.presentation?.focus.candidateSquares, [capture.from])

        wake.handle(.interactionChanged(snapshot()))
        XCTAssertEqual(
            wake.stage,
            .wakeChoosePiece(purpose: .openingDevelopment(firstMove: true))
        )
        XCTAssertEqual(
            wake.presentation?.headline,
            "A center pawn or knight is a simple way to start. Which would you like to move?"
        )
        XCTAssertTrue(wake.presentation?.actions.map(\.action).contains(.hint) == true)
        wake.handle(.actionChosen(.hint))
        wake.handle(.actionChosen(.hint))
        XCTAssertEqual(wake.presentation?.hint, .candidateMoves)
        XCTAssertEqual(
            wake.presentation?.focus.candidateSquares,
            [
                CoachingTestFixtures.openingKnightMove.to,
                CoachingTestFixtures.alternateKnightMove.to,
            ]
        )
        XCTAssertEqual(wake.presentation?.focus.paths, [
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
    }

    func testLegalCheckMoveAdvancesEvenWhenSeparateDangerIsUnresolved() {
        let move = CoachingTestFixtures.safeMove
        var session = preparedSession(for: .check)
        stage(move, in: &session)
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
            danger: CoachingTestFixtures.multipleDangerAdvice.dangerProblems
        )
        var session = preparedSession(for: .safe)
        session.handle(.actionChosen(.hint))

        for expectedMisses in 1...2 {
            stage(move, in: &session)
            session.receive(advice)
            XCTAssertEqual(
                session.stage,
                .safeResolve(target: CoachingTestFixtures.whiteQueen)
            )
            XCTAssertEqual(session.hintLevel, 1)
            XCTAssertEqual(session.missesAtCurrentLevel, expectedMisses)
            if expectedMisses < 2 {
                session.handle(.interactionChanged(snapshot(
                    selected: move.from
                )))
            }
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
            session.presentation?.response,
            "That move is safe, but I cannot name a verified purpose for it."
        )
        XCTAssertEqual(session.presentation?.headline, "Try another move.")
    }

    func testStopPreservesTentativeMove() {
        var active = session()
        active.receive(CoachingTestFixtures.fallbackAdvice)
        XCTAssertEqual(
            active.handle(.actionChosen(.stop)),
            [.stop(preservingTentativeMove: true)]
        )
    }

    func testKeepLookingDiscardsTentativeMoveAndRestartsFromCommittedAdvice() {
        var complete = opponentCheckSession(
            move: CoachingTestFixtures.openingKnightMove,
            origin: .wake,
            assessment: CoachingTestFixtures.acceptableAssessment(
                CoachingTestFixtures.openingKnightMove,
                concepts: [.developsKnightOrBishop]
            )
        )
        complete.handle(.actionChosen(.looksSafe))
        XCTAssertEqual(
            complete.handle(.actionChosen(.keepLooking)),
            [.discardTentativeMove]
        )
        XCTAssertEqual(
            complete.stage,
            .wakeChoosePiece(purpose: .openingDevelopment(firstMove: true))
        )
        XCTAssertEqual(
            complete.presentation?.headline,
            "A center pawn or knight is a simple way to start. Which would you like to move?"
        )
        XCTAssertNil(complete.presentation?.response)
    }

    func testHintAdvancesOneLevelOnlyAfterActionAndCapsAtStrongestFocusLevel() {
        var session = session()
        session.receive(CoachingTestFixtures.multipleDangerAdvice)

        let unrelated = Square(file: .a, rank: 2)
        session.handle(.identificationTapped(unrelated))
        session.handle(.identificationTapped(unrelated))
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
                    piece: CoachingTestFixtures.whiteQueen,
                    purpose: .centralActivity
                )
            ),
            (.fallback, .fallbackChooseMove),
        ]

        for (origin, expectedStage) in expected {
            var session = preparedSession(for: origin)
            stage(move, in: &session)
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
            stage(move, in: &session)
            session.receive(advice)
            XCTAssertEqual(session.stage, .fallbackChooseMove)
            XCTAssertEqual(session.hintLevel, 0)
            XCTAssertEqual(session.missesAtCurrentLevel, expectedMisses)
            if expectedMisses < 2 {
                session.handle(.interactionChanged(snapshot()))
            }
        }
        XCTAssertFalse(session.presentation?.instruction?.contains("Want a hint?") == true)
        XCTAssertFalse(session.presentation?.actions.map(\.action).contains(.hint) == true)
    }

    func testEveryOriginCompletesWithCheckResolutionSkippingOpponentReplyQuiz() {
        for origin in [
            CoachingMoveOrigin.preexisting, .check, .safe, .take, .wake, .fallback,
        ] {
            let move = origin == .take
                ? CoachingTestFixtures.profitableCapture
                : CoachingTestFixtures.safeMove
            var session = preparedSession(for: origin)
            stage(move, in: &session)
            let concept: CoachingConcept = origin == .wake
                ? .developsKnightOrBishop
                : (origin == .take ? .profitableCapture : .pieceNeedsHelp)
            let learnerCaptures = origin == .take
                ? CoachingTestFixtures.takeAdvice.evaluation.learnerCaptureEstimates
                : []
            session.receive(CoachingTestFixtures.adviceForTentativeMove(
                move,
                origin: origin,
                assessment: CoachingTestFixtures.acceptableAssessment(
                    move,
                    concepts: [concept]
                ),
                learnerCaptures: learnerCaptures,
                confidence: origin == .fallback ? .unsupported : .high
            ))
            if origin != .check {
                XCTAssertEqual(session.stage, .opponentCheck(move: move, origin: origin))
                XCTAssertTrue(session.handle(.actionChosen(.looksSafe)).isEmpty)
            }
            XCTAssertEqual(
                session.stage,
                .complete(move: move, origin: origin, concepts: [concept])
            )
        }
    }

    func testSafeAttackerHintsRevealRelationshipThenCandidatesWithoutInventingPersistentPath() {
        var session = session()
        session.receive(CoachingTestFixtures.multipleDangerAdvice)
        session.handle(.identificationTapped(CoachingTestFixtures.whiteQueen))

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

    func testWakeRookAfterKnightMatchesRookAsFirstSelection() {
        let rook = Square(file: .a, rank: 1)
        var direct = openingSession()
        direct.handle(.interactionChanged(snapshot(selected: rook)))

        var switched = openingSession()
        switched.handle(.interactionChanged(snapshot(
            selected: CoachingTestFixtures.openingKnight
        )))
        switched.handle(.interactionChanged(snapshot(selected: rook)))

        XCTAssertEqual(switched.stage, direct.stage)
        XCTAssertEqual(switched.presentation, direct.presentation)
        XCTAssertEqual(
            switched.presentation?.response,
            "Your pawn is blocking that rook. Choose a center pawn or knight."
        )
        XCTAssertEqual(
            switched.presentation?.headline,
            "A center pawn or knight is a simple way to start. Which would you like to move?"
        )
    }

    func testWakeOpeningKnightAfterAlternateKnightMatchesDirectSelection() {
        var direct = openingSession()
        direct.handle(.interactionChanged(snapshot(
            selected: CoachingTestFixtures.openingKnight
        )))

        var switched = openingSession()
        switched.handle(.interactionChanged(snapshot(
            selected: CoachingTestFixtures.alternateKnight
        )))
        switched.handle(.interactionChanged(snapshot(
            selected: CoachingTestFixtures.openingKnight
        )))

        XCTAssertEqual(switched.stage, direct.stage)
        XCTAssertEqual(switched.presentation, direct.presentation)
    }

    func testWakeAlternateKnightAfterOpeningKnightMatchesDirectSelection() {
        var direct = openingSession()
        direct.handle(.interactionChanged(snapshot(
            selected: CoachingTestFixtures.alternateKnight
        )))

        var switched = openingSession()
        switched.handle(.interactionChanged(snapshot(
            selected: CoachingTestFixtures.openingKnight
        )))
        switched.handle(.interactionChanged(snapshot(
            selected: CoachingTestFixtures.alternateKnight
        )))

        XCTAssertEqual(switched.stage, direct.stage)
        XCTAssertEqual(switched.presentation, direct.presentation)
    }

    func testClearingWakeSelectionAfterCandidateMatchesNoSelection() {
        let direct = openingSession()

        var cleared = openingSession()
        cleared.handle(.interactionChanged(snapshot(
            selected: CoachingTestFixtures.openingKnight
        )))
        cleared.handle(.interactionChanged(snapshot()))

        XCTAssertEqual(cleared.stage, direct.stage)
        XCTAssertEqual(cleared.presentation, direct.presentation)
    }

    func testLowerPriorityTargetAfterPrimaryMatchesDirectLowerPriorityTap() {
        var direct = dangerSession()
        direct.handle(.identificationTapped(CoachingTestFixtures.whiteRook))

        var switched = dangerSession()
        switched.handle(.identificationTapped(CoachingTestFixtures.whiteQueen))
        switched.handle(.identificationTapped(CoachingTestFixtures.whiteRook))

        XCTAssertEqual(switched.stage, direct.stage)
        XCTAssertEqual(switched.presentation, direct.presentation)
        XCTAssertEqual(
            switched.presentation?.focus.emphasizedSquares,
            []
        )
        XCTAssertFalse(
            switched.presentation?.focus.emphasizedSquares.contains(
                CoachingTestFixtures.whiteQueen
            ) == true
        )
        XCTAssertTrue(switched.presentation?.focus.paths.isEmpty == true)
    }

    func testSafeFocusSurvivesSelectingPossibleSavingPiece() {
        var direct = dangerSession()
        direct.handle(.identificationTapped(CoachingTestFixtures.whiteQueen))
        direct.handle(.identificationTapped(CoachingTestFixtures.blackBishop))

        var selected = direct
        selected.handle(.interactionChanged(snapshot(
            selected: CoachingTestFixtures.safeMove.from
        )))

        XCTAssertEqual(selected.stage, direct.stage)
        XCTAssertEqual(selected.presentation, direct.presentation)
        XCTAssertEqual(
            selected.presentation?.focus.emphasizedSquares,
            [CoachingTestFixtures.whiteQueen, CoachingTestFixtures.blackBishop]
        )
        XCTAssertEqual(selected.presentation?.focus.paths, [CoachFocusPath(
            source: CoachingTestFixtures.blackBishop,
            destination: CoachingTestFixtures.whiteQueen,
            role: .attacker
        )])
    }

    func testNewStartAdviceDropsOldSafeEvidenceAndFocus() {
        let direct = openingSession()

        var restarted = dangerSession()
        restarted.handle(.identificationTapped(CoachingTestFixtures.whiteQueen))
        restarted.handle(.identificationTapped(CoachingTestFixtures.blackBishop))
        restarted.receive(
            CoachingTestFixtures.startingPositionAdvice,
            interaction: snapshot()
        )

        XCTAssertEqual(restarted.stage, direct.stage)
        XCTAssertEqual(restarted.presentation, direct.presentation)
        XCTAssertEqual(restarted.presentation?.focus, .empty)
    }

    func testTentativeMoveCapturesOriginAndQueuesAdviceOnlyOnce() {
        let move = CoachingTestFixtures.openingKnightMove
        var session = openingSession()
        session.handle(.interactionChanged(snapshot(selected: move.from)))

        XCTAssertEqual(
            stage(move, in: &session),
            [.requestAdvice(context: .tentativeMove(origin: .wake))]
        )
        XCTAssertTrue(stage(move, in: &session).isEmpty)
        XCTAssertEqual(session.stage, .awaitingAdvice(origin: .wake))
    }

    func testStagingMovableNoncandidateWhileChoosingWakeSourceUsesWakeOrigin() {
        let pawn = Square(file: .e, rank: 2)
        let move = Move(from: pawn, to: Square(file: .e, rank: 3))
        var session = openingSession()
        session.handle(.interactionChanged(snapshot(selected: pawn)))
        XCTAssertEqual(
            session.stage,
            .wakeChoosePiece(purpose: .openingDevelopment(firstMove: true))
        )

        XCTAssertEqual(
            stage(move, in: &session),
            [.requestAdvice(context: .tentativeMove(origin: .wake))]
        )
        session.receive(
            CoachingTestFixtures.adviceForTentativeMove(
                move,
                origin: .wake,
                assessment: CoachingTestFixtures.acceptableAssessment(
                    move,
                    concepts: [],
                    isAcceptable: false
                )
            ),
            interaction: snapshot(selected: move.to, tentativeMove: move)
        )

        XCTAssertEqual(
            session.stage,
            .wakeChooseMove(piece: pawn, purpose: .centralActivity)
        )
        XCTAssertEqual(session.missesAtCurrentLevel, 1)
    }

    func testRemovingCompletedMoveDropsMoveEvidenceAndRederivesPositionQuestion() {
        let move = CoachingTestFixtures.openingKnightMove
        var session = openingSession()
        session.handle(.interactionChanged(snapshot(selected: move.from)))
        stage(move, in: &session)
        session.receive(
            CoachingTestFixtures.adviceForTentativeMove(
                move,
                origin: .wake,
                assessment: CoachingTestFixtures.acceptableAssessment(
                    move,
                    concepts: [.developsKnightOrBishop]
                )
            ),
            interaction: snapshot(selected: move.to, tentativeMove: move)
        )
        session.handle(.actionChosen(.looksSafe))
        XCTAssertEqual(
            session.stage,
            .complete(move: move, origin: .wake, concepts: [.developsKnightOrBishop])
        )

        XCTAssertTrue(session.handle(.interactionChanged(snapshot())).isEmpty)

        XCTAssertEqual(
            session.stage,
            .wakeChoosePiece(purpose: .openingDevelopment(firstMove: true))
        )
        XCTAssertEqual(session.presentation, openingSession().presentation)
        XCTAssertFalse(session.presentation?.actions.map(\.action).contains(.done) == true)
    }

    func testReplacingTentativeMoveRetainsOriginAndRequiresExactNewAdvice() {
        let first = CoachingTestFixtures.openingKnightMove
        let replacement = CoachingTestFixtures.alternateKnightMove
        var session = openingSession()
        session.handle(.interactionChanged(snapshot(selected: first.from)))
        stage(first, in: &session)
        session.receive(
            CoachingTestFixtures.adviceForTentativeMove(
                first,
                origin: .wake,
                assessment: CoachingTestFixtures.acceptableAssessment(
                    first,
                    concepts: [.developsKnightOrBishop]
                )
            ),
            interaction: snapshot(selected: first.to, tentativeMove: first)
        )

        XCTAssertEqual(
            session.handle(.interactionChanged(snapshot(
                selected: replacement.to,
                tentativeMove: replacement
            ))),
            [.requestAdvice(context: .tentativeMove(origin: .wake))]
        )
        XCTAssertEqual(session.stage, .awaitingAdvice(origin: .wake))

        session.receive(
            CoachingTestFixtures.adviceForTentativeMove(
                first,
                origin: .wake,
                assessment: CoachingTestFixtures.acceptableAssessment(
                    first,
                    concepts: [.developsKnightOrBishop]
                )
            ),
            interaction: snapshot(selected: replacement.to, tentativeMove: replacement)
        )
        XCTAssertEqual(session.stage, .awaitingAdvice(origin: .wake))
    }

    func testUnsupportedTentativeResponseFallsBackWithoutRequestLoop() {
        let move = CoachingTestFixtures.openingKnightMove
        var session = openingSession()
        session.handle(.interactionChanged(snapshot(selected: move.from)))
        stage(move, in: &session)

        XCTAssertTrue(session.receiveUnsupportedPosition(
            for: .tentativeMove(origin: .wake),
            interaction: snapshot(selected: move.to, tentativeMove: move)
        ).isEmpty)

        XCTAssertEqual(session.stage, .fallbackChooseMove)
        XCTAssertEqual(
            session.presentation?.headline,
            "I can check immediate dangers, but I do not have a confident plan for this position yet."
        )
        XCTAssertFalse(session.presentation?.actions.map(\.action).contains(.hint) == true)
    }

    func testStaleStartAdviceCannotReplaceTheCurrentSnapshot() {
        var session = openingSession()

        XCTAssertEqual(
            session.handle(.interactionChanged(snapshot(revision: 8))),
            [.requestAdvice(context: .start)]
        )
        XCTAssertTrue(session.receive(
            CoachingTestFixtures.startingPositionAdvice,
            interaction: snapshot(revision: 8)
        ).isEmpty)

        XCTAssertEqual(session.stage, .awaitingAdvice(origin: nil))
        XCTAssertNil(session.presentation)
    }

    func testTentativeAdviceCannotUseRetainedPositionAdviceFromDifferentRevision() {
        let move = CoachingTestFixtures.openingKnightMove
        let interaction = snapshot(
            selected: move.to,
            tentativeMove: move,
            revision: 8
        )
        let request = CoachingRequest(
            committedState: .startingPosition(),
            tentativeMove: move,
            learner: .white,
            positionRevision: 8,
            context: .tentativeMove(origin: .wake)
        )
        let advice = CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: .wake,
            assessment: CoachingTestFixtures.acceptableAssessment(
                move,
                concepts: [.developsKnightOrBishop]
            )
        ).replacingRequest(with: request)
        var session = openingSession()

        XCTAssertEqual(
            session.handle(.interactionChanged(interaction)),
            [.requestAdvice(context: .tentativeMove(origin: .wake))]
        )
        XCTAssertTrue(session.receive(advice, interaction: interaction).isEmpty)

        XCTAssertEqual(session.stage, .awaitingAdvice(origin: .wake))
        XCTAssertNil(session.presentation)
    }

    func testActionsOnlyApplyWhenExposedByTheDerivedQuestion() {
        var opening = openingSession()
        let openingPresentation = opening.presentation
        for action in [
            CoachingAction.noAnswer, .looksSafe, .keepLooking, .done,
        ] {
            XCTAssertTrue(opening.handle(.actionChosen(action)).isEmpty, "\(action)")
            XCTAssertEqual(opening.presentation, openingPresentation, "\(action)")
        }
        XCTAssertTrue(opening.handle(.actionChosen(.hint)).isEmpty)
        XCTAssertEqual(opening.hintLevel, 1)
        XCTAssertEqual(
            opening.handle(.actionChosen(.stop)),
            [.stop(preservingTentativeMove: true)]
        )

        var clearSafe = session()
        clearSafe.receive(
            CoachingTestFixtures.nontrivialSafeClearAdvice,
            interaction: snapshot()
        )
        clearSafe.handle(.actionChosen(.noAnswer))
        XCTAssertEqual(clearSafe.stage, .fallbackChooseMove)

        let move = CoachingTestFixtures.fallbackMove
        var reply = session(
            interaction: snapshot(selected: move.to, tentativeMove: move),
            initialContext: .tentativeMove(origin: .preexisting)
        )
        reply.receive(
            CoachingTestFixtures.adviceForTentativeMove(
                move,
                origin: .preexisting,
                assessment: CoachingTestFixtures.acceptableAssessment(move)
            ),
            interaction: snapshot(selected: move.to, tentativeMove: move)
        )
        reply.handle(.actionChosen(.looksSafe))
        XCTAssertEqual(
            reply.stage,
            .complete(move: move, origin: .preexisting, concepts: [])
        )
        XCTAssertEqual(
            reply.handle(.actionChosen(.done)),
            [.commitWithExistingDonePath]
        )
        XCTAssertEqual(
            reply.handle(.actionChosen(.keepLooking)),
            [.discardTentativeMove, .requestAdvice(context: .start)]
        )
        XCTAssertEqual(reply.stage, .awaitingAdvice(origin: nil))
    }

    private func opponentCheckSession(
        move: Move,
        origin: CoachingMoveOrigin,
        assessment: CoachingMoveAssessment
    ) -> CoachingSession {
        var session = preparedSession(for: origin)
        stage(move, in: &session)
        session.receive(CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: origin,
            assessment: assessment,
            confidence: origin == .fallback ? .unsupported : .high
        ))
        return session
    }

    private func preparedSession(for origin: CoachingMoveOrigin) -> CoachingSession {
        var session = session()
        switch origin {
        case .preexisting:
            break
        case .check:
            session.receive(CoachingTestFixtures.advice(
                checking: [CoachingTestFixtures.blackBishop],
                opponentHasCapture: true,
                learnerHasCapture: false
            ))
            session.handle(.identificationTapped(CoachingTestFixtures.blackBishop))
        case .safe:
            session.receive(CoachingTestFixtures.multipleDangerAdvice)
            session.handle(.identificationTapped(CoachingTestFixtures.whiteQueen))
            session.handle(.identificationTapped(CoachingTestFixtures.blackBishop))
        case .take:
            session.receive(CoachingTestFixtures.takeAdvice)
        case .wake:
            session.receive(CoachingTestFixtures.startingPositionAdvice)
            session.handle(.interactionChanged(snapshot(
                selected: CoachingTestFixtures.openingKnight
            )))
        case .fallback:
            session.receive(CoachingTestFixtures.fallbackAdvice)
        }
        return session
    }

    private func openingSession() -> CoachingSession {
        var session = session()
        session.receive(
            CoachingTestFixtures.startingPositionAdvice,
            interaction: snapshot()
        )
        return session
    }

    private func dangerSession() -> CoachingSession {
        var session = session()
        session.receive(
            CoachingTestFixtures.multipleDangerAdvice,
            interaction: snapshot()
        )
        return session
    }

    private func session(
        learner: PieceColor = .white,
        interaction: CoachingInteractionSnapshot? = nil,
        initialContext: CoachingRequest.Context = .start
    ) -> CoachingSession {
        CoachingSession(
            learner: learner,
            interaction: interaction ?? snapshot(),
            initialContext: initialContext
        )
    }

    private func snapshot(
        selected: Square? = nil,
        tentativeMove: Move? = nil,
        revision: Int = 7
    ) -> CoachingInteractionSnapshot {
        CoachingInteractionSnapshot(
            selectedSquare: selected,
            tentativeMove: tentativeMove,
            positionRevision: revision
        )
    }

    @discardableResult
    private func stage(
        _ move: Move,
        in session: inout CoachingSession,
        revision: Int = 7
    ) -> [CoachingDirective] {
        session.handle(.interactionChanged(snapshot(
            selected: move.to,
            tentativeMove: move,
            revision: revision
        )))
    }
}

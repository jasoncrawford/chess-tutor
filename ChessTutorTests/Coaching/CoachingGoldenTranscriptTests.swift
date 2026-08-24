import XCTest
@testable import ChessTutor

final class CoachingGoldenTranscriptTests: XCTestCase {
    func testCorpusContainsEveryApprovedAnchor() {
        XCTAssertEqual(CoachingGoldenPosition.allCases.count, 17)
        XCTAssertEqual(Set(CoachingGoldenPosition.allCases.map(\.rawValue)).count, 17)
        XCTAssertEqual(CoachingGoldenCase.allCases.count, 52)
        XCTAssertEqual(Set(CoachingGoldenCase.allCases.map(\.rawValue)).count, 52)
    }

    func testEveryApprovedBranchHasAGoldenTurn() async throws {
        let requiredCases: [CoachingGoldenCase] = [
            .t1Entry, .t1BlockedRook, .t1FlankPawn, .t1Hint, .t1KnightSelected,
            .t1PreferredKnight, .t1EdgeKnight, .t1CenterPawn, .t1OutsidePawnMove,
            .t2Entry, .t2OneSquareKingMove, .t2KnightSwitch, .t2Castle,
            .t3Entry, .t3WrongOwnPiece, .t3Target, .t3WrongAttacker, .t3Attacker,
            .t3UnresolvedMove, .t3ResolvedMove,
            .t4LowerPriorityPawn, .t4PrimaryKnight,
            .t5PawnDanger, .t5PawnResolved, .t5ProtectedTap, .t5ProtectedAbsence,
            .t6WrongSource, .t6Hint, .t6Capture,
            .t7UnsafeCapture, .t7NoSafeCapture,
            .t8AddsDefender,
            .t9Entry, .t9Hint, .t9Completed,
            .t10Entry, .t10Completed,
            .t11Safe, .t11QueenLoss, .t11IncorrectLooksSafe, .t11HarmlessCheck,
            .t11UnsafeBishopEntry, .t11UnsafeBishopFound,
            .t11BenignCaptureTap, .t11BenignCaptureLooksSafe,
            .t12CheckLocate, .t12WrongChecker, .t12Capture, .t12Block, .t12KingMove,
            .t12UnsupportedEntry, .t12UnsupportedSafeMove,
        ]

        XCTAssertEqual(requiredCases, CoachingGoldenCase.allCases)
        for testCase in requiredCases {
            let turn = try await goldenTurn(testCase)
            XCTAssertEqual(
                turn,
                expectedTurn(testCase),
                "Unexpected transcript for \(testCase.rawValue)"
            )
        }
    }

    func testEveryGoldenPresentationIsSemanticallyCoherent() async throws {
        for branch in CoachingGoldenCase.allCases {
            let presentation = try await goldenPresentation(branch)
            assertCoherent(presentation, branch: branch)

            if presentation.actions.contains(where: { $0.action == .noAnswer }) {
                let observation = presentation.observation?.lowercased() ?? ""
                let establishedAnswers: [String]
                switch presentation.primaryMessage {
                case "Which of your pieces is in danger?":
                    establishedAnswers = [
                        "one of your pieces does need help",
                        "no piece needs help right now",
                    ]
                case "Can one of your pieces safely take a black piece?":
                    establishedAnswers = [
                        "there is a safe capture to find",
                        "has a safe capture",
                        "there is no safe capture here",
                    ]
                default:
                    establishedAnswers = []
                }
                XCTAssertFalse(
                    establishedAnswers.contains(where: observation.contains),
                    "Current absence action survived an established answer for \(branch.rawValue)"
                )
            }
        }
    }

    func testEveryGoldenPresentationUsesCompactNonduplicativeCopy() async throws {
        for branch in CoachingGoldenCase.allCases {
            let presentation = try await goldenPresentation(branch)
            assertCompact(presentation)
        }
    }

    func testRevealedPositiveAnswersRemoveContradictoryAbsenceActions() async throws {
        let takeHint = try await goldenPresentation(.t6Hint)
        XCTAssertEqual(takeHint.observation, "Your bishop has a safe capture.")
        XCTAssertEqual(takeHint.actions.map(\.action), [.hint, .stop])
        XCTAssertFalse(takeHint.actions.map(\.title).contains("No safe capture"))

        let safe = try await goldenPresentation(.t3Entry)
        XCTAssertFalse(safe.actions.map(\.action).contains(.noAnswer))

        var opponent = try await tentativeSession(
            state: CoachingGoldenPosition.exposedQueen.state,
            move: CoachingGoldenMoves.exposesQueen,
            learner: .white
        )
        opponent.handle(.actionChosen(.hint))

        let opponentHint = try XCTUnwrap(opponent.presentation)
        XCTAssertEqual(opponentHint.hint, .attackerRelationship)
        XCTAssertEqual(opponentHint.actions.map(\.action), [.stop])
        XCTAssertFalse(opponentHint.actions.map(\.title).contains("Looks safe"))
    }

    func testGoldenCorpusChildFacingCopyAvoidsProhibitedPhrases() async throws {
        var childFacingValues: [String] = []
        for branch in CoachingGoldenCase.allCases {
            let presentation = try await goldenPresentation(branch)
            childFacingValues.append(contentsOf: [
                presentation.observation,
                presentation.primaryMessage,
                presentation.instruction,
            ].compactMap { $0 })
            childFacingValues.append(contentsOf: presentation.actions.flatMap {
                [$0.title, $0.accessibilityLabel]
            })
        }

        assertNoProhibitedChildFacingCopy(
            childFacingValues,
            source: "47-case golden corpus"
        )
    }

    func testHintReplacesRatherThanStacksMissFeedback() async throws {
        var t1 = try await preparedSession(for: .starting)
        t1.handle(.interactionChanged(snapshot(selected: sq("a1"))))
        let t1Miss = try XCTUnwrap(t1.presentation?.observation)
        t1.handle(.actionChosen(.hint))
        XCTAssertNil(t1.presentation?.observation)
        XCTAssertFalse(try XCTUnwrap(t1.presentation).primaryMessage.contains(t1Miss))

        var t3 = try await preparedSession(for: .endangeredKnight)
        t3.handle(.identificationTapped(sq("g1")))
        let t3Miss = try XCTUnwrap(t3.presentation?.observation)
        t3.handle(.actionChosen(.hint))
        XCTAssertNil(t3.presentation?.observation)
        XCTAssertFalse(try XCTUnwrap(t3.presentation).primaryMessage.contains(t3Miss))

        var t6 = try await preparedSession(for: .winningCapture)
        t6.handle(.interactionChanged(snapshot(selected: sq("g1"))))
        let t6Miss = try XCTUnwrap(t6.presentation?.observation)
        t6.handle(.actionChosen(.hint))
        XCTAssertEqual(t6.presentation?.observation, "Your bishop has a safe capture.")
        XCTAssertNotEqual(t6.presentation?.observation, t6Miss)

        var t11 = try await tentativeSession(
            state: CoachingGoldenPosition.exposedQueen.state,
            move: CoachingGoldenMoves.exposesQueen,
            learner: .white
        )
        t11.handle(.actionChosen(.looksSafe))
        let t11Miss = try XCTUnwrap(t11.presentation?.observation)
        t11.handle(.actionChosen(.hint))
        XCTAssertNil(t11.presentation?.observation)
        XCTAssertFalse(try XCTUnwrap(t11.presentation).primaryMessage.contains(t11Miss))
    }

    func testT1SourceSwitchingIsHistoryIndependent() async throws {
        let sources = [sq("a1"), sq("a2"), sq("b1")]
        for source in sources {
            var direct = try await preparedSession(for: .starting)
            direct.handle(.interactionChanged(snapshot(selected: source)))

            var historyRich = try await preparedSession(for: .starting)
            for prior in sources where prior != source {
                historyRich.handle(.interactionChanged(snapshot(selected: prior)))
            }
            historyRich.handle(.interactionChanged(snapshot(selected: source)))

            XCTAssertEqual(
                try turn(from: historyRich),
                try turn(from: direct),
                "T1 source \(source) depended on selection history"
            )
        }
    }

    func testT3TargetSwitchingIsHistoryIndependent() async throws {
        var direct = try await preparedSession(for: .endangeredKnight)
        direct.handle(.identificationTapped(sq("f3")))

        for misses in 1...3 {
            var historyRich = try await preparedSession(for: .endangeredKnight)
            for _ in 0..<misses {
                historyRich.handle(.identificationTapped(sq("g1")))
            }
            historyRich.handle(.identificationTapped(sq("f3")))

            XCTAssertEqual(
                try turn(from: historyRich),
                try turn(from: direct),
                "T3 target depended on \(misses) prior miss(es)"
            )
        }
    }

    func testT11TentativeMoveReplacementIsHistoryIndependent() async throws {
        let state = CoachingGoldenPosition.harmlessCheck.state
        let centerMove = CoachingGoldenMoves.developsKnight
        let edgeMove = Move(from: sq("b1"), to: sq("a3"))

        for (prior, current) in [(edgeMove, centerMove), (centerMove, edgeMove)] {
            let direct = try await tentativeSession(
                state: state,
                move: current,
                learner: .white
            )
            var historyRich = try await tentativeSession(
                state: state,
                move: prior,
                learner: .white
            )
            try await stage(
                current,
                origin: .fallback,
                state: state,
                in: &historyRich
            )

            XCTAssertEqual(
                try turn(from: historyRich),
                try turn(from: direct),
                "T11 move \(current) depended on prior tentative move"
            )
        }
    }

    @MainActor
    func testReportedMovePresentationsAreIndependentOfPriorInteractionHistory() async throws {
        let paths = [
            ReportedMovePath(
                name: "h2-h4",
                state: CoachingGoldenPosition.starting.state,
                learner: .white,
                move: CoachingGoldenMoves.outsidePawn,
                knight: sq("b1"),
                rook: sq("a1"),
                friendly: sq("a2"),
                enemy: sq("a7"),
                empty: sq("e4"),
                hintSource: nil,
                replacement: CoachingGoldenMoves.openingKnightToF3
            ),
            ReportedMovePath(
                name: "Bf1-a6",
                state: CoachingGoldenPosition.openingBishopCanBeTaken.state,
                learner: .white,
                move: CoachingGoldenMoves.bishopToA6,
                knight: sq("b1"),
                rook: sq("a1"),
                friendly: sq("a2"),
                enemy: sq("a7"),
                empty: sq("e3"),
                hintSource: nil,
                replacement: Move(from: sq("f1"), to: sq("b5"))
            ),
            ReportedMovePath(
                name: "e7-e6",
                state: CoachingGoldenPosition.protectedPawnUnderBishopAttack.state,
                learner: .black,
                move: CoachingGoldenMoves.blackPawnToE6,
                knight: sq("b8"),
                rook: sq("a8"),
                friendly: sq("a7"),
                enemy: sq("c4"),
                empty: sq("h6"),
                hintSource: sq("c4"),
                replacement: Move(from: sq("e7"), to: sq("e5"))
            ),
        ]

        for path in paths {
            let direct = try await reportedPresentation(for: path, history: nil)
            for history in ReportedInteractionHistory.allCases {
                let historyRich = try await reportedPresentation(
                    for: path,
                    history: history
                )
                XCTAssertEqual(
                    historyRich.presentation,
                    direct.presentation,
                    "\(path.name) depended on prior \(history.rawValue) interaction"
                )
                XCTAssertEqual(
                    historyRich.presentation.focus,
                    direct.presentation.focus,
                    "\(path.name) focus depended on prior \(history.rawValue) interaction"
                )
                XCTAssertEqual(
                    historyRich.moveHistory,
                    direct.moveHistory,
                    "\(path.name) committed after prior \(history.rawValue) interaction"
                )
            }
        }
    }

    func testQuietOpeningKnightCompletesWithoutOpponentQuiz() async throws {
        let session = try await tentativeSession(
            state: CoachingGoldenPosition.starting.state,
            move: CoachingGoldenMoves.openingKnightToF3,
            learner: .white
        )

        guard case .complete = session.stage else {
            return XCTFail("Expected direct completion, got \(session.stage)")
        }
        XCTAssertFalse(
            try XCTUnwrap(session.presentation).actions.map(\.action).contains(.looksSafe)
        )
    }

    func testOutsidePawnDoesNotInheritCentralActivity() async throws {
        let session = try await tentativeSession(
            state: CoachingGoldenPosition.starting.state,
            move: CoachingGoldenMoves.outsidePawn,
            learner: .white
        )

        guard case let .complete(_, _, concepts) = session.stage else {
            return XCTFail("Expected completion")
        }
        XCTAssertFalse(concepts.contains(.improvesCentralActivity))
    }

    func testUnsafeBishopAsksForOpponentReplyBeforePurpose() async throws {
        var session = try await tentativeSession(
            state: CoachingGoldenPosition.openingBishopCanBeTaken.state,
            move: CoachingGoldenMoves.bishopToA6,
            learner: .white
        )

        XCTAssertEqual(
            session.stage,
            .opponentCheck(move: CoachingGoldenMoves.bishopToA6, origin: .fallback)
        )
        XCTAssertEqual(session.presentation?.primaryMessage, "What could Black do next?")
        XCTAssertEqual(
            session.presentation?.instruction,
            "Tap the black piece that could win your bishop."
        )
        XCTAssertNil(session.presentation?.observation)

        session.handle(.identificationTapped(sq("b7")))

        XCTAssertEqual(
            session.presentation?.primaryMessage,
            "Black's pawn could take your bishop."
        )
        XCTAssertEqual(
            session.presentation?.instruction,
            "Try a different bishop move."
        )
        XCTAssertNil(session.presentation?.observation)
    }

    func testBenignOpponentActivityTapKeepsQuestionAndShowsFact() async throws {
        var session = try await tentativeSession(
            state: CoachingGoldenPosition.protectedPawnUnderBishopAttack.state,
            move: CoachingGoldenMoves.blackPawnToE6,
            learner: .black
        )

        session.handle(.identificationTapped(sq("c4")))

        XCTAssertEqual(
            session.stage,
            .opponentCheck(move: CoachingGoldenMoves.blackPawnToE6, origin: .fallback)
        )
        XCTAssertEqual(
            session.presentation?.observation,
            "That bishop attacks your pawn, but the pawn is protected."
        )
        XCTAssertEqual(session.presentation?.focus.paths, [CoachFocusPath(
            source: sq("c4"),
            destination: sq("e6"),
            role: .attacker
        )])
    }

    func testSafeDangerAndProtectionBranchesUseBoardFacts() async throws {
        let t3Entry = try await goldenTurn(.t3Entry)
        let t4LowerPriorityPawn = try await goldenTurn(.t4LowerPriorityPawn)
        let t5PawnResolved = try await goldenTurn(.t5PawnResolved)
        let t5ProtectedTap = try await goldenTurn(.t5ProtectedTap)
        let t8AddsDefender = try await goldenTurn(.t8AddsDefender)

        XCTAssertEqual(
            t3Entry.primaryMessage,
            "Which of your pieces is in danger?"
        )
        XCTAssertEqual(
            t4LowerPriorityPawn.observation,
            "You found a threatened pawn, but losing the knight would cost more."
        )
        XCTAssertEqual(
            t4LowerPriorityPawn.primaryMessage,
            "Which piece should you help first?"
        )
        XCTAssertEqual(
            t5PawnResolved.primaryMessage,
            "Your pawn is out of the bishop's path and safe."
        )
        XCTAssertEqual(
            t5ProtectedTap.observation,
            "The knight attacks your pawn, but another pawn protects it."
        )
        XCTAssertEqual(
            t8AddsDefender.primaryMessage,
            "Your pawn now protects the pawn from the attacking knight."
        )
    }

    func testSafeAndUnsafeCaptureBranchesUseConcreteExchangeFacts() async throws {
        let t6WrongSource = try await goldenTurn(.t6WrongSource)
        let t6Hint = try await goldenTurn(.t6Hint)
        let t6Capture = try await goldenTurn(.t6Capture)
        let t7UnsafeCapture = try await goldenTurn(.t7UnsafeCapture)
        let t7NoSafeCapture = try await goldenTurn(.t7NoSafeCapture)

        XCTAssertEqual(
            t6WrongSource.primaryMessage,
            "Can one of your pieces safely take a black piece?"
        )
        XCTAssertEqual(t6WrongSource.observation, "That piece has no safe capture here.")
        XCTAssertEqual(t6Hint.observation, "Your bishop has a safe capture.")
        XCTAssertEqual(t6Hint.instruction, "Tap the highlighted white piece.")
        XCTAssertEqual(
            t6Capture.primaryMessage,
            "Your bishop took a rook, and Black cannot take the bishop back."
        )
        XCTAssertEqual(
            t7UnsafeCapture.observation,
            "Black's king could take your bishop, so you would lose it for a pawn."
        )
        XCTAssertEqual(
            t7NoSafeCapture.observation,
            "There is no safe capture here."
        )
        XCTAssertEqual(
            t7NoSafeCapture.primaryMessage,
            "What move would you like to try?"
        )
    }

    func testConstructiveWakeBranchesUseNamedEvidenceAndBoundedGrades() async throws {
        let t1Entry = try await goldenTurn(.t1Entry)
        let t1BlockedRook = try await goldenTurn(.t1BlockedRook)
        let t1FlankPawn = try await goldenTurn(.t1FlankPawn)
        let t1Hint = try await goldenTurn(.t1Hint)
        let t1KnightSelected = try await goldenTurn(.t1KnightSelected)
        let t1PreferredKnight = try await goldenTurn(.t1PreferredKnight)
        let t1EdgeKnight = try await goldenTurn(.t1EdgeKnight)
        let t1CenterPawn = try await goldenTurn(.t1CenterPawn)
        let t2Entry = try await goldenTurn(.t2Entry)
        let t2OneSquareKingMove = try await goldenTurn(.t2OneSquareKingMove)
        let t2KnightSwitch = try await goldenTurn(.t2KnightSwitch)
        let t2Castle = try await goldenTurn(.t2Castle)
        let t9Entry = try await goldenTurn(.t9Entry)
        let t9Hint = try await goldenTurn(.t9Hint)
        let t9Completed = try await goldenTurn(.t9Completed)
        let t10Entry = try await goldenTurn(.t10Entry)
        let t10Completed = try await goldenTurn(.t10Completed)

        XCTAssertEqual(
            t1Entry.primaryMessage,
            "A center pawn or knight is a simple way to start."
        )
        XCTAssertEqual(
            t1BlockedRook.observation,
            "Your pawn blocks that rook."
        )
        XCTAssertEqual(
            t1FlankPawn.observation,
            "That pawn is outside the center."
        )
        XCTAssertEqual(t1Hint.primaryMessage, "Here are the four pieces you can try.")
        XCTAssertEqual(t1Hint.instruction, "Tap a highlighted piece.")
        XCTAssertEqual(
            t1KnightSelected.primaryMessage,
            "Moving this knight is called developing it."
        )
        XCTAssertEqual(
            t1PreferredKnight.primaryMessage,
            "You developed your knight toward the center."
        )
        XCTAssertEqual(
            t1EdgeKnight.primaryMessage,
            "You developed your knight away from the center, giving it fewer moves."
        )
        XCTAssertEqual(
            t1CenterPawn.primaryMessage,
            "Your center pawn moved forward and helps control the center."
        )
        XCTAssertEqual(t2Entry.primaryMessage, "Your king is ready to castle.")
        XCTAssertEqual(
            t2Entry.instruction,
            "Move your king two squares toward the rook."
        )
        XCTAssertNil(t2OneSquareKingMove.observation)
        XCTAssertEqual(
            t2OneSquareKingMove.primaryMessage,
            "What could Black do next?"
        )
        XCTAssertEqual(
            t2KnightSwitch.primaryMessage,
            "This knight can be developed."
        )
        XCTAssertEqual(
            t2KnightSwitch.instruction,
            "Move the knight."
        )
        XCTAssertEqual(
            t2Castle.primaryMessage,
            "You castled, moving your king toward safety and activating your rook."
        )
        XCTAssertEqual(
            t9Entry.primaryMessage,
            "Your knight can attack Black's rook."
        )
        XCTAssertEqual(
            t9Hint.primaryMessage,
            "Both highlighted squares let the knight attack the rook."
        )
        XCTAssertEqual(
            t9Hint.instruction,
            "Move the knight to one of the highlighted squares."
        )
        XCTAssertEqual(
            t9Completed.primaryMessage,
            "Your knight now attacks Black's rook."
        )
        XCTAssertEqual(t9Completed.emphasizedSquares, [sq("b3"), sq("d4")])
        XCTAssertEqual(t9Completed.candidateSquares, [])
        XCTAssertEqual(t9Completed.paths, [
            CoachFocusPath(
                source: sq("b3"),
                destination: sq("d4"),
                role: .attacker
            ),
        ])
        XCTAssertEqual(
            t10Entry.primaryMessage,
            "Your knight has only two moves in this corner."
        )
        XCTAssertEqual(
            t10Completed.primaryMessage,
            "Your knight can now reach six squares instead of two."
        )
    }

    func testOpponentPromptHasOneTapGrammar() async throws {
        let turn = try await opponentPromptTurn(
            state: CoachingGoldenPosition.exposedQueen.state,
            move: CoachingGoldenMoves.exposesQueen,
            learner: .white
        )

        XCTAssertEqual(turn.primaryMessage, "What could Black do next?")
        XCTAssertEqual(
            turn.instruction,
            "Tap the black piece that could win your queen."
        )
    }

    func testQueenLossAndHarmlessCheckCopy() async throws {
        let queenLoss = try await goldenTurn(.t11QueenLoss)
        let harmlessCheck = try await goldenTurn(.t11HarmlessCheck)

        XCTAssertNil(queenLoss.observation)
        XCTAssertEqual(queenLoss.primaryMessage, "Black's rook could take your queen.")
        XCTAssertEqual(queenLoss.instruction, "Try a different queen move.")
        XCTAssertEqual(queenLoss.actions, [.hint, .stop])
        XCTAssertEqual(queenLoss.actionTitles, ["Hint", "Close help"])
        XCTAssertEqual(queenLoss.boardTask, .move)
        XCTAssertEqual(
            queenLoss.emphasizedSquares,
            [
                CoachingGoldenMoves.rookTakesQueen.from,
                CoachingGoldenMoves.rookTakesQueen.to,
            ]
        )
        XCTAssertEqual(queenLoss.candidateSquares, [])
        XCTAssertEqual(queenLoss.paths, [
            CoachFocusPath(
                source: CoachingGoldenMoves.rookTakesQueen.from,
                destination: CoachingGoldenMoves.rookTakesQueen.to,
                role: .attacker
            ),
        ])
        XCTAssertEqual(
            harmlessCheck.observation,
            "That rook could check along your back row, but your knight move still works."
        )
        XCTAssertEqual(
            harmlessCheck.primaryMessage,
            "Your knight moved closer to the center."
        )
    }

    func testHintInConcreteOpponentReviseStateRepulsesTheRealReplyOnly() async throws {
        var session = try await tentativeSession(
            state: CoachingGoldenPosition.exposedQueen.state,
            move: CoachingGoldenMoves.exposesQueen,
            learner: .white
        )
        session.handle(.identificationTapped(CoachingGoldenMoves.rookTakesQueen.from))
        let initialPulseID = try XCTUnwrap(session.presentation).focus.pulseID

        session.handle(.actionChosen(.hint))

        let presentation = try XCTUnwrap(session.presentation)
        XCTAssertNil(presentation.observation)
        XCTAssertEqual(
            presentation.primaryMessage,
            "Black could take your queen."
        )
        XCTAssertEqual(
            presentation.instruction,
            "Try a different queen move."
        )
        XCTAssertEqual(presentation.actions.map(\.action), [.stop])
        XCTAssertEqual(presentation.focus.pulseID, initialPulseID + 1)
        XCTAssertEqual(presentation.focus.candidateSquares, [])
        XCTAssertEqual(
            presentation.focus.emphasizedSquares,
            [
                CoachingGoldenMoves.rookTakesQueen.from,
                CoachingGoldenMoves.rookTakesQueen.to,
            ]
        )
        XCTAssertEqual(presentation.focus.paths, [
            CoachFocusPath(
                source: CoachingGoldenMoves.rookTakesQueen.from,
                destination: CoachingGoldenMoves.rookTakesQueen.to,
                role: .attacker
            ),
        ])
    }

    func testIncorrectLooksSafeNamesIssueAndRemovesInvalidAbsenceAction() async throws {
        let turn = try await goldenTurn(.t11IncorrectLooksSafe)

        XCTAssertEqual(turn.observation, "Black's rook could take your queen.")
        XCTAssertEqual(turn.actions, [.hint, .stop])
        XCTAssertEqual(turn.actionTitles, ["Hint", "Close help"])
        XCTAssertEqual(
            turn.instruction,
            "Tap the black rook, or choose Hint."
        )
    }

    func testHintAfterIncorrectLooksSafeClearsResponseWithoutRestoringLooksSafe() async throws {
        var session = try await tentativeSession(
            state: CoachingGoldenPosition.exposedQueen.state,
            move: CoachingGoldenMoves.exposesQueen,
            learner: .white
        )
        session.handle(.actionChosen(.looksSafe))
        session.handle(.actionChosen(.hint))

        let turn = try turn(from: session)
        XCTAssertNil(turn.observation)
        XCTAssertEqual(turn.instruction, "Tap the black rook.")
        XCTAssertEqual(turn.actions, [.stop])
        XCTAssertEqual(turn.candidateSquares, [CoachingGoldenMoves.rookTakesQueen.from])
        XCTAssertEqual(turn.paths, [
            CoachFocusPath(
                source: CoachingGoldenMoves.rookTakesQueen.from,
                destination: CoachingGoldenMoves.rookTakesQueen.to,
                role: .attacker
            ),
        ])
    }

    func testQuietMoveCompletesWithoutOpponentBoundaryObservation() async throws {
        let turn = try await goldenTurn(.t11Safe)

        XCTAssertNil(turn.observation)
        XCTAssertEqual(
            turn.primaryMessage,
            "You developed your knight toward the center."
        )
        XCTAssertEqual(turn.instruction, "Play it, or try another move.")
    }

    func testForcedCheckMovesWithRemainingActivityAskForOpponentReply() async throws {
        let capture = try await goldenTurn(.t12Capture)
        let block = try await goldenTurn(.t12Block)
        let kingMove = try await goldenTurn(.t12KingMove)

        XCTAssertEqual(
            capture.primaryMessage,
            "Your bishop took the checking rook, so your king is safe."
        )
        XCTAssertEqual(
            block.primaryMessage,
            "What could Black do next?"
        )
        XCTAssertEqual(
            kingMove.primaryMessage,
            "What could Black do next?"
        )
    }

    func testUnsupportedEntryIsHonestAndHasNoRoutineOrCandidateFocus() async throws {
        let turn = try await goldenTurn(.t12UnsupportedEntry)

        XCTAssertEqual(
            turn.primaryMessage,
            "What move would you like to try?"
        )
        XCTAssertEqual(
            turn.instruction,
            "Move a piece."
        )
        XCTAssertEqual(turn.actions, [.stop])
        XCTAssertEqual(turn.routine, [])
        XCTAssertEqual(turn.emphasizedSquares, [])
        XCTAssertEqual(turn.candidateSquares, [])
        XCTAssertEqual(turn.paths, [])
    }

    func testUnsupportedSafeMoveStatesOnlyTheImmediateScanBoundary() async throws {
        let turn = try await goldenTurn(.t12UnsupportedSafeMove)

        XCTAssertNil(turn.observation)
        XCTAssertEqual(
            turn.primaryMessage,
            "That move seems safe."
        )
        XCTAssertEqual(turn.instruction, "Play it, or try another move.")
        XCTAssertEqual(turn.actions, [.done, .keepLooking, .stop])
        XCTAssertEqual(
            turn.actionTitles,
            ["Play this move", "Try another move", "Close help"]
        )
        XCTAssertEqual(turn.boardTask, .none)
        XCTAssertEqual(turn.routine, [])
        XCTAssertEqual(turn.emphasizedSquares, [])
        XCTAssertEqual(turn.candidateSquares, [])
        XCTAssertEqual(turn.paths, [])
    }

    func testColorMirrorsT1T3AndT11Semantics() async throws {
        var t1 = try await preparedSession(for: CoachingGoldenPosition.starting.state)
        t1.handle(.actionChosen(.hint))
        let originalT1 = try turn(from: t1)
        var mirroredT1 = try await preparedSession(
            for: colorMirror(CoachingGoldenPosition.starting.state),
            learner: .black
        )
        mirroredT1.handle(.actionChosen(.hint))
        let blackT1 = try turn(from: mirroredT1)

        XCTAssertNil(originalT1.observation)
        XCTAssertNil(blackT1.observation)
        XCTAssertEqual(originalT1.primaryMessage, "Here are the four pieces you can try.")
        XCTAssertEqual(blackT1.primaryMessage, "Here are the four pieces you can try.")
        XCTAssertEqual(originalT1.instruction, "Tap a highlighted piece.")
        XCTAssertEqual(blackT1.instruction, "Tap a highlighted piece.")
        assertMatchingStructureAndMirroredFocus(originalT1, blackT1)

        var t3 = try await preparedSession(for: CoachingGoldenPosition.endangeredKnight.state)
        t3.handle(.identificationTapped(sq("f3")))
        let originalT3 = try turn(from: t3)
        var mirroredT3 = try await preparedSession(
            for: colorMirror(CoachingGoldenPosition.endangeredKnight.state),
            learner: .black
        )
        mirroredT3.handle(.identificationTapped(colorMirror(sq("f3"))))
        let blackT3 = try turn(from: mirroredT3)

        XCTAssertEqual(
            originalT3.primaryMessage,
            "What black piece is attacking your knight?"
        )
        XCTAssertEqual(
            blackT3.primaryMessage,
            "What white piece is attacking your knight?"
        )
        XCTAssertNil(originalT3.observation)
        XCTAssertNil(blackT3.observation)
        XCTAssertEqual(originalT3.instruction, "Tap the black piece.")
        XCTAssertEqual(blackT3.instruction, "Tap the white piece.")
        assertMatchingStructureAndMirroredFocus(originalT3, blackT3)

        let originalT11 = try await opponentAnswerTurn(
            state: CoachingGoldenPosition.exposedQueen.state,
            move: CoachingGoldenMoves.exposesQueen,
            learner: .white,
            answer: CoachingGoldenMoves.rookTakesQueen.from
        )
        let blackT11 = try await opponentAnswerTurn(
            state: colorMirror(CoachingGoldenPosition.exposedQueen.state),
            move: colorMirror(CoachingGoldenMoves.exposesQueen),
            learner: .black,
            answer: colorMirror(CoachingGoldenMoves.rookTakesQueen.from)
        )

        XCTAssertNil(originalT11.observation)
        XCTAssertNil(blackT11.observation)
        XCTAssertEqual(
            originalT11.primaryMessage,
            "Black's rook could take your queen."
        )
        XCTAssertEqual(
            blackT11.primaryMessage,
            "White's rook could take your queen."
        )
        XCTAssertEqual(
            originalT11.instruction,
            "Try a different queen move."
        )
        XCTAssertEqual(
            blackT11.instruction,
            "Try a different queen move."
        )
        assertMatchingStructureAndMirroredFocus(originalT11, blackT11)
    }

    func testCanonicalT2ClearsSafeAndTakeBeforeWake() async throws {
        var session = try await preparedSession(for: .readyToCastle)

        XCTAssertEqual(
            session.presentation?.primaryMessage,
            "Which of your pieces is in danger?"
        )

        session.handle(.actionChosen(.noAnswer))

        XCTAssertEqual(
            session.presentation?.primaryMessage,
            "Can one of your pieces safely take a black piece?"
        )

        session.handle(.actionChosen(.noAnswer))

        XCTAssertEqual(session.presentation?.primaryMessage, "Your king is ready to castle.")
        XCTAssertEqual(
            session.presentation?.instruction,
            "Move your king two squares toward the rook."
        )
    }

    private func expectedTurn(_ branch: CoachingGoldenCase) -> CoachingGoldenTurn {
        let immediateBoundary =
            "Black cannot check your king or win a piece next."
        let openingAsk =
            "A center pawn or knight is a simple way to start."
        let openingInstruction =
            "Tap a center pawn or knight."
        let safeAsk = "Which of your pieces is in danger?"
        let safeInstruction = "Tap your piece."
        let takeAsk = "Can one of your pieces safely take a black piece?"

        switch branch {
        case .t1Entry:
            return expected(
                primaryMessage: openingAsk,
                instruction: openingInstruction,
                actions: [.hint, .stop],
                boardTask: .move,
                routine: wakeRoutine
            )
        case .t1BlockedRook:
            return expected(
                observation: "Your pawn blocks that rook.",
                primaryMessage: openingAsk,
                instruction: openingInstruction,
                actions: [.hint, .stop],
                hintIsPrimary: true,
                boardTask: .move,
                routine: wakeRoutine
            )
        case .t1FlankPawn:
            return expected(
                observation: "That pawn is outside the center.",
                primaryMessage: openingAsk,
                instruction: openingInstruction,
                actions: [.hint, .stop],
                hintIsPrimary: true,
                boardTask: .move,
                routine: wakeRoutine
            )
        case .t1Hint:
            return expected(
                primaryMessage: "Here are the four pieces you can try.",
                instruction: "Tap a highlighted piece.",
                hint: .candidatePieces,
                actions: [.hint, .stop],
                boardTask: .move,
                routine: wakeRoutine,
                candidates: ["b1", "d2", "e2", "g1"],
                pulseID: 1
            )
        case .t1KnightSelected:
            return expected(
                primaryMessage: "Moving this knight is called developing it.",
                instruction: "Move the knight.",
                actions: [.hint, .stop],
                boardTask: .move,
                routine: wakeRoutine
            )
        case .t1PreferredKnight:
            return completion(
                primaryMessage: "You developed your knight toward the center."
            )
        case .t1EdgeKnight:
            return completion(
                primaryMessage: "You developed your knight away from the center, giving it fewer moves."
            )
        case .t1CenterPawn:
            return completion(
                primaryMessage: "Your center pawn moved forward and helps control the center."
            )
        case .t1OutsidePawnMove:
            return completion(
                primaryMessage: "That move seems safe, but a center pawn or knight is a simpler start."
            )

        case .t2Entry:
            return expected(
                observation: "There is no safe capture here.",
                primaryMessage: "Your king is ready to castle.",
                instruction: "Move your king two squares toward the rook.",
                actions: [.hint, .stop],
                boardTask: .move,
                routine: wakeRoutine,
                emphasized: ["e1"]
            )
        case .t2OneSquareKingMove:
            return expected(
                primaryMessage: "What could Black do next?",
                instruction: "Tap a black piece that could check your king or win one of your pieces.",
                actions: [.looksSafe, .stop],
                boardTask: .identify(allowsMoveRevision: true)
            )
        case .t2KnightSwitch:
            return expected(
                primaryMessage: "This knight can be developed.",
                instruction: "Move the knight.",
                actions: [.hint, .stop],
                boardTask: .move,
                routine: wakeRoutine
            )
        case .t2Castle:
            return completion(
                observation: immediateBoundary,
                primaryMessage: "You castled, moving your king toward safety and activating your rook."
            )

        case .t3Entry:
            return expected(
                primaryMessage: safeAsk,
                instruction: safeInstruction,
                actions: [.hint, .stop],
                boardTask: .identify(allowsMoveRevision: false),
                routine: safeRoutine
            )
        case .t3WrongOwnPiece:
            return expected(
                observation: "That king is safe.",
                primaryMessage: safeAsk,
                instruction: safeInstruction,
                actions: [.hint, .stop],
                hintIsPrimary: true,
                boardTask: .identify(allowsMoveRevision: false),
                routine: safeRoutine
            )
        case .t3Target:
            return expected(
                primaryMessage: "What black piece is attacking your knight?",
                instruction: "Tap the black piece.",
                actions: [.hint, .stop],
                boardTask: .identify(allowsMoveRevision: false),
                routine: safeRoutine,
                emphasized: ["f3"]
            )
        case .t3WrongAttacker:
            return expected(
                observation: "That king isn’t attacking your knight.",
                primaryMessage: "What black piece is attacking your knight?",
                instruction: "Tap the black piece.",
                actions: [.hint, .stop],
                hintIsPrimary: true,
                boardTask: .identify(allowsMoveRevision: false),
                routine: safeRoutine,
                emphasized: ["f3"]
            )
        case .t3Attacker:
            return expected(
                primaryMessage: "The pawn attacks your knight.",
                instruction: "Move, protect, or trade your knight.",
                actions: [.hint, .stop],
                boardTask: .move,
                routine: safeRoutine,
                emphasized: ["e4", "f3"],
                paths: [("e4", "f3", .attacker)]
            )
        case .t3UnresolvedMove:
            return expected(
                observation: "The pawn could still take your knight after that move.",
                primaryMessage: "The pawn attacks your knight.",
                instruction: "Move, protect, or trade your knight.",
                actions: [.stop],
                boardTask: .move,
                routine: safeRoutine
            )
        case .t3ResolvedMove:
            return completion(
                primaryMessage: "Your knight is out of the pawn's attack and safe."
            )

        case .t4LowerPriorityPawn:
            return expected(
                observation: "You found a threatened pawn, but losing the knight would cost more.",
                primaryMessage: "Which piece should you help first?",
                instruction: safeInstruction,
                actions: [.hint, .stop],
                hintIsPrimary: true,
                boardTask: .identify(allowsMoveRevision: false),
                routine: safeRoutine
            )
        case .t4PrimaryKnight:
            return expected(
                primaryMessage: "What black piece is attacking your knight?",
                instruction: "Tap the black piece.",
                actions: [.hint, .stop],
                boardTask: .identify(allowsMoveRevision: false),
                routine: safeRoutine,
                emphasized: ["f3"]
            )

        case .t5PawnDanger:
            return expected(
                primaryMessage: safeAsk,
                instruction: safeInstruction,
                actions: [.hint, .stop],
                boardTask: .identify(allowsMoveRevision: false),
                routine: safeRoutine
            )
        case .t5PawnResolved:
            return completion(
                primaryMessage: "Your pawn is out of the bishop's path and safe."
            )
        case .t5ProtectedTap:
            return expected(
                observation: "The knight attacks your pawn, but another pawn protects it.",
                primaryMessage: takeAsk,
                instruction: "Make the capture, or choose No safe capture.",
                actions: [.noAnswer, .stop],
                noAnswerTitle: "No safe capture",
                boardTask: .move,
                routine: takeRoutine,
                emphasized: ["f6", "g4", "h3"],
                paths: [
                    ("f6", "g4", .attacker),
                    ("h3", "g4", .defender),
                ]
            )
        case .t5ProtectedAbsence:
            return expected(
                observation: "No piece needs help right now.",
                primaryMessage: takeAsk,
                instruction: "Make the capture, or choose No safe capture.",
                actions: [.noAnswer, .stop],
                noAnswerTitle: "No safe capture",
                boardTask: .move,
                routine: takeRoutine
            )

        case .t6WrongSource:
            return expected(
                observation: "That piece has no safe capture here.",
                primaryMessage: takeAsk,
                instruction: "Try another piece, or choose No safe capture.",
                actions: [.noAnswer, .hint, .stop],
                noAnswerTitle: "No safe capture",
                hintIsPrimary: true,
                boardTask: .move,
                routine: takeRoutine
            )
        case .t6Hint:
            return expected(
                observation: "Your bishop has a safe capture.",
                primaryMessage: takeAsk,
                instruction: "Tap the highlighted white piece.",
                hint: .candidatePieces,
                actions: [.hint, .stop],
                boardTask: .move,
                routine: takeRoutine,
                candidates: ["c4"],
                pulseID: 1
            )
        case .t6Capture:
            return completion(
                primaryMessage: "Your bishop took a rook, and Black cannot take the bishop back."
            )
        case .t7UnsafeCapture:
            return expected(
                observation: "Black's king could take your bishop, so you would lose it for a pawn.",
                primaryMessage: takeAsk,
                instruction: "Change your move, or choose No safe capture.",
                actions: [.noAnswer, .stop],
                noAnswerTitle: "No safe capture",
                boardTask: .move,
                routine: takeRoutine
            )
        case .t7NoSafeCapture:
            return expected(
                observation: "There is no safe capture here.",
                primaryMessage: "What move would you like to try?",
                instruction: "Move a piece.",
                actions: [.stop],
                boardTask: .move
            )

        case .t8AddsDefender:
            return completion(
                observation: immediateBoundary,
                primaryMessage: "Your pawn now protects the pawn from the attacking knight."
            )

        case .t9Entry:
            return expected(
                primaryMessage: "Your knight can attack Black's rook.",
                instruction: "Move the knight to attack the rook.",
                actions: [.hint, .stop],
                boardTask: .move,
                routine: wakeRoutine,
                emphasized: ["a1", "d4"]
            )
        case .t9Hint:
            return expected(
                primaryMessage: "Both highlighted squares let the knight attack the rook.",
                instruction: "Move the knight to one of the highlighted squares.",
                hint: .candidateMoves,
                actions: [.stop],
                boardTask: .move,
                routine: wakeRoutine,
                emphasized: ["a1", "d4"],
                candidates: ["b3", "c2"],
                paths: [
                    ("a1", "b3", .candidate),
                    ("a1", "c2", .candidate),
                ],
                pulseID: 1
            )
        case .t9Completed:
            return completion(
                observation: "That rook could check along your back row, but your knight move still works.",
                primaryMessage: "Your knight now attacks Black's rook.",
                emphasized: ["b3", "d4"],
                paths: [("b3", "d4", .attacker)]
            )

        case .t10Entry:
            return expected(
                primaryMessage: "Your knight has only two moves in this corner.",
                instruction: "Move it closer to the center.",
                actions: [.hint, .stop],
                boardTask: .move,
                routine: wakeRoutine,
                emphasized: ["a1"]
            )
        case .t10Completed:
            return completion(
                primaryMessage: "Your knight can now reach six squares instead of two."
            )

        case .t11Safe:
            return completion(
                primaryMessage: "You developed your knight toward the center."
            )
        case .t11QueenLoss:
            return expected(
                primaryMessage: "Black's rook could take your queen.",
                instruction: "Try a different queen move.",
                actions: [.hint, .stop],
                boardTask: .move,
                emphasized: ["d4", "d8"],
                paths: [("d8", "d4", .attacker)]
            )
        case .t11IncorrectLooksSafe:
            return expected(
                observation: "Black's rook could take your queen.",
                primaryMessage: "What could Black do next?",
                instruction: "Tap the black rook, or choose Hint.",
                actions: [.hint, .stop],
                hintIsPrimary: true,
                boardTask: .identify(allowsMoveRevision: true)
            )
        case .t11HarmlessCheck:
            return completion(
                observation: "That rook could check along your back row, but your knight move still works.",
                primaryMessage: "Your knight moved closer to the center.",
                emphasized: ["a8", "a1", "g1"],
                paths: [
                    ("a8", "a1", .attacker),
                    ("a1", "g1", .attacker),
                ]
            )
        case .t11UnsafeBishopEntry:
            return expected(
                primaryMessage: "What could Black do next?",
                instruction: "Tap the black piece that could win your bishop.",
                actions: [.looksSafe, .hint, .stop],
                boardTask: .identify(allowsMoveRevision: true)
            )
        case .t11UnsafeBishopFound:
            return expected(
                primaryMessage: "Black's pawn could take your bishop.",
                instruction: "Try a different bishop move.",
                actions: [.hint, .stop],
                boardTask: .move,
                emphasized: ["a6", "b7"],
                paths: [("b7", "a6", .attacker)]
            )
        case .t11BenignCaptureTap:
            return expected(
                observation: "That bishop attacks your pawn, but the pawn is protected.",
                primaryMessage: "What could White do next?",
                instruction: "Tap a white piece that could check your king or win one of your pieces.",
                actions: [.looksSafe, .hint, .stop],
                hintIsPrimary: true,
                boardTask: .identify(allowsMoveRevision: true),
                emphasized: ["c4", "e6"],
                paths: [("c4", "e6", .attacker)]
            )
        case .t11BenignCaptureLooksSafe:
            return completion(
                primaryMessage: "That move seems safe."
            )

        case .t12CheckLocate:
            return expected(
                primaryMessage: "What piece is checking your king?",
                instruction: "Tap the checking piece.",
                actions: [.hint, .stop],
                boardTask: .identify(allowsMoveRevision: false)
            )
        case .t12WrongChecker:
            return expected(
                observation: "That king isn’t giving check.",
                primaryMessage: "What piece is checking your king?",
                instruction: "Tap the checking piece.",
                actions: [.hint, .stop],
                hintIsPrimary: true,
                boardTask: .identify(allowsMoveRevision: false)
            )
        case .t12Capture:
            return completion(
                primaryMessage: "Your bishop took the checking rook, so your king is safe."
            )
        case .t12Block:
            return expected(
                observation: "That rook could check your king, but your bishop move still works.",
                primaryMessage: "What could Black do next?",
                instruction: "Tap the black rook, or choose Hint.",
                actions: [.hint, .stop],
                hintIsPrimary: true,
                boardTask: .identify(allowsMoveRevision: true)
            )
        case .t12KingMove:
            return expected(
                observation: "That rook could check along your back row, but your king move still works.",
                primaryMessage: "What could Black do next?",
                instruction: "Tap the black rook, or choose Hint.",
                actions: [.hint, .stop],
                hintIsPrimary: true,
                boardTask: .identify(allowsMoveRevision: true)
            )
        case .t12UnsupportedEntry:
            return expected(
                primaryMessage: "What move would you like to try?",
                instruction: "Move a piece.",
                actions: [.stop],
                boardTask: .move
            )
        case .t12UnsupportedSafeMove:
            return completion(
                primaryMessage: "That move seems safe."
            )
        }
    }

    private var safeRoutine: [CoachingRoutineState] {
        [.safeCurrent, .takePending, .wakePending]
    }

    private var takeRoutine: [CoachingRoutineState] {
        [.safeCleared, .takeCurrent, .wakePending]
    }

    private var wakeRoutine: [CoachingRoutineState] {
        [.safeCleared, .takeCleared, .wakeCurrent]
    }

    private func completion(
        observation: String? = nil,
        primaryMessage: String,
        emphasized: [String] = [],
        paths: [(String, String, CoachFocusPath.Role)] = []
    ) -> CoachingGoldenTurn {
        expected(
            observation: observation,
            primaryMessage: primaryMessage,
            instruction: "Play it, or try another move.",
            actions: [.done, .keepLooking, .stop],
            emphasized: emphasized,
            paths: paths
        )
    }

    private func expected(
        observation: String? = nil,
        primaryMessage: String,
        instruction: String? = nil,
        hint: CoachingHint? = nil,
        actions: [CoachingAction],
        noAnswerTitle: String = "No piece needs help",
        hintIsPrimary: Bool = false,
        boardTask: CoachingBoardTask = .none,
        routine: [CoachingRoutineState] = [],
        emphasized: [String] = [],
        candidates: [String] = [],
        paths: [(String, String, CoachFocusPath.Role)] = [],
        pulseID: Int = 0
    ) -> CoachingGoldenTurn {
        CoachingGoldenTurn(
            observation: observation,
            primaryMessage: primaryMessage,
            instruction: instruction,
            hint: hint,
            actionPresentations: actions.map { action in
                expectedActionPresentation(
                    action,
                    noAnswerTitle: noAnswerTitle,
                    hintIsPrimary: hintIsPrimary
                )
            },
            boardTask: boardTask,
            routine: routine,
            emphasizedSquares: Set(emphasized.map(sq)),
            candidateSquares: Set(candidates.map(sq)),
            paths: Set(paths.map { source, destination, role in
                CoachFocusPath(
                    source: sq(source),
                    destination: sq(destination),
                    role: role
                )
            }),
            pulseID: pulseID
        )
    }

    private func expectedActionPresentation(
        _ action: CoachingAction,
        noAnswerTitle: String,
        hintIsPrimary: Bool
    ) -> CoachingActionPresentation {
        switch action {
        case .noAnswer:
            return CoachingActionPresentation(
                action: action,
                title: noAnswerTitle,
                accessibilityLabel: noAnswerTitle,
                prominence: .primary
            )
        case .looksSafe:
            return CoachingActionPresentation(
                action: action,
                title: "Looks safe",
                accessibilityLabel: "Looks safe",
                prominence: .primary
            )
        case .hint:
            return CoachingActionPresentation(
                action: action,
                title: "Hint",
                accessibilityLabel: "Show a hint",
                prominence: hintIsPrimary ? .primary : .secondary
            )
        case .stop:
            return CoachingActionPresentation(
                action: action,
                title: "Close help",
                accessibilityLabel: "Close coaching help",
                prominence: .quiet
            )
        case .done:
            return CoachingActionPresentation(
                action: action,
                title: "Play this move",
                accessibilityLabel: "Play this move",
                prominence: .primary
            )
        case .keepLooking:
            return CoachingActionPresentation(
                action: action,
                title: "Try another move",
                accessibilityLabel: "Try another move",
                prominence: .secondary
            )
        }
    }

    private func goldenTurn(_ branch: CoachingGoldenCase) async throws -> CoachingGoldenTurn {
        let presentation = try await goldenPresentation(branch)
        return turn(from: presentation)
    }

    private func goldenPresentation(
        _ branch: CoachingGoldenCase
    ) async throws -> CoachingPresentation {
        var session: CoachingSession
        switch branch {
        case .t1Entry:
            session = try await preparedSession(for: .starting)

        case .t1BlockedRook:
            session = try await preparedSession(for: .starting)
            session.handle(.interactionChanged(snapshot(selected: sq("a1"))))

        case .t1FlankPawn:
            session = try await preparedSession(for: .starting)
            session.handle(.interactionChanged(snapshot(selected: sq("a2"))))

        case .t1Hint:
            session = try await preparedSession(for: .starting)
            session.handle(.actionChosen(.hint))

        case .t1KnightSelected:
            session = try await preparedSession(for: .starting)
            session.handle(.interactionChanged(snapshot(selected: sq("b1"))))

        case .t1PreferredKnight:
            session = try await preparedSession(for: .starting)
            try await complete(
                Move(from: sq("g1"), to: sq("f3")),
                origin: .wake,
                position: .starting,
                in: &session
            )

        case .t1EdgeKnight:
            session = try await preparedSession(for: .starting)
            try await complete(
                Move(from: sq("g1"), to: sq("h3")),
                origin: .wake,
                position: .starting,
                in: &session
            )

        case .t1CenterPawn:
            session = try await preparedSession(for: .starting)
            try await complete(
                Move(from: sq("e2"), to: sq("e4")),
                origin: .wake,
                position: .starting,
                in: &session
            )

        case .t1OutsidePawnMove:
            session = try await preparedSession(for: .starting)
            try await complete(
                CoachingGoldenMoves.outsidePawn,
                origin: .wake,
                position: .starting,
                in: &session
            )

        case .t2Entry:
            session = try await preparedT2WakeSession()

        case .t2OneSquareKingMove:
            session = try await preparedT2WakeSession()
            try await stage(
                Move(from: sq("e1"), to: sq("f1")),
                origin: .wake,
                position: .readyToCastle,
                in: &session
            )

        case .t2KnightSwitch:
            session = try await preparedT2WakeSession()
            session.handle(.interactionChanged(snapshot(selected: sq("b1"))))

        case .t2Castle:
            session = try await preparedT2WakeSession()
            try await stage(
                CoachingGoldenMoves.castle,
                origin: .wake,
                position: .readyToCastle,
                in: &session
            )
            XCTAssertEqual(
                session.presentation?.primaryMessage,
                "What could Black do next?"
            )
            session.handle(.actionChosen(.looksSafe))

        case .t3Entry:
            session = try await preparedSession(for: .endangeredKnight)

        case .t3WrongOwnPiece:
            session = try await preparedSession(for: .endangeredKnight)
            session.handle(.identificationTapped(sq("g1")))

        case .t3Target:
            session = try await preparedSession(for: .endangeredKnight)
            session.handle(.identificationTapped(sq("f3")))

        case .t3WrongAttacker:
            session = try await preparedSession(for: .endangeredKnight)
            session.handle(.identificationTapped(sq("f3")))
            session.handle(.identificationTapped(sq("g8")))

        case .t3Attacker:
            session = try await preparedSession(for: .endangeredKnight)
            session.handle(.identificationTapped(sq("f3")))
            session.handle(.identificationTapped(sq("e4")))

        case .t3UnresolvedMove:
            session = try await preparedSession(for: .endangeredKnight)
            session.handle(.identificationTapped(sq("f3")))
            session.handle(.identificationTapped(sq("e4")))
            try await stage(
                Move(from: sq("g1"), to: sq("h1")),
                origin: .safe,
                position: .endangeredKnight,
                in: &session
            )

        case .t3ResolvedMove:
            session = try await preparedSession(for: .endangeredKnight)
            session.handle(.identificationTapped(sq("f3")))
            session.handle(.identificationTapped(sq("e4")))
            try await complete(
                Move(from: sq("f3"), to: sq("g5")),
                origin: .safe,
                position: .endangeredKnight,
                in: &session
            )

        case .t4LowerPriorityPawn:
            session = try await preparedSession(for: .twoDangerPriorities)
            session.handle(.identificationTapped(sq("a3")))

        case .t4PrimaryKnight:
            session = try await preparedSession(for: .twoDangerPriorities)
            session.handle(.identificationTapped(sq("f3")))

        case .t5PawnDanger:
            session = try await preparedSession(for: .endangeredPawn)

        case .t5PawnResolved:
            session = try await preparedSession(for: .endangeredPawn)
            session.handle(.identificationTapped(sq("e3")))
            session.handle(.identificationTapped(sq("b6")))
            try await complete(
                CoachingGoldenMoves.pawnEscapes,
                origin: .safe,
                position: .endangeredPawn,
                in: &session
            )

        case .t5ProtectedTap:
            session = try await preparedSession(for: .protectedPawn)
            session.handle(.identificationTapped(sq("g4")))

        case .t5ProtectedAbsence:
            session = try await preparedSession(for: .protectedPawn)
            session.handle(.actionChosen(.noAnswer))

        case .t6WrongSource:
            session = try await preparedSession(for: .winningCapture)
            session.handle(.interactionChanged(snapshot(selected: sq("g1"))))

        case .t6Hint:
            session = try await preparedSession(for: .winningCapture)
            session.handle(.actionChosen(.hint))

        case .t6Capture:
            session = try await preparedSession(for: .winningCapture)
            try await complete(
                CoachingGoldenMoves.bishopWinsRook,
                origin: .take,
                position: .winningCapture,
                in: &session
            )

        case .t7UnsafeCapture:
            session = try await preparedSession(for: .losingCapture)
            try await stage(
                CoachingGoldenMoves.bishopTakesPawn,
                origin: .take,
                position: .losingCapture,
                in: &session
            )

        case .t7NoSafeCapture:
            session = try await preparedSession(for: .losingCapture)
            session.handle(.actionChosen(.noAnswer))

        case .t8AddsDefender:
            session = try await preparedSession(for: .protectPawn)
            session.handle(.identificationTapped(sq("g4")))
            session.handle(.identificationTapped(sq("f6")))
            try await complete(
                CoachingGoldenMoves.addsPawnDefender,
                origin: .safe,
                position: .protectPawn,
                in: &session
            )

        case .t9Entry:
            session = try await preparedSession(for: .createRookThreat)

        case .t9Hint:
            session = try await preparedSession(for: .createRookThreat)
            session.handle(.actionChosen(.hint))

        case .t9Completed:
            session = try await preparedSession(for: .createRookThreat)
            try await stage(
                CoachingGoldenMoves.knightThreatB3,
                origin: .wake,
                position: .createRookThreat,
                in: &session
            )
            session.handle(.identificationTapped(sq("d4")))

        case .t10Entry:
            session = try await preparedSession(for: .cornerKnight)

        case .t10Completed:
            session = try await preparedSession(for: .cornerKnight)
            try await complete(
                CoachingGoldenMoves.knightThreatB3,
                origin: .wake,
                position: .cornerKnight,
                in: &session
            )

        case .t11Safe:
            session = try await preparedSession(for: .starting)
            try await complete(
                Move(from: sq("g1"), to: sq("f3")),
                origin: .wake,
                position: .starting,
                in: &session
            )

        case .t11QueenLoss:
            session = try await tentativeSession(
                state: CoachingGoldenPosition.exposedQueen.state,
                move: CoachingGoldenMoves.exposesQueen,
                learner: .white
            )
            session.handle(
                .identificationTapped(CoachingGoldenMoves.rookTakesQueen.from)
            )

        case .t11IncorrectLooksSafe:
            session = try await tentativeSession(
                state: CoachingGoldenPosition.exposedQueen.state,
                move: CoachingGoldenMoves.exposesQueen,
                learner: .white
            )
            session.handle(.actionChosen(.looksSafe))

        case .t11HarmlessCheck:
            session = try await tentativeSession(
                state: CoachingGoldenPosition.harmlessCheck.state,
                move: CoachingGoldenMoves.developsKnight,
                learner: .white
            )
            session.handle(.identificationTapped(CoachingGoldenMoves.rookChecks.from))

        case .t11UnsafeBishopEntry:
            session = try await tentativeSession(
                state: CoachingGoldenPosition.openingBishopCanBeTaken.state,
                move: CoachingGoldenMoves.bishopToA6,
                learner: .white
            )

        case .t11UnsafeBishopFound:
            session = try await tentativeSession(
                state: CoachingGoldenPosition.openingBishopCanBeTaken.state,
                move: CoachingGoldenMoves.bishopToA6,
                learner: .white
            )
            session.handle(.identificationTapped(sq("b7")))

        case .t11BenignCaptureTap:
            session = try await tentativeSession(
                state: CoachingGoldenPosition.protectedPawnUnderBishopAttack.state,
                move: CoachingGoldenMoves.blackPawnToE6,
                learner: .black
            )
            session.handle(.identificationTapped(sq("c4")))

        case .t11BenignCaptureLooksSafe:
            session = try await tentativeSession(
                state: CoachingGoldenPosition.protectedPawnUnderBishopAttack.state,
                move: CoachingGoldenMoves.blackPawnToE6,
                learner: .black
            )
            session.handle(.identificationTapped(sq("c4")))
            session.handle(.actionChosen(.looksSafe))

        case .t12CheckLocate:
            session = try await preparedSession(for: .forcedCheck)

        case .t12WrongChecker:
            session = try await preparedSession(for: .forcedCheck)
            session.handle(.identificationTapped(sq("a8")))

        case .t12Capture:
            session = try await preparedSession(for: .forcedCheck)
            session.handle(.identificationTapped(sq("e8")))
            try await complete(
                CoachingGoldenMoves.capturesChecker,
                origin: .check,
                position: .forcedCheck,
                in: &session
            )

        case .t12Block:
            session = try await preparedSession(for: .forcedCheck)
            session.handle(.identificationTapped(sq("e8")))
            try await complete(
                CoachingGoldenMoves.blocksChecker,
                origin: .check,
                position: .forcedCheck,
                in: &session
            )

        case .t12KingMove:
            session = try await preparedSession(for: .forcedCheck)
            session.handle(.identificationTapped(sq("e8")))
            try await complete(
                Move(from: sq("e1"), to: sq("d1")),
                origin: .check,
                position: .forcedCheck,
                in: &session
            )

        case .t12UnsupportedEntry:
            session = try await preparedSession(for: .unsupportedEndgame)

        case .t12UnsupportedSafeMove:
            session = try await preparedSession(for: .unsupportedEndgame)
            try await complete(
                Move(from: sq("d4"), to: sq("d5")),
                origin: .fallback,
                position: .unsupportedEndgame,
                in: &session
            )

        }

        return try XCTUnwrap(
            session.presentation,
            "Missing presentation for \(branch.rawValue)"
        )
    }

    private func turn(from presentation: CoachingPresentation) -> CoachingGoldenTurn {
        CoachingGoldenTurn(
            observation: presentation.observation,
            primaryMessage: presentation.primaryMessage,
            instruction: presentation.instruction,
            hint: presentation.hint,
            actionPresentations: presentation.actions,
            boardTask: presentation.boardTask,
            routine: presentation.routine,
            emphasizedSquares: presentation.focus.emphasizedSquares,
            candidateSquares: presentation.focus.candidateSquares,
            paths: presentation.focus.paths,
            pulseID: presentation.focus.pulseID
        )
    }

    private func assertCoherent(
        _ presentation: CoachingPresentation,
        branch: CoachingGoldenCase,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            presentation.primaryMessage
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty,
            "Empty headline for \(branch.rawValue)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(presentation.actions.map(\.action)).count,
            presentation.actions.count,
            "Duplicate action for \(branch.rawValue)",
            file: file,
            line: line
        )
        if presentation.instruction?.contains("highlighted") == true {
            XCTAssertFalse(
                presentation.focus.candidateSquares.isEmpty
                    && presentation.focus.paths.isEmpty,
                "Highlighted instruction has no focus for \(branch.rawValue)",
                file: file,
                line: line
            )
        }
        let namedActions: [(phrase: String, action: CoachingAction)] = [
            ("No piece needs help", .noAnswer),
            ("No safe capture", .noAnswer),
            ("Looks safe", .looksSafe),
            ("Hint", .hint),
            ("Play this move", .done),
            ("Try another move", .keepLooking),
            ("Close help", .stop),
        ]
        for namedAction in namedActions where
            presentation.instruction?.localizedCaseInsensitiveContains(
                namedAction.phrase
            ) == true {
            XCTAssertTrue(
                presentation.actions.contains { $0.action == namedAction.action },
                "Instruction names hidden action \(namedAction.phrase) for \(branch.rawValue)",
                file: file,
                line: line
            )
        }
    }

    private func normalizedClauses(_ text: String?) -> Set<String> {
        guard let text else { return [] }
        return Set(text
            .split(whereSeparator: { ".!?;".contains($0) })
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
    }

    private func normalizedText(_ text: String?) -> String? {
        guard let text else { return nil }
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }
        guard !words.isEmpty else { return nil }
        return words.joined(separator: " ")
    }

    private func hasContainedMeaning(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = normalizedText(lhs),
              let rhs = normalizedText(rhs),
              min(lhs.split(separator: " ").count, rhs.split(separator: " ").count) >= 3
        else {
            return false
        }
        return lhs.contains(rhs) || rhs.contains(lhs)
    }

    private func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private func sentenceCount(_ text: String) -> Int {
        text.filter { ".!?".contains($0) }.count
    }

    private func assertCompact(
        _ presentation: CoachingPresentation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let mandatedOpeningCompletion =
            "That move seems safe, but a center pawn or knight is a simpler start."
        XCTAssertLessThanOrEqual(
            wordCount(presentation.primaryMessage),
            presentation.primaryMessage == mandatedOpeningCompletion ? 14 : 12,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            sentenceCount(presentation.primaryMessage),
            1,
            file: file,
            line: line
        )
        if let instruction = presentation.instruction {
            XCTAssertLessThanOrEqual(wordCount(instruction), 16, file: file, line: line)
            XCTAssertLessThanOrEqual(sentenceCount(instruction), 1, file: file, line: line)
        }
        if let observation = presentation.observation {
            XCTAssertLessThanOrEqual(wordCount(observation), 18, file: file, line: line)
            XCTAssertLessThanOrEqual(sentenceCount(observation), 1, file: file, line: line)
        }
        XCTAssertTrue(
            normalizedClauses(presentation.primaryMessage)
                .isDisjoint(with: normalizedClauses(presentation.instruction)),
            file: file,
            line: line
        )
        XCTAssertTrue(
            normalizedClauses(presentation.primaryMessage)
                .isDisjoint(with: normalizedClauses(presentation.observation)),
            file: file,
            line: line
        )
        XCTAssertTrue(
            normalizedClauses(presentation.instruction)
                .isDisjoint(with: normalizedClauses(presentation.observation)),
            file: file,
            line: line
        )
        XCTAssertFalse(
            hasContainedMeaning(presentation.primaryMessage, presentation.instruction),
            file: file,
            line: line
        )
        XCTAssertFalse(
            hasContainedMeaning(presentation.primaryMessage, presentation.observation),
            file: file,
            line: line
        )
        XCTAssertFalse(
            hasContainedMeaning(presentation.instruction, presentation.observation),
            file: file,
            line: line
        )
    }

    private func assertNoProhibitedChildFacingCopy(
        _ values: [String],
        source: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let prohibited = [
            "part of this problem", "big danger", "job", "tap the problem",
            "nothing urgent stands out", "clear plan", "reply to notice",
            "win some material", "come into the game", "attack something",
            "protect another piece", "more useful place", "verified purpose",
            "qualifying issue", "immediate-response scan", "material",
            "cannot name a purpose", "bring a new piece into the game",
            "i can check immediate dangers", "i do not have a confident plan",
            "i do not see an immediate",
        ]
        let copy = values.joined(separator: " ").lowercased()
        XCTAssertEqual(
            prohibited.filter(copy.contains),
            [],
            "Found prohibited copy in \(source)",
            file: file,
            line: line
        )
    }

    private func preparedSession(
        for position: CoachingGoldenPosition
    ) async throws -> CoachingSession {
        try await preparedSession(for: position.state)
    }

    private func preparedSession(for state: GameState) async throws -> CoachingSession {
        try await preparedSession(for: state, learner: .white)
    }

    private func preparedSession(
        for state: GameState,
        learner: PieceColor
    ) async throws -> CoachingSession {
        let interaction = snapshot()
        var session = CoachingSession(
            learner: learner,
            interaction: interaction,
            initialContext: .start
        )
        let advice = try await LocalCoachingAdvisor().advice(for: CoachingRequest(
            committedState: state,
            tentativeMove: nil,
            learner: learner,
            positionRevision: interaction.positionRevision,
            context: .start
        ))
        session.receive(advice, interaction: interaction)
        return session
    }

    @MainActor
    private func reportedPresentation(
        for path: ReportedMovePath,
        history: ReportedInteractionHistory?
    ) async throws -> ReportedPathResult {
        let session = GameSession(
            state: path.state,
            coachingAdvisor: LocalCoachingAdvisor()
        )
        session.startCoaching()
        await session.resolvePendingCoachingAdvice()

        switch history {
        case .knight:
            session.select(path.knight)
        case .rook:
            session.select(path.rook)
        case .friendly:
            session.select(path.friendly)
        case .enemy:
            session.select(path.enemy)
        case .emptySquare:
            XCTAssertNil(session.tapEmptySquare(at: path.empty))
        case .hint:
            if session.coachingPresentation?.actions.map(\.action).contains(.hint) != true,
               let hintSource = path.hintSource {
                stage(path.move, in: session)
                await session.resolvePendingCoachingAdvice()
                XCTAssertTrue(session.handleCoachingSquareTap(hintSource))
            }
            XCTAssertTrue(
                session.coachingPresentation?.actions.map(\.action).contains(.hint) == true,
                "\(path.name) did not expose Hint before the reported move"
            )
            _ = session.chooseCoachingAction(.hint)
        case .replacement:
            stage(path.replacement, in: session)
            await session.resolvePendingCoachingAdvice()
        case nil:
            break
        }

        stage(path.move, in: session)
        await session.resolvePendingCoachingAdvice()
        XCTAssertEqual(session.state.moveHistory, [], "\(path.name) committed during coaching")
        return ReportedPathResult(
            presentation: try XCTUnwrap(
                session.coachingPresentation,
                "\(path.name) had no presentation after \(history?.rawValue ?? "direct") history"
            ),
            moveHistory: session.state.moveHistory
        )
    }

    @MainActor
    private func stage(_ move: Move, in session: GameSession) {
        session.select(move.from)
        XCTAssertEqual(session.moveSelectedPiece(to: move.to), .moved)
    }

    private func tentativeSession(
        state: GameState,
        move: Move,
        learner: PieceColor
    ) async throws -> CoachingSession {
        let interaction = snapshot(selected: move.to, tentativeMove: move)
        var session = CoachingSession(
            learner: learner,
            interaction: interaction,
            initialContext: .tentativeMove(origin: .fallback)
        )
        let advice = try await LocalCoachingAdvisor().advice(for: CoachingRequest(
            committedState: state,
            tentativeMove: move,
            learner: learner,
            positionRevision: interaction.positionRevision,
            context: .tentativeMove(origin: .fallback)
        ))
        session.receive(advice, interaction: interaction)
        return session
    }

    private func opponentAnswerTurn(
        state: GameState,
        move: Move,
        learner: PieceColor,
        answer: Square
    ) async throws -> CoachingGoldenTurn {
        var session = try await tentativeSession(state: state, move: move, learner: learner)
        session.handle(.identificationTapped(answer))
        return try turn(from: session)
    }

    private func opponentPromptTurn(
        state: GameState,
        move: Move,
        learner: PieceColor
    ) async throws -> CoachingGoldenTurn {
        let session = try await tentativeSession(
            state: state,
            move: move,
            learner: learner
        )
        return try turn(from: session)
    }

    private func turn(from session: CoachingSession) throws -> CoachingGoldenTurn {
        turn(from: try XCTUnwrap(session.presentation))
    }

    private func assertMirroredFocus(
        _ original: CoachingGoldenTurn,
        _ mirrored: CoachingGoldenTurn,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            mirrored.emphasizedSquares,
            Set(original.emphasizedSquares.map(colorMirror)),
            file: file,
            line: line
        )
        XCTAssertEqual(
            mirrored.candidateSquares,
            Set(original.candidateSquares.map(colorMirror)),
            file: file,
            line: line
        )
        XCTAssertEqual(
            mirrored.paths,
            Set(original.paths.map { path in
                CoachFocusPath(
                    source: colorMirror(path.source),
                    destination: colorMirror(path.destination),
                    role: path.role
                )
            }),
            file: file,
            line: line
        )
    }

    private func assertMatchingStructureAndMirroredFocus(
        _ original: CoachingGoldenTurn,
        _ mirrored: CoachingGoldenTurn,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            mirrored.actionPresentations,
            original.actionPresentations,
            file: file,
            line: line
        )
        XCTAssertEqual(mirrored.hint, original.hint, file: file, line: line)
        XCTAssertEqual(mirrored.boardTask, original.boardTask, file: file, line: line)
        XCTAssertEqual(mirrored.routine, original.routine, file: file, line: line)
        XCTAssertEqual(mirrored.pulseID, original.pulseID, file: file, line: line)
        assertMirroredFocus(original, mirrored, file: file, line: line)
    }

    private func colorMirror(_ square: Square) -> Square {
        Square(file: square.file, rank: 9 - square.rank)
    }

    private func colorMirror(_ move: Move) -> Move {
        Move(
            from: colorMirror(move.from),
            to: colorMirror(move.to),
            special: move.special
        )
    }

    private func colorMirror(_ state: GameState) -> GameState {
        let mirroredPieces = Dictionary(uniqueKeysWithValues: state.board.pieces.map {
            square, piece in
            (colorMirror(square), Piece(kind: piece.kind, color: piece.color.opposite))
        })
        return GameState(
            board: Board(pieces: mirroredPieces),
            sideToMove: state.sideToMove.opposite,
            castlingRights: CastlingRights(
                whiteKingside: state.castlingRights.blackKingside,
                whiteQueenside: state.castlingRights.blackQueenside,
                blackKingside: state.castlingRights.whiteKingside,
                blackQueenside: state.castlingRights.whiteQueenside
            ),
            enPassantTarget: state.enPassantTarget.map(colorMirror)
        )
    }

    private func preparedT2WakeSession() async throws -> CoachingSession {
        var session = try await preparedSession(for: .readyToCastle)
        session.handle(.actionChosen(.noAnswer))
        session.handle(.actionChosen(.noAnswer))
        return session
    }

    private func complete(
        _ move: Move,
        origin: CoachingMoveOrigin,
        position: CoachingGoldenPosition,
        in session: inout CoachingSession
    ) async throws {
        try await complete(
            move,
            origin: origin,
            state: position.state,
            in: &session
        )
    }

    private func complete(
        _ move: Move,
        origin: CoachingMoveOrigin,
        state: GameState,
        in session: inout CoachingSession
    ) async throws {
        try await stage(move, origin: origin, state: state, in: &session)
        session.handle(.actionChosen(.looksSafe))
    }

    private func stage(
        _ move: Move,
        origin: CoachingMoveOrigin,
        position: CoachingGoldenPosition,
        in session: inout CoachingSession
    ) async throws {
        try await stage(
            move,
            origin: origin,
            state: position.state,
            in: &session
        )
    }

    private func stage(
        _ move: Move,
        origin: CoachingMoveOrigin,
        state: GameState,
        learner: PieceColor = .white,
        in session: inout CoachingSession
    ) async throws {
        let interaction = snapshot(selected: move.to, tentativeMove: move)
        session.handle(.interactionChanged(interaction))
        let advice = try await LocalCoachingAdvisor().advice(for: CoachingRequest(
            committedState: state,
            tentativeMove: move,
            learner: learner,
            positionRevision: interaction.positionRevision,
            context: .tentativeMove(origin: origin)
        ))
        session.receive(advice, interaction: interaction)
    }

    private func snapshot(
        selected: Square? = nil,
        tentativeMove: Move? = nil
    ) -> CoachingInteractionSnapshot {
        CoachingInteractionSnapshot(
            selectedSquare: selected,
            tentativeMove: tentativeMove,
            positionRevision: 1
        )
    }
}

private enum ReportedInteractionHistory: String, CaseIterable {
    case knight
    case rook
    case friendly
    case enemy
    case emptySquare
    case hint
    case replacement
}

private struct ReportedMovePath {
    let name: String
    let state: GameState
    let learner: PieceColor
    let move: Move
    let knight: Square
    let rook: Square
    let friendly: Square
    let enemy: Square
    let empty: Square
    let hintSource: Square?
    let replacement: Move
}

private struct ReportedPathResult: Equatable {
    let presentation: CoachingPresentation
    let moveHistory: [Move]
}

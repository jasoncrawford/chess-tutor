import XCTest
@testable import ChessTutor

final class LocalCoachingExplanationSourceTests: XCTestCase {
    private let source = LocalCoachingExplanationSource()

    func testSafeLocatePresentationAsksForBoardTap() {
        let presentation = source.presentation(
            for: context(
                prompt: .safeLocate,
                routine: [.safeCurrent, .takePending, .wakePending],
                actions: [.noAnswer, .hint, .stop],
                boardTask: .identify(allowsMoveRevision: false)
            )
        )

        XCTAssertEqual(presentation.headline, "One of your pieces is in danger. Which one?")
        XCTAssertEqual(presentation.instruction, "Tap your piece, or choose No piece needs help.")
        XCTAssertEqual(presentation.boardTask, .identify(allowsMoveRevision: false))
        XCTAssertEqual(
            presentation.actions.map(\.title),
            ["No piece needs help", "Hint", "Close help"]
        )
    }

    func testFallbackDoesNotInventPurpose() {
        let presentation = source.presentation(
            for: context(
                prompt: .fallbackChooseMove,
                actions: [.hint, .stop],
                boardTask: .move
            )
        )

        XCTAssertEqual(
            presentation.headline,
            "Nothing urgent stands out. Try a move you like, and we’ll check it together."
        )
        XCTAssertEqual(presentation.instruction, "Make a move on the board.")
        XCTAssertEqual(presentation.boardTask, .move)
    }

    func testEveryQuestionPromptUsesConcreteAnswerInstructions() {
        let cases: [(CoachingPrompt, String, String?)] = [
            (
                .checkLocate,
                "Your king is in check. What is giving check?",
                "Tap the piece giving check."
            ),
            (
                .checkResolve,
                "Make a move that gets your king safe.",
                "Move a piece on the board."
            ),
            (
                .safeLocate,
                "One of your pieces is in danger. Which one?",
                "Tap your piece, or choose No piece needs help."
            ),
            (
                .safeIdentifyAttacker(piece: .knight),
                "You found the knight. What black piece is attacking it?",
                "Tap the black piece."
            ),
            (
                .safeResolve(target: .knight, attacker: .pawn),
                "Yes—that pawn is attacking your knight. How could you help your knight?",
                "Make a move that gets it safe."
            ),
            (
                .takeChooseMove,
                "Can one of your pieces safely take a black piece?",
                "Make the capture, or choose No safe capture."
            ),
            (
                .wakeChoosePiece(purpose: .openingDevelopment(firstMove: true)),
                "A center pawn or knight is a simple way to start. Which would you like to move?",
                "Tap one of your two center pawns or one of your knights."
            ),
            (
                .wakeChoosePiece(purpose: .openingDevelopment(firstMove: false)),
                "Could you bring out a knight or bishop, move a center pawn, or castle?",
                "Tap the piece you want to move."
            ),
            (
                .wakeChooseMove(piece: .knight, purpose: .openingDevelopment(firstMove: true)),
                "This knight can come into the game.",
                "Move it on the board."
            ),
            (
                .wakeChoosePiece(purpose: .addsDefender),
                "Which piece could help protect another piece?",
                "Tap the piece you want to move."
            ),
            (
                .wakeChoosePiece(purpose: .createsThreat),
                "Which piece could safely attack something?",
                "Tap the piece you want to move."
            ),
            (
                .wakeChoosePiece(purpose: .centralActivity),
                "Which piece could move closer to the center?",
                "Tap the piece you want to move."
            ),
            (
                .wakeChoosePiece(purpose: .castle),
                "Which piece would you move to castle?",
                "Tap your king."
            ),
            (
                .opponentReply(opponent: .black),
                "Could Black check your king or win one of your pieces?",
                "Tap the black checking piece, or tap your piece Black could take. Otherwise choose Looks safe."
            ),
            (
                .opponentReply(opponent: .white),
                "Could White check your king or win one of your pieces?",
                "Tap the white checking piece, or tap your piece White could take. Otherwise choose Looks safe."
            ),
            (
                .fallbackChooseMove,
                "Nothing urgent stands out. Try a move you like, and we’ll check it together.",
                "Make a move on the board."
            ),
            (
                .reviseMove,
                "Try another move.",
                "Move a piece on the board."
            ),
            (
                .illegalKingSafety,
                "This move leaves your king in check. Try another move.",
                "Move a piece on the board."
            ),
        ]

        for (prompt, headline, instruction) in cases {
            let presentation = source.presentation(for: context(prompt: prompt))
            XCTAssertEqual(presentation.headline, headline, "Unexpected headline for \(prompt)")
            XCTAssertEqual(presentation.instruction, instruction, "Unexpected instruction for \(prompt)")
        }
    }

    func testGenericAcceptableKnightDoesNotInventACentralAlternative() {
        let move = Move(from: sq("b1"), to: sq("a3"))
        let task = CoachingWakeTask.opening(
            firstMove: false,
            castleIsAlternative: false,
            candidates: [.init(move: move, grade: .acceptable)]
        )

        let presentation = source.presentation(for: context(
            prompt: .complete(
                origin: .wake,
                idea: .constructive(task: task, move: move, piece: .knight)
            )
        ))

        XCTAssertEqual(presentation.headline, "You developed your knight.")
        XCTAssertFalse(presentation.headline.contains("closer to the center"))
    }

    func testNonFirstOpeningWithoutCastleDoesNotSayKnightAlsoDevelops() {
        let task = CoachingWakeTask.opening(
            firstMove: false,
            castleIsAlternative: false,
            candidates: [
                .init(
                    move: Move(from: sq("b1"), to: sq("c3")),
                    grade: .acceptable
                ),
            ]
        )

        let presentation = source.presentation(for: context(
            prompt: .wake(task: task, selectedPiece: .knight)
        ))

        XCTAssertEqual(
            presentation.headline,
            "You chose a knight. Moving it off its starting square is called developing it."
        )
        XCTAssertEqual(presentation.instruction, "Move the knight.")
        XCTAssertFalse(presentation.headline.contains("also"))
    }

    func testNonCornerMobilityTaskDoesNotClaimThePieceIsInTheCorner() {
        let task = CoachingWakeTask.improveMobility(
            source: sq("c3"),
            piece: .knight,
            sourceIsCorner: false,
            before: 4,
            candidates: [
                .init(
                    move: Move(from: sq("c3"), to: sq("d5")),
                    grade: .acceptable,
                    resultingMobility: 6
                ),
            ]
        )

        let presentation = source.presentation(for: context(
            prompt: .wake(task: task, selectedPiece: nil)
        ))

        XCTAssertEqual(
            presentation.headline,
            "Your knight can move to a square where it has more choices. Can you find the move?"
        )
        XCTAssertEqual(presentation.instruction, "Move the knight.")
        XCTAssertFalse(presentation.headline.contains("corner"))
    }

    func testEveryActionHasAnUnambiguousLabelAndProminence() {
        let presentation = source.presentation(
            for: context(
                prompt: .safeLocate,
                actions: [.noAnswer, .looksSafe, .hint, .stop, .done, .keepLooking]
            )
        )

        XCTAssertEqual(presentation.actions, [
            CoachingActionPresentation(
                action: .noAnswer,
                title: "No piece needs help",
                accessibilityLabel: "No piece needs help",
                prominence: .primary
            ),
            CoachingActionPresentation(
                action: .looksSafe,
                title: "Looks safe",
                accessibilityLabel: "Looks safe",
                prominence: .primary
            ),
            CoachingActionPresentation(
                action: .hint,
                title: "Hint",
                accessibilityLabel: "Show a hint",
                prominence: .secondary
            ),
            CoachingActionPresentation(
                action: .stop,
                title: "Close help",
                accessibilityLabel: "Close coaching help",
                prominence: .quiet
            ),
            CoachingActionPresentation(
                action: .done,
                title: "Play this move",
                accessibilityLabel: "Play this move",
                prominence: .primary
            ),
            CoachingActionPresentation(
                action: .keepLooking,
                title: "Try another move",
                accessibilityLabel: "Try another move",
                prominence: .secondary
            ),
        ])
    }

    func testCompletionActionsDescribeTheirConsequences() {
        let presentation = source.presentation(for: context(
            prompt: .complete(origin: .wake, idea: .develops(piece: .knight)),
            actions: [.done, .keepLooking, .stop]
        ))

        XCTAssertEqual(
            presentation.actions.map(\.title),
            ["Play this move", "Try another move", "Close help"]
        )
        XCTAssertEqual(
            presentation.actions.map(\.accessibilityLabel),
            ["Play this move", "Try another move", "Close coaching help"]
        )
    }

    func testAbsenceActionsNameTheClaimForTheCurrentQuestion() {
        let safe = source.presentation(for: context(
            prompt: .safeLocate,
            actions: [.noAnswer]
        ))
        let take = source.presentation(for: context(
            prompt: .takeChooseMove,
            actions: [.noAnswer]
        ))

        XCTAssertEqual(safe.actions.map(\.title), ["No piece needs help"])
        XCTAssertEqual(safe.actions.map(\.accessibilityLabel), ["No piece needs help"])
        XCTAssertEqual(take.actions.map(\.title), ["No safe capture"])
        XCTAssertEqual(take.actions.map(\.accessibilityLabel), ["No safe capture"])
    }

    func testOpeningPromptAndHintUseApprovedTranscript() {
        let prompt = CoachingPrompt.wakeChoosePiece(
            purpose: .openingDevelopment(firstMove: true)
        )
        let base = source.presentation(for: context(prompt: prompt))
        let hint = source.presentation(for: context(prompt: prompt, hint: .candidatePieces))

        XCTAssertEqual(
            base.headline,
            "A center pawn or knight is a simple way to start. Which would you like to move?"
        )
        XCTAssertEqual(
            base.instruction,
            "Tap one of your two center pawns or one of your knights."
        )
        XCTAssertEqual(hint.headline, "Here are the four pieces you can try.")
        XCTAssertEqual(hint.instruction, "Tap a highlighted piece.")
    }

    func testFirstMissEmphasizesHintWithoutChangingInstruction() {
        let presentation = source.presentation(for: context(
            prompt: .safeLocate,
            missesAtCurrentLevel: 1,
            actions: [.noAnswer, .hint, .stop]
        ))

        XCTAssertEqual(presentation.instruction, "Tap your piece, or choose No piece needs help.")
        XCTAssertEqual(
            presentation.actions.first(where: { $0.action == .hint })?.prominence,
            .primary
        )
    }

    func testMissResponseDoesNotReplaceOpeningAsk() {
        let presentation = source.presentation(for: context(
            prompt: .wakeChoosePiece(purpose: .openingDevelopment(firstMove: true)),
            feedback: .blockedWakePiece(piece: .rook, blocker: .pawn)
        ))
        XCTAssertEqual(
            presentation.response,
            "Your pawn is blocking that rook. Choose a center pawn or knight."
        )
        XCTAssertEqual(presentation.headline, "A center pawn or knight is a simple way to start. Which would you like to move?")
        XCTAssertEqual(presentation.instruction, "Tap one of your two center pawns or one of your knights.")
    }

    func testCorrectAbsenceIsSeparateFromNextAsk() {
        let presentation = source.presentation(for: context(
            prompt: .takeChooseMove,
            feedback: .correctAbsence(.noSafeCapture)
        ))
        XCTAssertEqual(presentation.response, "Right—there is no safe capture here.")
        XCTAssertEqual(presentation.headline, "Can one of your pieces safely take a black piece?")
    }

    func testUnsafeCaptureFeedbackNamesTheImmediateExchange() {
        let move = CoachingGoldenMoves.bishopTakesPawn
        let fact = CoachingExchangeFact(
            move: move,
            mover: .bishop,
            captured: .pawn,
            immediateRecapture: CoachingGoldenMoves.kingTakesBishop,
            immediateRecapturer: .king,
            netGainForLearner: -2
        )

        let presentation = source.presentation(for: context(
            prompt: .takeChooseMove,
            feedback: .unsafeCapture(fact)
        ))

        XCTAssertEqual(
            presentation.response,
            "Black’s king could take your bishop. You would lose a bishop to take one pawn."
        )
        XCTAssertEqual(
            presentation.instruction,
            "Change your move, or choose No safe capture."
        )
    }

    func testSafeCaptureCompletionNamesTheConcreteExchange() {
        let move = CoachingGoldenMoves.bishopWinsRook
        let fact = CoachingExchangeFact(
            move: move,
            mover: .bishop,
            captured: .rook,
            immediateRecapture: nil,
            immediateRecapturer: nil,
            netGainForLearner: 5
        )

        let presentation = source.presentation(for: context(
            prompt: .complete(origin: .take, idea: .safeCapture(fact))
        ))

        XCTAssertEqual(
            presentation.headline,
            "Your bishop took a rook, and Black cannot take the bishop back."
        )
    }

    func testSafeCaptureCompletionNamesWhiteForBlackLearner() {
        let fact = CoachingExchangeFact(
            move: CoachingGoldenMoves.bishopWinsRook,
            mover: .bishop,
            captured: .rook,
            immediateRecapture: nil,
            immediateRecapturer: nil,
            netGainForLearner: 5
        )

        let presentation = source.presentation(for: context(
            prompt: .complete(origin: .take, idea: .safeCapture(fact)),
            learner: .black
        ))

        XCTAssertEqual(
            presentation.headline,
            "Your bishop took a rook, and White cannot take the bishop back."
        )
    }

    func testSafeCaptureHintNamesThePieceAndTapInstruction() {
        let presentation = source.presentation(for: context(
            prompt: .takeChooseMove,
            feedback: .safeCaptureHint(piece: .bishop),
            hint: .candidatePieces
        ))

        XCTAssertEqual(presentation.response, "Your bishop has a safe capture.")
        XCTAssertEqual(presentation.instruction, "Tap the highlighted white piece.")
    }

    func testWrongTakeSourceUsesCaptureSpecificMissCopy() {
        let presentation = source.presentation(for: context(
            prompt: .takeChooseMove,
            feedback: .noSafeCaptureForPiece
        ))

        XCTAssertEqual(presentation.response, "That piece has no safe capture here.")
        XCTAssertEqual(
            presentation.instruction,
            "Try another piece, or choose No safe capture."
        )
    }

    func testHintHasNoStaleMissResponse() {
        let presentation = source.presentation(for: context(
            prompt: .wakeChoosePiece(purpose: .openingDevelopment(firstMove: true)),
            feedback: nil,
            hint: .candidatePieces
        ))
        XCTAssertNil(presentation.response)
        XCTAssertEqual(presentation.headline, "Here are the four pieces you can try.")
        XCTAssertEqual(presentation.instruction, "Tap a highlighted piece.")
    }

    func testFeedbackStatesAVisibleChessFact() {
        let cases: [(CoachingPrompt, CoachingFeedback, String)] = [
            (.safeLocate, .safePiece(piece: .bishop), "That bishop is safe right now."),
            (
                .safeLocate,
                .lowerPriorityDanger(
                    chosen: .pawn,
                    chosenLoss: 1,
                    primary: .knight,
                    primaryLoss: 3
                ),
                "You found a threatened pawn. A knight is worth about three pawns, so losing the knight would cost more."
            ),
            (
                .safeLocate,
                .attackedButProtected(target: .pawn, attacker: .knight, defender: .pawn),
                "The pawn is attacked, but your other pawn protects it. If the knight takes it, your pawn can take the knight back. No piece needs help right now."
            ),
            (.safeLocate, .expectedLearnerPiece, "Tap one of your pieces."),
            (
                .safeIdentifyAttacker(piece: .knight),
                .notAttacker(piece: .bishop, target: .knight),
                "That bishop isn’t attacking your knight."
            ),
            (
                .safeIdentifyAttacker(piece: .knight),
                .expectedAttacker(target: .knight),
                "Tap a black piece attacking your knight."
            ),
            (
                .wakeChoosePiece(purpose: .openingDevelopment(firstMove: true)),
                .blockedWakePiece(piece: .rook, blocker: .pawn),
                "Your pawn is blocking that rook. Choose a center pawn or knight."
            ),
            (
                .opponentReply(opponent: .black),
                .notReplyIssue,
                "That square doesn’t show a check or capture after this move."
            ),
            (
                .safeResolve(target: .knight, attacker: .pawn),
                .dangerStillPresent(attacker: .pawn, target: .knight),
                "The pawn could still take your knight after that move."
            ),
        ]

        for (prompt, feedback, response) in cases {
            let result = source.presentation(for: context(prompt: prompt, feedback: feedback))
            XCTAssertEqual(result.response, response)
        }
    }

    func testCorrectAbsenceAcknowledgesAndAsksTheNextQuestion() {
        let presentation = source.presentation(for: context(
            prompt: .takeChooseMove,
            feedback: .correctAbsence(.noSafeCapture)
        ))

        XCTAssertEqual(
            presentation.response,
            "Right—there is no safe capture here."
        )
        XCTAssertEqual(
            presentation.headline,
            "Can one of your pieces safely take a black piece?"
        )
        XCTAssertEqual(
            presentation.instruction,
            "Make the capture, or choose No safe capture."
        )
    }

    func testConcreteFeedbackNamesWhiteWhenWhiteIsTheOpponent() {
        let presentation = source.presentation(
            for: context(
                prompt: .opponentReply(opponent: .white),
                feedback: .concreteFlaw(kind: .check, affectedPiece: nil),
                learner: .black
            )
        )

        XCTAssertEqual(presentation.response, "White could check your king.")
        XCTAssertEqual(
            presentation.headline,
            "Could White check your king or win one of your pieces?"
        )
    }

    func testBlackLearnerSafePromptNamesWhiteAsTheAttacker() {
        let presentation = source.presentation(for: context(
            prompt: .safeIdentifyAttacker(piece: .knight),
            learner: .black
        ))

        XCTAssertEqual(
            presentation.headline,
            "You found the knight. What white piece is attacking it?"
        )
        XCTAssertEqual(presentation.instruction, "Tap the white piece.")
    }

    func testCompletionNamesExactlyOneSuppliedVerifiedIdea() {
        let cases: [(CoachingCompletionIdea, String)] = [
            (
                .resolvesDanger(.movedTarget(target: .queen, attacker: .rook)),
                "Your queen moved out of the rook’s path. It is safe now."
            ),
            (.mate, "That works. You found checkmate."),
            (
                .profitableCapture(captured: .rook),
                "That works. Your capture wins a rook."
            ),
            (
                .develops(piece: .knight),
                "That works. Your knight came into the game. Chess players call that developing a piece."
            ),
            (.advancesCenterPawn, "That works. Your pawn helps control the center."),
            (.castles, "That works. Castling helps keep your king safe."),
            (
                .addsDefender(piece: .bishop),
                "That works. Your bishop adds a defender."
            ),
            (
                .createsThreat(piece: .rook),
                "That works. Your rook creates a threat."
            ),
            (
                .centralizes(piece: .queen),
                "That works. Your queen gets a more useful place near the center."
            ),
            (.verifiedSafe, "That works. Your move stays safe after the reply."),
        ]

        for (idea, headline) in cases {
            let presentation = source.presentation(
                for: context(prompt: .complete(origin: .wake, idea: idea))
            )
            XCTAssertEqual(presentation.headline, headline, "Unexpected completion for \(idea)")
            XCTAssertNil(presentation.instruction)
        }
    }

    func testPresentationPassesThroughRoutineBoardTaskAndSemanticFocus() {
        let path = CoachFocusPath(
            source: Square(file: .c, rank: 3),
            destination: Square(file: .d, rank: 5),
            role: .candidate
        )
        let focus = CoachFocusPresentation(
            emphasizedSquares: [Square(file: .c, rank: 3)],
            candidateSquares: [Square(file: .d, rank: 5)],
            paths: [path],
            pulseID: 7
        )
        let routine: [CoachingRoutineState] = [.safeCleared, .takeCleared, .wakeCurrent]
        let boardTask = CoachingBoardTask.identify(allowsMoveRevision: true)

        let presentation = source.presentation(
            for: context(
                prompt: .wakeChoosePiece(purpose: .centralActivity),
                routine: routine,
                boardTask: boardTask,
                focus: focus
            )
        )

        XCTAssertEqual(presentation.routine, routine)
        XCTAssertEqual(presentation.boardTask, boardTask)
        XCTAssertEqual(presentation.focus, focus)
    }

    func testHintLanguageNamesOnlyItsSemanticClue() {
        let cases: [(CoachingPrompt, CoachingHint, String)] = [
            (.safeLocate, .dangerMarker, "Look for the red danger marker, then tap your piece."),
            (
                .wakeChoosePiece(purpose: .openingDevelopment(firstMove: true)),
                .candidatePieces,
                "Tap a highlighted piece."
            ),
            (
                .safeIdentifyAttacker(piece: .knight),
                .attackerRelationship,
                "Follow the highlighted line to the piece attacking your knight."
            ),
            (
                .safeResolve(target: .knight, attacker: .pawn),
                .safeResponseIdeas,
                "Try moving your knight, protecting it, or taking the attacker."
            ),
            (
                .wakeChooseMove(piece: .knight, purpose: .openingDevelopment(firstMove: true)),
                .movementMarkers,
                "Use the movement markers to choose where your knight should go."
            ),
            (
                .opponentReply(opponent: .black),
                .replyMarkers,
                "Look for a red danger marker or a check marker."
            ),
        ]

        for (prompt, hint, instruction) in cases {
            let result = source.presentation(for: context(prompt: prompt, hint: hint))
            XCTAssertEqual(result.instruction, instruction)
            XCTAssertEqual(result.hint, hint)
        }
    }

    func testCanonicalOutputAvoidsJudgmentalAndEngineVocabulary() {
        let prompts: [CoachingPrompt] = [
            .checkLocate,
            .checkResolve,
            .safeLocate,
            .safeIdentifyAttacker(piece: .queen),
            .safeResolve(target: .queen, attacker: .rook),
            .takeChooseMove,
            .wakeChoosePiece(purpose: .openingDevelopment(firstMove: true)),
            .wakeChoosePiece(purpose: .centralActivity),
            .wakeChooseMove(piece: .knight, purpose: .openingDevelopment(firstMove: true)),
            .opponentReply(opponent: .black),
            .fallbackChooseMove,
            .reviseMove,
            .illegalKingSafety,
            .complete(origin: .safe, idea: .verifiedSafe),
        ]
        let feedback: [CoachingFeedback?] = [
            nil,
            .safePiece(piece: .bishop),
            .lowerPriorityDanger(
                chosen: .pawn,
                chosenLoss: 1,
                primary: .knight,
                primaryLoss: 3
            ),
            .attackedButProtected(target: .pawn, attacker: .knight, defender: .pawn),
            .expectedLearnerPiece,
            .notCheckingPiece(piece: .bishop),
            .notAttacker(piece: .bishop, target: .knight),
            .expectedAttacker(target: .knight),
            .blockedWakePiece(piece: .rook, blocker: .pawn),
            .notWakeCandidate(piece: .bishop, purpose: .centralActivity),
            .notReplyIssue,
            .correctAbsence(.noPieceNeedsHelp),
            .correctAbsence(.noSafeCapture),
            .missedExistingAnswer(.noPieceNeedsHelp),
            .missedExistingAnswer(.noSafeCapture),
            .missedOpponentReply,
            .concreteFlaw(kind: .materialLoss(points: 9), affectedPiece: .queen),
            .dangerStillPresent(attacker: .rook, target: .queen),
            .noRecognizedPurpose(purpose: .centralActivity),
            .harmlessCheckFound,
            .checkFoundOtherDangerRemains,
        ]

        let feedbackCopy = prompts.flatMap { prompt in
            feedback.map { item in
                let presentation = source.presentation(
                    for: context(prompt: prompt, feedback: item)
                )
                return ([
                    presentation.response,
                    presentation.headline,
                    presentation.instruction,
                ].compactMap { $0 })
                    .joined(separator: " ")
            }
        }.joined(separator: " ")
        let hintCopy = prompts.map { prompt in
            let presentation = source.presentation(
                for: context(
                    prompt: prompt,
                    hint: .candidatePieces,
                    actions: [.hint]
                )
            )
            return ([
                presentation.response,
                presentation.headline,
                presentation.instruction,
            ].compactMap { $0 })
                .joined(separator: " ")
        }.joined(separator: " ")
        let copy = "\(feedbackCopy) \(hintCopy)".lowercased()

        XCTAssertFalse(copy.contains("best"))
        XCTAssertFalse(copy.contains("wrong move"))
        XCTAssertNil(copy.range(of: #"\b[+-]?\d+(?:\.\d+)?\b"#, options: .regularExpression))

        let prohibited = [
            "job",
            "part of this problem",
            "big danger",
            "tap the problem",
        ]
        for phrase in prohibited {
            XCTAssertFalse(copy.contains(phrase), "Found prohibited copy: \(phrase)")
        }
        XCTAssertNotEqual(copy.trimmingCharacters(in: .whitespacesAndNewlines), "Yes.")
    }

    private func context(
        prompt: CoachingPrompt,
        feedback: CoachingFeedback? = nil,
        learner: PieceColor = .white,
        hint: CoachingHint? = nil,
        missesAtCurrentLevel: Int = 0,
        routine: [CoachingRoutineState] = [],
        actions: [CoachingAction] = [],
        boardTask: CoachingBoardTask = .none,
        focus: CoachFocusPresentation = .empty
    ) -> CoachingPresentationContext {
        CoachingPresentationContext(
            prompt: prompt,
            feedback: feedback,
            learner: learner,
            hint: hint,
            missesAtCurrentLevel: missesAtCurrentLevel,
            routine: routine,
            actions: actions,
            boardTask: boardTask,
            focus: focus
        )
    }
}

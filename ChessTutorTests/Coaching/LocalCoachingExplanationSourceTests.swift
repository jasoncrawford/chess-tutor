import XCTest
@testable import ChessTutor

final class LocalCoachingExplanationSourceTests: XCTestCase {
    private let explainer = LocalCoachingExplanationSource()

    func testSafeLocatePresentationAsksForBoardTap() {
        let presentation = explainer.presentation(
            for: context(
                prompt: .safeLocate,
                routine: [.safeCurrent, .takePending, .wakePending],
                actions: [.noAnswer, .hint, .stop],
                boardTask: .identify(allowsMoveRevision: false)
            )
        )

        XCTAssertEqual(presentation.headline, "Which of your pieces needs help most?")
        XCTAssertEqual(presentation.instruction, "Tap your piece, or choose I don’t see one.")
        XCTAssertEqual(presentation.boardTask, .identify(allowsMoveRevision: false))
        XCTAssertEqual(presentation.actions.map(\.title), ["I don’t see one", "Hint", "Stop"])
    }

    func testFallbackDoesNotInventPurpose() {
        let presentation = explainer.presentation(
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
                "Which of your pieces needs help most?",
                "Tap your piece, or choose I don’t see one."
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
                "Can one of your pieces make a useful capture?",
                "Make the capture, or choose I don’t see one."
            ),
            (
                .wakeChoosePiece(purpose: .openingDevelopment(firstMove: true)),
                "A good first step is to move a center pawn or bring out a knight. Which would you like to try?",
                "Tap the piece you want to move."
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
                "Tap the black checking piece, or tap your piece White could take. Otherwise choose Looks safe."
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
            let presentation = explainer.presentation(for: context(prompt: prompt))
            XCTAssertEqual(presentation.headline, headline, "Unexpected headline for \(prompt)")
            XCTAssertEqual(presentation.instruction, instruction, "Unexpected instruction for \(prompt)")
        }
    }

    func testEveryActionHasAnUnambiguousLabelAndProminence() {
        let presentation = explainer.presentation(
            for: context(
                prompt: .safeLocate,
                actions: [.noAnswer, .looksSafe, .hint, .stop, .done, .keepLooking]
            )
        )

        XCTAssertEqual(presentation.actions, [
            CoachingActionPresentation(
                action: .noAnswer,
                title: "I don’t see one",
                accessibilityLabel: "I don’t see one",
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
                title: "Stop",
                accessibilityLabel: "Stop coaching",
                prominence: .quiet
            ),
            CoachingActionPresentation(
                action: .done,
                title: "Done",
                accessibilityLabel: "Done with this move",
                prominence: .primary
            ),
            CoachingActionPresentation(
                action: .keepLooking,
                title: "Keep looking",
                accessibilityLabel: "Keep looking for another move",
                prominence: .secondary
            ),
        ])
    }

    func testTwoMissesOfferAndEmphasizeHint() {
        let presentation = explainer.presentation(
            for: context(
                prompt: .safeLocate,
                missesAtCurrentLevel: 2,
                actions: [.noAnswer, .hint, .stop]
            )
        )

        XCTAssertEqual(
            presentation.instruction,
            "Tap your piece, or choose I don’t see one. Want a hint?"
        )
        XCTAssertEqual(
            presentation.actions.first(where: { $0.action == .hint })?.prominence,
            .primary
        )
    }

    func testFeedbackReplacesHeadlineAndRetainsCurrentInstruction() {
        let cases: [(CoachingFeedback, String)] = [
            (.correct, "Yes."),
            (.correctAlternative, "Yes, that works too."),
            (
                .relevantButNonurgent(piece: .bishop),
                "That bishop is threatened, but it isn’t in big danger."
            ),
            (.unrelatedTap, "That piece isn’t part of this problem."),
            (.correctAbsence, "Right—there isn’t one."),
            (.missedExistingAnswer, "There is one to find."),
            (.dangerStillPresent(piece: .queen), "Your queen would still need help."),
            (
                .noRecognizedPurpose,
                "That move looks safe, but give the piece a clear job."
            ),
            (
                .harmlessCheckFound,
                "Yes. Black could check your king, but your move still works."
            ),
            (
                .concreteFlaw(kind: .mateInOne, affectedPiece: nil),
                "Black could checkmate your king."
            ),
            (
                .concreteFlaw(kind: .check, affectedPiece: nil),
                "Black could check your king."
            ),
            (
                .concreteFlaw(kind: .materialLoss(points: 3), affectedPiece: .rook),
                "Black could take your rook."
            ),
            (
                .concreteFlaw(kind: .materialLoss(points: 2), affectedPiece: nil),
                "Black could win some material."
            ),
        ]

        for (feedback, headline) in cases {
            let presentation = explainer.presentation(
                for: context(
                    prompt: .opponentReply(opponent: .black),
                    feedback: feedback
                )
            )
            XCTAssertEqual(presentation.headline, headline, "Unexpected feedback for \(feedback)")
            XCTAssertEqual(
                presentation.instruction,
                "Tap the black checking piece, or tap your piece Black could take. Otherwise choose Looks safe."
            )
        }
    }

    func testConcreteFeedbackNamesWhiteWhenWhiteIsTheOpponent() {
        let presentation = explainer.presentation(
            for: context(
                prompt: .opponentReply(opponent: .white),
                feedback: .concreteFlaw(kind: .check, affectedPiece: nil),
                learner: .black
            )
        )

        XCTAssertEqual(presentation.headline, "White could check your king.")
    }

    func testCompletionNamesExactlyOneSuppliedVerifiedIdea() {
        let cases: [(CoachingCompletionIdea, String)] = [
            (.resolvesDanger(piece: .queen), "That works. Your queen is safe now."),
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
            let presentation = explainer.presentation(
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

        let presentation = explainer.presentation(
            for: context(
                prompt: .wakeChoosePiece(purpose: .centralActivity),
                hintLevel: 4,
                routine: routine,
                boardTask: boardTask,
                focus: focus
            )
        )

        XCTAssertEqual(presentation.routine, routine)
        XCTAssertEqual(presentation.boardTask, boardTask)
        XCTAssertEqual(presentation.focus, focus)
    }

    func testHintLevelsUseOnlyTheSuppliedSemanticFocusAndNeverStageAMove() throws {
        let attackerPath = CoachFocusPath(
            source: Square(file: .d, rank: 7),
            destination: Square(file: .d, rank: 4),
            role: .attacker
        )
        let candidatePath = CoachFocusPath(
            source: Square(file: .b, rank: 1),
            destination: Square(file: .c, rank: 3),
            role: .candidate
        )
        let focusByLevel: [Int: CoachFocusPresentation] = [
            0: .empty,
            1: .empty,
            2: CoachFocusPresentation(
                emphasizedSquares: [],
                candidateSquares: [Square(file: .d, rank: 4)],
                paths: [],
                pulseID: 2
            ),
            3: CoachFocusPresentation(
                emphasizedSquares: [Square(file: .d, rank: 7), Square(file: .d, rank: 4)],
                candidateSquares: [Square(file: .d, rank: 4)],
                paths: [attackerPath],
                pulseID: 3
            ),
            4: CoachFocusPresentation(
                emphasizedSquares: [Square(file: .b, rank: 1), Square(file: .c, rank: 3)],
                candidateSquares: [Square(file: .c, rank: 3)],
                paths: [candidatePath],
                pulseID: 4
            ),
        ]
        let instructionByLevel: [Int: String] = [
            0: "Tap the black piece.",
            1: "Follow the danger marker to the attacker, then tap it.",
            2: "Look at the highlighted choices. Tap the black piece.",
            3: "Look at the highlighted pieces and their connection. Tap the black piece.",
            4: "Follow the highlighted path, then make the move yourself.",
        ]

        for level in 0...4 {
            let expectedFocus = try XCTUnwrap(focusByLevel[level])
            let presentation = explainer.presentation(
                for: context(
                    prompt: level == 4
                        ? .wakeChooseMove(piece: .knight, purpose: .openingDevelopment(firstMove: true))
                        : .safeIdentifyAttacker(piece: .queen),
                    hintLevel: level,
                    boardTask: level == 4 ? .move : .identify(allowsMoveRevision: false),
                    focus: expectedFocus
                )
            )

            XCTAssertEqual(presentation.focus, expectedFocus)
            XCTAssertEqual(
                presentation.boardTask,
                level == 4 ? .move : .identify(allowsMoveRevision: false)
            )
            XCTAssertEqual(
                presentation.instruction,
                try XCTUnwrap(instructionByLevel[level])
            )
        }
    }

    func testLevelFourIdentificationNamesTheSuppliedPathWithoutMovingAPiece() {
        let focus = CoachFocusPresentation(
            emphasizedSquares: [Square(file: .d, rank: 7), Square(file: .d, rank: 4)],
            candidateSquares: [Square(file: .d, rank: 7)],
            paths: [CoachFocusPath(
                source: Square(file: .d, rank: 7),
                destination: Square(file: .d, rank: 4),
                role: .attacker
            )],
            pulseID: 4
        )

        let presentation = explainer.presentation(
            for: context(
                prompt: .safeIdentifyAttacker(piece: .queen),
                hintLevel: 4,
                boardTask: .identify(allowsMoveRevision: false),
                focus: focus
            )
        )

        XCTAssertEqual(
            presentation.instruction,
            "Follow the highlighted path, then tap the piece yourself."
        )
        XCTAssertEqual(presentation.boardTask, .identify(allowsMoveRevision: false))
        XCTAssertEqual(presentation.focus, focus)
    }

    func testLevelOneInstructionsReferToExistingBoardGuidance() {
        let cases: [(CoachingPrompt, String)] = [
            (
                .safeLocate,
                "Look for a danger marker. Tap your piece, or choose I don’t see one."
            ),
            (
                .safeIdentifyAttacker(piece: .queen),
                "Follow the danger marker to the attacker, then tap it."
            ),
            (
                .safeResolve(target: .queen, attacker: .rook),
                "Use the defense and movement markers, then make a move."
            ),
            (
                .wakeChooseMove(piece: .bishop, purpose: .openingDevelopment(firstMove: false)),
                "Use the movement markers to find a square where it can help."
            ),
        ]

        for (prompt, instruction) in cases {
            let presentation = explainer.presentation(
                for: context(prompt: prompt, hintLevel: 1)
            )
            XCTAssertEqual(presentation.instruction, instruction)
            XCTAssertEqual(presentation.focus, .empty)
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
            .correct,
            .correctAlternative,
            .relevantButNonurgent(piece: .bishop),
            .unrelatedTap,
            .correctAbsence,
            .missedExistingAnswer,
            .concreteFlaw(kind: .materialLoss(points: 9), affectedPiece: .queen),
            .dangerStillPresent(piece: .rook),
            .noRecognizedPurpose,
            .harmlessCheckFound,
        ]

        let copy = prompts.flatMap { prompt in
            feedback.map { item in
                let presentation = explainer.presentation(
                    for: context(prompt: prompt, feedback: item)
                )
                return ([presentation.headline, presentation.instruction].compactMap { $0 })
                    .joined(separator: " ")
            }
        }.joined(separator: " ").lowercased()

        XCTAssertFalse(copy.contains("best"))
        XCTAssertFalse(copy.contains("wrong move"))
        XCTAssertNil(copy.range(of: #"\b[+-]?\d+(?:\.\d+)?\b"#, options: .regularExpression))
    }

    private func context(
        prompt: CoachingPrompt,
        feedback: CoachingFeedback? = nil,
        learner: PieceColor = .white,
        hintLevel: Int = 0,
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
            hintLevel: hintLevel,
            missesAtCurrentLevel: missesAtCurrentLevel,
            routine: routine,
            actions: actions,
            boardTask: boardTask,
            focus: focus
        )
    }
}

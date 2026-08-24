import XCTest
@testable import ChessTutor

final class LocalCoachingExplanationSourceTests: XCTestCase {
    private let source = LocalCoachingExplanationSource()

    func testPresentationUsesPrimaryInstructionObservationContract() {
        let presentation = CoachingPresentation(
            primaryMessage: "What could Black do next?",
            instruction: "Tap a black piece that could check your king or win one of your pieces.",
            observation: "That knight does not cause trouble here.",
            hint: nil,
            routine: [],
            actions: [],
            boardTask: .identify(allowsMoveRevision: true),
            focus: .empty
        )

        XCTAssertEqual(presentation.primaryMessage, "What could Black do next?")
        XCTAssertEqual(
            [presentation.primaryMessage, presentation.instruction, presentation.observation]
                .compactMap { $0 },
            [
                "What could Black do next?",
                "Tap a black piece that could check your king or win one of your pieces.",
                "That knight does not cause trouble here.",
            ]
        )
    }

    func testSafeLocatePresentationAsksForBoardTap() {
        let presentation = source.presentation(
            for: context(
                prompt: .safeLocate,
                routine: [.safeCurrent, .takePending, .wakePending],
                actions: [.noAnswer, .hint, .stop],
                boardTask: .identify(allowsMoveRevision: false)
            )
        )

        XCTAssertEqual(presentation.primaryMessage, "One of your pieces is in danger. Which one?")
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
            presentation.primaryMessage,
            "Choose a move you are considering, and I will check it with you."
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
                "Tap your piece."
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
                "You can develop this knight.",
                "Move it on the board."
            ),
            (
                .wakeChoosePiece(purpose: .addsDefender),
                "Which piece could add a defender?",
                "Tap the piece you want to move."
            ),
            (
                .wakeChoosePiece(purpose: .createsThreat),
                "Which piece could create a safe threat?",
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
                .opponentReply(opponent: .black, threatenedPiece: nil),
                "What could Black do after your move?",
                "Tap a black piece that could check your king or win one of your pieces."
            ),
            (
                .opponentReply(opponent: .white, threatenedPiece: nil),
                "What could White do after your move?",
                "Tap a white piece that could check your king or win one of your pieces."
            ),
            (
                .fallbackChooseMove,
                "Choose a move you are considering, and I will check it with you.",
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
            XCTAssertEqual(presentation.primaryMessage, headline, "Unexpected headline for \(prompt)")
            XCTAssertEqual(presentation.instruction, instruction, "Unexpected instruction for \(prompt)")
        }
    }

    func testLegacyWakePurposeCopyUsesConcreteSemanticNames() {
        let cases: [(CoachingPrompt, CoachingFeedback?, String, String?)] = [
            (
                .wakeChooseMove(piece: .bishop, purpose: .addsDefender),
                nil,
                "This bishop can add a defender.",
                nil
            ),
            (
                .wakeChooseMove(piece: .rook, purpose: .createsThreat),
                nil,
                "This rook can create a safe threat.",
                nil
            ),
            (
                .wakeChoosePiece(purpose: .addsDefender),
                .noRecognizedPurpose(purpose: .addsDefender),
                "Which piece could add a defender?",
                "That move is safe, but it doesn’t add a defender."
            ),
            (
                .fallbackChooseMove,
                .noRecognizedPurpose(purpose: nil),
                "Choose a move you are considering, and I will check it with you.",
                "That move seems safe."
            ),
            (
                .wakeChoosePiece(purpose: .openingDevelopment(firstMove: true)),
                .noRecognizedPurpose(purpose: .openingDevelopment(firstMove: true)),
                "A center pawn or knight is a simple way to start. Which would you like to move?",
                "That move is safe, but it doesn’t move a knight or bishop off its starting square."
            ),
        ]

        for (prompt, feedback, headline, response) in cases {
            let presentation = source.presentation(
                for: context(prompt: prompt, feedback: feedback)
            )
            XCTAssertEqual(presentation.primaryMessage, headline)
            XCTAssertEqual(presentation.observation, response)
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

        XCTAssertEqual(presentation.primaryMessage, "You developed your knight.")
        XCTAssertFalse(presentation.primaryMessage.contains("closer to the center"))
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
            presentation.primaryMessage,
            "You chose a knight. Moving it off its starting square is called developing it."
        )
        XCTAssertEqual(presentation.instruction, "Move the knight.")
        XCTAssertFalse(presentation.primaryMessage.contains("also"))
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
            presentation.primaryMessage,
            "Your knight can move to a square where it has more choices. Can you find the move?"
        )
        XCTAssertEqual(presentation.instruction, "Move the knight.")
        XCTAssertFalse(presentation.primaryMessage.contains("corner"))
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
            base.primaryMessage,
            "A center pawn or knight is a simple way to start. Which would you like to move?"
        )
        XCTAssertEqual(
            base.instruction,
            "Tap one of your two center pawns or one of your knights."
        )
        XCTAssertEqual(hint.primaryMessage, "Here are the four pieces you can try.")
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
            presentation.observation,
            "Your pawn is blocking that rook. Choose a center pawn or knight."
        )
        XCTAssertEqual(presentation.primaryMessage, "A center pawn or knight is a simple way to start. Which would you like to move?")
        XCTAssertEqual(presentation.instruction, "Tap one of your two center pawns or one of your knights.")
    }

    func testCorrectAbsenceIsSeparateFromNextAsk() {
        let presentation = source.presentation(for: context(
            prompt: .takeChooseMove,
            feedback: .correctAbsence(.noSafeCapture)
        ))
        XCTAssertEqual(presentation.observation, "Right—there is no safe capture here.")
        XCTAssertEqual(presentation.primaryMessage, "Can one of your pieces safely take a black piece?")
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
            presentation.observation,
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
            presentation.primaryMessage,
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
            presentation.primaryMessage,
            "Your bishop took a rook, and White cannot take the bishop back."
        )
    }

    func testSafeCaptureHintNamesThePieceAndTapInstruction() {
        let presentation = source.presentation(for: context(
            prompt: .takeChooseMove,
            feedback: .safeCaptureHint(piece: .bishop),
            hint: .candidatePieces
        ))

        XCTAssertEqual(presentation.observation, "Your bishop has a safe capture.")
        XCTAssertEqual(presentation.instruction, "Tap the highlighted white piece.")
    }

    func testWrongTakeSourceUsesCaptureSpecificMissCopy() {
        let presentation = source.presentation(for: context(
            prompt: .takeChooseMove,
            feedback: .noSafeCaptureForPiece
        ))

        XCTAssertEqual(presentation.observation, "That piece has no safe capture here.")
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
        XCTAssertNil(presentation.observation)
        XCTAssertEqual(presentation.primaryMessage, "Here are the four pieces you can try.")
        XCTAssertEqual(presentation.instruction, "Tap a highlighted piece.")
    }

    func testInstructionsNameOnlyActionsThatAreActuallyExposed() {
        let knownDanger = source.presentation(for: context(
            prompt: .safeLocate,
            actions: [.hint, .stop]
        ))
        XCTAssertEqual(knownDanger.instruction, "Tap your piece.")
        XCTAssertFalse(knownDanger.instruction?.contains("No piece needs help") == true)

        let protectedOnly = source.presentation(for: context(
            prompt: .safeLocate,
            actions: [.noAnswer, .hint, .stop]
        ))
        XCTAssertEqual(
            protectedOnly.instruction,
            "Tap your piece, or choose No piece needs help."
        )

        let revealedOpponentIssue = source.presentation(for: context(
            prompt: .opponentReply(opponent: .black, threatenedPiece: nil),
            actions: [.hint, .stop]
        ))
        XCTAssertEqual(
            revealedOpponentIssue.instruction,
            "Tap a black piece that could check your king or win one of your pieces."
        )
        XCTAssertFalse(revealedOpponentIssue.instruction?.contains("Looks safe") == true)

        let unansweredOpponentScan = source.presentation(for: context(
            prompt: .opponentReply(opponent: .black, threatenedPiece: nil),
            actions: [.looksSafe, .hint, .stop]
        ))
        XCTAssertEqual(
            unansweredOpponentScan.instruction,
            "Tap a black piece that could check your king or win one of your pieces."
        )
    }

    func testWakeRelationshipCopyNamesSourceAndTargetFromSemanticPayload() {
        let move = Move(from: sq("c1"), to: sq("g5"))
        let candidate = CoachingCandidateMove(move: move, grade: .acceptable)
        let threat = source.presentation(for: context(
            prompt: .wake(
                task: .createThreat(
                    source: move.from,
                    sourcePiece: .bishop,
                    target: sq("d8"),
                    targetPiece: .queen,
                    candidates: [candidate]
                ),
                selectedPiece: nil
            )
        ))
        XCTAssertEqual(
            threat.primaryMessage,
            "Your bishop can move to a square where it attacks Black’s queen. Can you find the square?"
        )
        XCTAssertEqual(threat.instruction, "Move the bishop so it attacks the queen.")

        let protection = source.presentation(for: context(
            prompt: .wake(
                task: .protect(
                    source: sq("a1"),
                    sourcePiece: .rook,
                    target: sq("c3"),
                    targetPiece: .bishop,
                    candidates: [candidate]
                ),
                selectedPiece: nil
            )
        ))
        XCTAssertEqual(
            protection.primaryMessage,
            "Your rook can help protect your bishop."
        )
        XCTAssertEqual(
            protection.instruction,
            "Move the rook so it protects the bishop."
        )
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
                .attackedButProtected(
                    target: .pawn,
                    attacker: .knight,
                    defender: .pawn,
                    noPieceNeedsHelp: true
                ),
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
                .opponentReply(opponent: .black, threatenedPiece: nil),
                .notReplyIssue,
                "That piece cannot immediately check your king or win one of your pieces."
            ),
            (
                .opponentReply(opponent: .black, threatenedPiece: nil),
                .missedOpponentReply,
                "Black could still check your king or win one of your pieces."
            ),
            (
                .safeResolve(target: .knight, attacker: .pawn),
                .dangerStillPresent(attacker: .pawn, target: .knight),
                "The pawn could still take your knight after that move."
            ),
        ]

        for (prompt, feedback, response) in cases {
            let result = source.presentation(for: context(prompt: prompt, feedback: feedback))
            XCTAssertEqual(result.observation, response)
        }
    }

    func testCorrectAbsenceAcknowledgesAndAsksTheNextQuestion() {
        let presentation = source.presentation(for: context(
            prompt: .takeChooseMove,
            feedback: .correctAbsence(.noSafeCapture)
        ))

        XCTAssertEqual(
            presentation.observation,
            "Right—there is no safe capture here."
        )
        XCTAssertEqual(
            presentation.primaryMessage,
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
                prompt: .opponentReply(opponent: .white, threatenedPiece: nil),
                feedback: .concreteFlaw(kind: .check, affectedPiece: nil),
                learner: .black
            )
        )

        XCTAssertEqual(presentation.observation, "White could check your king.")
        XCTAssertEqual(
            presentation.primaryMessage,
            "What could White do after your move?"
        )
    }

    func testBlackLearnerSafePromptNamesWhiteAsTheAttacker() {
        let presentation = source.presentation(for: context(
            prompt: .safeIdentifyAttacker(piece: .knight),
            learner: .black
        ))

        XCTAssertEqual(
            presentation.primaryMessage,
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
                "That works. You developed your knight."
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
                "That works. Your queen moved closer to the center."
            ),
            (
                .verifiedSafe,
                "I do not see an immediate check or lost piece after this move."
            ),
        ]

        for (idea, headline) in cases {
            let presentation = source.presentation(
                for: context(prompt: .complete(origin: .wake, idea: idea))
            )
            XCTAssertEqual(presentation.primaryMessage, headline, "Unexpected completion for \(idea)")
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
                .opponentReply(opponent: .black, threatenedPiece: nil),
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
        let move = Move(from: sq("b1"), to: sq("c3"))
        let alternative = Move(from: sq("b1"), to: sq("a3"))
        let candidate = CoachingCandidateMove(
            move: move,
            grade: .preferred,
            resultingMobility: 6,
            centralityComparison: .closerWithMoreMobility(
                alternative: alternative,
                candidateMobility: 6,
                alternativeMobility: 2
            )
        )
        let wakeTasks: [CoachingWakeTask] = [
            .opening(firstMove: true, castleIsAlternative: false, candidates: [candidate]),
            .castle(move: Move(from: sq("e1"), to: sq("g1"), special: .castleKingside)),
            .protect(
                source: sq("b1"),
                sourcePiece: .knight,
                target: sq("e4"),
                targetPiece: .pawn,
                candidates: [candidate]
            ),
            .createThreat(
                source: sq("b1"),
                sourcePiece: .knight,
                target: sq("d4"),
                targetPiece: .rook,
                candidates: [candidate]
            ),
            .improveMobility(
                source: sq("b1"),
                piece: .knight,
                sourceIsCorner: true,
                before: 2,
                candidates: [candidate]
            ),
        ]
        let exchange = CoachingExchangeFact(
            move: Move(from: sq("c4"), to: sq("f7")),
            mover: .bishop,
            captured: .rook,
            immediateRecapture: Move(from: sq("g8"), to: sq("f7")),
            immediateRecapturer: .king,
            netGainForLearner: -2
        )
        let issue = CoachingOpponentIssue(
            reply: Move(from: sq("d8"), to: sq("d4")),
            kind: .materialLoss(points: 9),
            severity: .reviseMove,
            affectedSquare: sq("d4"),
            checkingSquares: []
        )
        let replyFact = CoachingOpponentReplyFact(
            issue: issue,
            opponentPiece: .rook,
            affectedPiece: .queen,
            learnerPiece: .queen
        )
        let benignActivity = CoachingOpponentActivity(
            reply: Move(from: sq("c4"), to: sq("e6")),
            opponentPiece: .bishop,
            checkingSquares: [],
            capturedSquare: sq("e6"),
            capturedPiece: .pawn,
            netGainForOpponent: -2,
            immediateRecapture: Move(from: sq("d7"), to: sq("e6")),
            isMate: false
        )
        let purposes: [CoachingWakePurpose] = [
            .openingDevelopment(firstMove: true),
            .openingDevelopment(firstMove: false),
            .addsDefender,
            .createsThreat,
            .centralActivity,
            .castle,
        ]
        let completions: [CoachingCompletionIdea] = [
            .resolvesDanger(.movedTarget(target: .queen, attacker: .rook)),
            .resolvesDanger(.capturedAttacker(
                capturer: .bishop,
                target: .queen,
                attacker: .rook
            )),
            .resolvesDanger(.addedDefender(
                defender: .knight,
                target: .queen,
                attacker: .rook
            )),
            .resolvesCheck(resolution: .movedKing, checker: .rook),
            .resolvesCheck(resolution: .movedKing, checker: nil),
            .resolvesCheck(
                resolution: .blocked(attacker: .rook, blocker: .bishop),
                checker: .rook
            ),
            .resolvesCheck(
                resolution: .capturedChecker(checker: .rook, capturer: .bishop),
                checker: .rook
            ),
            .mate,
            .profitableCapture(captured: .rook),
            .safeCapture(exchange),
            .develops(piece: .knight),
            .advancesCenterPawn,
            .castles,
            .addsDefender(piece: .bishop),
            .createsThreat(piece: .rook),
            .centralizes(piece: .queen),
            .constructive(task: wakeTasks[0], move: move, piece: .knight),
            .constructive(task: wakeTasks[1], move: move, piece: .king),
            .constructive(task: wakeTasks[2], move: move, piece: .knight),
            .constructive(task: wakeTasks[3], move: move, piece: .knight),
            .constructive(task: wakeTasks[4], move: move, piece: .knight),
            .verifiedSafe,
            .seemsSafe(suggestion: nil),
            .seemsSafe(suggestion: .openingDevelopment(firstMove: true)),
        ]
        let origins: [CoachingMoveOrigin] = [
            .preexisting, .check, .safe, .take, .wake, .fallback,
        ]
        let prompts: [CoachingPrompt] = [
            .checkLocate,
            .checkResolve,
            .safeLocate,
            .safeIdentifyAttacker(piece: .queen),
            .safeResolve(target: .queen, attacker: .rook),
            .takeChooseMove,
            .opponentReply(opponent: .black, threatenedPiece: nil),
            .opponentReply(opponent: .white, threatenedPiece: nil),
            .opponentReply(opponent: .black, threatenedPiece: .bishop),
            .fallbackChooseMove,
            .unsupportedFallbackChooseMove,
            .opponentIssueRevise(kind: .mateInOne, affectedPiece: nil),
            .opponentIssueRevise(kind: .check, affectedPiece: .king),
            .opponentIssueRevise(kind: .materialLoss(points: 9), affectedPiece: nil),
            .opponentIssueRevise(kind: .materialLoss(points: 9), affectedPiece: .queen),
            .reviseMove,
            .illegalKingSafety,
        ]
        + purposes.flatMap { purpose in
            [
                .wakeChoosePiece(purpose: purpose),
                .wakeChooseMove(piece: .knight, purpose: purpose),
            ]
        }
        + wakeTasks.flatMap { task in
            [
                .wake(task: task, selectedPiece: nil),
                .wake(task: task, selectedPiece: .knight),
            ]
        }
        + completions.map { .complete(origin: .wake, idea: $0) }
        + origins.map { .complete(origin: $0, idea: .verifiedSafe) }
        let feedback: [CoachingFeedback?] = [
            nil,
            .safePiece(piece: .bishop),
            .lowerPriorityDanger(
                chosen: .pawn,
                chosenLoss: 1,
                primary: .knight,
                primaryLoss: 3
            ),
            .attackedButProtected(
                target: .pawn,
                attacker: .knight,
                defender: .pawn,
                noPieceNeedsHelp: true
            ),
            .expectedLearnerPiece,
            .notCheckingPiece(piece: nil),
            .notCheckingPiece(piece: .bishop),
            .notAttacker(piece: .bishop, target: .knight),
            .expectedAttacker(target: .knight),
            .blockedWakePiece(piece: .rook, blocker: .pawn),
            .notWakeCandidate(
                piece: .pawn,
                purpose: .openingDevelopment(firstMove: true)
            ),
            .notWakeCandidate(piece: .bishop, purpose: .centralActivity),
            .notReplyIssue,
            .benignOpponentActivity(benignActivity),
            .correctAbsence(.noPieceNeedsHelp),
            .correctAbsence(.noSafeCapture),
            .missedExistingAnswer(.noPieceNeedsHelp),
            .missedExistingAnswer(.noSafeCapture),
            .missedOpponentReply,
            .missedOpponentIssue(replyFact),
            .opponentIssue(replyFact),
            .opponentReplyLooksSafe,
            .noSafeCaptureForPiece,
            .safeCaptureHint(piece: .bishop),
            .unsafeCapture(exchange),
            .concreteFlaw(kind: .mateInOne, affectedPiece: nil),
            .concreteFlaw(kind: .mateInOne, affectedPiece: .king),
            .concreteFlaw(kind: .check, affectedPiece: nil),
            .concreteFlaw(kind: .check, affectedPiece: .king),
            .concreteFlaw(kind: .materialLoss(points: 9), affectedPiece: nil),
            .concreteFlaw(kind: .materialLoss(points: 9), affectedPiece: .queen),
            .dangerStillPresent(attacker: nil, target: .queen),
            .dangerStillPresent(attacker: .rook, target: .queen),
            .noRecognizedPurpose(purpose: nil),
            .noRecognizedPurpose(purpose: .openingDevelopment(firstMove: true)),
            .noRecognizedPurpose(purpose: .addsDefender),
            .noRecognizedPurpose(purpose: .createsThreat),
            .noRecognizedPurpose(purpose: .centralActivity),
            .noRecognizedPurpose(purpose: .castle),
            .harmlessCheckFound,
            .checkFoundOtherDangerRemains,
        ]

        func childFacingCopy(_ presentation: CoachingPresentation) -> [String] {
            [
                presentation.observation,
                presentation.primaryMessage,
                presentation.instruction,
            ].compactMap { $0 }
            + presentation.actions.flatMap { [$0.title, $0.accessibilityLabel] }
        }

        let feedbackCopy = prompts.flatMap { prompt in
            feedback.map { item in
                let presentation = source.presentation(
                    for: context(
                        prompt: prompt,
                        feedback: item,
                        actions: [.noAnswer, .looksSafe, .hint, .stop, .done, .keepLooking]
                    )
                )
                return childFacingCopy(presentation).joined(separator: " ")
            }
        }.joined(separator: " ")
        let hints: [CoachingHint] = [
            .checkMarker, .dangerMarker, .replyMarkers, .candidatePieces,
            .attackerRelationship, .safeResponseIdeas, .movementMarkers,
            .candidateMoves,
        ]
        let hintCopy = prompts.flatMap { prompt in
            hints.map { hint in
                childFacingCopy(source.presentation(
                    for: context(prompt: prompt, hint: hint, actions: [.hint])
                )).joined(separator: " ")
            }
        }.joined(separator: " ")
        let copy = "\(feedbackCopy) \(hintCopy)".lowercased()

        XCTAssertFalse(copy.contains("best"))
        XCTAssertFalse(copy.contains("wrong move"))
        XCTAssertNil(copy.range(of: #"\b[+-]?\d+(?:\.\d+)?\b"#, options: .regularExpression))

        let prohibited = [
            "part of this problem",
            "big danger",
            "job",
            "tap the problem",
            "nothing urgent stands out",
            "clear plan",
            "reply to notice",
            "win some material",
            "come into the game",
            "attack something",
            "protect another piece",
            "more useful place",
            "verified purpose",
            "qualifying issue",
            "immediate-response scan",
            "material",
            "cannot name a purpose",
            "bring a new piece into the game",
        ]
        XCTAssertEqual(
            prohibited.filter(copy.contains),
            [],
            "Found prohibited child-facing copy"
        )
        XCTAssertNotEqual(copy.trimmingCharacters(in: .whitespacesAndNewlines), "Yes.")
    }

    func testMaterialLossWithoutAffectedPieceUsesBoundedCaptureCopy() {
        let presentation = source.presentation(for: context(
            prompt: .opponentIssueRevise(
                kind: .materialLoss(points: 3),
                affectedPiece: nil
            ),
            feedback: .concreteFlaw(
                kind: .materialLoss(points: 3),
                affectedPiece: nil
            )
        ))

        XCTAssertEqual(presentation.observation, "Black could take one of your pieces.")
        XCTAssertEqual(
            presentation.primaryMessage,
            "How can you change your move to keep your pieces safe?"
        )
        XCTAssertEqual(
            presentation.instruction,
            "Change your move to keep your pieces safe."
        )
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

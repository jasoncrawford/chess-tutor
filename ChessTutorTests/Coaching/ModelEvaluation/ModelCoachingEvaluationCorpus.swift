@testable import ChessTutor

enum ModelCoachingCorpusSplit: String, Codable, Sendable {
    case visible
    case hidden
}

struct ModelCoachingSemanticOracle: Codable, Equatable, Sendable {
    let requiredEvidenceReferences: [String]
    let requiredAnyEvidenceReferenceGroups: [[String]]
    let forbiddenEvidenceReferences: [String]
    let requiredActionKinds: [String]
    let forbiddenActionKinds: [String]
    let permittedTeachingIntents: [ModelCoachingTeachingIntent]
    let prohibitedPhrases: [String]
    let successCriteria: [String]
    let severeFailureCriteria: [String]
}

struct ModelCoachingEvaluationCase: Codable, Equatable, Sendable {
    let id: String
    let split: ModelCoachingCorpusSplit
    let request: ModelCoachingRequest
    let oracle: ModelCoachingSemanticOracle
}

enum ModelCoachingEvaluationCorpus {
    static var allCases: [ModelCoachingEvaluationCase] {
        CoachingGoldenCase.allCases.map(evaluationCase(for:))
    }

    static var visibleCases: [ModelCoachingEvaluationCase] {
        allCases.filter { $0.split == .visible }
    }

    static var hiddenCases: [ModelCoachingEvaluationCase] {
        allCases.filter { $0.split == .hidden }
    }

    private static let hiddenIDs: Set<String> = [
        CoachingGoldenCase.t1OutsidePawnMove.rawValue,
        CoachingGoldenCase.t3WrongAttacker.rawValue,
        CoachingGoldenCase.t4LowerPriorityPawn.rawValue,
        CoachingGoldenCase.t5ProtectedAbsence.rawValue,
        CoachingGoldenCase.t7UnsafeCapture.rawValue,
        CoachingGoldenCase.t9Completed.rawValue,
        CoachingGoldenCase.t10Completed.rawValue,
        CoachingGoldenCase.t11IncorrectLooksSafe.rawValue,
        CoachingGoldenCase.t11BenignCaptureLooksSafe.rawValue,
        CoachingGoldenCase.t12WrongChecker.rawValue,
        CoachingGoldenCase.t12UnsupportedSafeMove.rawValue,
    ]

    private static let sharedProhibitedPhrases = [
        "mixed stages",
        "evaluator",
        "debugger",
        "invented board facts",
        "unanswered question",
        "unanswerable question",
        "repeated feedback",
        "force an obsolete step after a staged or replaced move",
    ]

    private static let locateOperations: [ModelCoachingOperation] = [
        .selectBoardPiece, .inspectSquare, .hint, .closeHelp,
    ]
    private static let openingLocateOperations: [ModelCoachingOperation] = [
        .selectBoardPiece, .inspectSquare, .stageMove, .hint, .noPieceNeedsHelp, .closeHelp,
    ]
    private static let chooseMoveOperations: [ModelCoachingOperation] = [
        .selectBoardPiece, .inspectSquare, .stageMove, .hint, .closeHelp,
    ]
    private static let captureScanOperations: [ModelCoachingOperation] = [
        .selectBoardPiece, .inspectSquare, .stageMove, .hint, .noSafeCapture, .closeHelp,
    ]
    private static let tentativeOperations: [ModelCoachingOperation] = [
        .inspectSquare, .replaceMove, .removeMove, .hint, .looksSafe, .tryAnotherMove, .closeHelp,
    ]
    private static let completionOperations: [ModelCoachingOperation] = [
        .replaceMove, .removeMove, .playMove, .tryAnotherMove, .closeHelp,
    ]

    private static func evaluationCase(
        for goldenCase: CoachingGoldenCase
    ) -> ModelCoachingEvaluationCase {
        switch goldenCase {
        case .t1Entry:
            let snapshot = snapshot(
                .starting,
                steps: [step(.helpOpened)],
                operations: openingLocateOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: oracle(
                    intents: [.orient, .chooseMove],
                    prohibited: ["safety quiz on White's first move", "Is any White piece unsafe?"],
                    success: (
                        "The tutor recognizes that White is choosing an opening move from the starting position.",
                        "The tutor invites one concrete opening choice without making the learner prove an obvious absence of danger."
                    ),
                    severe: "The turn starts with a safety interrogation even though no White piece is under an immediate material threat."
                )
            )

        case .t1BlockedRook:
            let snapshot = snapshot(
                .starting,
                selected: "a1",
                steps: [step(.helpOpened), pieceStep(.pieceSelected, .starting, "a1")],
                operations: openingLocateOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: oracle(
                    intents: [.orient, .chooseMove],
                    success: (
                        "The tutor responds to the selected rook and notes that its own pawn blocks its useful path.",
                        "The tutor redirects toward a piece or pawn that can make a legal opening move."
                    ),
                    severe: "The turn claims that the a1 rook can move through the pawn on a2."
                )
            )

        case .t1FlankPawn:
            let snapshot = snapshot(
                .starting,
                selected: "a2",
                steps: [step(.helpOpened), pieceStep(.pieceSelected, .starting, "a2")],
                operations: openingLocateOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: oracle(
                    intents: [.orient, .chooseMove],
                    success: (
                        "The tutor acknowledges that the a-pawn has legal moves.",
                        "The tutor keeps the lesson on choosing an opening move without falsely calling the a-pawn central."
                    ),
                    severe: "The turn invents a central-control purpose for the a2 pawn."
                )
            )

        case .t1Hint:
            let snapshot = snapshot(
                .starting,
                steps: [step(.helpOpened), actionStep(.hint)],
                operations: openingLocateOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: oracle(
                    intents: [.orient, .chooseMove],
                    success: (
                        "The tutor answers the Hint action with one concrete legal opening option.",
                        "The tutor gives enough board direction for the learner to act without prescribing an unrelated safety stage."
                    ),
                    severe: "The hint names a piece or move that is not legal in the starting position."
                )
            )

        case .t1KnightSelected:
            let snapshot = snapshot(
                .starting,
                selected: "b1",
                steps: [step(.helpOpened), pieceStep(.pieceSelected, .starting, "b1")],
                operations: chooseMoveOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: oracle(
                    intents: [.chooseMove],
                    success: (
                        "The tutor follows the learner's b1-knight selection.",
                        "The tutor asks for or suggests a legal knight destination using the encoded move choices."
                    ),
                    severe: "The turn ignores the selected knight and forces the learner back to an obsolete piece-selection step."
                )
            )

        case .t1PreferredKnight:
            let move = CoachingGoldenMoves.openingKnightToF3
            let snapshot = stagedSnapshot(
                .starting,
                move: move,
                completed: true,
                operations: completionOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: oracle(
                    intents: [.evaluateMove, .confirmMove],
                    requiredActions: ["playMove"],
                    success: (
                        "The tutor evaluates g1-f3 as a legal developing move in the current position.",
                        "The tutor follows the staged move and offers a clear path to commit or revise it."
                    ),
                    severe: "The turn discards the staged knight move and restarts the opening scan."
                )
            )

        case .t1EdgeKnight:
            let move = Move(from: sq("g1"), to: sq("h3"))
            let snapshot = stagedSnapshot(
                .starting,
                move: move,
                completed: true,
                operations: completionOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: oracle(
                    intents: [.evaluateMove, .confirmMove],
                    requiredActions: ["playMove"],
                    success: (
                        "The tutor recognizes g1-h3 as legal without presenting it as central development.",
                        "The tutor responds to the actual staged move and lets the learner commit or revise it."
                    ),
                    severe: "The turn falsely claims that the knight on h3 directly controls the center."
                )
            )

        case .t1CenterPawn:
            let move = Move(from: sq("e2"), to: sq("e4"))
            let snapshot = stagedSnapshot(
                .starting,
                move: move,
                completed: true,
                operations: completionOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: oracle(
                    intents: [.evaluateMove, .confirmMove],
                    requiredActions: ["playMove"],
                    success: (
                        "The tutor recognizes e2-e4 as a legal central pawn move.",
                        "The tutor keeps its response tied to the staged pawn move and offers commit or revision."
                    ),
                    severe: "The turn asks the learner to select another piece before addressing the staged e-pawn move."
                )
            )

        case .t1OutsidePawnMove:
            let snapshot = stagedSnapshot(
                .starting,
                move: CoachingGoldenMoves.outsidePawn,
                completed: true,
                operations: completionOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: oracle(
                    intents: [.evaluateMove, .confirmMove],
                    requiredActions: ["playMove"],
                    prohibited: ["h2-h4 controls the center", "h-pawn develops toward the center"],
                    success: (
                        "The tutor recognizes h2-h4 as the staged legal edge-pawn move.",
                        "The tutor avoids attaching a central-development purpose that the move does not have."
                    ),
                    severe: "The turn claims that h2-h4 occupies or directly controls the center."
                )
            )

        case .t2Entry:
            let snapshot = snapshot(
                .readyToCastle,
                steps: [
                    step(.helpOpened),
                    actionStep(.noPieceNeedsHelp),
                    actionStep(.noSafeCapture),
                ],
                operations: chooseMoveOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: oracle(
                    intents: [.chooseMove],
                    success: (
                        "The tutor moves on from the completed danger and capture scans.",
                        "The tutor helps choose a useful legal move and may surface kingside castling as one option."
                    ),
                    severe: "The turn repeats either resolved absence question instead of addressing move choice."
                )
            )

        case .t2OneSquareKingMove:
            let move = Move(from: sq("e1"), to: sq("f1"))
            let replyMove = Move(
                from: sq("e8"),
                to: sq("g8"),
                special: .castleKingside
            )
            let snapshot = stagedSnapshot(
                state: castlingCheckReplyState(),
                move: move,
                prefix: [step(.helpOpened), actionStep(.noPieceNeedsHelp), actionStep(.noSafeCapture)],
                operations: tentativeOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: replyOracle(
                    after: move,
                    replyMove: replyMove,
                    intents: [.evaluateMove, .reviseMove, .confirmMove],
                    success: (
                        "The tutor addresses the legal e1-f1 king move and the encoded black kingside-castling reply.",
                        "The tutor recognizes the rook from h8 as the checker after castling and gives a bounded next choice."
                    ),
                    severe: "The turn calls e1-f1 castling or misses the h8 rook's check after Black castles."
                )
            )

        case .t2KnightSwitch:
            let snapshot = snapshot(
                .readyToCastle,
                selected: "b1",
                steps: [
                    step(.helpOpened),
                    actionStep(.noPieceNeedsHelp),
                    actionStep(.noSafeCapture),
                    pieceStep(.pieceSelected, .readyToCastle, "b1"),
                ],
                operations: chooseMoveOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: oracle(
                    intents: [.chooseMove],
                    success: (
                        "The tutor follows the learner's switch to the b1 knight.",
                        "The tutor uses only legal knight destinations from the encoded position."
                    ),
                    severe: "The turn forces the castling idea after the learner has selected a different piece."
                )
            )

        case .t2Castle:
            let snapshot = stagedSnapshot(
                .readyToCastle,
                move: CoachingGoldenMoves.castle,
                prefix: [step(.helpOpened), actionStep(.noPieceNeedsHelp), actionStep(.noSafeCapture)],
                completed: true,
                operations: completionOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: oracle(
                    intents: [.evaluateMove, .confirmMove],
                    requiredActions: ["playMove"],
                    success: (
                        "The tutor recognizes the staged e1-g1 special move as legal kingside castling.",
                        "The tutor follows the completed opponent scan and offers commit or revision."
                    ),
                    severe: "The turn treats castling as an ordinary two-square king move or invents an illegal reply."
                )
            )

        case .t3Entry:
            let snapshot = snapshot(
                .endangeredKnight,
                steps: [step(.helpOpened)],
                operations: locateOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: dangerOracle(
                    position: .endangeredKnight,
                    target: "f3",
                    intents: [.scanDanger],
                    success: (
                        "The tutor focuses on the white knight on f3 as the endangered learner piece.",
                        "The tutor asks for a board action that can identify or address that concrete danger."
                    ),
                    severe: "The turn claims that no White piece is threatened."
                )
            )

        case .t3WrongOwnPiece:
            let snapshot = snapshot(
                .endangeredKnight,
                steps: [step(.helpOpened), pieceStep(.squareInspected, .endangeredKnight, "g1")],
                operations: locateOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: dangerOracle(
                    position: .endangeredKnight,
                    target: "f3",
                    intents: [.scanDanger],
                    success: (
                        "The tutor briefly responds that the inspected g1 king is not the endangered target.",
                        "The tutor keeps the current task on locating the f3 knight without stacking old feedback."
                    ),
                    severe: "The turn accepts the g1 king as the piece facing the encoded three-point loss."
                )
            )

        case .t3Target:
            let snapshot = snapshot(
                .endangeredKnight,
                steps: [step(.helpOpened), pieceStep(.squareInspected, .endangeredKnight, "f3")],
                operations: locateOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: dangerOracle(
                    position: .endangeredKnight,
                    target: "f3",
                    intents: [.scanDanger],
                    success: (
                        "The tutor acknowledges that the learner found the endangered f3 knight.",
                        "The tutor advances to the concrete attacker relationship instead of asking for the target again."
                    ),
                    severe: "The turn repeats the resolved target question and ignores the latest tap."
                )
            )

        case .t3WrongAttacker:
            let snapshot = snapshot(
                .endangeredKnight,
                steps: [
                    step(.helpOpened),
                    pieceStep(.squareInspected, .endangeredKnight, "f3"),
                    pieceStep(.squareInspected, .endangeredKnight, "g8"),
                ],
                operations: locateOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: dangerOracle(
                    position: .endangeredKnight,
                    target: "f3",
                    intents: [.scanDanger],
                    success: (
                        "The tutor rejects the g8 king as the attacker of the f3 knight.",
                        "The tutor keeps the learner focused on finding the e4 pawn's attack."
                    ),
                    severe: "The turn claims that the black king on g8 attacks the f3 knight."
                )
            )

        case .t3Attacker:
            let snapshot = snapshot(
                .endangeredKnight,
                steps: [
                    step(.helpOpened),
                    pieceStep(.squareInspected, .endangeredKnight, "f3"),
                    pieceStep(.squareInspected, .endangeredKnight, "e4"),
                ],
                operations: chooseMoveOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: dangerOracle(
                    position: .endangeredKnight,
                    target: "f3",
                    intents: [.scanDanger, .chooseMove],
                    success: (
                        "The tutor acknowledges the e4 pawn as the attacker of the f3 knight.",
                        "The tutor advances to choosing a legal way to resolve that danger."
                    ),
                    severe: "The turn asks for the attacker again after the learner identified e4."
                )
            )

        case .t3UnresolvedMove:
            let move = Move(from: sq("g1"), to: sq("h1"))
            let snapshot = stagedSnapshot(
                .endangeredKnight,
                move: move,
                prefix: [
                    step(.helpOpened),
                    pieceStep(.squareInspected, .endangeredKnight, "f3"),
                    pieceStep(.squareInspected, .endangeredKnight, "e4"),
                ],
                operations: [.replaceMove, .removeMove, .tryAnotherMove, .closeHelp]
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: dangerOracle(
                    position: .endangeredKnight,
                    target: "f3",
                    intents: [.evaluateMove, .reviseMove],
                    requiredActions: ["tryAnotherMove"],
                    success: (
                        "The tutor responds to the staged g1-h1 king move rather than restarting the earlier questions.",
                        "The tutor explains that the f3 knight remains exposed and asks for a different legal move."
                    ),
                    severe: "The turn approves g1-h1 as resolving the pawn's attack on the f3 knight."
                )
            )

        case .t3ResolvedMove:
            let move = Move(from: sq("f3"), to: sq("g5"))
            let snapshot = stagedSnapshot(
                .endangeredKnight,
                move: move,
                prefix: [
                    step(.helpOpened),
                    pieceStep(.squareInspected, .endangeredKnight, "f3"),
                    pieceStep(.squareInspected, .endangeredKnight, "e4"),
                ],
                completed: true,
                operations: completionOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: dangerOracle(
                    position: .endangeredKnight,
                    target: "f3",
                    intents: [.evaluateMove, .confirmMove],
                    requiredActions: ["playMove"],
                    success: (
                        "The tutor recognizes that f3-g5 moves the endangered knight away from the pawn's capture.",
                        "The tutor offers commit or revision without returning to the resolved identification steps."
                    ),
                    severe: "The turn says the knight remains on f3 or requires the learner to find it again."
                )
            )

        case .t4LowerPriorityPawn:
            let snapshot = snapshot(
                .twoDangerPriorities,
                steps: [step(.helpOpened), pieceStep(.squareInspected, .twoDangerPriorities, "a3")],
                operations: locateOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: dangerOracle(
                    position: .twoDangerPriorities,
                    target: "f3",
                    intents: [.scanDanger],
                    success: (
                        "The tutor acknowledges that the a3 pawn is threatened by the a8 rook.",
                        "The tutor prioritizes the higher-value f3 knight danger as the one current teaching target."
                    ),
                    severe: "The turn treats the lower-value pawn loss as more urgent than the knight loss."
                )
            )

        case .t4PrimaryKnight:
            let snapshot = snapshot(
                .twoDangerPriorities,
                steps: [step(.helpOpened), pieceStep(.squareInspected, .twoDangerPriorities, "f3")],
                operations: locateOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: dangerOracle(
                    position: .twoDangerPriorities,
                    target: "f3",
                    intents: [.scanDanger],
                    success: (
                        "The tutor confirms the f3 knight as the primary danger target.",
                        "The tutor advances toward identifying its attacker or resolving the knight's danger."
                    ),
                    severe: "The turn redirects away from the knight to the lower-priority a3 pawn."
                )
            )

        case .t5PawnDanger:
            let snapshot = snapshot(
                .endangeredPawn,
                steps: [step(.helpOpened)],
                operations: locateOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: dangerOracle(
                    position: .endangeredPawn,
                    target: "e3",
                    intents: [.scanDanger],
                    success: (
                        "The tutor identifies the white pawn on e3 as threatened by the bishop on b6.",
                        "The tutor gives one concrete board response for exploring or resolving that threat."
                    ),
                    severe: "The turn claims that the e3 pawn is protected from the b6 bishop."
                )
            )

        case .t5PawnResolved:
            let snapshot = stagedSnapshot(
                .endangeredPawn,
                move: CoachingGoldenMoves.pawnEscapes,
                prefix: [
                    step(.helpOpened),
                    pieceStep(.squareInspected, .endangeredPawn, "e3"),
                    pieceStep(.squareInspected, .endangeredPawn, "b6"),
                ],
                completed: true,
                operations: completionOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: dangerOracle(
                    position: .endangeredPawn,
                    target: "e3",
                    intents: [.evaluateMove, .confirmMove],
                    requiredActions: ["playMove"],
                    success: (
                        "The tutor follows e3-e4 and recognizes that it moves the pawn off the bishop's diagonal.",
                        "The tutor offers commit or revision without repeating the old danger questions."
                    ),
                    severe: "The turn says that the pawn remains on e3 after the staged move."
                )
            )

        case .t5ProtectedTap:
            let snapshot = snapshot(
                .protectedPawn,
                steps: [step(.helpOpened), pieceStep(.squareInspected, .protectedPawn, "g4")],
                operations: captureScanOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: oracle(
                    intents: [.scanDanger, .scanCapture],
                    success: (
                        "The tutor recognizes that the g4 pawn is attacked by the f6 knight but defended by h3.",
                        "The tutor avoids labeling the pawn as an immediate material-loss danger and moves to a useful next scan."
                    ),
                    severe: "The turn claims the g4 pawn is undefended or certain to be lost."
                )
            )

        case .t5ProtectedAbsence:
            let snapshot = snapshot(
                .protectedPawn,
                steps: [step(.helpOpened), actionStep(.noPieceNeedsHelp)],
                operations: captureScanOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: oracle(
                    intents: [.scanDanger, .scanCapture],
                    success: (
                        "The tutor accepts the absence answer because the attacked g4 pawn is adequately defended.",
                        "The tutor advances to one useful current scan rather than contradicting the resolved answer."
                    ),
                    severe: "The turn marks No piece needs help as wrong despite the available recapture from h3."
                )
            )

        case .t6WrongSource:
            let snapshot = snapshot(
                .winningCapture,
                selected: "g1",
                steps: [step(.helpOpened), pieceStep(.pieceSelected, .winningCapture, "g1")],
                operations: captureScanOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: exchangeOracle(
                    move: CoachingGoldenMoves.bishopWinsRook,
                    intents: [.scanCapture],
                    success: (
                        "The tutor responds that the g1 king is not the source of the profitable capture.",
                        "The tutor redirects toward the c4 bishop and its legal capture on f7."
                    ),
                    severe: "The turn invents a profitable king capture from g1."
                )
            )

        case .t6Hint:
            let snapshot = snapshot(
                .winningCapture,
                steps: [step(.helpOpened), actionStep(.hint)],
                operations: captureScanOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: exchangeOracle(
                    move: CoachingGoldenMoves.bishopWinsRook,
                    intents: [.scanCapture],
                    success: (
                        "The tutor uses the Hint action to point to the c4 bishop or f7 rook.",
                        "The tutor keeps the hint grounded in the profitable c4-f7 capture."
                    ),
                    severe: "The hint recommends a capture other than the encoded bishop capture of the rook."
                )
            )

        case .t6Capture:
            let snapshot = stagedSnapshot(
                .winningCapture,
                move: CoachingGoldenMoves.bishopWinsRook,
                completed: true,
                operations: completionOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: exchangeOracle(
                    move: CoachingGoldenMoves.bishopWinsRook,
                    intents: [.evaluateMove, .confirmMove],
                    requiredActions: ["playMove"],
                    success: (
                        "The tutor recognizes c4-f7 as the staged profitable capture of the rook.",
                        "The tutor follows the learner's move and offers commit or revision."
                    ),
                    severe: "The turn describes the bishop capture as losing material in this position."
                )
            )

        case .t7UnsafeCapture:
            let snapshot = stagedSnapshot(
                .losingCapture,
                move: CoachingGoldenMoves.bishopTakesPawn,
                operations: tentativeOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: exchangeOracle(
                    move: CoachingGoldenMoves.bishopTakesPawn,
                    intents: [.evaluateMove, .reviseMove],
                    requiredActions: ["tryAnotherMove"],
                    success: (
                        "The tutor responds to c4-f7 and uses the encoded king recapture to show why it loses material.",
                        "The tutor asks for a different move without returning to the earlier capture scan."
                    ),
                    severe: "The turn approves c4-f7 as a safe winning capture despite the g8 king's legal recapture."
                )
            )

        case .t7NoSafeCapture:
            let move = Move(from: sq("c4"), to: sq("d3"))
            let snapshot = stagedSnapshot(
                .losingCapture,
                move: move,
                prefix: [
                    step(.helpOpened),
                    actionStep(.noSafeCapture),
                    tutorStep("no-safe-capture answer accepted"),
                ],
                operations: tentativeOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: oracle(
                    intents: [.chooseMove, .evaluateMove],
                    success: (
                        "The tutor accepts the earlier no-safe-capture answer and follows the learner's ordinary c4-d3 move.",
                        "The tutor evaluates the current staged move instead of repeating the resolved capture scan."
                    ),
                    severe: "The turn ignores c4-d3 and returns to the obsolete capture question after the learner moved ahead."
                )
            )

        case .t8AddsDefender:
            let snapshot = stagedSnapshot(
                .protectPawn,
                move: CoachingGoldenMoves.addsPawnDefender,
                prefix: [
                    step(.helpOpened),
                    pieceStep(.squareInspected, .protectPawn, "g4"),
                    pieceStep(.squareInspected, .protectPawn, "f6"),
                ],
                completed: true,
                operations: completionOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: oracle(
                    requiredEvidence: [reply(CoachingGoldenMoves.addsPawnDefender, CoachingGoldenMoves.knightTakesPawn)],
                    intents: [.evaluateMove, .confirmMove],
                    requiredActions: ["playMove"],
                    success: (
                        "The tutor recognizes that h2-h3 adds an exact pawn defender for g4.",
                        "The tutor follows the staged move and may ground its evaluation in the f6-g4 reply."
                    ),
                    severe: "The turn claims that h2-h3 leaves no possible recapture after the knight takes g4."
                )
            )

        case .t9Entry:
            let snapshot = snapshot(
                .createRookThreat,
                steps: [step(.helpOpened)],
                operations: chooseMoveOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: mobilityThreatOracle()
            )

        case .t9Hint:
            let matingMove = Move(from: sq("g6"), to: sq("g7"))
            let snapshot = snapshot(
                state: mateInOneState(),
                steps: [step(.helpOpened), actionStep(.hint)],
                operations: chooseMoveOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: oracle(
                    requiredEvidence: ["fact:mate-in-one:\(ModelCoachingPositionEncoder.moveID(matingMove))"],
                    intents: [.findMate],
                    success: (
                        "The tutor answers Hint with the supplied noncapturing g6-g7 checkmate move.",
                        "The tutor gives one concrete board task for finding mate without describing the move as a capture."
                    ),
                    severe: "The hint ignores the supplied mate-in-one fact or invents a capture that is absent from the position."
                )
            )

        case .t9Completed:
            let move = CoachingGoldenMoves.knightThreatB3
            let snapshot = stagedSnapshot(
                .createRookThreat,
                move: move,
                trailing: [pieceStep(.squareInspected, .createRookThreat, "d4")],
                operations: completionOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: oracle(
                    intents: [.evaluateMove, .confirmMove],
                    requiredActions: ["playMove"],
                    success: (
                        "The tutor follows the staged a1-b3 move and the learner's inspection of the d4 rook.",
                        "The tutor recognizes the exact knight-to-rook threat and offers commit or revision."
                    ),
                    severe: "The turn ignores the staged move and asks the learner to choose a knight again."
                )
            )

        case .t10Entry:
            let snapshot = snapshot(
                state: longMobilityThreatState(),
                steps: [step(.helpOpened)],
                operations: chooseMoveOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: mobilityThreatOracle()
            )

        case .t10Completed:
            let snapshot = stagedSnapshot(
                .cornerKnight,
                move: CoachingGoldenMoves.knightThreatB3,
                completed: true,
                operations: completionOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: oracle(
                    intents: [.evaluateMove, .confirmMove],
                    requiredActions: ["playMove"],
                    success: (
                        "The tutor recognizes a1-b3 as a legal move that increases the knight's mobility.",
                        "The tutor follows the staged move and offers commit or revision."
                    ),
                    severe: "The turn invents a capture or named threat for a1-b3 in the quiet king-and-knight position."
                )
            )

        case .t11Safe:
            let replacedMove = CoachingGoldenMoves.openingKnightToF3
            let snapshot = snapshot(
                .starting,
                selected: "g1",
                tentativeMove: replacedMove,
                steps: [
                    step(.helpOpened),
                    step(.moveStaged, [ModelCoachingPositionEncoder.moveID(CoachingGoldenMoves.outsidePawn)]),
                    tutorStep(
                        "staged outside-pawn move considered",
                        [ModelCoachingPositionEncoder.moveID(CoachingGoldenMoves.outsidePawn)]
                    ),
                    step(.moveReplaced, [ModelCoachingPositionEncoder.moveID(replacedMove)]),
                ],
                operations: completionOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: oracle(
                    intents: [.evaluateMove, .confirmMove],
                    requiredActions: ["playMove"],
                    success: (
                        "The tutor follows the learner's replacement g1-f3 move instead of continuing to discuss h2-h4.",
                        "The tutor treats the replacement as legal with no encoded severe opponent reply and offers commit or revision."
                    ),
                    severe: "The turn keeps teaching the superseded h2-h4 move or invents a severe reply to g1-f3."
                )
            )

        case .t11QueenLoss:
            let move = CoachingGoldenMoves.exposesQueen
            let snapshot = stagedSnapshot(
                .exposedQueen,
                move: move,
                trailing: [pieceStep(.squareInspected, .exposedQueen, "d8")],
                operations: [.inspectSquare, .replaceMove, .removeMove, .hint, .tryAnotherMove, .closeHelp]
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: replyOracle(
                    after: move,
                    replyMove: CoachingGoldenMoves.rookTakesQueen,
                    intents: [.evaluateMove, .reviseMove],
                    requiredActions: ["tryAnotherMove"],
                    success: (
                        "The tutor acknowledges that the learner found the d8 rook as the dangerous responder.",
                        "The tutor uses the d8-d4 capture evidence to recommend revising d1-d4."
                    ),
                    severe: "The turn approves d1-d4 despite the encoded rook capture of the queen."
                )
            )

        case .t11IncorrectLooksSafe:
            let move = CoachingGoldenMoves.exposesQueen
            let snapshot = stagedSnapshot(
                .exposedQueen,
                move: move,
                trailing: [actionStep(.looksSafe)],
                operations: [.inspectSquare, .replaceMove, .removeMove, .hint, .tryAnotherMove, .closeHelp]
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: replyOracle(
                    after: move,
                    replyMove: CoachingGoldenMoves.rookTakesQueen,
                    intents: [.evaluateMove, .reviseMove],
                    requiredActions: ["tryAnotherMove"],
                    forbiddenActions: ["looksSafe"],
                    success: (
                        "The tutor directly corrects the Looks safe answer with the d8-d4 queen capture.",
                        "The tutor removes the invalid safety option and asks for revision without repeating itself."
                    ),
                    severe: "The turn accepts Looks safe or offers the same invalid answer again."
                )
            )

        case .t11HarmlessCheck:
            let move = CoachingGoldenMoves.developsKnight
            let state = discoveredCheckReplyState()
            let replyMove = Move(from: sq("e7"), to: sq("c8"))
            let snapshot = stagedSnapshot(
                state: state,
                move: move,
                trailing: [pieceStep(.squareInspected, state: state, square: "e8")],
                operations: tentativeOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: replyOracle(
                    after: move,
                    replyMove: replyMove,
                    intents: [.evaluateMove, .confirmMove],
                    success: (
                        "The tutor recognizes that e7-c8 uncovers the e8 rook's check after the staged knight move.",
                        "The tutor identifies the stationary e8 rook as the checker and keeps the next step bounded."
                    ),
                    severe: "The turn assigns the discovered check to the knight on c8 or proves the white knight move illegal."
                )
            )

        case .t11UnsafeBishopEntry:
            let move = CoachingGoldenMoves.bishopToA6
            let snapshot = stagedSnapshot(
                state: openingBishopStateWithHistory(),
                move: move,
                operations: tentativeOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: replyOracle(
                    after: move,
                    replyMove: Move(from: sq("b7"), to: sq("a6")),
                    intents: [.evaluateMove],
                    success: (
                        "The tutor evaluates the staged f1-a6 bishop move from the latest snapshot.",
                        "The tutor asks an answerable opponent-reply question grounded in b7-a6."
                    ),
                    severe: "The turn approves f1-a6 without accounting for the b7 pawn capture."
                )
            )

        case .t11UnsafeBishopFound:
            let move = CoachingGoldenMoves.bishopToA6
            let state = openingBishopStateWithHistory()
            let snapshot = snapshot(
                state: state,
                selected: "f1",
                steps: [
                    step(.helpOpened),
                    step(.moveStaged, [ModelCoachingPositionEncoder.moveID(move)]),
                    tutorStep("opponent reply requested", [ModelCoachingPositionEncoder.moveID(move)]),
                    pieceStep(.squareInspected, state: state, square: "b7"),
                    step(.moveRemoved, [ModelCoachingPositionEncoder.moveID(move)]),
                ],
                operations: chooseMoveOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: replyOracle(
                    after: move,
                    replyMove: Move(from: sq("b7"), to: sq("a6")),
                    intents: [.reviseMove, .chooseMove],
                    success: (
                        "The tutor acknowledges that the learner found b7-a6 and then removed the unsafe bishop move.",
                        "The tutor follows the empty current tentative state and invites a new legal choice without asking for the opponent again."
                    ),
                    severe: "The turn treats the removed f1-a6 move as current or offers to commit it."
                )
            )

        case .t11BenignCaptureTap:
            let move = CoachingGoldenMoves.blackPawnToE6
            let snapshot = stagedSnapshot(
                .protectedPawnUnderBishopAttack,
                move: move,
                learner: .black,
                trailing: [pieceStep(.squareInspected, .protectedPawnUnderBishopAttack, "c4")],
                operations: tentativeOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: replyOracle(
                    after: move,
                    replyMove: CoachingGoldenMoves.bishopTakesE6,
                    intents: [.evaluateMove],
                    success: (
                        "The tutor acknowledges the white bishop's possible c4-e6 capture after Black stages e7-e6.",
                        "The tutor keeps the reply in proportion because Black can answer rather than declaring a forced severe loss."
                    ),
                    severe: "The turn claims that c4-e6 immediately wins an undefended black pawn with no recapture context."
                )
            )

        case .t11BenignCaptureLooksSafe:
            let move = CoachingGoldenMoves.blackPawnToE6
            let snapshot = stagedSnapshot(
                .protectedPawnUnderBishopAttack,
                move: move,
                learner: .black,
                trailing: [
                    pieceStep(.squareInspected, .protectedPawnUnderBishopAttack, "c4"),
                    actionStep(.looksSafe),
                ],
                operations: completionOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: replyOracle(
                    after: move,
                    replyMove: CoachingGoldenMoves.bishopTakesE6,
                    intents: [.evaluateMove, .confirmMove],
                    requiredActions: ["playMove"],
                    success: (
                        "The tutor follows the learner's safety judgment after the benign c4-e6 activity was identified.",
                        "The tutor avoids repeating the same bishop observation and offers commit or revision."
                    ),
                    severe: "The turn changes the benign activity into a forced severe loss or asks the resolved reply question again."
                )
            )

        case .t12CheckLocate:
            let snapshot = snapshot(
                .forcedCheck,
                steps: [step(.helpOpened)],
                operations: locateOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: checkOracle(
                    intents: [.resolveCheck],
                    success: (
                        "The tutor recognizes that White is in check from the black rook on e8.",
                        "The tutor asks one concrete board question about the checker or a legal check response."
                    ),
                    severe: "The turn ignores check and teaches an unrelated capture or development idea."
                )
            )

        case .t12WrongChecker:
            let snapshot = snapshot(
                .forcedCheck,
                steps: [step(.helpOpened), pieceStep(.squareInspected, .forcedCheck, "a8")],
                operations: locateOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: checkOracle(
                    intents: [.resolveCheck],
                    success: (
                        "The tutor rejects the a8 king as the checking piece.",
                        "The tutor redirects to the black rook on e8 without leaving the check-resolution task."
                    ),
                    severe: "The turn says the black king on a8 is checking the white king."
                )
            )

        case .t12Capture:
            let snapshot = stagedSnapshot(
                .forcedCheck,
                move: CoachingGoldenMoves.capturesChecker,
                prefix: [step(.helpOpened), pieceStep(.squareInspected, .forcedCheck, "e8")],
                completed: true,
                operations: completionOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: checkOracle(
                    intents: [.resolveCheck, .confirmMove],
                    requiredActions: ["playMove"],
                    success: (
                        "The tutor recognizes b5-e8 as a legal capture of the checking rook.",
                        "The tutor follows the staged check response and offers commit or revision."
                    ),
                    severe: "The turn says White remains in the same rook check after capturing the rook."
                )
            )

        case .t12Block:
            let snapshot = stagedSnapshot(
                .forcedCheck,
                move: CoachingGoldenMoves.blocksChecker,
                prefix: [step(.helpOpened), pieceStep(.squareInspected, .forcedCheck, "e8")],
                completed: true,
                operations: completionOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: checkOracle(
                    intents: [.resolveCheck, .confirmMove],
                    requiredActions: ["playMove"],
                    success: (
                        "The tutor recognizes b5-e2 as a legal block on the rook's checking line.",
                        "The tutor follows the staged block and offers commit or revision."
                    ),
                    severe: "The turn claims that only capturing the rook can resolve this check."
                )
            )

        case .t12KingMove:
            let move = Move(from: sq("e1"), to: sq("d1"))
            let snapshot = stagedSnapshot(
                .forcedCheck,
                move: move,
                prefix: [step(.helpOpened), pieceStep(.squareInspected, .forcedCheck, "e8")],
                completed: true,
                operations: completionOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: checkOracle(
                    intents: [.resolveCheck, .confirmMove],
                    requiredActions: ["playMove"],
                    success: (
                        "The tutor recognizes e1-d1 as a legal king move out of the rook's line.",
                        "The tutor follows the staged king move and offers commit or revision."
                    ),
                    severe: "The turn says the king must capture or block instead of allowing the legal move to d1."
                )
            )

        case .t12UnsupportedEntry:
            let snapshot = snapshot(
                .unsupportedEndgame,
                steps: [
                    step(.helpOpened),
                    tutorStep("quiet-position guidance displayed"),
                    step(.helpClosed),
                    supersededStep("help panel closed"),
                    step(.helpReopened),
                ],
                operations: [.selectBoardPiece, .stageMove, .closeHelp]
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: oracle(
                    intents: [.chooseMove, .other],
                    forbiddenActions: ["noPieceNeedsHelp", "noSafeCapture", "looksSafe"],
                    success: (
                        "The tutor recalculates the quiet king-only position after Help is closed and reopened.",
                        "The tutor offers a simple current move-selection instruction without resurrecting prior copy or inventing a tactical purpose."
                    ),
                    severe: "The turn repeats superseded guidance as an established stage or invents a board fact in the king-only position."
                )
            )

        case .t12UnsupportedSafeMove:
            let move = Move(from: sq("d4"), to: sq("d5"))
            let snapshot = stagedSnapshot(
                .unsupportedEndgame,
                move: move,
                completed: true,
                operations: completionOperations
            )
            return build(
                goldenCase,
                snapshot: snapshot,
                oracle: oracle(
                    intents: [.evaluateMove, .confirmMove, .other],
                    requiredActions: ["playMove"],
                    success: (
                        "The tutor recognizes d4-d5 as a legal quiet king move with no supplied tactical claim.",
                        "The tutor limits itself to the immediate safety boundary and offers commit or revision."
                    ),
                    severe: "The turn assigns a fabricated named purpose, capture, or forced continuation to d4-d5."
                )
            )
        }
    }

    private static func build(
        _ goldenCase: CoachingGoldenCase,
        snapshot: ModelCoachingSnapshot,
        oracle: ModelCoachingSemanticOracle
    ) -> ModelCoachingEvaluationCase {
        ModelCoachingEvaluationCase(
            id: goldenCase.rawValue,
            split: hiddenIDs.contains(goldenCase.rawValue) ? .hidden : .visible,
            request: ModelCoachingRequestBuilder.build(
                snapshot: snapshot,
                requestID: "corpus:\(goldenCase.rawValue)",
                promptVersion: "tutor-v1"
            ),
            oracle: oracle
        )
    }

    private static func snapshot(
        _ position: CoachingGoldenPosition,
        learner: PieceColor? = nil,
        selected: String? = nil,
        tentativeMove: Move? = nil,
        steps: [CorpusHistoryStep],
        operations: [ModelCoachingOperation]
    ) -> ModelCoachingSnapshot {
        snapshot(
            state: position.state,
            learner: learner,
            selected: selected,
            tentativeMove: tentativeMove,
            steps: steps,
            operations: operations
        )
    }

    private static func snapshot(
        state: GameState,
        learner: PieceColor? = nil,
        selected: String? = nil,
        tentativeMove: Move? = nil,
        steps: [CorpusHistoryStep],
        operations: [ModelCoachingOperation]
    ) -> ModelCoachingSnapshot {
        precondition(!steps.isEmpty)
        guard let latestEventKind = steps.last?.learnerEventKind else {
            preconditionFailure("The final corpus history step must be a learner event")
        }
        let revision = steps.count
        let selectedSquare = tentativeMove?.to ?? selected.map(sq)
        let interaction = CoachingInteractionSnapshot(
            selectedSquare: selectedSquare,
            tentativeMove: tentativeMove,
            positionRevision: revision
        )
        let latest = steps[steps.count - 1]
        return ModelCoachingSnapshot(
            coachingRequest: CoachingRequest(
                committedState: state,
                tentativeMove: tentativeMove,
                learner: learner ?? state.sideToMove,
                positionRevision: revision,
                context: tentativeMove.map { _ in .tentativeMove(origin: .fallback) } ?? .start
            ),
            interaction: interaction,
            latestEvent: ModelCoachingLearnerEvent(
                kind: latestEventKind,
                referencedIDs: latest.referencedIDs
            ),
            currentTurnHistory: steps.enumerated().map { index, event in
                ModelCoachingHistoryEntry(
                    sequence: index + 1,
                    kind: event.historyKind,
                    summary: event.summary,
                    referencedIDs: event.referencedIDs
                )
            },
            availableOperations: operations
        )
    }

    private static func stagedSnapshot(
        _ position: CoachingGoldenPosition,
        move: Move,
        learner: PieceColor? = nil,
        prefix: [CorpusHistoryStep] = [step(.helpOpened)],
        trailing: [CorpusHistoryStep] = [],
        completed: Bool = false,
        operations: [ModelCoachingOperation]
    ) -> ModelCoachingSnapshot {
        stagedSnapshot(
            state: position.state,
            move: move,
            learner: learner,
            prefix: prefix,
            trailing: trailing,
            completed: completed,
            operations: operations
        )
    }

    private static func stagedSnapshot(
        state: GameState,
        move: Move,
        learner: PieceColor? = nil,
        prefix: [CorpusHistoryStep] = [step(.helpOpened)],
        trailing: [CorpusHistoryStep] = [],
        completed: Bool = false,
        operations: [ModelCoachingOperation]
    ) -> ModelCoachingSnapshot {
        var steps = prefix + [step(.moveStaged, [ModelCoachingPositionEncoder.moveID(move)])] + trailing
        if completed {
            steps.append(actionStep(.looksSafe))
        }
        return snapshot(
            state: state,
            learner: learner,
            selected: ModelCoachingPositionEncoder.squareName(move.to),
            tentativeMove: move,
            steps: steps,
            operations: operations
        )
    }

    private static func discoveredCheckReplyState() -> GameState {
        GameState(
            board: Board(pieces: [
                sq("e1"): Piece(kind: .king, color: .white),
                sq("b1"): Piece(kind: .knight, color: .white),
                sq("h8"): Piece(kind: .king, color: .black),
                sq("e8"): Piece(kind: .rook, color: .black),
                sq("e7"): Piece(kind: .knight, color: .black),
            ]),
            sideToMove: .white
        )
    }

    private static func castlingCheckReplyState() -> GameState {
        GameState(
            board: Board(pieces: [
                sq("e1"): Piece(kind: .king, color: .white),
                sq("e8"): Piece(kind: .king, color: .black),
                sq("h8"): Piece(kind: .rook, color: .black),
            ]),
            sideToMove: .white,
            castlingRights: CastlingRights(blackKingside: true)
        )
    }

    private static func longMobilityThreatState() -> GameState {
        let shortState = CoachingGoldenPosition.createRookThreat.state
        var longState = shortState
        let excursion = [
            Move(from: sq("g1"), to: sq("h1")),
            Move(from: sq("g8"), to: sq("h8")),
            Move(from: sq("h1"), to: sq("h2")),
            Move(from: sq("h8"), to: sq("g8")),
            Move(from: sq("h2"), to: sq("g2")),
            Move(from: sq("g8"), to: sq("f8")),
            Move(from: sq("g2"), to: sq("g1")),
            Move(from: sq("f8"), to: sq("g8")),
        ]
        excursion.forEach { move in
            precondition(LegalMoveGenerator.allLegalMoves(in: longState).contains(move))
            longState.apply(move)
        }
        precondition(longState.board == shortState.board)
        precondition(longState.sideToMove == shortState.sideToMove)
        precondition(longState.castlingRights == shortState.castlingRights)
        precondition(longState.enPassantTarget == shortState.enPassantTarget)
        return longState
    }

    private static func mateInOneState() -> GameState {
        GameState(
            board: Board(pieces: [
                sq("f6"): Piece(kind: .king, color: .white),
                sq("g6"): Piece(kind: .queen, color: .white),
                sq("h8"): Piece(kind: .king, color: .black),
            ]),
            sideToMove: .white
        )
    }

    private static func openingBishopStateWithHistory() -> GameState {
        var state = GameState.startingPosition()
        state.apply(Move(from: sq("e2"), to: sq("e4")))
        state.apply(CoachingGoldenMoves.blackPawnToE6)
        precondition(state.board == CoachingGoldenPosition.openingBishopCanBeTaken.state.board)
        return state
    }

    private static func oracle(
        requiredEvidence: [String] = [],
        requiredAnyEvidence: [[String]] = [],
        forbiddenEvidence: [String] = [],
        intents: [ModelCoachingTeachingIntent],
        requiredActions: [String] = [],
        forbiddenActions: [String] = [],
        prohibited: [String] = [],
        success: (String, String),
        severe: String
    ) -> ModelCoachingSemanticOracle {
        ModelCoachingSemanticOracle(
            requiredEvidenceReferences: requiredEvidence.sorted(),
            requiredAnyEvidenceReferenceGroups: requiredAnyEvidence.map { $0.sorted() },
            forbiddenEvidenceReferences: forbiddenEvidence.sorted(),
            requiredActionKinds: requiredActions.sorted(),
            forbiddenActionKinds: forbiddenActions.sorted(),
            permittedTeachingIntents: intents,
            prohibitedPhrases: sharedProhibitedPhrases + prohibited,
            successCriteria: [success.0, success.1],
            severeFailureCriteria: [
                severe,
                "The turn invents a piece, relationship, legal move, or reply that is absent from the request."
            ]
        )
    }

    private static func mobilityThreatOracle() -> ModelCoachingSemanticOracle {
        oracle(
            intents: [.chooseMove],
            success: (
                "The tutor focuses on a legal a1-knight move that improves mobility and creates pressure on d4.",
                "The tutor gives one answerable board task from the current position regardless of prior reversible moves."
            ),
            severe: "The turn claims the a1 knight already attacks the d4 rook before it moves."
        )
    }

    private static func dangerOracle(
        position: CoachingGoldenPosition,
        target: String,
        intents: [ModelCoachingTeachingIntent],
        requiredActions: [String] = [],
        success: (String, String),
        severe: String
    ) -> ModelCoachingSemanticOracle {
        oracle(
            requiredEvidence: [dangerFact(position, target)],
            intents: intents,
            requiredActions: requiredActions,
            success: success,
            severe: severe
        )
    }

    private static func exchangeOracle(
        move: Move,
        intents: [ModelCoachingTeachingIntent],
        requiredActions: [String] = [],
        success: (String, String),
        severe: String
    ) -> ModelCoachingSemanticOracle {
        oracle(
            requiredEvidence: ["fact:exchange-gain:\(ModelCoachingPositionEncoder.moveID(move))"],
            intents: intents,
            requiredActions: requiredActions,
            success: success,
            severe: severe
        )
    }

    private static func replyOracle(
        after move: Move,
        replyMove: Move,
        intents: [ModelCoachingTeachingIntent],
        requiredActions: [String] = [],
        forbiddenActions: [String] = [],
        success: (String, String),
        severe: String
    ) -> ModelCoachingSemanticOracle {
        oracle(
            requiredEvidence: [reply(move, replyMove)],
            intents: intents,
            requiredActions: requiredActions,
            forbiddenActions: forbiddenActions,
            success: success,
            severe: severe
        )
    }

    private static func checkOracle(
        intents: [ModelCoachingTeachingIntent],
        requiredActions: [String] = [],
        success: (String, String),
        severe: String
    ) -> ModelCoachingSemanticOracle {
        oracle(
            requiredEvidence: ["fact:in-check"],
            intents: intents,
            requiredActions: requiredActions,
            forbiddenActions: ["noPieceNeedsHelp", "noSafeCapture", "looksSafe"],
            success: success,
            severe: severe
        )
    }

    private static func dangerFact(_ position: CoachingGoldenPosition, _ square: String) -> String {
        "fact:danger-loss:\(pieceID(position, square))"
    }

    private static func reply(_ move: Move, _ replyMove: Move) -> String {
        "reply:\(ModelCoachingPositionEncoder.moveID(move))->\(ModelCoachingPositionEncoder.moveID(replyMove))"
    }

    private static func pieceID(_ position: CoachingGoldenPosition, _ square: String) -> String {
        pieceID(state: position.state, square: square)
    }

    private static func pieceID(state: GameState, square: String) -> String {
        let boardSquare = sq(square)
        guard let piece = state.board[boardSquare] else {
            preconditionFailure("No piece at \(square)")
        }
        return ModelCoachingPositionEncoder.pieceID(piece, at: boardSquare)
    }

    private static func step(
        _ kind: ModelCoachingLearnerEventKind,
        _ referencedIDs: [String] = []
    ) -> CorpusHistoryStep {
        CorpusHistoryStep(
            historyKind: .learnerEvent,
            learnerEventKind: kind,
            summary: "learner event: \(kind.rawValue)",
            referencedIDs: referencedIDs
        )
    }

    private static func pieceStep(
        _ kind: ModelCoachingLearnerEventKind,
        _ position: CoachingGoldenPosition,
        _ square: String
    ) -> CorpusHistoryStep {
        step(kind, [pieceID(position, square)])
    }

    private static func pieceStep(
        _ kind: ModelCoachingLearnerEventKind,
        state: GameState,
        square: String
    ) -> CorpusHistoryStep {
        step(kind, [pieceID(state: state, square: square)])
    }

    private static func actionStep(_ operation: ModelCoachingOperation) -> CorpusHistoryStep {
        step(.actionChosen, ["action:\(operation.rawValue)"])
    }

    private static func tutorStep(
        _ summary: String,
        _ referencedIDs: [String] = []
    ) -> CorpusHistoryStep {
        CorpusHistoryStep(
            historyKind: .tutorTurn,
            learnerEventKind: nil,
            summary: "tutor turn: \(summary)",
            referencedIDs: referencedIDs
        )
    }

    private static func supersededStep(
        _ summary: String,
        _ referencedIDs: [String] = []
    ) -> CorpusHistoryStep {
        CorpusHistoryStep(
            historyKind: .supersededRequest,
            learnerEventKind: nil,
            summary: "superseded request: \(summary)",
            referencedIDs: referencedIDs
        )
    }
}

private struct CorpusHistoryStep {
    let historyKind: ModelCoachingHistoryKind
    let learnerEventKind: ModelCoachingLearnerEventKind?
    let summary: String
    let referencedIDs: [String]
}

struct LocalCoachingExplanationSource: CoachingExplaining {
    func presentation(for context: CoachingPresentationContext) -> CoachingPresentation {
        let base = baseCopy(for: context.prompt)
        let instruction = instruction(for: context, base: base.instruction)

        return CoachingPresentation(
            headline: headline(for: context, base: base.headline),
            instruction: instruction,
            hint: context.hint,
            routine: context.routine,
            actions: context.actions.map {
                actionPresentation(
                    for: $0,
                    emphasizeHint: context.missesAtCurrentLevel >= 1
                )
            },
            boardTask: context.boardTask,
            focus: context.focus
        )
    }

    private func headline(
        for context: CoachingPresentationContext,
        base: String
    ) -> String {
        guard let feedback = context.feedback else { return base }
        if feedback == .correctAbsence {
            return "Right—there isn’t one. \(base)"
        }
        let acknowledgement = feedbackHeadline(
            for: feedback,
            opponent: opponentColor(for: context),
            prompt: context.prompt
        )
        guard case let .complete(_, idea) = context.prompt else {
            return acknowledgement
        }

        switch feedback {
        case .harmlessCheckFound:
            return "\(acknowledgement) \(completionPurpose(for: idea))"
        case .concreteFlaw:
            return "\(acknowledgement) Your move still works. \(completionPurpose(for: idea))"
        default:
            return acknowledgement
        }
    }

    private func baseCopy(for prompt: CoachingPrompt) -> (headline: String, instruction: String?) {
        switch prompt {
        case .checkLocate:
            return (
                "Your king is in check. What is giving check?",
                "Tap the piece giving check."
            )
        case .checkResolve:
            return (
                "Make a move that gets your king safe.",
                "Move a piece on the board."
            )
        case .safeLocate:
            return (
                "Which of your pieces needs help most?",
                "Tap your piece, or choose I don’t see one."
            )
        case let .safeIdentifyAttacker(piece):
            return (
                "You found the \(piece.rawValue). What black piece is attacking it?",
                "Tap the black piece."
            )
        case let .safeResolve(target, attacker):
            return (
                "Yes—that \(attacker.rawValue) is attacking your \(target.rawValue). How could you help your \(target.rawValue)?",
                "Make a move that gets it safe."
            )
        case .takeChooseMove:
            return (
                "Can one of your pieces make a useful capture?",
                "Make the capture, or choose I don’t see one."
            )
        case let .wakeChoosePiece(purpose):
            return wakePieceCopy(for: purpose)
        case let .wakeChooseMove(piece, purpose):
            return wakeMoveCopy(for: piece, purpose: purpose)
        case let .opponentReply(opponent):
            return (
                "Could \(colorName(opponent)) check your king or win one of your pieces?",
                "Tap the black checking piece, or tap your piece \(colorName(opponent)) could take. Otherwise choose Looks safe."
            )
        case .fallbackChooseMove:
            return (
                "Nothing urgent stands out. Try a move you like, and we’ll check it together.",
                "Make a move on the board."
            )
        case .reviseMove:
            return (
                "Try another move.",
                "Move a piece on the board."
            )
        case .illegalKingSafety:
            return (
                "This move leaves your king in check. Try another move.",
                "Move a piece on the board."
            )
        case let .complete(_, idea):
            return (completionHeadline(for: idea), nil)
        }
    }

    private func wakePieceCopy(
        for purpose: CoachingWakePurpose
    ) -> (headline: String, instruction: String) {
        switch purpose {
        case .openingDevelopment(firstMove: true):
            return (
                "A good first step is to move a center pawn or bring out a knight. Which would you like to try?",
                "Tap the piece you want to move."
            )
        case .openingDevelopment(firstMove: false):
            return (
                "Could you bring out a knight or bishop, move a center pawn, or castle?",
                "Tap the piece you want to move."
            )
        case .addsDefender:
            return ("Which piece could help protect another piece?", "Tap the piece you want to move.")
        case .createsThreat:
            return ("Which piece could safely attack something?", "Tap the piece you want to move.")
        case .centralActivity:
            return ("Which piece could move closer to the center?", "Tap the piece you want to move.")
        case .castle:
            return ("Which piece would you move to castle?", "Tap your king.")
        }
    }

    private func wakeMoveCopy(
        for piece: Piece.Kind,
        purpose: CoachingWakePurpose
    ) -> (headline: String, instruction: String) {
        let headline: String
        switch purpose {
        case .openingDevelopment:
            headline = piece == .pawn
                ? "This pawn can help in the center."
                : "This \(piece.rawValue) can come into the game."
        case .addsDefender:
            headline = "This \(piece.rawValue) can help protect another piece."
        case .createsThreat:
            headline = "This \(piece.rawValue) can safely attack something."
        case .centralActivity:
            headline = "This \(piece.rawValue) can move closer to the center."
        case .castle:
            headline = "Your king can castle."
        }
        let instruction = purpose == .castle
            ? "Move it two squares toward a rook."
            : "Move it on the board."
        return (headline, instruction)
    }

    private func instruction(
        for context: CoachingPresentationContext,
        base: String?
    ) -> String? {
        guard let base else { return nil }
        guard let hint = context.hint else { return base }
        return hintedInstruction(for: hint, prompt: context.prompt, base: base)
    }

    private func hintedInstruction(
        for hint: CoachingHint,
        prompt: CoachingPrompt,
        base: String
    ) -> String {
        switch (hint, prompt) {
        case (.dangerMarker, .safeLocate):
            return "Look for the red danger marker, then tap your piece."
        case (.candidatePieces, .wakeChoosePiece(purpose: .openingDevelopment(firstMove: true))):
            return "Try one of the highlighted knights or center pawns."
        case let (.attackerRelationship, .safeIdentifyAttacker(piece)):
            return "Follow the highlighted line to the piece attacking your \(piece.rawValue)."
        case let (.safeResponseIdeas, .safeResolve(target, _)):
            return "Try moving your \(target.rawValue), protecting it, or taking the attacker."
        case let (.movementMarkers, .wakeChooseMove(piece, _)):
            return "Use the movement markers to choose where your \(piece.rawValue) should go."
        case (.replyMarkers, .opponentReply):
            return "Look for a red danger marker or a check marker."
        case (.candidatePieces, _):
            return "Try one of the highlighted pieces."
        case (.candidateMoves, _):
            return "Try one of the highlighted paths, then make the move yourself."
        case (.checkMarker, .checkLocate):
            return "Look for the check marker, then tap the checking piece."
        default:
            return base
        }
    }

    private func feedbackHeadline(
        for feedback: CoachingFeedback,
        opponent: PieceColor,
        prompt: CoachingPrompt
    ) -> String {
        switch feedback {
        case let .safePiece(piece):
            return "That \(piece.rawValue) is safe right now."
        case let .lowerPriorityThreat(piece, urgentPiece):
            return "Yes, that \(piece.rawValue) is threatened. Your \(urgentPiece.rawValue) is worth more, so help the \(urgentPiece.rawValue) first."
        case let .nonurgentThreat(piece):
            return "Yes, that \(piece.rawValue) is threatened. We’re looking for a knight, bishop, rook, or queen \(colorName(opponent)) could win."
        case .expectedLearnerPiece:
            return "Tap one of your pieces."
        case let .notCheckingPiece(piece):
            if let piece {
                return "That \(piece.rawValue) isn’t giving check."
            }
            return "That square isn’t giving check."
        case let .notAttacker(piece, target):
            return "That \(piece.rawValue) isn’t attacking your \(target.rawValue)."
        case let .expectedAttacker(target):
            return "Tap a \(colorName(opponent).lowercased()) piece attacking your \(target.rawValue)."
        case let .blockedWakePiece(piece):
            return "That \(piece.rawValue) can’t come out yet because other pieces are in the way."
        case let .notWakeCandidate(piece, purpose):
            return "That \(piece.rawValue) can move, but it doesn’t \(wakePurposeVerb(for: purpose))."
        case .notReplyIssue:
            return "That piece doesn’t show a check or capture after this move."
        case .correctAbsence:
            return "Right—there isn’t one."
        case .missedExistingAnswer:
            return missedAnswerHeadline(for: prompt)
        case let .concreteFlaw(kind, affectedPiece):
            return concreteFlawHeadline(
                kind: kind,
                affectedPiece: affectedPiece,
                opponent: opponent
            )
        case let .dangerStillPresent(attacker, target):
            if let attacker {
                return "The \(attacker.rawValue) could still take your \(target.rawValue) after that move."
            }
            return "Your \(target.rawValue) would still need help after that move."
        case let .noRecognizedPurpose(purpose):
            if let purpose {
                return "That move is safe, but it doesn’t \(wakePurposeVerb(for: purpose))."
            }
            return "That move is safe, but it doesn’t help with a clear plan yet."
        case .harmlessCheckFound:
            return "You found it. \(colorName(opponent)) could check your king, but your move still works."
        case .checkFoundOtherDangerRemains:
            return "You found the check. There is still another danger after this move."
        }
    }

    private func missedAnswerHeadline(for prompt: CoachingPrompt) -> String {
        switch prompt {
        case .safeLocate:
            return "One of your pieces does need help."
        case .takeChooseMove:
            return "There is a useful capture to find."
        case let .opponentReply(opponent):
            return "\(colorName(opponent)) has a reply to notice."
        default:
            return "There is something to find."
        }
    }

    private func wakePurposeVerb(for purpose: CoachingWakePurpose) -> String {
        switch purpose {
        case .openingDevelopment:
            return "bring a new piece into the game"
        case .addsDefender:
            return "help protect another piece"
        case .createsThreat:
            return "create a safe threat"
        case .centralActivity:
            return "move closer to the center"
        case .castle:
            return "help your king castle"
        }
    }

    private func concreteFlawHeadline(
        kind: CoachingOpponentIssueKind,
        affectedPiece: Piece.Kind?,
        opponent: PieceColor
    ) -> String {
        let name = colorName(opponent)
        switch kind {
        case .mateInOne:
            return "\(name) could checkmate your king."
        case .check:
            return "\(name) could check your king."
        case .materialLoss:
            if let affectedPiece {
                return "\(name) could take your \(affectedPiece.rawValue)."
            }
            return "\(name) could win some material."
        }
    }

    private func completionHeadline(for idea: CoachingCompletionIdea) -> String {
        "That works. \(completionPurpose(for: idea))"
    }

    private func completionPurpose(for idea: CoachingCompletionIdea) -> String {
        let concept: String
        switch idea {
        case let .resolvesDanger(piece):
            concept = "Your \(piece.rawValue) is safe now."
        case .mate:
            concept = "You found checkmate."
        case let .profitableCapture(captured):
            concept = "Your capture wins a \(captured.rawValue)."
        case let .develops(piece):
            concept = "Your \(piece.rawValue) came into the game. Chess players call that developing a piece."
        case .advancesCenterPawn:
            concept = "Your pawn helps control the center."
        case .castles:
            concept = "Castling helps keep your king safe."
        case let .addsDefender(piece):
            concept = "Your \(piece.rawValue) adds a defender."
        case let .createsThreat(piece):
            concept = "Your \(piece.rawValue) creates a threat."
        case let .centralizes(piece):
            concept = "Your \(piece.rawValue) gets a more useful place near the center."
        case .verifiedSafe:
            concept = "Your move stays safe after the reply."
        }
        return concept
    }

    private func actionPresentation(
        for action: CoachingAction,
        emphasizeHint: Bool
    ) -> CoachingActionPresentation {
        switch action {
        case .noAnswer:
            return CoachingActionPresentation(
                action: action,
                title: "I don’t see one",
                accessibilityLabel: "I don’t see one",
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
                prominence: emphasizeHint ? .primary : .secondary
            )
        case .stop:
            return CoachingActionPresentation(
                action: action,
                title: "Stop",
                accessibilityLabel: "Stop coaching",
                prominence: .quiet
            )
        case .done:
            return CoachingActionPresentation(
                action: action,
                title: "Done",
                accessibilityLabel: "Done with this move",
                prominence: .primary
            )
        case .keepLooking:
            return CoachingActionPresentation(
                action: action,
                title: "Keep looking",
                accessibilityLabel: "Keep looking for another move",
                prominence: .secondary
            )
        }
    }

    private func opponentColor(for context: CoachingPresentationContext) -> PieceColor {
        if case let .opponentReply(opponent) = context.prompt {
            return opponent
        }
        return context.learner.opposite
    }

    private func colorName(_ color: PieceColor) -> String {
        switch color {
        case .white:
            return "White"
        case .black:
            return "Black"
        }
    }
}

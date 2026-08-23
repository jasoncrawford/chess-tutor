struct LocalCoachingExplanationSource: CoachingExplaining {
    func presentation(for context: CoachingPresentationContext) -> CoachingPresentation {
        let base = baseCopy(for: context.prompt, learner: context.learner)
        return CoachingPresentation(
            response: responseCopy(for: context),
            headline: headline(for: context, base: base.headline),
            instruction: instruction(for: context, base: base.instruction),
            hint: context.hint,
            routine: context.routine,
            actions: context.actions.map { actionPresentation(for: $0, context: context) },
            boardTask: context.boardTask,
            focus: context.focus
        )
    }

    private func responseCopy(for context: CoachingPresentationContext) -> String? {
        guard let feedback = context.feedback else { return nil }
        return feedbackHeadline(
            for: feedback,
            opponent: opponentColor(for: context),
            prompt: context.prompt
        )
    }

    private func baseCopy(
        for prompt: CoachingPrompt,
        learner: PieceColor
    ) -> (headline: String, instruction: String?) {
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
                "One of your pieces is in danger. Which one?",
                "Tap your piece, or choose No piece needs help."
            )
        case let .safeIdentifyAttacker(piece):
            let opponent = colorName(learner.opposite)
            return (
                "You found the \(piece.rawValue). What \(opponent.lowercased()) piece is attacking it?",
                "Tap the \(opponent.lowercased()) piece."
            )
        case let .safeResolve(target, attacker):
            return (
                "Yes—that \(attacker.rawValue) is attacking your \(target.rawValue). How could you help your \(target.rawValue)?",
                "Make a move that gets it safe."
            )
        case .takeChooseMove:
            return (
                "Can one of your pieces safely take a \(colorName(learner.opposite).lowercased()) piece?",
                "Make the capture, or choose No safe capture."
            )
        case let .wakeChoosePiece(purpose):
            return wakePieceCopy(for: purpose)
        case let .wakeChooseMove(piece, purpose):
            return wakeMoveCopy(for: piece, purpose: purpose)
        case let .opponentReply(opponent):
            let opponentName = colorName(opponent)
            return (
                "Could \(opponentName) check your king or win one of your pieces?",
                "Tap the \(opponentName.lowercased()) checking piece, or tap your piece \(opponentName) could take. Otherwise choose Looks safe."
            )
        case .fallbackChooseMove:
            return (
                "Nothing urgent stands out. Try a move you like, and we’ll check it together.",
                "Make a move on the board."
            )
        case .unsupportedFallbackChooseMove:
            return (
                "I do not have a confident plan for this position yet.",
                "Choose a move you are considering, and I will check it with you."
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
            return (
                completionHeadline(for: idea, opponent: learner.opposite),
                nil
            )
        }
    }

    private func wakePieceCopy(
        for purpose: CoachingWakePurpose
    ) -> (headline: String, instruction: String) {
        switch purpose {
        case .openingDevelopment(firstMove: true):
            return (
                "A center pawn or knight is a simple way to start. Which would you like to move?",
                "Tap one of your two center pawns or one of your knights."
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

    private func headline(for context: CoachingPresentationContext, base: String) -> String {
        if case .lowerPriorityDanger = context.feedback {
            return "Which piece should you help first?"
        }
        if context.hint == .candidatePieces,
           context.prompt == .wakeChoosePiece(
               purpose: .openingDevelopment(firstMove: true)
           ) {
            return "Here are the four pieces you can try."
        }
        return base
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
        switch context.feedback {
        case .unsafeCapture:
            return "Change your move, or choose No safe capture."
        case .noSafeCaptureForPiece:
            return "Try another piece, or choose No safe capture."
        case .safeCaptureHint:
            return "Tap the highlighted \(colorName(context.learner).lowercased()) piece."
        default:
            break
        }
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
            return "Tap a highlighted piece."
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
        case let .lowerPriorityDanger(chosen, chosenLoss, primary, primaryLoss):
            if chosen == .pawn,
               primary == .knight,
               chosenLoss == 1,
               primaryLoss == 3 {
                return "You found a threatened pawn. A knight is worth about three pawns, so losing the knight would cost more."
            }
            if primaryLoss > chosenLoss {
                return "You found a threatened \(chosen.rawValue). Losing the \(primary.rawValue) would cost more."
            }
            return "You found a threatened \(chosen.rawValue). Your \(primary.rawValue) is worth more, so help it first."
        case let .attackedButProtected(target, attacker, defender):
            return "The \(target.rawValue) is attacked, but your other \(defender.rawValue) protects it. If the \(attacker.rawValue) takes it, your \(defender.rawValue) can take the \(attacker.rawValue) back. No piece needs help right now."
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
            return "That square doesn’t show a check or capture after this move."
        case let .correctAbsence(kind):
            switch kind {
            case .noPieceNeedsHelp:
                return "Right—no piece needs help right now."
            case .noSafeCapture:
                return "Right—there is no safe capture here."
            }
        case let .missedExistingAnswer(kind):
            switch kind {
            case .noPieceNeedsHelp:
                return "One of your pieces does need help."
            case .noSafeCapture:
                return "There is a safe capture to find."
            }
        case .missedOpponentReply:
            return missedAnswerHeadline(for: prompt)
        case .noSafeCaptureForPiece:
            return "That piece has no safe capture here."
        case let .safeCaptureHint(piece):
            return "Your \(piece.rawValue) has a safe capture."
        case let .unsafeCapture(fact):
            return unsafeCaptureCopy(fact, opponent: opponent)
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
            return "There is a safe capture to find."
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

    private func completionHeadline(
        for idea: CoachingCompletionIdea,
        opponent: PieceColor
    ) -> String {
        if case .resolvesDanger = idea {
            return completionPurpose(for: idea, opponent: opponent)
        }
        if case .safeCapture = idea {
            return completionPurpose(for: idea, opponent: opponent)
        }
        return "That works. \(completionPurpose(for: idea, opponent: opponent))"
    }

    private func completionPurpose(
        for idea: CoachingCompletionIdea,
        opponent: PieceColor
    ) -> String {
        let concept: String
        switch idea {
        case let .resolvesDanger(resolution):
            return dangerResolutionCopy(resolution)
        case .resolvesCheck:
            concept = "Your king is safe now."
        case .mate:
            concept = "You found checkmate."
        case let .profitableCapture(captured):
            concept = "Your capture wins a \(captured.rawValue)."
        case let .safeCapture(fact):
            return safeCaptureCopy(fact, opponent: opponent)
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

    private func safeCaptureCopy(
        _ fact: CoachingExchangeFact,
        opponent: PieceColor
    ) -> String {
        let opponentName = colorName(opponent)
        if let recapturer = fact.immediateRecapturer {
            return "Your \(fact.mover.rawValue) took a \(fact.captured.rawValue). \(opponentName)’s \(recapturer.rawValue) could take the \(fact.mover.rawValue) back, so you would trade a \(fact.mover.rawValue) for a \(fact.captured.rawValue)."
        }
        return "Your \(fact.mover.rawValue) took a \(fact.captured.rawValue), and \(opponentName) cannot take the \(fact.mover.rawValue) back."
    }

    private func unsafeCaptureCopy(
        _ fact: CoachingExchangeFact,
        opponent: PieceColor
    ) -> String {
        guard let recapturer = fact.immediateRecapturer else {
            return "That piece has no safe capture here."
        }
        return "\(colorName(opponent))’s \(recapturer.rawValue) could take your \(fact.mover.rawValue). You would lose a \(fact.mover.rawValue) to take one \(fact.captured.rawValue)."
    }

    private func dangerResolutionCopy(_ resolution: CoachingDangerResolution) -> String {
        switch resolution {
        case let .movedTarget(target, attacker):
            switch attacker {
            case .bishop, .rook, .queen:
                return "Your \(target.rawValue) moved out of the \(attacker.rawValue)’s path. It is safe now."
            case .pawn, .knight, .king:
                return "Your \(target.rawValue) is out of the \(attacker.rawValue)'s attack. It is safe now."
            }
        case let .capturedAttacker(capturer, target, attacker):
            if capturer == target {
                return "Your \(capturer.rawValue) took the attacking \(attacker.rawValue). It is safe now."
            }
            return "Your \(capturer.rawValue) took the attacking \(attacker.rawValue). Your \(target.rawValue) is safe now."
        case let .addedDefender(defender, target, attacker):
            return "Your other \(defender.rawValue) now protects the threatened \(target.rawValue). If the \(attacker.rawValue) takes it, your \(defender.rawValue) can take the \(attacker.rawValue) back."
        }
    }

    private func actionPresentation(
        for action: CoachingAction,
        context: CoachingPresentationContext
    ) -> CoachingActionPresentation {
        switch action {
        case .noAnswer:
            let title = context.prompt == .safeLocate
                ? "No piece needs help"
                : "No safe capture"
            return CoachingActionPresentation(
                action: action,
                title: title,
                accessibilityLabel: title,
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
                prominence: context.missesAtCurrentLevel >= 1 ? .primary : .secondary
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

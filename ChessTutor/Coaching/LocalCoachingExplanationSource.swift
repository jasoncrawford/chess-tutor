struct LocalCoachingExplanationSource: CoachingExplaining {
    func presentation(for context: CoachingPresentationContext) -> CoachingPresentation {
        let base = baseCopy(for: context.prompt)
        let instruction = instruction(for: context, base: base.instruction)

        return CoachingPresentation(
            headline: context.feedback.map {
                feedbackHeadline(
                    for: $0,
                    opponent: opponentColor(for: context)
                )
            } ?? base.headline,
            instruction: instruction,
            routine: context.routine,
            actions: context.actions.map {
                actionPresentation(
                    for: $0,
                    emphasizeHint: context.missesAtCurrentLevel >= 2
                )
            },
            boardTask: context.boardTask,
            focus: context.focus
        )
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
                "Does one of your pieces need help?",
                "Tap that piece, or choose I don’t see one."
            )
        case let .safeIdentifyAttacker(piece):
            return (
                "What could take your \(piece.rawValue)?",
                "Tap the attacker."
            )
        case let .safeResolve(piece):
            return (
                "How could you help your \(piece.rawValue)?",
                "Make a move on the board."
            )
        case .takeChooseMove:
            return (
                "Can you find a capture that helps you?",
                "Make the capture, or choose I don’t see one."
            )
        case let .wakeChoosePiece(opening):
            if opening {
                return (
                    "Nothing is in danger yet. Can you help the center or wake up a piece?",
                    "Tap a piece that could get a job."
                )
            }
            return (
                "Which piece could get a useful job?",
                "Tap that piece."
            )
        case let .wakeChooseMove(piece):
            return (
                "Where could your \(piece.rawValue) help from?",
                "Move it on the board."
            )
        case let .opponentReply(opponent):
            return (
                "Could \(colorName(opponent)) check your king or win something?",
                "Tap the problem, change your move, or choose Looks safe."
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

    private func instruction(
        for context: CoachingPresentationContext,
        base: String?
    ) -> String? {
        guard let base else { return nil }

        let hinted: String
        switch context.hintLevel {
        case ...0:
            hinted = base
        case 1:
            hinted = levelOneInstruction(for: context.prompt, base: base)
        case 2:
            hinted = "Look at the highlighted choices. \(base)"
        case 3:
            hinted = "Look at the highlighted pieces and their connection. \(base)"
        default:
            switch context.boardTask {
            case .none:
                hinted = base
            case .identify:
                hinted = "Follow the highlighted path, then tap the piece yourself."
            case .move:
                hinted = "Follow the highlighted path, then make the move yourself."
            }
        }

        guard context.missesAtCurrentLevel >= 2,
              context.actions.contains(.hint)
        else {
            return hinted
        }
        return "\(hinted) Want a hint?"
    }

    private func levelOneInstruction(for prompt: CoachingPrompt, base: String) -> String {
        switch prompt {
        case .checkLocate:
            return "Follow the check marker, then tap the checking piece."
        case .checkResolve:
            return "Use the movement markers to find a move that makes the check marker disappear."
        case .safeLocate:
            return "Look for a danger marker. Tap that piece, or choose I don’t see one."
        case .safeIdentifyAttacker:
            return "Follow the danger marker to the attacker, then tap it."
        case .safeResolve:
            return "Use the defense and movement markers, then make a move."
        case .takeChooseMove:
            return "Use the capture markers to look for a helpful capture."
        case .wakeChoosePiece:
            return "Look at the movement markers for a piece that could get a job."
        case .wakeChooseMove:
            return "Use the movement markers to find a square where it can help."
        case .opponentReply:
            return "Look for a check or danger marker, then tap the problem or choose Looks safe."
        case .fallbackChooseMove, .reviseMove, .illegalKingSafety:
            return "Use the movement markers, then make a move on the board."
        case .complete:
            return base
        }
    }

    private func feedbackHeadline(
        for feedback: CoachingFeedback,
        opponent: PieceColor
    ) -> String {
        switch feedback {
        case .correct:
            return "Yes."
        case .correctAlternative:
            return "Yes, that works too."
        case let .relevantButNonurgent(piece):
            return "That \(piece.rawValue) is threatened, but it isn’t in big danger."
        case .unrelatedTap:
            return "That piece isn’t part of this problem."
        case .correctAbsence:
            return "Right—there isn’t one."
        case .missedExistingAnswer:
            return "There is one to find."
        case let .concreteFlaw(kind, affectedPiece):
            return concreteFlawHeadline(
                kind: kind,
                affectedPiece: affectedPiece,
                opponent: opponent
            )
        case let .dangerStillPresent(piece):
            return "Your \(piece.rawValue) would still need help."
        case .noRecognizedPurpose:
            return "That move looks safe, but give the piece a clear job."
        case .harmlessCheckFound:
            return "Yes. \(colorName(opponent)) could check your king, but your move still works."
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
        let concept: String
        switch idea {
        case let .resolvesDanger(piece):
            concept = "Your \(piece.rawValue) is safe now."
        case .mate:
            concept = "You found checkmate."
        case let .profitableCapture(captured):
            concept = "Your capture wins a \(captured.rawValue)."
        case let .develops(piece):
            concept = "Your \(piece.rawValue) joined the game and helps in the center."
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
        return "That works. \(concept)"
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

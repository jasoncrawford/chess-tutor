struct LocalCoachingExplanationSource: CoachingExplaining {
    private struct AuthoredTurn {
        let primaryMessage: String
        let instruction: String?
        let observation: String?
    }

    func presentation(for context: CoachingPresentationContext) -> CoachingPresentation {
        let turn = authoredTurn(for: context)
        return CoachingPresentation(
            primaryMessage: turn.primaryMessage,
            instruction: turn.instruction,
            observation: turn.observation,
            hint: context.hint,
            routine: context.routine,
            actions: context.actions.map { actionPresentation(for: $0, context: context) },
            boardTask: context.boardTask,
            focus: context.focus
        )
    }

    private func authoredTurn(for context: CoachingPresentationContext) -> AuthoredTurn {
        var current = currentTaskCopy(for: context)

        if case .lowerPriorityDanger = context.feedback {
            current = AuthoredTurn(
                primaryMessage: "Which piece should you help first?",
                instruction: current.instruction,
                observation: nil
            )
        }
        if context.hint == .candidatePieces,
           context.prompt == .wakeChoosePiece(
               purpose: .openingDevelopment(firstMove: true)
           ) {
            current = AuthoredTurn(
                primaryMessage: "Here are the four pieces you can try.",
                instruction: "Tap a highlighted piece.",
                observation: nil
            )
        }
        if context.hint == .candidatePieces,
           case .wake(
               task: .opening(firstMove: true, castleIsAlternative: _, candidates: _),
               selectedPiece: nil
           ) = context.prompt {
            current = AuthoredTurn(
                primaryMessage: "Here are the four pieces you can try.",
                instruction: "Tap a highlighted piece.",
                observation: nil
            )
        }
        if context.hint == .candidateMoves,
           case let .wake(
               task: .createThreat(_, sourcePiece, _, targetPiece, candidates),
               selectedPiece: _
           ) = context.prompt,
           candidates.count == 2 {
            current = AuthoredTurn(
                primaryMessage:
                    "Both highlighted squares let the \(sourcePiece.rawValue) attack the \(targetPiece.rawValue).",
                instruction:
                    "Move the \(sourcePiece.rawValue) to one of the highlighted squares.",
                observation: nil
            )
        }

        return AuthoredTurn(
            primaryMessage: current.primaryMessage,
            instruction: contextualInstruction(for: context, base: current.instruction),
            observation: observationCopy(for: context)
        )
    }

    private func currentTaskCopy(for context: CoachingPresentationContext) -> AuthoredTurn {
        let learner = context.learner
        switch context.prompt {
        case .awaitingAdvice:
            return AuthoredTurn(
                primaryMessage: "I'm checking the board.",
                instruction: nil,
                observation: nil
            )
        case .checkLocate:
            return AuthoredTurn(
                primaryMessage: "What piece is checking your king?",
                instruction: "Tap the checking piece.",
                observation: nil
            )
        case .checkResolve:
            return AuthoredTurn(
                primaryMessage: "Get your king out of check.",
                instruction: "Move your king, block the check, or take the checking piece.",
                observation: nil
            )
        case .safeLocate:
            return AuthoredTurn(
                primaryMessage: "Which of your pieces is in danger?",
                instruction: "Tap your piece, or choose No piece needs help.",
                observation: nil
            )
        case let .safeIdentifyAttacker(piece):
            let opponent = colorName(learner.opposite).lowercased()
            return AuthoredTurn(
                primaryMessage: "What \(opponent) piece is attacking your \(piece.rawValue)?",
                instruction: "Tap the \(opponent) piece.",
                observation: nil
            )
        case let .safeResolve(target, attacker):
            return AuthoredTurn(
                primaryMessage: "The \(attacker.rawValue) attacks your \(target.rawValue).",
                instruction: "Move, protect, or trade your \(target.rawValue).",
                observation: nil
            )
        case .takeChooseMove:
            return AuthoredTurn(
                primaryMessage:
                    "Can one of your pieces safely take a \(colorName(learner.opposite).lowercased()) piece?",
                instruction: "Make the capture, or choose No safe capture.",
                observation: nil
            )
        case .mateChooseMove:
            return AuthoredTurn(
                primaryMessage: "Can you find checkmate in one move?",
                instruction: "Make the checkmating move.",
                observation: nil
            )
        case let .wakeChoosePiece(purpose):
            return authoredWakePieceCopy(for: purpose)
        case let .wakeChooseMove(piece, purpose):
            return authoredWakeMoveCopy(for: piece, purpose: purpose)
        case let .wake(task, selectedPiece):
            return authoredWakeTaskCopy(
                for: task,
                selectedPiece: selectedPiece,
                learner: learner
            )
        case let .opponentReply(opponent, threatenedPiece):
            let opponentName = colorName(opponent)
            let instruction = threatenedPiece.map {
                "Tap the \(opponentName.lowercased()) piece that could win your \($0.rawValue)."
            } ?? "Tap a \(opponentName.lowercased()) piece that could check your king or win one of your pieces."
            return AuthoredTurn(
                primaryMessage: "What could \(opponentName) do next?",
                instruction: instruction,
                observation: nil
            )
        case .fallbackChooseMove, .unsupportedFallbackChooseMove:
            return AuthoredTurn(
                primaryMessage: "What move would you like to try?",
                instruction: "Move a piece.",
                observation: nil
            )
        case let .opponentIssueRevise(kind, affectedPiece):
            return authoredOpponentIssueRevision(
                kind: kind,
                affectedPiece: affectedPiece,
                context: context
            )
        case .reviseMove:
            return AuthoredTurn(
                primaryMessage: "Try another move.",
                instruction: "Move a piece.",
                observation: nil
            )
        case .illegalKingSafety:
            return AuthoredTurn(
                primaryMessage: "That move leaves your king in check.",
                instruction: "Try another move.",
                observation: nil
            )
        case let .complete(_, idea):
            return AuthoredTurn(
                primaryMessage: completionCopy(for: idea, opponent: learner.opposite),
                instruction: "Play it, or try another move.",
                observation: nil
            )
        }
    }

    private func authoredOpponentIssueRevision(
        kind: CoachingOpponentIssueKind,
        affectedPiece: Piece.Kind?,
        context: CoachingPresentationContext
    ) -> AuthoredTurn {
        let primaryMessage: String
        if case let .opponentIssue(fact) = context.feedback {
            primaryMessage = opponentIssueCopy(
                fact,
                opponent: opponentColor(for: context)
            )
        } else {
            primaryMessage = concreteFlawCopy(
                kind: kind,
                affectedPiece: affectedPiece,
                opponent: opponentColor(for: context)
            )
        }

        let instruction: String
        switch (kind, affectedPiece) {
        case (.materialLoss, let piece?):
            instruction = "Try a different \(piece.rawValue) move."
        case (.check, _), (.mateInOne, _):
            instruction = "Try a move that keeps your king safe."
        case (.materialLoss, nil):
            instruction = "Try a different move."
        }
        return AuthoredTurn(
            primaryMessage: primaryMessage,
            instruction: instruction,
            observation: nil
        )
    }

    private func authoredWakePieceCopy(for purpose: CoachingWakePurpose) -> AuthoredTurn {
        switch purpose {
        case .openingDevelopment(firstMove: true):
            return AuthoredTurn(
                primaryMessage: "A center pawn or knight is a simple way to start.",
                instruction: "Tap a center pawn or knight.",
                observation: nil
            )
        case .openingDevelopment(firstMove: false):
            return AuthoredTurn(
                primaryMessage: "Could you develop a piece or castle?",
                instruction: "Tap the piece you want to move.",
                observation: nil
            )
        case .addsDefender:
            return AuthoredTurn(
                primaryMessage: "Which piece would you like to move?",
                instruction: "Tap the piece you want to move.",
                observation: nil
            )
        case .createsThreat:
            return AuthoredTurn(
                primaryMessage: "Which piece would you like to move?",
                instruction: "Tap the piece you want to move.",
                observation: nil
            )
        case .centralActivity:
            return AuthoredTurn(
                primaryMessage: "Which piece could move closer to the center?",
                instruction: "Tap the piece you want to move.",
                observation: nil
            )
        case .castle:
            return AuthoredTurn(
                primaryMessage: "Your king can castle.",
                instruction: "Tap your king.",
                observation: nil
            )
        }
    }

    private func authoredWakeTaskCopy(
        for task: CoachingWakeTask,
        selectedPiece: Piece.Kind?,
        learner: PieceColor
    ) -> AuthoredTurn {
        switch task {
        case let .opening(firstMove, castleIsAlternative, _):
            if let selectedPiece {
                if !firstMove, castleIsAlternative, selectedPiece == .knight {
                    return AuthoredTurn(
                        primaryMessage: "This knight can be developed.",
                        instruction: "Move the knight.",
                        observation: nil
                    )
                }
                if selectedPiece == .pawn {
                    return AuthoredTurn(
                        primaryMessage: "This center pawn can help control the center.",
                        instruction: "Move the pawn one or two squares.",
                        observation: nil
                    )
                }
                if selectedPiece == .knight || selectedPiece == .bishop {
                    return AuthoredTurn(
                        primaryMessage:
                            "Moving this \(selectedPiece.rawValue) is called developing it.",
                        instruction: "Move the \(selectedPiece.rawValue).",
                        observation: nil
                    )
                }
            }
            return authoredWakePieceCopy(
                for: .openingDevelopment(firstMove: firstMove)
            )
        case .castle:
            return AuthoredTurn(
                primaryMessage: "Your king is ready to castle.",
                instruction: "Move your king two squares toward the rook.",
                observation: nil
            )
        case let .protect(_, sourcePiece, _, targetPiece, _):
            return AuthoredTurn(
                primaryMessage:
                    "Your \(sourcePiece.rawValue) can protect your \(targetPiece.rawValue).",
                instruction:
                    "Move the \(sourcePiece.rawValue) to protect the \(targetPiece.rawValue).",
                observation: nil
            )
        case let .createThreat(_, sourcePiece, _, targetPiece, _):
            return AuthoredTurn(
                primaryMessage:
                    "Your \(sourcePiece.rawValue) can attack \(colorName(learner.opposite))'s \(targetPiece.rawValue).",
                instruction:
                    "Move the \(sourcePiece.rawValue) to attack the \(targetPiece.rawValue).",
                observation: nil
            )
        case let .improveMobility(_, piece, sourceIsCorner, before, _):
            guard sourceIsCorner else {
                return AuthoredTurn(
                    primaryMessage: "Your \(piece.rawValue) can reach more squares.",
                    instruction: "Move the \(piece.rawValue).",
                    observation: nil
                )
            }
            return AuthoredTurn(
                primaryMessage:
                    "Your \(piece.rawValue) has only \(countName(before)) moves in this corner.",
                instruction: "Move it closer to the center.",
                observation: nil
            )
        }
    }

    private func authoredWakeMoveCopy(
        for piece: Piece.Kind,
        purpose: CoachingWakePurpose
    ) -> AuthoredTurn {
        let primaryMessage: String
        switch purpose {
        case .openingDevelopment:
            primaryMessage = piece == .pawn
                ? "This pawn can help in the center."
                : "Moving this \(piece.rawValue) is called developing it."
        case .addsDefender, .createsThreat:
            primaryMessage = "Where would you like to move your \(piece.rawValue)?"
        case .centralActivity:
            primaryMessage = "This \(piece.rawValue) can move closer to the center."
        case .castle:
            primaryMessage = "Your king can castle."
        }
        return AuthoredTurn(
            primaryMessage: primaryMessage,
            instruction: purpose == .castle
                ? "Move it two squares toward a rook."
                : "Move the \(piece.rawValue).",
            observation: nil
        )
    }

    private func observationCopy(for context: CoachingPresentationContext) -> String? {
        guard let feedback = context.feedback else { return nil }
        if context.hint != nil,
           case .missedOpponentIssue = feedback {
            return nil
        }
        if case .opponentIssueRevise = context.prompt {
            return nil
        }
        return feedbackObservation(
            for: feedback,
            opponent: opponentColor(for: context),
            prompt: context.prompt
        )
    }

    private func contextualInstruction(
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
        case let .missedOpponentIssue(fact):
            let opponent = colorName(context.learner.opposite).lowercased()
            let target = "the \(opponent) \(fact.replyPiece.rawValue)"
            return context.actions.contains(.hint)
                ? "Tap \(target), or choose Hint."
                : "Tap \(target)."
        default:
            break
        }
        let actionConsistentBase: String
        switch context.prompt {
        case .safeLocate where !context.actions.contains(.noAnswer):
            actionConsistentBase = "Tap your piece."
        case let .opponentReply(opponent, threatenedPiece)
            where !context.actions.contains(.looksSafe):
            actionConsistentBase = threatenedPiece.map {
                "Tap the \(colorName(opponent).lowercased()) piece that could win your \($0.rawValue)."
            } ?? "Tap a \(colorName(opponent).lowercased()) piece that could check your king or win one of your pieces."
        default:
            actionConsistentBase = base
        }
        guard let hint = context.hint else { return actionConsistentBase }
        return hintedInstruction(
            for: hint,
            prompt: context.prompt,
            base: actionConsistentBase
        )
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
        case (
            .candidatePieces,
            .wake(
                task: .opening(firstMove: true, castleIsAlternative: _, candidates: _),
                selectedPiece: nil
            )
        ):
            return "Tap a highlighted piece."
        case (
            .candidateMoves,
            .wake(task: .createThreat(_, let sourcePiece, _, _, _), selectedPiece: _)
        ):
            return "Move the \(sourcePiece.rawValue) to one of the highlighted squares."
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

    private func feedbackObservation(
        for feedback: CoachingFeedback,
        opponent: PieceColor,
        prompt: CoachingPrompt
    ) -> String {
        switch feedback {
        case let .safePiece(piece):
            return "That \(piece.rawValue) is safe."
        case let .lowerPriorityDanger(chosen, _, primary, _):
            return "You found a threatened \(chosen.rawValue), but losing the \(primary.rawValue) would cost more."
        case let .attackedButProtected(fact):
            let defender = fact.target == fact.defender
                ? "another \(fact.defender.rawValue)"
                : "your \(fact.defender.rawValue)"
            return "The \(fact.attacker.rawValue) attacks your \(fact.target.rawValue), but \(defender) protects it."
        case .expectedLearnerPiece:
            return "That is not one of your pieces."
        case let .notCheckingPiece(piece):
            if let piece {
                return "That \(piece.rawValue) isn’t giving check."
            }
            return "That square isn’t giving check."
        case let .notAttacker(piece, target):
            return "That \(piece.rawValue) isn’t attacking your \(target.rawValue)."
        case let .expectedAttacker(target):
            return "That piece is not attacking your \(target.rawValue)."
        case let .blockedWakePiece(piece, blocker):
            return "Your \(blocker.rawValue) blocks that \(piece.rawValue)."
        case let .notWakeCandidate(piece, purpose):
            if purpose == .addsDefender || purpose == .createsThreat {
                return "Try another piece."
            }
            if piece == .pawn,
               case .wake(
                   task: .opening(firstMove: true, castleIsAlternative: _, candidates: _),
                   selectedPiece: nil
               )
                = prompt {
                return "That pawn is outside the center."
            }
            return "That \(piece.rawValue) does not \(wakePurposeVerb(for: purpose))."
        case .notReplyIssue:
            return "That piece cannot check or win a piece here."
        case let .benignOpponentActivity(activity):
            if let capturedPiece = activity.capturedPiece,
               activity.immediateRecapture != nil {
                return "That \(activity.opponentPiece.rawValue) attacks your \(capturedPiece.rawValue), but the \(capturedPiece.rawValue) is protected."
            }
            if let capturedPiece = activity.capturedPiece {
                return "That \(activity.opponentPiece.rawValue) attacks your \(capturedPiece.rawValue), but it does not win the piece."
            }
            return "That \(activity.opponentPiece.rawValue) cannot win a piece here."
        case let .correctAbsence(kind):
            switch kind {
            case .noPieceNeedsHelp:
                return "No piece needs help right now."
            case .noSafeCapture:
                return "There is no safe capture here."
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
        case let .missedOpponentIssue(fact), let .opponentIssue(fact):
            return opponentIssueCopy(fact, opponent: opponent)
        case .opponentReplyLooksSafe:
            return "\(colorName(opponent)) cannot check your king or win a piece next."
        case .noSafeCaptureForPiece:
            return "That piece has no safe capture here."
        case let .safeCaptureHint(piece):
            return "Your \(piece.rawValue) has a safe capture."
        case let .unsafeCapture(fact):
            return unsafeCaptureCopy(fact, opponent: opponent)
        case let .concreteFlaw(kind, affectedPiece):
            return concreteFlawCopy(
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
            if purpose == .addsDefender || purpose == .createsThreat {
                return "Try another idea."
            }
            if purpose == .castle,
               case .wake(task: .castle, selectedPiece: .king) = prompt {
                return "Castling moves your king two squares toward the rook."
            }
            if let purpose {
                return "That move does not \(wakePurposeVerb(for: purpose))."
            }
            return "That move seems safe."
        case .harmlessCheckFound:
            return "\(colorName(opponent)) could check your king, but your move still works."
        case .checkFoundOtherDangerRemains:
            return "You found the check, but another danger remains."
        }
    }

    private func missedAnswerHeadline(for prompt: CoachingPrompt) -> String {
        switch prompt {
        case .safeLocate:
            return "One of your pieces does need help."
        case .takeChooseMove:
            return "There is a safe capture to find."
        case .mateChooseMove:
            return "There is a checkmating move to find."
        case let .opponentReply(opponent, _):
            return "\(colorName(opponent)) can check your king or win a piece."
        default:
            return "There is something to find."
        }
    }

    private func wakePurposeVerb(for purpose: CoachingWakePurpose) -> String {
        switch purpose {
        case .openingDevelopment:
            return "move a knight or bishop off its starting square"
        case .addsDefender, .createsThreat:
            return "fit this idea"
        case .centralActivity:
            return "move closer to the center"
        case .castle:
            return "help your king castle"
        }
    }

    private func concreteFlawCopy(
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
            return "\(name) could take one of your pieces."
        }
    }

    private func opponentIssueCopy(
        _ fact: CoachingOpponentReplyFact,
        opponent: PieceColor
    ) -> String {
        let opponentName = colorName(opponent)
        switch fact.issue.kind {
        case .mateInOne:
            return checkCopy(
                fact,
                opponentName: opponentName,
                result: "checkmate your king"
            )
        case .materialLoss:
            if let affectedPiece = fact.affectedPiece {
                return "\(opponentName)'s \(fact.replyPiece.rawValue) could take your \(affectedPiece.rawValue)."
            }
            return "\(opponentName)'s \(fact.replyPiece.rawValue) could take one of your pieces."
        case .check:
            guard fact.issue.severity == .notice else {
                return checkCopy(
                    fact,
                    opponentName: opponentName,
                    result: "check your king"
                )
            }
            let learnerBackRank = opponent == .black ? 1 : 8
            let checkDescription: String
            if isDirectSingleChecker(fact, kind: .rook),
               fact.issue.reply.to.rank == learnerBackRank {
                checkDescription = "That rook could check along your back row"
            } else {
                checkDescription = checkCopy(
                    fact,
                    opponentName: opponentName,
                    result: "check your king",
                    ending: ""
                )
            }
            let learnerMove = fact.learnerPiece.map {
                "your \($0.rawValue) move still works"
            } ?? "your move still works"
            return "\(checkDescription), but \(learnerMove)."
        }
    }

    private func checkCopy(
        _ fact: CoachingOpponentReplyFact,
        opponentName: String,
        result: String,
        ending: String = "."
    ) -> String {
        guard !fact.checkingPieces.isEmpty else {
            return "\(opponentName) could \(result)\(ending)"
        }
        if fact.checkingPieces.count == 1,
           let checker = fact.checkingPieces.first,
           checker.visibleSquare == fact.issue.reply.from,
           checker.checkingSquare == fact.issue.reply.to {
            return "That \(checker.piece.rawValue) could \(result)\(ending)"
        }

        let names = fact.checkingPieces.map { $0.piece.rawValue }
        let checkerNames: String
        if names.count == 2, names[0] == names[1] {
            checkerNames = "two \(names[0])s"
        } else if let last = names.last {
            checkerNames = names.count == 1
                ? last
                : names.dropLast().joined(separator: ", ") + " and " + last
        } else {
            return "\(opponentName) could \(result)\(ending)"
        }
        let both = names.count > 1 ? " both" : ""
        let enablingAction: String
        switch fact.issue.reply.special {
        case .castleKingside, .castleQueenside:
            enablingAction = " after the \(fact.replyPiece.rawValue) castles"
        case nil, .enPassant, .promotion:
            enablingAction = " after the \(fact.replyPiece.rawValue) moves"
        }
        return "\(opponentName)'s \(checkerNames) could\(both) \(result)\(enablingAction)\(ending)"
    }

    private func isDirectSingleChecker(
        _ fact: CoachingOpponentReplyFact,
        kind: Piece.Kind
    ) -> Bool {
        guard fact.checkingPieces.count == 1,
              let checker = fact.checkingPieces.first else {
            return false
        }
        return checker.piece == kind
            && checker.visibleSquare == fact.issue.reply.from
            && checker.checkingSquare == fact.issue.reply.to
    }

    private func completionCopy(
        for idea: CoachingCompletionIdea,
        opponent: PieceColor
    ) -> String {
        completionPurpose(for: idea, opponent: opponent)
    }

    private func completionPurpose(
        for idea: CoachingCompletionIdea,
        opponent: PieceColor
    ) -> String {
        let concept: String
        switch idea {
        case let .resolvesDanger(resolution):
            return dangerResolutionCopy(resolution)
        case let .resolvesCheck(resolution, checker):
            return checkResolutionCopy(resolution, checker: checker)
        case .mate:
            concept = "You found checkmate."
        case let .profitableCapture(captured):
            concept = "Your capture wins a \(captured.rawValue)."
        case let .safeCapture(fact):
            return safeCaptureCopy(fact, opponent: opponent)
        case let .develops(piece):
            concept = "You developed your \(piece.rawValue)."
        case .advancesCenterPawn:
            concept = "Your pawn helps control the center."
        case .castles:
            concept = "Castling helps keep your king safe."
        case .addsDefender, .createsThreat:
            concept = "That move seems safe."
        case let .centralizes(piece):
            concept = "Your \(piece.rawValue) moved closer to the center."
        case let .constructive(task, move, piece):
            return constructiveCompletion(
                task: task,
                move: move,
                piece: piece,
                opponent: opponent
            )
        case .verifiedSafe:
            concept = "That move seems safe."
        case let .seemsSafe(suggestion):
            if suggestion == .openingDevelopment(firstMove: true) {
                return "That move seems safe, but a center pawn or knight is a simpler start."
            }
            return "That move seems safe."
        }
        return concept
    }

    private func constructiveCompletion(
        task: CoachingWakeTask,
        move: Move,
        piece: Piece.Kind,
        opponent: PieceColor
    ) -> String {
        switch task {
        case let .opening(_, _, candidates):
            if piece == .pawn {
                return "Your center pawn moved forward and helps control the center."
            }
            let comparison = candidates.first(where: { $0.move == move })?
                .centralityComparison
            if piece == .knight,
               case .closerWithMoreMobility = comparison {
                return "You developed your knight toward the center."
            }
            if piece == .knight,
               case .fartherWithLessMobility = comparison {
                return "You developed your knight away from the center, giving it fewer moves."
            }
            if piece == .knight { return "You developed your knight." }
            return "You developed your \(piece.rawValue)."

        case .castle:
            return "You castled, moving your king toward safety and activating your rook."

        case let .protect(_, sourcePiece, _, targetPiece, _):
            return "Your \(sourcePiece.rawValue) now protects the \(targetPiece.rawValue)."

        case let .createThreat(_, sourcePiece, _, targetPiece, _):
            return "Your \(sourcePiece.rawValue) now attacks \(colorName(opponent))'s \(targetPiece.rawValue)."

        case let .improveMobility(_, piece, _, before, candidates):
            guard let after = candidates.first(where: { $0.move == move })?.resultingMobility else {
                return "Your \(piece.rawValue) can reach more squares now."
            }
            return "Your \(piece.rawValue) can now reach \(countName(after)) squares instead of \(countName(before))."
        }
    }

    private func countName(_ count: Int) -> String {
        let names = [
            "zero", "one", "two", "three", "four",
            "five", "six", "seven", "eight",
        ]
        return names.indices.contains(count) ? names[count] : String(count)
    }

    private func safeCaptureCopy(
        _ fact: CoachingExchangeFact,
        opponent: PieceColor
    ) -> String {
        let opponentName = colorName(opponent)
        if let recapturer = fact.immediateRecapturer {
            return "Your \(fact.mover.rawValue) wins a \(fact.captured.rawValue) even if \(opponentName)'s \(recapturer.rawValue) takes it back."
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
        return "\(colorName(opponent))'s \(recapturer.rawValue) could take your \(fact.mover.rawValue), so you would lose it for a \(fact.captured.rawValue)."
    }

    private func dangerResolutionCopy(_ resolution: CoachingDangerResolution) -> String {
        switch resolution {
        case let .movedTarget(target, attacker):
            switch attacker {
            case .bishop, .rook, .queen:
                return "Your \(target.rawValue) is out of the \(attacker.rawValue)'s path and safe."
            case .pawn, .knight, .king:
                return "Your \(target.rawValue) is out of the \(attacker.rawValue)'s attack and safe."
            }
        case let .capturedAttacker(capturer, target, attacker):
            if capturer == target {
                return "Your \(capturer.rawValue) took the attacking \(attacker.rawValue) and is safe."
            }
            return "Your \(capturer.rawValue) took the attacking \(attacker.rawValue), so your \(target.rawValue) is safe."
        case let .addedDefender(defender, target, attacker):
            return "Your \(defender.rawValue) now protects the \(target.rawValue) from the attacking \(attacker.rawValue)."
        }
    }

    private func checkResolutionCopy(
        _ resolution: CoachingCheckResolution,
        checker: Piece.Kind?
    ) -> String {
        switch resolution {
        case .movedKing:
            if let checker {
                return "Your king moved out of the \(checker.rawValue)'s line and is safe."
            }
            return "Your king moved out of check and is safe."
        case let .blocked(attacker, blocker):
            return "Your \(blocker.rawValue) blocked the \(attacker.rawValue)'s path, so your king is safe."
        case let .capturedChecker(checker, capturer):
            return "Your \(capturer.rawValue) took the checking \(checker.rawValue), so your king is safe."
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
        if case let .opponentReply(opponent, _) = context.prompt {
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

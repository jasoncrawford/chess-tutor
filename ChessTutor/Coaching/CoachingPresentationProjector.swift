struct CoachingPresentationProjector: Sendable {
    func context(
        learner: PieceColor,
        derived: CoachingDerivedState,
        episode: CoachingEpisodeState
    ) -> CoachingPresentationContext? {
        let advice = applicableAdvice(learner: learner, in: episode)
        guard let prompt = derived.promptOverride
            ?? prompt(for: derived.stage, learner: learner, episode: episode, advice: advice)
        else {
            return nil
        }

        let progressMatchesQuestion = episode.progress.questionID == derived.questionID
        let hintLevel = progressMatchesQuestion ? episode.progress.hintLevel : 0
        let misses = progressMatchesQuestion ? episode.progress.missesAtCurrentLevel : 0
        let hints = hintSteps(for: derived.stage, episode: episode, advice: advice)
        let hint = hints.indices.contains(hintLevel - 1) ? hints[hintLevel - 1] : nil
        let recordedFeedback = progressMatchesQuestion ? episode.progress.feedback : nil
        let feedback: CoachingFeedback?
        if let hint,
           recordedFeedback == nil {
            if case .missedOpponentIssue = derived.derivedFeedback {
                feedback = derived.derivedFeedback
            } else {
                feedback = hintFeedback(for: derived.stage, hint: hint, advice: advice)
            }
        } else {
            feedback = recordedFeedback ?? derived.derivedFeedback
        }
        let positiveAnswerWasRevealed = positiveAnswerWasRevealed(
            for: derived.stage,
            hint: hint,
            feedback: feedback,
            advice: advice
        )

        return CoachingPresentationContext(
            prompt: prompt,
            feedback: feedback,
            learner: learner,
            hint: hint,
            missesAtCurrentLevel: misses,
            routine: routine(for: derived.stage),
            actions: actions(
                for: derived.stage,
                hintLevel: hintLevel,
                availableHints: hints,
                advice: advice,
                positiveAnswerWasRevealed: positiveAnswerWasRevealed
            ),
            boardTask: boardTask(for: derived.stage),
            focus: focus(
                for: derived.stage,
                hint: hint,
                feedback: feedback,
                episode: episode,
                advice: advice
            )
        )
    }

    private func applicableAdvice(
        learner: PieceColor,
        in episode: CoachingEpisodeState
    ) -> CoachingAdvice? {
        if let move = episode.interaction.tentativeMove {
            guard let origin = episode.evidence.tentativeOrigin,
                  let advice = episode.knowledge.tentativeAdvice,
                  advice.evaluation.request.learner == learner,
                  advice.evaluation.request.positionRevision
                    == episode.interaction.positionRevision,
                  advice.evaluation.request.tentativeMove == move,
                  advice.evaluation.request.context == .tentativeMove(origin: origin),
                  advice.evaluation.moveAssessments[move]?.move == move,
                  advice.moveAssessments[move]?.move == move
            else {
                return nil
            }
            return advice
        }

        guard let advice = episode.knowledge.positionAdvice,
              advice.evaluation.request.learner == learner,
              advice.evaluation.request.positionRevision == episode.interaction.positionRevision,
              advice.evaluation.request.tentativeMove == nil,
              advice.evaluation.request.context == .start
        else {
            return nil
        }
        return advice
    }

    private func prompt(
        for stage: CoachingStage,
        learner: PieceColor,
        episode: CoachingEpisodeState,
        advice: CoachingAdvice?
    ) -> CoachingPrompt? {
        switch stage {
        case .awaitingAdvice:
            return .awaitingAdvice
        case .checkLocate:
            return .checkLocate
        case .checkResolve:
            return .checkResolve
        case .safeLocate:
            return .safeLocate
        case let .safeIdentifyAttacker(target):
            return .safeIdentifyAttacker(piece: pieceKind(at: target, advice: advice) ?? .pawn)
        case let .safeResolve(target):
            return .safeResolve(
                target: pieceKind(at: target, advice: advice) ?? .pawn,
                attacker: validSafeAttacker(
                    target: target,
                    episode: episode,
                    advice: advice
                ).flatMap { pieceKind(at: $0, advice: advice) } ?? .pawn
            )
        case .takeChooseMove:
            return .takeChooseMove
        case let .wakeChoosePiece(purpose):
            if let task = wakeTask(for: stage, advice: advice) {
                return .wake(task: task, selectedPiece: nil)
            }
            return .wakeChoosePiece(purpose: purpose)
        case let .wakeChooseMove(piece, purpose):
            if let task = wakeTask(for: stage, advice: advice) {
                return .wake(
                    task: task,
                    selectedPiece: pieceKind(at: piece, advice: advice) ?? .pawn
                )
            }
            return .wakeChooseMove(
                piece: pieceKind(at: piece, advice: advice) ?? .pawn,
                purpose: purpose
            )
        case .fallbackChooseMove:
            return advice?.confidence == .unsupported
                || episode.knowledge.unsupportedContext != nil
                ? .unsupportedFallbackChooseMove
                : .fallbackChooseMove
        case let .opponentCheck(move, _):
            return .opponentReply(
                opponent: learner.opposite,
                threatenedPiece: threatenedPiece(
                    in: advice?.moveAssessments[move]?.opponentActivities ?? []
                )
            )
        case .reviseMove:
            return .reviseMove
        case let .complete(move, origin, concepts):
            return .complete(
                origin: origin,
                idea: completionIdea(
                    for: move,
                    origin: origin,
                    concepts: concepts,
                    episode: episode,
                    advice: advice
                )
            )
        }
    }

    private func routine(for stage: CoachingStage) -> [CoachingRoutineState] {
        switch stage {
        case .safeLocate, .safeIdentifyAttacker, .safeResolve:
            return [.safeCurrent, .takePending, .wakePending]
        case .takeChooseMove:
            return [.safeCleared, .takeCurrent, .wakePending]
        case .wakeChoosePiece, .wakeChooseMove:
            return [.safeCleared, .takeCleared, .wakeCurrent]
        case .awaitingAdvice, .checkLocate, .checkResolve, .fallbackChooseMove,
             .opponentCheck, .reviseMove, .complete:
            return []
        }
    }

    private func boardTask(for stage: CoachingStage) -> CoachingBoardTask {
        switch stage {
        case .checkLocate, .safeLocate, .safeIdentifyAttacker:
            return .identify(allowsMoveRevision: false)
        case .opponentCheck:
            return .identify(allowsMoveRevision: true)
        case .checkResolve, .safeResolve, .takeChooseMove, .wakeChoosePiece,
             .wakeChooseMove, .fallbackChooseMove, .reviseMove:
            return .move
        case .awaitingAdvice, .complete:
            return .none
        }
    }

    private func actions(
        for stage: CoachingStage,
        hintLevel: Int,
        availableHints: [CoachingHint],
        advice: CoachingAdvice?,
        positiveAnswerWasRevealed: Bool
    ) -> [CoachingAction] {
        let hintActions: [CoachingAction] = hintLevel < availableHints.count ? [.hint] : []
        switch stage {
        case .safeLocate:
            let absenceIsValid = advice?.dangerProblems.isEmpty == true
                && !positiveAnswerWasRevealed
            return (absenceIsValid ? [.noAnswer] : []) + hintActions + [.stop]
        case .takeChooseMove:
            return (positiveAnswerWasRevealed ? [] : [.noAnswer]) + hintActions + [.stop]
        case .opponentCheck:
            return (positiveAnswerWasRevealed ? [] : [.looksSafe]) + hintActions + [.stop]
        case .complete:
            return [.done, .keepLooking, .stop]
        case .awaitingAdvice:
            return [.stop]
        default:
            return hintActions + [.stop]
        }
    }

    private func positiveAnswerWasRevealed(
        for stage: CoachingStage,
        hint: CoachingHint?,
        feedback: CoachingFeedback?,
        advice: CoachingAdvice?
    ) -> Bool {
        switch stage {
        case .safeLocate:
            return advice?.dangerProblems.isEmpty == false
                || feedback == .missedExistingAnswer(.noPieceNeedsHelp)
        case .takeChooseMove:
            if case .safeCaptureHint = feedback {
                return true
            }
            return feedback == .missedExistingAnswer(.noSafeCapture)
        case .opponentCheck:
            if case .missedOpponentIssue = feedback {
                return true
            }
            return hint != nil
                && !opponentIssueAnswerSquares(for: stage, advice: advice).isEmpty
        case .awaitingAdvice, .checkLocate, .checkResolve, .safeIdentifyAttacker,
             .safeResolve, .wakeChoosePiece, .wakeChooseMove, .fallbackChooseMove,
             .reviseMove, .complete:
            return false
        }
    }

    private func hintSteps(
        for stage: CoachingStage,
        episode: CoachingEpisodeState,
        advice: CoachingAdvice?
    ) -> [CoachingHint] {
        switch stage {
        case .checkLocate:
            return [.checkMarker, .candidatePieces]
        case .checkResolve:
            guard episode.interaction.tentativeMove == nil else { return [] }
            return candidateMoves(for: stage, advice: advice).isEmpty
                ? []
                : [.candidatePieces, .candidateMoves]
        case .safeLocate:
            return candidateSourceSquares(for: stage, advice: advice).isEmpty
                ? []
                : [.dangerMarker, .candidatePieces]
        case .safeIdentifyAttacker:
            return [.attackerRelationship, .candidatePieces]
        case .safeResolve:
            guard episode.interaction.tentativeMove == nil else { return [] }
            return candidateMoves(for: stage, advice: advice).isEmpty
                ? [.safeResponseIdeas]
                : [.safeResponseIdeas, .candidateMoves]
        case .takeChooseMove:
            guard episode.interaction.tentativeMove == nil else { return [] }
            return candidateMoves(for: stage, advice: advice).isEmpty
                ? []
                : [.candidatePieces, .candidateMoves]
        case let .wakeChoosePiece(purpose):
            guard let advice,
                  !wakeSources(for: purpose, in: advice).isEmpty
            else {
                return []
            }
            if let task = wakeTask(for: stage, advice: advice) {
                switch task {
                case .opening:
                    return [.candidatePieces, .candidateMoves]
                case .castle, .protect, .createThreat, .improveMobility:
                    return [.candidateMoves]
                }
            }
            return [.candidatePieces, .candidateMoves]
        case .wakeChooseMove:
            guard episode.interaction.tentativeMove == nil else { return [] }
            return candidateMoves(for: stage, advice: advice).isEmpty
                ? [.movementMarkers]
                : [.movementMarkers, .candidateMoves]
        case .opponentCheck:
            if opponentIssueAnswerSquares(for: stage, advice: advice).isEmpty,
               episode.evidence.benignOpponentActivityObserved {
                return [.replyMarkers]
            }
            return opponentIssueAnswerSquares(for: stage, advice: advice).isEmpty
                ? []
                : [.attackerRelationship]
        case .reviseMove:
            return answeredOpponentIssue(in: episode, advice: advice) == nil
                ? []
                : [.attackerRelationship]
        case .awaitingAdvice, .fallbackChooseMove, .complete:
            return []
        }
    }

    private func hintFeedback(
        for stage: CoachingStage,
        hint: CoachingHint,
        advice: CoachingAdvice?
    ) -> CoachingFeedback? {
        guard stage == .takeChooseMove,
              hint == .candidatePieces,
              let move = advice?.takeOpportunities.first?.moves.first,
              let fact = advice?.exchangeFact(for: move) else {
            return nil
        }
        return .safeCaptureHint(piece: fact.mover)
    }

    private func focus(
        for stage: CoachingStage,
        hint: CoachingHint?,
        feedback: CoachingFeedback?,
        episode: CoachingEpisodeState,
        advice: CoachingAdvice?
    ) -> CoachFocusPresentation {
        let persistent = persistentFocus(
            for: stage,
            feedback: feedback,
            episode: episode,
            advice: advice
        )
        let hinted = hintFocus(
            for: stage,
            hint: hint,
            pulseID: episode.progress.pulseID,
            advice: advice
        )
        return CoachFocusPresentation(
            emphasizedSquares: persistent.emphasizedSquares.union(hinted.emphasizedSquares),
            candidateSquares: hinted.candidateSquares,
            paths: persistent.paths.union(hinted.paths),
            pulseID: episode.progress.pulseID
        )
    }

    private func hintFocus(
        for stage: CoachingStage,
        hint: CoachingHint?,
        pulseID: Int,
        advice: CoachingAdvice?
    ) -> CoachFocusPresentation {
        guard let hint else { return .empty }
        switch hint {
        case .candidatePieces:
            return CoachFocusPresentation(
                emphasizedSquares: [],
                candidateSquares: candidateSourceSquares(for: stage, advice: advice),
                paths: [],
                pulseID: pulseID
            )
        case .candidateMoves:
            return CoachFocusPresentation(
                emphasizedSquares: [],
                candidateSquares: candidateDestinationSquares(for: stage, advice: advice),
                paths: candidatePaths(for: stage, advice: advice),
                pulseID: pulseID
            )
        case .attackerRelationship:
            let attackerSquares = opponentIssueAnswerSquares(for: stage, advice: advice)
            return CoachFocusPresentation(
                emphasizedSquares: [],
                candidateSquares: attackerSquares.isEmpty
                    ? candidateSourceSquares(for: stage, advice: advice)
                    : attackerSquares,
                paths: candidatePaths(for: stage, advice: advice),
                pulseID: pulseID
            )
        case .checkMarker, .dangerMarker, .replyMarkers,
             .safeResponseIdeas, .movementMarkers:
            return .empty
        }
    }

    private func persistentFocus(
        for stage: CoachingStage,
        feedback: CoachingFeedback?,
        episode: CoachingEpisodeState,
        advice: CoachingAdvice?
    ) -> CoachFocusPresentation {
        if case let .attackedButProtected(fact) = episode.progress.feedback {
            return CoachFocusPresentation(
                emphasizedSquares: [
                    fact.targetSquare,
                    fact.attackerSquare,
                    fact.defenderSquare,
                ],
                candidateSquares: [],
                paths: [
                    CoachFocusPath(
                        source: fact.attackerSquare,
                        destination: fact.targetSquare,
                        role: .attacker
                    ),
                    CoachFocusPath(
                        source: fact.defenderSquare,
                        destination: fact.targetSquare,
                        role: .defender
                    ),
                ],
                pulseID: episode.progress.pulseID
            )
        }
        if case let .opponentCheck(move, origin) = stage,
           episode.progress.questionID == .opponentReply(move: move, origin: origin),
           case let .benignOpponentActivity(activity) = episode.progress.feedback {
            return CoachFocusPresentation(
                emphasizedSquares: [activity.reply.from, activity.reply.to],
                candidateSquares: [],
                paths: [CoachFocusPath(
                    source: activity.reply.from,
                    destination: activity.reply.to,
                    role: .attacker
                )],
                pulseID: episode.progress.pulseID
            )
        }
        if case let .complete(move, .wake, _) = stage,
           let task = episode.knowledge.positionAdvice?.wakeTasks.first(where: {
               wakeMoves(in: $0).contains(move)
           }),
           case let .createThreat(_, _, target, _, _) = task {
            return CoachFocusPresentation(
                emphasizedSquares: [move.to, target],
                candidateSquares: [],
                paths: [CoachFocusPath(
                    source: move.to,
                    destination: target,
                    role: .attacker
                )],
                pulseID: episode.progress.pulseID
            )
        }
        if stage.isOpponentIssueOutcome,
           let fact = opponentReplyFact(from: feedback) {
            return CoachFocusPresentation(
                emphasizedSquares: opponentIssueEmphasizedSquares(fact),
                candidateSquares: [],
                paths: Set(opponentIssuePaths(fact)),
                pulseID: episode.progress.pulseID
            )
        }
        if let move = episode.interaction.tentativeMove,
           case let .issue(answeredMove, issue) = episode.evidence.replyAnswer,
            answeredMove == move,
           stage.isOpponentIssueOutcome {
            return CoachFocusPresentation(
                emphasizedSquares: Set(
                    [issue.reply.from] + (issue.affectedSquare.map { [$0] } ?? [])
                ),
                candidateSquares: [],
                paths: Set(opponentIssuePaths(issue)),
                pulseID: episode.progress.pulseID
            )
        }
        guard episode.interaction.tentativeMove == nil else { return .empty }
        switch stage {
        case let .safeIdentifyAttacker(target):
            guard episode.evidence.safeTarget == target,
                  advice?.primaryDangerProblems.contains(where: { $0.target == target }) == true
            else {
                return .empty
            }
            return CoachFocusPresentation(
                emphasizedSquares: [target],
                candidateSquares: [],
                paths: [],
                pulseID: episode.progress.pulseID
            )
        case let .safeResolve(target):
            guard let attacker = validSafeAttacker(
                target: target,
                episode: episode,
                advice: advice
            ) else {
                return .empty
            }
            return CoachFocusPresentation(
                emphasizedSquares: [target, attacker],
                candidateSquares: [],
                paths: [CoachFocusPath(
                    source: attacker,
                    destination: target,
                    role: .attacker
                )],
                pulseID: episode.progress.pulseID
            )
        case .wakeChoosePiece, .wakeChooseMove:
            guard let task = wakeTask(for: stage, advice: advice) else {
                return .empty
            }
            return CoachFocusPresentation(
                emphasizedSquares: emphasizedSquares(for: task),
                candidateSquares: [],
                paths: [],
                pulseID: episode.progress.pulseID
            )
        default:
            return .empty
        }
    }

    private func validSafeAttacker(
        target: Square,
        episode: CoachingEpisodeState,
        advice: CoachingAdvice?
    ) -> Square? {
        guard episode.evidence.safeTarget == target,
              let attacker = episode.evidence.safeAttacker,
              let problem = advice?.primaryDangerProblems.first(where: { $0.target == target }),
              problem.captures.contains(where: { $0.move.from == attacker })
        else {
            return nil
        }
        return attacker
    }

    private func candidateSourceSquares(
        for stage: CoachingStage,
        advice: CoachingAdvice?
    ) -> Set<Square> {
        guard let advice else { return [] }
        switch stage {
        case .checkLocate:
            return advice.checkingPieces
        case .safeLocate:
            return Set(advice.primaryDangerProblems.map(\.target))
        case let .safeIdentifyAttacker(target):
            return Set(advice.primaryDangerProblems
                .first(where: { $0.target == target })?
                .captures.map(\.move.from) ?? [])
        case .checkResolve, .takeChooseMove:
            return Set(candidateMoves(for: stage, advice: advice).map(\.from))
        case let .wakeChoosePiece(purpose):
            if let task = wakeTask(for: stage, advice: advice) {
                return Set(wakeMoves(in: task).map(\.from))
            }
            return wakeSources(for: purpose, in: advice)
        default:
            return []
        }
    }

    private func candidateDestinationSquares(
        for stage: CoachingStage,
        advice: CoachingAdvice?
    ) -> Set<Square> {
        Set(candidateMoves(for: stage, advice: advice).map(\.to))
    }

    private func candidatePaths(
        for stage: CoachingStage,
        advice: CoachingAdvice?
    ) -> Set<CoachFocusPath> {
        guard let advice else { return [] }
        switch stage {
        case let .safeIdentifyAttacker(target):
            return Set(advice.primaryDangerProblems
                .first(where: { $0.target == target })?
                .captures.map {
                    CoachFocusPath(source: $0.move.from, destination: target, role: .attacker)
                } ?? [])
        case let .opponentCheck(move, _):
            return Set(advice.moveAssessments[move]?.opponentIssues.flatMap(
                opponentIssuePaths
            ) ?? [])
        case .checkResolve, .safeResolve, .takeChooseMove,
             .wakeChoosePiece, .wakeChooseMove:
            return Set(candidateMoves(for: stage, advice: advice).map {
                CoachFocusPath(source: $0.from, destination: $0.to, role: .candidate)
            })
        default:
            return []
        }
    }

    private func opponentIssueAnswerSquares(
        for stage: CoachingStage,
        advice: CoachingAdvice?
    ) -> Set<Square> {
        guard case let .opponentCheck(move, _) = stage else { return [] }
        return Set(advice?.moveAssessments[move]?.opponentIssues
            .flatMap(\.answerSquares) ?? [])
    }

    private func answeredOpponentIssue(
        in episode: CoachingEpisodeState,
        advice: CoachingAdvice?
    ) -> CoachingOpponentIssue? {
        guard let move = episode.interaction.tentativeMove,
              case let .issue(answeredMove, issue) = episode.evidence.replyAnswer,
              answeredMove == move,
              advice?.moveAssessments[move]?.opponentIssues.contains(issue) == true
        else {
            return nil
        }
        return issue
    }

    private func opponentIssuePaths(_ issue: CoachingOpponentIssue) -> [CoachFocusPath] {
        var paths = [CoachFocusPath(
            source: issue.reply.from,
            destination: issue.reply.to,
            role: .attacker
        )]
        if case .materialLoss = issue.kind,
           let affectedSquare = issue.affectedSquare,
           affectedSquare != issue.reply.to {
            paths.append(CoachFocusPath(
                source: issue.reply.to,
                destination: affectedSquare,
                role: .attacker
            ))
        }
        return paths
    }

    private func opponentReplyFact(
        from feedback: CoachingFeedback?
    ) -> CoachingOpponentReplyFact? {
        switch feedback {
        case let .opponentIssue(fact), let .missedOpponentIssue(fact):
            return fact
        default:
            return nil
        }
    }

    private func opponentIssueEmphasizedSquares(
        _ fact: CoachingOpponentReplyFact
    ) -> Set<Square> {
        var squares: Set<Square> = [fact.issue.reply.from, fact.issue.reply.to]
        if let affectedSquare = fact.issue.affectedSquare {
            squares.insert(affectedSquare)
        }
        if let secondaryReply = fact.secondaryReply {
            squares.insert(secondaryReply.from)
            squares.insert(secondaryReply.to)
        }
        for checker in fact.checkingPieces {
            squares.insert(checker.visibleSquare)
            squares.insert(checker.checkingSquare)
        }
        return squares
    }

    private func opponentIssuePaths(
        _ fact: CoachingOpponentReplyFact
    ) -> [CoachFocusPath] {
        var paths = [CoachFocusPath(
            source: fact.issue.reply.from,
            destination: fact.issue.reply.to,
            role: .attacker
        )]
        if let secondaryReply = fact.secondaryReply {
            paths.append(CoachFocusPath(
                source: secondaryReply.from,
                destination: secondaryReply.to,
                role: .attacker
            ))
        }
        if let affectedSquare = fact.issue.affectedSquare {
            paths += fact.checkingPieces.map {
                CoachFocusPath(
                    source: $0.checkingSquare,
                    destination: affectedSquare,
                    role: .attacker
                )
            }
            if case .materialLoss = fact.issue.kind,
               affectedSquare != fact.issue.reply.to {
                paths.append(CoachFocusPath(
                    source: fact.issue.reply.to,
                    destination: affectedSquare,
                    role: .attacker
                ))
            }
        }
        return paths
    }

    private func candidateMoves(
        for stage: CoachingStage,
        advice: CoachingAdvice?
    ) -> [Move] {
        guard let advice else { return [] }
        switch stage {
        case .checkResolve:
            return advice.moveAssessments.values
                .filter(\.isLegal)
                .map(\.move)
        case .safeResolve:
            return advice.moveAssessments.values
                .filter { $0.isLegal && $0.resolvesRequiredDanger }
                .map(\.move)
        case .takeChooseMove:
            return advice.takeOpportunities.flatMap(\.moves)
        case let .wakeChoosePiece(purpose):
            if let task = wakeTask(for: stage, advice: advice) {
                return wakeMoves(in: task)
            }
            return advice.wakeOpportunities
                .filter { wakePurpose(for: $0.concept, in: advice) == purpose }
                .flatMap(\.moves)
        case let .wakeChooseMove(piece, purpose):
            if let task = wakeTask(for: stage, advice: advice) {
                return wakeMoves(in: task).filter { $0.from == piece }
            }
            return advice.wakeOpportunities
                .filter { wakePurpose(for: $0.concept, in: advice) == purpose }
                .flatMap(\.moves)
                .filter { $0.from == piece }
        default:
            return []
        }
    }

    private func wakeSources(
        for purpose: CoachingWakePurpose,
        in advice: CoachingAdvice
    ) -> Set<Square> {
        if let task = advice.wakeTasks.first(where: { wakePurpose(for: $0) == purpose }) {
            return Set(wakeMoves(in: task).map(\.from))
        }
        return Set(advice.wakeOpportunities
            .filter { wakePurpose(for: $0.concept, in: advice) == purpose }
            .flatMap(\.moves)
            .map(\.from))
    }

    private func wakePurpose(
        for concept: CoachingConcept?,
        in advice: CoachingAdvice
    ) -> CoachingWakePurpose {
        switch concept {
        case .developsKnightOrBishop, .advancesCenterPawn:
            return .openingDevelopment(
                firstMove: advice.evaluation.request.committedState == GameState.startingPosition()
            )
        case .addsUsefulDefender:
            return .addsDefender
        case .createsSafeImmediateThreat:
            return .createsThreat
        case .castlesForKingSafety:
            return .castle
        default:
            return .centralActivity
        }
    }

    private func wakePurpose(for task: CoachingWakeTask) -> CoachingWakePurpose {
        switch task {
        case let .opening(firstMove, _, _):
            return .openingDevelopment(firstMove: firstMove)
        case .castle:
            return .castle
        case .protect:
            return .addsDefender
        case .createThreat:
            return .createsThreat
        case .improveMobility:
            return .centralActivity
        }
    }

    private func wakeTask(
        for stage: CoachingStage,
        advice: CoachingAdvice?
    ) -> CoachingWakeTask? {
        guard let advice else { return nil }
        switch stage {
        case let .wakeChoosePiece(purpose):
            return advice.wakeTasks.first { wakePurpose(for: $0) == purpose }
        case let .wakeChooseMove(source, purpose):
            return advice.wakeTasks.first {
                wakePurpose(for: $0) == purpose
                    && wakeMoves(in: $0).contains(where: { $0.from == source })
            }
        default:
            return nil
        }
    }

    private func wakeMoves(in task: CoachingWakeTask) -> [Move] {
        switch task {
        case let .castle(move):
            return [move]
        default:
            return task.candidates.map(\.move)
        }
    }

    private func emphasizedSquares(for task: CoachingWakeTask) -> Set<Square> {
        switch task {
        case .opening:
            return []
        case let .castle(move):
            return [move.from]
        case let .protect(source, _, target, _, _),
             let .createThreat(source, _, target, _, _):
            return [source, target]
        case let .improveMobility(source, _, _, _, _):
            return [source]
        }
    }

    private func completionIdea(
        for move: Move,
        origin: CoachingMoveOrigin,
        concepts: [CoachingConcept],
        episode: CoachingEpisodeState,
        advice: CoachingAdvice?
    ) -> CoachingCompletionIdea {
        if origin == .fallback,
           case let .looksSafe(answeredMove, afterBenignActivity) = episode.evidence.replyAnswer,
           answeredMove == move,
           afterBenignActivity {
            return .seemsSafe(suggestion: nil)
        }
        if origin == .wake,
           let task = (episode.knowledge.positionAdvice?.wakeTasks ?? advice?.wakeTasks ?? [])
            .first(where: { wakeMoves(in: $0).contains(move) }) {
            return .constructive(
                task: task,
                move: move,
                piece: pieceKind(at: move.from, advice: advice) ?? .pawn
            )
        }
        for concept in concepts {
            switch concept {
            case .kingInCheck:
                guard let advice,
                      let resolution = MaterialTacticalEvaluator().checkResolution(
                        for: move,
                        in: advice.evaluation.request.committedState,
                        learner: advice.evaluation.request.learner,
                        checkingSquares: advice.checkingPieces
                      ) else {
                    continue
                }
                let checker = advice.checkingPieces.count == 1
                    ? advice.checkingPieces.first.flatMap {
                        advice.evaluation.request.committedState.board[$0]?.kind
                    }
                    : nil
                return .resolvesCheck(resolution: resolution, checker: checker)
            case .pieceNeedsHelp:
                if let resolution = dangerResolution(
                    for: move,
                    episode: episode,
                    advice: advice
                ) {
                    return .resolvesDanger(resolution)
                }
                continue
            case .mateInOne:
                return .mate
            case .profitableCapture, .captureResolvesDanger:
                if let fact = advice?.exchangeFact(for: move) {
                    return .safeCapture(fact)
                }
                return .profitableCapture(captured: capturedKind(for: move, advice: advice) ?? .pawn)
            case .developsKnightOrBishop:
                return .develops(piece: pieceKind(at: move.from, advice: advice) ?? .knight)
            case .advancesCenterPawn:
                return .advancesCenterPawn
            case .castlesForKingSafety:
                return .castles
            case .addsUsefulDefender:
                return .addsDefender(piece: pieceKind(at: move.from, advice: advice) ?? .pawn)
            case .createsSafeImmediateThreat:
                return .createsThreat(piece: pieceKind(at: move.from, advice: advice) ?? .pawn)
            case .improvesCentralActivity:
                return .centralizes(piece: pieceKind(at: move.from, advice: advice) ?? .pawn)
            case .allowsCheck, .allowsMateInOne, .allowsMaterialLoss,
                 .checkingPiece, .profitableAttacker, .safeAfterReplyCheck:
                continue
            }
        }
        return .seemsSafe(
            suggestion: origin == .wake
                ? initialWakePurpose(in: episode.knowledge.positionAdvice)
                : nil
        )
    }

    private func threatenedPiece(
        in activities: [CoachingOpponentActivity]
    ) -> Piece.Kind? {
        guard !activities.contains(where: \.isCheck) else { return nil }
        let winningActivities = activities.filter(\.canWinPiece)
        guard let piece = winningActivities.first?.capturedPiece,
              winningActivities.allSatisfy({ $0.capturedPiece == piece }) else {
            return nil
        }
        return piece
    }

    private func initialWakePurpose(
        in advice: CoachingAdvice?
    ) -> CoachingWakePurpose? {
        guard let advice else { return nil }
        if let task = advice.wakeTasks.first {
            return wakePurpose(for: task)
        }
        guard let opportunity = advice.wakeOpportunities.first,
              !opportunity.moves.isEmpty else {
            return nil
        }
        switch opportunity.concept {
        case .developsKnightOrBishop, .advancesCenterPawn:
            return .openingDevelopment(
                firstMove: advice.evaluation.request.committedState
                    == GameState.startingPosition()
            )
        case .addsUsefulDefender:
            return .addsDefender
        case .createsSafeImmediateThreat:
            return .createsThreat
        case .castlesForKingSafety:
            return .castle
        case .improvesCentralActivity:
            return .centralActivity
        default:
            return nil
        }
    }

    private func dangerResolution(
        for move: Move,
        episode: CoachingEpisodeState,
        advice: CoachingAdvice?
    ) -> CoachingDangerResolution? {
        guard let advice,
              let targetSquare = episode.evidence.safeTarget,
              let attackerSquare = episode.evidence.safeAttacker else {
            return nil
        }
        let state = advice.evaluation.request.committedState
        guard let target = state.board[targetSquare],
              let attacker = state.board[attackerSquare] else {
            return nil
        }

        if LegalMoveGenerator.capture(for: move, in: state)?.square == attackerSquare,
           let capturer = state.board[move.from] {
            return .capturedAttacker(
                capturer: capturer.kind,
                target: target.kind,
                attacker: attacker.kind
            )
        }
        if move.from == targetSquare {
            return .movedTarget(target: target.kind, attacker: attacker.kind)
        }

        let stateAfterMove = state.applyingUnchecked(move)
        guard let attackMove = LegalMoveGenerator.legalMoves(
            for: attackerSquare,
            in: stateAfterMove
        ).first(where: {
            LegalMoveGenerator.capture(for: $0, in: stateAfterMove)?.square == targetSquare
        }),
        let estimate = MaterialTacticalEvaluator().captureEstimate(
            for: attackMove,
            in: stateAfterMove
        ),
        estimate.netGainForMover <= 0,
        let recapture = estimate.immediateRecapture,
        recapture.from == move.to,
        let defender = stateAfterMove.board[recapture.from] else {
            return nil
        }
        return .addedDefender(
            defender: defender.kind,
            target: target.kind,
            attacker: attacker.kind
        )
    }

    private func capturedKind(for move: Move, advice: CoachingAdvice?) -> Piece.Kind? {
        advice?.evaluation.learnerCaptureEstimates
            .first(where: { $0.move == move })?.capturedPiece.kind
            ?? advice?.evaluation.request.committedState.board[move.to]?.kind
    }

    private func pieceKind(at square: Square, advice: CoachingAdvice?) -> Piece.Kind? {
        advice?.evaluation.request.committedState.board[square]?.kind
    }
}

private extension CoachingStage {
    var isOpponentIssueOutcome: Bool {
        switch self {
        case .reviseMove, .complete:
            true
        default:
            false
        }
    }
}

extension CoachingQuestionProgress {
    mutating func enter(_ questionID: CoachingQuestionID?) {
        guard self.questionID != questionID else { return }
        self.questionID = questionID
        hintLevel = 0
        missesAtCurrentLevel = 0
        feedback = nil
        feedbackAnchor = nil
    }

    mutating func recordMiss(
        _ feedback: CoachingFeedback,
        anchor: CoachingFeedbackAnchor
    ) {
        missesAtCurrentLevel += 1
        self.feedback = feedback
        feedbackAnchor = anchor
    }

    mutating func revealNextHint(available: [CoachingHint]) {
        guard hintLevel < available.count else { return }
        hintLevel += 1
        missesAtCurrentLevel = 0
        feedback = nil
        feedbackAnchor = nil
        pulseID += 1
    }

    mutating func discardFeedbackInvalidated(
        by interaction: CoachingInteractionSnapshot
    ) {
        let remainsValid: Bool
        switch feedbackAnchor {
        case let .selection(square):
            remainsValid = interaction.selectedSquare == square
        case let .tentativeMove(move):
            remainsValid = interaction.tentativeMove == move
        case .identification, nil:
            remainsValid = true
        case .action:
            remainsValid = false
        }

        if !remainsValid {
            feedback = nil
            feedbackAnchor = nil
        }
    }
}

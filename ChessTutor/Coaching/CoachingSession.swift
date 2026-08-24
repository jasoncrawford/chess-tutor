struct CoachingSession: Sendable {
    private let learner: PieceColor
    private let explainer: any CoachingExplaining
    private let reconciler = CoachingReconciler()
    private let projector = CoachingPresentationProjector()
    private var episode: CoachingEpisodeState

    private(set) var stage: CoachingStage
    private(set) var presentation: CoachingPresentation?

    var authoritativeBoardTask: CoachingBoardTask {
        let derived = reconciler.derive(learner: learner, episode: episode)
        return projector.context(
            learner: learner,
            derived: derived,
            episode: episode
        )?.boardTask ?? .none
    }

    var hintLevel: Int { episode.progress.hintLevel }
    var missesAtCurrentLevel: Int { episode.progress.missesAtCurrentLevel }

    init(
        learner: PieceColor,
        interaction: CoachingInteractionSnapshot,
        initialContext: CoachingRequest.Context,
        explainer: any CoachingExplaining = LocalCoachingExplanationSource()
    ) {
        var evidence = CoachingPedagogicalEvidence.empty
        let initialOrigin: CoachingMoveOrigin?
        if case let .tentativeMove(origin) = initialContext,
           interaction.tentativeMove != nil {
            evidence.tentativeOrigin = origin
            initialOrigin = origin
        } else {
            initialOrigin = nil
        }

        self.learner = learner
        self.explainer = explainer
        episode = CoachingEpisodeState(
            knowledge: CoachingKnowledge(
                positionAdvice: nil,
                tentativeAdvice: nil,
                unsupportedContext: nil,
                pendingContext: initialContext
            ),
            evidence: evidence,
            progress: CoachingQuestionProgress(
                questionID: nil,
                hintLevel: 0,
                missesAtCurrentLevel: 0,
                feedback: nil,
                feedbackAnchor: nil,
                pulseID: 0
            ),
            interaction: interaction
        )
        stage = .awaitingAdvice(origin: initialOrigin)
        presentation = nil
        _ = reconcile()
    }

    @discardableResult
    mutating func receive(
        _ advice: CoachingAdvice,
        interaction: CoachingInteractionSnapshot
    ) -> [CoachingDirective] {
        reduceInteraction(to: interaction)

        let request = advice.evaluation.request
        guard adviceMatchesCurrentInteraction(advice),
              adviceMatchesCurrentKnowledgeRequirement(advice) else {
            return reconcile()
        }

        let pendingContext = episode.knowledge.pendingContext
        switch request.context {
        case .start:
            episode.knowledge.positionAdvice = advice
            episode.knowledge.tentativeAdvice = nil
            episode.knowledge.unsupportedContext = nil
            episode.knowledge.pendingContext = nil
            episode.evidence = .empty
            resetProgressPreservingPulse()

        case .tentativeMove:
            episode.knowledge.tentativeAdvice = advice
            episode.knowledge.unsupportedContext = nil
            episode.knowledge.pendingContext = nil
        }

        let derived = reconciler.derive(learner: learner, episode: episode)
        let correction = request.context == pendingContext
            && (derived.promptOverride != nil || derived.derivedFeedback != nil)
        let directives = reconcile()
        if correction, let move = interaction.tentativeMove {
            recordAttempt(
                feedback: derived.derivedFeedback,
                anchor: .tentativeMove(move)
            )
        }
        return directives
    }

    @discardableResult
    mutating func receiveUnsupportedPosition(
        for context: CoachingRequest.Context,
        interaction: CoachingInteractionSnapshot
    ) -> [CoachingDirective] {
        reduceInteraction(to: interaction)
        guard contextMatchesCurrentInteraction(context) else {
            return reconcile()
        }

        episode.knowledge.unsupportedContext = context
        episode.knowledge.pendingContext = nil
        switch context {
        case .start:
            episode.knowledge.positionAdvice = nil
            episode.knowledge.tentativeAdvice = nil
            episode.evidence = .empty
            resetProgressPreservingPulse()
        case .tentativeMove:
            episode.knowledge.tentativeAdvice = nil
            episode.evidence.replyAnswer = nil
        }
        return reconcile()
    }

    @discardableResult
    mutating func handle(_ event: CoachingEvent) -> [CoachingDirective] {
        switch event {
        case let .identificationTapped(square):
            return handleIdentificationTap(square)
        case let .interactionChanged(interaction):
            return handleInteractionChange(interaction)
        case let .actionChosen(action):
            return handleAction(action)
        }
    }

    private mutating func handleIdentificationTap(
        _ square: Square
    ) -> [CoachingDirective] {
        let derived = reconciler.derive(learner: learner, episode: episode)
        var miss: CoachingFeedback?

        switch derived.stage {
        case .checkLocate:
            guard let advice = reconciler.applicablePositionAdvice(
                in: episode,
                learner: learner
            ) else {
                return reconcile()
            }
            if advice.checkingPieces.contains(square) {
                episode.evidence.checkingPiece = square
            } else {
                miss = .notCheckingPiece(piece: pieceKind(at: square, advice: advice))
            }

        case .safeLocate, .safeIdentifyAttacker:
            guard let advice = reconciler.applicablePositionAdvice(
                in: episode,
                learner: learner
            ) else {
                return reconcile()
            }
            let board = advice.evaluation.request.committedState.board
            if let piece = board[square], piece.color == learner {
                if advice.primaryDangerProblems.contains(where: { $0.target == square }) {
                    if episode.evidence.safeTarget != square {
                        episode.evidence.safeTarget = square
                        episode.evidence.safeAttacker = nil
                    }
                } else {
                    episode.evidence.safeTarget = nil
                    episode.evidence.safeAttacker = nil
                    let feedback = safeTargetFeedback(
                        for: square,
                        piece: piece,
                        advice: advice
                    )
                    if case .attackedButProtected = feedback {
                        if advice.dangerProblems.isEmpty {
                            episode.evidence.confirmedSafeAbsence = true
                        }
                        let directives = reconcile()
                        recordFeedback(
                            feedback,
                            anchor: .identification(square: square)
                        )
                        return directives
                    }
                    miss = feedback
                }
            } else if case let .safeIdentifyAttacker(target) = derived.stage,
                      let problem = advice.primaryDangerProblems.first(where: {
                          $0.target == target
                      }),
                      let piece = board[square], piece.color == learner.opposite {
                if problem.captures.contains(where: { $0.move.from == square }) {
                    episode.evidence.safeAttacker = square
                } else {
                    miss = .notAttacker(piece: piece.kind, target: problem.piece.kind)
                }
            } else if case let .safeIdentifyAttacker(target) = derived.stage {
                let targetKind = advice.primaryDangerProblems.first(where: {
                    $0.target == target
                })?.piece.kind ?? .pawn
                miss = .expectedAttacker(target: targetKind)
            } else {
                miss = .expectedLearnerPiece
            }

        case let .opponentCheck(move, _):
            let origin = episode.evidence.tentativeOrigin ?? .preexisting
            guard let (_, assessment) = reconciler.applicableTentativeAdvice(
                for: move,
                origin: origin,
                learner: learner,
                episode: episode
            ) else {
                return reconcile()
            }
            let matchingIssues = assessment.opponentIssues.filter {
                $0.reply.from == square
            }
            if let issue = matchingIssues.first(where: {
                $0.severity == .reviseMove
            }) ?? matchingIssues.first {
                episode.evidence.replyAnswer = .issue(move: move, issue: issue)
            } else if let activity = assessment.opponentActivities.first(where: {
                $0.reply.from == square
            }) {
                miss = .benignOpponentActivity(activity)
            } else {
                miss = .notReplyIssue
            }

        default:
            return []
        }

        let directives = reconcile()
        if let miss {
            recordAttempt(feedback: miss, anchor: .identification(square: square))
        }
        return directives
    }

    private mutating func handleInteractionChange(
        _ interaction: CoachingInteractionSnapshot
    ) -> [CoachingDirective] {
        let previous = episode.interaction
        guard previous != interaction else {
            return reconcile()
        }

        reduceInteraction(to: interaction)
        let directives = reconcile()
        let selectionOnlyChange = previous.tentativeMove == interaction.tentativeMove
            && previous.positionRevision == interaction.positionRevision
            && previous.selectedSquare != interaction.selectedSquare
        if selectionOnlyChange {
            let derived = reconciler.derive(learner: learner, episode: episode)
            if let feedback = derived.derivedFeedback {
                recordAttempt(
                    feedback: feedback,
                    anchor: .selection(square: interaction.selectedSquare)
                )
            }
        }
        return directives
    }

    private mutating func handleAction(
        _ action: CoachingAction
    ) -> [CoachingDirective] {
        let current = reconciler.derive(learner: learner, episode: episode)
        let context = projector.context(
            learner: learner,
            derived: current,
            episode: episode
        )
        guard context?.actions.contains(action) == true else {
            return []
        }

        switch action {
        case .hint:
            episode.progress.hintLevel += 1
            episode.progress.missesAtCurrentLevel = 0
            episode.progress.feedback = nil
            episode.progress.feedbackAnchor = nil
            episode.progress.pulseID += 1
            return reconcile()

        case .noAnswer:
            guard let advice = reconciler.applicablePositionAdvice(
                in: episode,
                learner: learner
            ) else {
                return reconcile()
            }
            switch current.stage {
            case .safeLocate:
                if advice.dangerProblems.isEmpty {
                    episode.evidence.confirmedSafeAbsence = true
                    let directives = reconcile()
                    recordFeedback(
                        .correctAbsence(.noPieceNeedsHelp),
                        anchor: .action(.noAnswer)
                    )
                    return directives
                }
            case .takeChooseMove:
                if advice.takeOpportunities.isEmpty {
                    let discardsTentativeMove = episode.interaction.tentativeMove != nil
                    if discardsTentativeMove {
                        reduceInteraction(to: CoachingInteractionSnapshot(
                            selectedSquare: nil,
                            tentativeMove: nil,
                            positionRevision: episode.interaction.positionRevision
                        ))
                    }
                    episode.evidence.confirmedTakeAbsence = true
                    let directives = reconcile()
                    recordFeedback(
                        .correctAbsence(.noSafeCapture),
                        anchor: .action(.noAnswer)
                    )
                    return (discardsTentativeMove ? [.discardTentativeMove] : [])
                        + directives
                }
            default:
                return []
            }
            recordAttempt(
                feedback: .missedExistingAnswer(
                    current.stage == .safeLocate ? .noPieceNeedsHelp : .noSafeCapture
                ),
                anchor: .action(.noAnswer)
            )
            return []

        case .looksSafe:
            guard case let .opponentCheck(move, _) = current.stage else { return [] }
            episode.evidence.replyAnswer = .looksSafe(
                move: move,
                afterBenignActivity: episode.evidence.benignOpponentActivityObserved
            )
            let derived = reconciler.derive(learner: learner, episode: episode)
            let directives = reconcile()
            if derived.derivedFeedback != nil,
               !isCompletion(derived.stage) {
                recordAttempt(
                    feedback: derived.derivedFeedback,
                    anchor: .action(.looksSafe)
                )
            }
            return directives

        case .stop:
            return [.stop(preservingTentativeMove: true)]
        case .keepLooking:
            reduceInteraction(to: CoachingInteractionSnapshot(
                selectedSquare: nil,
                tentativeMove: nil,
                positionRevision: episode.interaction.positionRevision
            ))
            episode.evidence = .empty
            resetProgressPreservingPulse()
            return [.discardTentativeMove] + reconcile()
        case .done:
            return [.commitWithExistingDonePath]
        }
    }

    private mutating func reduceInteraction(
        to interaction: CoachingInteractionSnapshot
    ) {
        let previous = episode.interaction
        let previousDerived = reconciler.derive(learner: learner, episode: episode)
        let oldMove = previous.tentativeMove
        let newMove = interaction.tentativeMove

        episode.interaction = interaction

        if oldMove == nil, newMove != nil {
            episode.evidence.tentativeOrigin = moveOrigin(for: previousDerived.stage)
                ?? .preexisting
            clearMoveKnowledgeAndEvidence()
        } else if oldMove != newMove {
            if newMove == nil {
                episode.evidence.tentativeOrigin = nil
            }
            clearMoveKnowledgeAndEvidence()
        } else if previous.positionRevision != interaction.positionRevision {
            episode.knowledge.tentativeAdvice = nil
            episode.knowledge.pendingContext = nil
            episode.knowledge.unsupportedContext = nil
            episode.evidence.replyAnswer = nil
        }
    }

    private mutating func clearMoveKnowledgeAndEvidence() {
        episode.knowledge.tentativeAdvice = nil
        episode.knowledge.unsupportedContext = nil
        episode.knowledge.pendingContext = nil
        episode.evidence.replyAnswer = nil
        episode.evidence.benignOpponentActivityObserved = false
        episode.progress.pulseID = 0
    }

    @discardableResult
    private mutating func reconcile() -> [CoachingDirective] {
        var derived = reconciler.derive(learner: learner, episode: episode)
        if derived.questionID != nil {
            episode.progress.enter(derived.questionID)
        }
        episode.progress.discardFeedbackInvalidated(by: episode.interaction)
        derived = reconciler.derive(learner: learner, episode: episode)
        publish(derived)
        return directiveForUnqueuedRequest(derived.requestedAdvice)
    }

    private mutating func publish(_ derived: CoachingDerivedState) {
        stage = derived.stage
        guard !derived.stage.isAwaitingAdvice else { return }
        let context = projector.context(
            learner: learner,
            derived: derived,
            episode: episode
        )
        presentation = context.map { explainer.presentation(for: $0) }
    }

    private mutating func directiveForUnqueuedRequest(
        _ requestedContext: CoachingRequest.Context?
    ) -> [CoachingDirective] {
        guard let requestedContext,
              episode.knowledge.pendingContext != requestedContext else {
            return []
        }
        episode.knowledge.pendingContext = requestedContext
        return [.requestAdvice(context: requestedContext)]
    }

    private mutating func recordAttempt(
        feedback: CoachingFeedback?,
        anchor: CoachingFeedbackAnchor
    ) {
        if case .benignOpponentActivity = feedback {
            episode.evidence.benignOpponentActivityObserved = true
        }
        episode.progress.missesAtCurrentLevel += 1
        episode.progress.feedback = feedback
        episode.progress.feedbackAnchor = anchor
        publish(reconciler.derive(learner: learner, episode: episode))
    }

    private mutating func recordFeedback(
        _ feedback: CoachingFeedback,
        anchor: CoachingFeedbackAnchor
    ) {
        episode.progress.feedback = feedback
        episode.progress.feedbackAnchor = anchor
        publish(reconciler.derive(learner: learner, episode: episode))
    }

    private mutating func resetProgressPreservingPulse() {
        episode.progress = CoachingQuestionProgress(
            questionID: nil,
            hintLevel: 0,
            missesAtCurrentLevel: 0,
            feedback: nil,
            feedbackAnchor: nil,
            pulseID: episode.progress.pulseID
        )
    }

    private func adviceMatchesCurrentInteraction(_ advice: CoachingAdvice) -> Bool {
        let request = advice.evaluation.request
        guard request.learner == learner,
              request.positionRevision == episode.interaction.positionRevision,
              request.tentativeMove == episode.interaction.tentativeMove else {
            return false
        }
        return contextMatchesCurrentInteraction(request.context)
    }

    private func adviceMatchesCurrentKnowledgeRequirement(
        _ advice: CoachingAdvice
    ) -> Bool {
        let request = advice.evaluation.request
        if let pendingContext = episode.knowledge.pendingContext,
           request.context != pendingContext {
            return false
        }
        guard case .tentativeMove = request.context,
              let positionAdvice = episode.knowledge.positionAdvice else {
            return true
        }
        let positionRequest = positionAdvice.evaluation.request
        return request.committedState == positionRequest.committedState
            && request.positionRevision == positionRequest.positionRevision
    }

    private func contextMatchesCurrentInteraction(
        _ context: CoachingRequest.Context
    ) -> Bool {
        switch context {
        case .start:
            return episode.interaction.tentativeMove == nil
        case let .tentativeMove(origin):
            return episode.interaction.tentativeMove != nil
                && episode.evidence.tentativeOrigin == origin
        }
    }

    private func moveOrigin(for stage: CoachingStage) -> CoachingMoveOrigin? {
        switch stage {
        case .awaitingAdvice(origin: nil):
            return .preexisting
        case .checkResolve:
            return .check
        case .safeResolve:
            return .safe
        case .takeChooseMove:
            return .take
        case .wakeChoosePiece, .wakeChooseMove:
            return .wake
        case .fallbackChooseMove:
            return .fallback
        case let .awaitingAdvice(origin):
            return origin
        case let .opponentCheck(_, origin),
             let .reviseMove(origin),
             let .complete(_, origin, _):
            return origin
        case .checkLocate, .safeLocate, .safeIdentifyAttacker:
            return nil
        }
    }

    private func safeTargetFeedback(
        for square: Square,
        piece: Piece,
        advice: CoachingAdvice
    ) -> CoachingFeedback {
        if let chosen = advice.dangerProblems.first(where: { $0.target == square }),
           let primary = advice.dangerProblems.first {
            return .lowerPriorityDanger(
                chosen: chosen.piece.kind,
                chosenLoss: chosen.worstEstimatedLoss,
                primary: primary.piece.kind,
                primaryLoss: primary.worstEstimatedLoss
            )
        }

        let board = advice.evaluation.request.committedState.board
        if let attack = advice.evaluation.opponentCaptureEstimates.first(where: {
            $0.capturedSquare == square
                && $0.netGainForMover <= 0
                && $0.immediateRecapture != nil
        }),
           let recapture = attack.immediateRecapture,
           let attacker = board[attack.move.from],
           let defender = board[recapture.from] {
            return .attackedButProtected(CoachingProtectedPieceFact(
                targetSquare: square,
                target: piece.kind,
                attackerSquare: attack.move.from,
                attacker: attacker.kind,
                defenderSquare: recapture.from,
                defender: defender.kind,
                noPieceNeedsHelp: advice.dangerProblems.isEmpty
            ))
        }

        return .safePiece(piece: piece.kind)
    }

    private func pieceKind(
        at square: Square,
        advice: CoachingAdvice
    ) -> Piece.Kind? {
        advice.evaluation.request.committedState.board[square]?.kind
    }

    private func isCompletion(_ stage: CoachingStage) -> Bool {
        if case .complete = stage { return true }
        return false
    }
}

private extension CoachingStage {
    var isAwaitingAdvice: Bool {
        if case .awaitingAdvice = self { return true }
        return false
    }
}

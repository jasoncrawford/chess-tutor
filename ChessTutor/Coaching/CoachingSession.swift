struct CoachingSession: Sendable {
    private let learner: PieceColor
    private let explainer: any CoachingExplaining
    private let reconciler = CoachingReconciler()
    private let projector = CoachingPresentationProjector()
    private var episode: CoachingEpisodeState

    private(set) var stage: CoachingStage
    private(set) var presentation: CoachingPresentation?

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
                if episode.evidence.safeTarget != square {
                    episode.evidence.safeTarget = square
                    episode.evidence.safeAttacker = nil
                }
                miss = safeTargetFeedback(for: square, piece: piece, advice: advice)
            } else if case let .safeIdentifyAttacker(target) = derived.stage,
                      let problem = advice.urgentProblems.first(where: {
                          $0.target == target
                      }),
                      let piece = board[square], piece.color == learner.opposite {
                if problem.captures.contains(where: { $0.move.from == square }) {
                    episode.evidence.safeAttacker = square
                } else {
                    miss = .notAttacker(piece: piece.kind, target: problem.piece.kind)
                }
            } else if case let .safeIdentifyAttacker(target) = derived.stage {
                let targetKind = advice.urgentProblems.first(where: {
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
                $0.answerSquares.contains(square)
            }
            if let issue = matchingIssues.first(where: {
                $0.severity == .reviseMove
            }) ?? matchingIssues.first {
                episode.evidence.replyAnswer = .issue(move: move, issue: issue)
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
                if advice.urgentProblems.isEmpty {
                    episode.evidence.confirmedSafeAbsence = true
                    let directives = reconcile()
                    recordFeedback(
                        .correctAbsence(.noPieceNeedsHelp),
                        anchor: .action(.noAnswer)
                    )
                    return directives
                }
            case .takeChooseMove:
                if advice.takeOpportunities.isEmpty
                    && advice.evaluation.mateInOneMoves.isEmpty {
                    episode.evidence.confirmedTakeAbsence = true
                    let directives = reconcile()
                    recordFeedback(
                        .correctAbsence(.noSafeCapture),
                        anchor: .action(.noAnswer)
                    )
                    return directives
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
            episode.evidence.replyAnswer = .looksSafe(move: move)
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
            return [.stop(preservingTentativeMove: true)]
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
    ) -> CoachingFeedback? {
        if advice.urgentProblems.contains(where: { $0.target == square }) {
            return nil
        }
        let isThreatened = advice.evaluation.opponentCaptureEstimates.contains {
            $0.capturedSquare == square
        }
        guard isThreatened else { return .safePiece(piece: piece.kind) }
        if let urgent = advice.urgentProblems.first,
           isMoreValuable(urgent.piece.kind, than: piece.kind) {
            return .lowerPriorityThreat(
                piece: piece.kind,
                urgentPiece: urgent.piece.kind
            )
        }
        return .nonurgentThreat(piece: piece.kind)
    }

    private func isMoreValuable(_ lhs: Piece.Kind, than rhs: Piece.Kind) -> Bool {
        let evaluator = MaterialTacticalEvaluator()
        guard let lhsValue = evaluator.pieceValue(lhs),
              let rhsValue = evaluator.pieceValue(rhs) else {
            return false
        }
        return lhsValue > rhsValue
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

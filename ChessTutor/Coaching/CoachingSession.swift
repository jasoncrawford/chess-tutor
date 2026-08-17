struct CoachingSession: Sendable {
    private let learner: PieceColor
    private let explainer: any CoachingExplaining
    private let projector = CoachingPresentationProjector()
    private var latestAdvice: CoachingAdvice?
    private var selectedSafeTarget: Square?
    private var selectedSafeAttacker: Square?
    private var selectedWakePiece: Square?
    private var selectedWakePurpose: CoachingWakePurpose?
    private var tentativeMove: Move?
    private var positionRevision: Int?
    private var feedback: CoachingFeedback?
    private var promptOverride: CoachingPrompt?
    private var pulseID = 0

    private(set) var stage: CoachingStage
    private(set) var presentation: CoachingPresentation?
    private(set) var hintLevel: Int
    private(set) var missesAtCurrentLevel: Int

    init(
        learner: PieceColor,
        explainer: any CoachingExplaining = LocalCoachingExplanationSource()
    ) {
        self.learner = learner
        self.explainer = explainer
        stage = .awaitingAdvice(origin: nil)
        presentation = nil
        hintLevel = 0
        missesAtCurrentLevel = 0
    }

    @discardableResult
    mutating func receive(_ advice: CoachingAdvice) -> [CoachingDirective] {
        latestAdvice = advice
        positionRevision = advice.evaluation.request.positionRevision
        switch advice.evaluation.request.context {
        case .start:
            tentativeMove = nil
            clearSafeFocus()
            selectedWakePiece = nil
            selectedWakePurpose = nil
            begin(with: advice)
        case let .tentativeMove(origin):
            receiveMoveAdvice(advice, origin: origin)
        }
        return []
    }

    mutating func receiveUnsupportedPosition() {
        latestAdvice = nil
        tentativeMove = nil
        clearSafeFocus()
        selectedWakePiece = nil
        selectedWakePurpose = nil
        transition(to: .fallbackChooseMove)
    }

    @discardableResult
    mutating func handle(_ event: CoachingEvent) -> [CoachingDirective] {
        switch event {
        case let .squareTapped(square):
            return handleSquareTap(square)
        case let .moveStaged(move):
            return handleStagedMove(move)
        case let .actionChosen(action):
            return handleAction(action)
        case let .positionChanged(revision):
            positionRevision = revision
            invalidateTentativeMoveIfNeeded()
            return []
        }
    }

    private mutating func begin(with advice: CoachingAdvice) {
        if !advice.checkingPieces.isEmpty {
            transition(to: .checkLocate)
        } else if advice.evaluation.opponentHasAnyLegalCapture {
            transition(to: .safeLocate)
        } else {
            proceedToTake()
        }
    }

    private mutating func proceedToTake(feedback: CoachingFeedback? = nil) {
        guard let advice = latestAdvice else {
            transition(to: .fallbackChooseMove, feedback: feedback)
            return
        }
        if advice.evaluation.learnerHasAnyLegalCapture
            || !advice.evaluation.mateInOneMoves.isEmpty {
            transition(to: .takeChooseMove, feedback: feedback)
        } else {
            proceedToWake(feedback: feedback)
        }
    }

    private mutating func proceedToWake(feedback: CoachingFeedback? = nil) {
        guard let advice = latestAdvice,
              advice.confidence != .unsupported,
              !wakeSources(in: advice).isEmpty
        else {
            transition(to: .fallbackChooseMove, feedback: feedback)
            return
        }
        transition(
            to: .wakeChoosePiece(purpose: initialWakePurpose(in: advice)),
            feedback: feedback
        )
    }

    private mutating func handleSquareTap(_ square: Square) -> [CoachingDirective] {
        guard let advice = latestAdvice else { return [] }
        switch stage {
        case .checkLocate:
            handleCheckTap(square, advice: advice)
        case .safeLocate:
            handleSafeLocateTap(square, advice: advice)
        case let .safeIdentifyAttacker(target):
            handleSafeAttackerTap(square, target: target, advice: advice)
        case let .wakeChoosePiece(purpose):
            return handleWakeSourceTap(square, purpose: purpose, advice: advice)
        case let .opponentCheck(move, origin):
            handleOpponentReplyTap(square, move: move, origin: origin, advice: advice)
        default:
            break
        }
        return []
    }

    private mutating func handleCheckTap(_ square: Square, advice: CoachingAdvice) {
        if advice.checkingPieces.contains(square) {
            transition(to: .checkResolve)
        } else {
            recordMiss(.notCheckingPiece(piece: pieceKind(at: square)))
        }
    }

    private mutating func handleSafeLocateTap(_ square: Square, advice: CoachingAdvice) {
        let board = advice.evaluation.request.committedState.board
        if advice.urgentProblems.contains(where: { $0.target == square }) {
            selectedSafeTarget = square
            selectedSafeAttacker = nil
            transition(to: .safeIdentifyAttacker(target: square))
        } else if let piece = board[square], piece.color == learner {
            let isThreatened = advice.evaluation.opponentCaptureEstimates.contains {
                $0.capturedSquare == square
            }
            if isThreatened {
                if let urgent = advice.urgentProblems.first,
                   isMoreValuable(urgent.piece.kind, than: piece.kind) {
                    recordMiss(.lowerPriorityThreat(
                        piece: piece.kind,
                        urgentPiece: urgent.piece.kind
                    ))
                } else {
                    recordMiss(.nonurgentThreat(piece: piece.kind))
                }
            } else {
                recordMiss(.safePiece(piece: piece.kind))
            }
        } else {
            recordMiss(.expectedLearnerPiece)
        }
    }

    private mutating func handleSafeAttackerTap(
        _ square: Square,
        target: Square,
        advice: CoachingAdvice
    ) {
        guard let problem = advice.urgentProblems.first(where: { $0.target == target }) else {
            recordMiss(.expectedAttacker(target: pieceKind(at: target) ?? .pawn))
            return
        }
        if problem.captures.contains(where: { $0.move.from == square }) {
            selectedSafeAttacker = square
            transition(to: .safeResolve(target: target))
        } else if let piece = advice.evaluation.request.committedState.board[square],
                  piece.color == learner.opposite {
            recordMiss(.notAttacker(
                piece: piece.kind,
                target: problem.piece.kind
            ))
        } else {
            recordMiss(.expectedAttacker(target: problem.piece.kind))
        }
    }

    private mutating func handleWakeSourceTap(
        _ square: Square,
        purpose: CoachingWakePurpose,
        advice: CoachingAdvice
    ) -> [CoachingDirective] {
        let board = advice.evaluation.request.committedState.board
        let sources = wakeSources(in: advice)
        if sources.contains(square) {
            let selectedPurpose = wakePurpose(for: square, in: advice)
            selectedWakePiece = square
            selectedWakePurpose = selectedPurpose
            transition(to: .wakeChooseMove(piece: square, purpose: selectedPurpose))
            return [.selectSquare(square)]
        }
        guard let piece = board[square], piece.color == learner else {
            recordMiss(.expectedLearnerPiece)
            return []
        }
        let allowed = LegalMoveGenerator.allowedMoves(
            for: square,
            by: learner,
            in: advice.evaluation.request.committedState
        )
        let feedback: CoachingFeedback = allowed.isEmpty
            ? .blockedWakePiece(piece: piece.kind)
            : .notWakeCandidate(piece: piece.kind, purpose: purpose)
        recordMiss(feedback)
        return []
    }

    private mutating func handleOpponentReplyTap(
        _ square: Square,
        move: Move,
        origin: CoachingMoveOrigin,
        advice: CoachingAdvice
    ) {
        guard let assessment = advice.moveAssessments[move] else {
            recordMiss(.notReplyIssue)
            return
        }
        let matchingIssues = assessment.opponentIssues.filter {
            $0.answerSquares.contains(square)
        }
        guard let issue = matchingIssues.first(where: {
            $0.severity == .reviseMove
        }) ?? matchingIssues.first else {
            recordMiss(.notReplyIssue)
            return
        }
        handleFoundIssue(issue, assessment: assessment, move: move, origin: origin)
    }

    private mutating func handleStagedMove(_ move: Move) -> [CoachingDirective] {
        let origin = moveOrigin(for: stage)
        guard let origin else { return [] }

        tentativeMove = move
        transition(to: .awaitingAdvice(origin: origin), resetsQuestion: false)
        return [.requestAdvice(context: .tentativeMove(origin: origin))]
    }

    private mutating func handleAction(_ action: CoachingAction) -> [CoachingDirective] {
        switch action {
        case .hint:
            guard projectionContext()?.actions.contains(.hint) == true
            else { return [] }
            hintLevel += 1
            missesAtCurrentLevel = 0
            feedback = nil
            pulseID += 1
            rebuildPresentation()
            return []
        case .noAnswer:
            switch stage {
            case .safeLocate:
                if latestAdvice?.urgentProblems.isEmpty == true {
                    proceedToTake(feedback: .correctAbsence)
                } else {
                    recordMiss(.missedExistingAnswer)
                }
            case .takeChooseMove:
                if latestAdvice?.takeOpportunities.isEmpty == true {
                    proceedToWake(feedback: .correctAbsence)
                } else {
                    recordMiss(.missedExistingAnswer)
                }
            default:
                break
            }
            return []
        case .looksSafe:
            handleLooksSafe()
            return []
        case .stop, .keepLooking:
            clearSafeFocus()
            return [.stop(preservingTentativeMove: true)]
        case .done:
            guard case .complete = stage else { return [] }
            return [.commitWithExistingDonePath]
        }
    }

    private mutating func receiveMoveAdvice(
        _ advice: CoachingAdvice,
        origin: CoachingMoveOrigin
    ) {
        guard let move = advice.evaluation.request.tentativeMove,
              let assessment = advice.moveAssessments[move]
        else {
            transition(to: .fallbackChooseMove)
            return
        }

        tentativeMove = move
        if !assessment.isLegal {
            returnToOrigin(
                origin,
                feedback: nil,
                prompt: .illegalKingSafety,
                preservingQuestionProgress: true
            )
            return
        }

        if origin == .take && !hasTakePurpose(assessment.concepts) {
            returnToOrigin(
                origin,
                feedback: unprofitableCaptureFeedback(for: move, advice: advice),
                preservingQuestionProgress: true
            )
            return
        }

        if origin == .safe && !assessment.resolvesRequiredDanger {
            returnToOrigin(
                origin,
                feedback: unresolvedDangerFeedback(for: assessment, advice: advice),
                preservingQuestionProgress: true
            )
            return
        }

        if origin == .wake && !hasWakePurpose(assessment.concepts) {
            returnToOrigin(
                origin,
                feedback: .noRecognizedPurpose(purpose: selectedWakePurpose),
                preservingQuestionProgress: true
            )
            return
        }

        transition(to: .opponentCheck(move: move, origin: origin))
    }

    private mutating func handleLooksSafe() {
        guard case let .opponentCheck(move, origin) = stage,
              let assessment = latestAdvice?.moveAssessments[move]
        else { return }

        if !assessment.opponentIssues.isEmpty {
            recordMiss(.missedExistingAnswer)
        } else if assessment.isAcceptable {
            complete(move: move, origin: origin, assessment: assessment)
        } else {
            returnToOrigin(origin, feedback: .noRecognizedPurpose(purpose: selectedWakePurpose))
        }
    }

    private mutating func handleFoundIssue(
        _ issue: CoachingOpponentIssue,
        assessment: CoachingMoveAssessment,
        move: Move,
        origin: CoachingMoveOrigin
    ) {
        switch issue.severity {
        case .reviseMove:
            transition(
                to: .reviseMove(origin: origin),
                feedback: .concreteFlaw(
                    kind: issue.kind,
                    affectedPiece: affectedPieceKind(for: issue, move: move)
                )
            )
        case .notice:
            if issue.kind == .check,
               assessment.opponentIssues.contains(where: { $0.severity == .reviseMove }) {
                missesAtCurrentLevel = 0
                feedback = .checkFoundOtherDangerRemains
                promptOverride = nil
                rebuildPresentation()
                return
            }
            let foundFeedback: CoachingFeedback
            if issue.kind == .check {
                foundFeedback = .harmlessCheckFound
            } else {
                foundFeedback = .concreteFlaw(
                    kind: issue.kind,
                    affectedPiece: affectedPieceKind(for: issue, move: move)
                )
            }
            if assessment.isAcceptable {
                complete(
                    move: move,
                    origin: origin,
                    assessment: assessment,
                    feedback: foundFeedback
                )
            } else {
                transition(to: .reviseMove(origin: origin), feedback: foundFeedback)
            }
        }
    }

    private mutating func complete(
        move: Move,
        origin: CoachingMoveOrigin,
        assessment: CoachingMoveAssessment,
        feedback: CoachingFeedback? = nil
    ) {
        transition(
            to: .complete(move: move, origin: origin, concepts: assessment.concepts),
            feedback: feedback
        )
    }

    private mutating func invalidateTentativeMoveIfNeeded() {
        guard tentativeMove != nil else { return }
        switch stage {
        case let .awaitingAdvice(storedOrigin):
            guard let storedOrigin else { return }
            tentativeMove = nil
            latestAdvice = nil
            transition(to: .reviseMove(origin: storedOrigin))
        case let .opponentCheck(_, storedOrigin),
             let .complete(_, storedOrigin, _):
            tentativeMove = nil
            latestAdvice = nil
            transition(to: .reviseMove(origin: storedOrigin))
        case .checkResolve, .safeResolve, .takeChooseMove, .wakeChooseMove,
             .fallbackChooseMove, .reviseMove:
            tentativeMove = nil
            rebuildPresentation()
        default:
            break
        }
    }

    private mutating func returnToOrigin(
        _ origin: CoachingMoveOrigin,
        feedback: CoachingFeedback?,
        prompt: CoachingPrompt? = nil,
        preservingQuestionProgress: Bool = false
    ) {
        let returnStage: CoachingStage
        switch origin {
        case .preexisting:
            returnStage = .reviseMove(origin: .preexisting)
        case .check:
            returnStage = .checkResolve
        case .safe:
            if let target = selectedSafeTarget {
                returnStage = .safeResolve(target: target)
            } else if let target = latestAdvice?.urgentProblems.first?.target {
                returnStage = .safeResolve(target: target)
            } else {
                returnStage = .reviseMove(origin: .safe)
            }
        case .take:
            returnStage = .takeChooseMove
        case .wake:
            if let piece = selectedWakePiece,
               let purpose = selectedWakePurpose {
                returnStage = .wakeChooseMove(piece: piece, purpose: purpose)
            } else {
                returnStage = .reviseMove(origin: .wake)
            }
        case .fallback:
            returnStage = .fallbackChooseMove
        }
        stage = returnStage
        if !preservingQuestionProgress {
            hintLevel = 0
            missesAtCurrentLevel = 0
        }
        missesAtCurrentLevel += 1
        self.feedback = feedback
        promptOverride = prompt
        rebuildPresentation()
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
        case .wakeChooseMove:
            return .wake
        case .fallbackChooseMove:
            return .fallback
        case let .reviseMove(origin), let .opponentCheck(_, origin):
            return origin
        default:
            return nil
        }
    }

    private func hasTakePurpose(_ concepts: [CoachingConcept]) -> Bool {
        concepts.contains(.profitableCapture)
            || concepts.contains(.mateInOne)
            || concepts.contains(.captureResolvesDanger)
    }

    private func hasWakePurpose(_ concepts: [CoachingConcept]) -> Bool {
        let wakeConcepts: Set<CoachingConcept> = [
            .developsKnightOrBishop,
            .advancesCenterPawn,
            .castlesForKingSafety,
            .addsUsefulDefender,
            .createsSafeImmediateThreat,
            .improvesCentralActivity,
        ]
        return concepts.contains(where: wakeConcepts.contains)
    }

    private func wakeSources(in advice: CoachingAdvice) -> Set<Square> {
        Set(advice.wakeOpportunities.flatMap { $0.moves.map(\.from) })
    }

    private func wakeSources(
        for purpose: CoachingWakePurpose,
        in advice: CoachingAdvice
    ) -> Set<Square> {
        Set(advice.wakeOpportunities
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

    private func wakePurpose(for source: Square, in advice: CoachingAdvice) -> CoachingWakePurpose {
        let concept = advice.wakeOpportunities.first {
            $0.moves.contains { $0.from == source }
        }?.concept
        return wakePurpose(for: concept, in: advice)
    }

    private func initialWakePurpose(in advice: CoachingAdvice) -> CoachingWakePurpose {
        guard let source = advice.wakeOpportunities.first?.moves.first?.from else {
            return .centralActivity
        }
        return wakePurpose(for: source, in: advice)
    }

    private func unresolvedDangerFeedback(
        for assessment: CoachingMoveAssessment,
        advice: CoachingAdvice
    ) -> CoachingFeedback {
        let committedState = advice.evaluation.request.committedState
        let stateAfterMove = committedState.applyingUnchecked(assessment.move)
        if let issue = assessment.opponentIssues.first(where: {
            if case .materialLoss = $0.kind { return true }
            return false
        }),
           let capturedSquare = LegalMoveGenerator.capture(
               for: issue.reply,
               in: stateAfterMove
           )?.square,
           let attacker = stateAfterMove.board[issue.reply.from]?.kind,
           let target = stateAfterMove.board[capturedSquare]?.kind {
            return .dangerStillPresent(attacker: attacker, target: target)
        }
        let target = selectedSafeTarget.flatMap(pieceKind(at:))
            ?? advice.urgentProblems.first?.piece.kind
            ?? .king
        let attacker = selectedSafeAttacker.flatMap { pieceKind(at: $0) }
        return .dangerStillPresent(attacker: attacker, target: target)
    }

    private func isMoreValuable(_ lhs: Piece.Kind, than rhs: Piece.Kind) -> Bool {
        let evaluator = MaterialTacticalEvaluator()
        guard let lhsValue = evaluator.pieceValue(lhs),
              let rhsValue = evaluator.pieceValue(rhs)
        else {
            return false
        }
        return lhsValue > rhsValue
    }

    private func unprofitableCaptureFeedback(
        for move: Move,
        advice: CoachingAdvice
    ) -> CoachingFeedback {
        let estimate = advice.evaluation.learnerCaptureEstimates.first { $0.move == move }
        let movedPiece = advice.evaluation.request.committedState.board[move.from]?.kind
        let points = max(1, -(estimate?.netGainForMover ?? 0))
        return .concreteFlaw(kind: .materialLoss(points: points), affectedPiece: movedPiece)
    }

    private func affectedPieceKind(for issue: CoachingOpponentIssue, move: Move) -> Piece.Kind? {
        guard let advice = latestAdvice else { return nil }
        if issue.reply.to == move.to {
            return advice.evaluation.request.committedState.board[move.from]?.kind
        }
        return advice.evaluation.request.committedState.board[issue.reply.to]?.kind
    }

    private mutating func recordMiss(_ newFeedback: CoachingFeedback) {
        missesAtCurrentLevel += 1
        feedback = newFeedback
        promptOverride = nil
        rebuildPresentation()
    }

    private mutating func clearSafeFocus() {
        selectedSafeTarget = nil
        selectedSafeAttacker = nil
    }

    private mutating func transition(
        to newStage: CoachingStage,
        feedback newFeedback: CoachingFeedback? = nil,
        prompt: CoachingPrompt? = nil,
        resetsQuestion: Bool = true
    ) {
        stage = newStage
        if resetsQuestion {
            hintLevel = 0
            missesAtCurrentLevel = 0
        }
        feedback = newFeedback
        promptOverride = prompt
        rebuildPresentation()
    }

    private mutating func rebuildPresentation() {
        guard let context = projectionContext() else {
            presentation = nil
            return
        }
        presentation = explainer.presentation(for: context)
    }

    private func projectionContext() -> CoachingPresentationContext? {
        let episode = projectorEpisode
        let derived = CoachingDerivedState(
            stage: stage,
            questionID: episode.progress.questionID,
            promptOverride: promptOverride,
            derivedFeedback: nil,
            requestedAdvice: nil
        )
        return projector.context(learner: learner, derived: derived, episode: episode)
    }

    private var projectorEpisode: CoachingEpisodeState {
        let positionAdvice: CoachingAdvice?
        let tentativeAdvice: CoachingAdvice?
        switch latestAdvice?.evaluation.request.context {
        case .start:
            positionAdvice = latestAdvice
            tentativeAdvice = nil
        case .tentativeMove:
            positionAdvice = tentativeMove == nil ? latestAdvice : nil
            tentativeAdvice = tentativeMove == nil ? nil : latestAdvice
        case nil:
            positionAdvice = nil
            tentativeAdvice = nil
        }

        return CoachingEpisodeState(
            knowledge: CoachingKnowledge(
                positionAdvice: positionAdvice,
                tentativeAdvice: tentativeAdvice,
                unsupportedContext: nil,
                pendingContext: nil
            ),
            evidence: CoachingPedagogicalEvidence(
                checkingPiece: checkingPieceForProjection,
                safeTarget: selectedSafeTarget,
                safeAttacker: selectedSafeAttacker,
                confirmedSafeAbsence: false,
                confirmedTakeAbsence: false,
                tentativeOrigin: tentativeOriginForProjection,
                replyAnswer: nil
            ),
            progress: CoachingQuestionProgress(
                questionID: projectorQuestionID,
                hintLevel: hintLevel,
                missesAtCurrentLevel: missesAtCurrentLevel,
                feedback: feedback,
                feedbackAnchor: nil,
                pulseID: pulseID
            ),
            interaction: CoachingInteractionSnapshot(
                selectedSquare: selectedWakePiece,
                tentativeMove: tentativeMove,
                positionRevision: positionRevision
                    ?? latestAdvice?.evaluation.request.positionRevision
                    ?? 0
            )
        )
    }

    private var projectorQuestionID: CoachingQuestionID? {
        switch stage {
        case .awaitingAdvice:
            return nil
        case .checkLocate:
            return .checkLocate
        case .checkResolve:
            guard let checker = checkingPieceForProjection else { return nil }
            return .checkResolve(checker: checker)
        case .safeLocate:
            return .safeLocate
        case let .safeIdentifyAttacker(target):
            return .safeAttacker(target: target)
        case let .safeResolve(target):
            guard let attacker = selectedSafeAttacker else { return nil }
            return .safeResolve(target: target, attacker: attacker)
        case .takeChooseMove:
            return .take
        case let .wakeChoosePiece(purpose):
            return .wakeSource(purpose: purpose)
        case let .wakeChooseMove(piece, purpose):
            return .wakeMove(source: piece, purpose: purpose)
        case .fallbackChooseMove:
            return .fallback
        case let .opponentCheck(move, origin):
            return .opponentReply(move: move, origin: origin)
        case let .reviseMove(origin):
            return .revise(move: tentativeMove, origin: origin)
        case let .complete(move, origin, _):
            return .complete(move: move, origin: origin)
        }
    }

    private var checkingPieceForProjection: Square? {
        guard case .checkResolve = stage else { return nil }
        return latestAdvice?.checkingPieces.first
    }

    private var tentativeOriginForProjection: CoachingMoveOrigin? {
        switch stage {
        case let .awaitingAdvice(origin):
            return origin
        case let .opponentCheck(_, origin),
             let .reviseMove(origin),
             let .complete(_, origin, _):
            return origin
        default:
            return moveOrigin(for: stage)
        }
    }

    private func pieceKind(at square: Square) -> Piece.Kind? {
        latestAdvice?.evaluation.request.committedState.board[square]?.kind
    }
}

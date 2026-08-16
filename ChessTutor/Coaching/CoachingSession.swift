enum CoachingStage: Equatable, Sendable {
    case awaitingAdvice(origin: CoachingMoveOrigin?)
    case checkLocate
    case checkResolve
    case safeLocate
    case safeIdentifyAttacker(target: Square)
    case safeResolve(target: Square)
    case takeChooseMove
    case wakeChoosePiece(purpose: CoachingWakePurpose)
    case wakeChooseMove(piece: Square, purpose: CoachingWakePurpose)
    case fallbackChooseMove
    case opponentCheck(move: Move, origin: CoachingMoveOrigin)
    case reviseMove(origin: CoachingMoveOrigin)
    case complete(move: Move, origin: CoachingMoveOrigin, concepts: [CoachingConcept])
}

enum CoachingEvent: Equatable, Sendable {
    case squareTapped(Square)
    case moveStaged(Move)
    case actionChosen(CoachingAction)
    case positionChanged(revision: Int)
}

enum CoachingDirective: Equatable, Sendable {
    case requestAdvice(context: CoachingRequest.Context)
    case selectSquare(Square)
    case stop(preservingTentativeMove: Bool)
    case commitWithExistingDonePath
}

struct CoachingSession: Sendable {
    private let learner: PieceColor
    private let explainer: any CoachingExplaining
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
            guard presentation != nil,
                  hintLevel < hintSteps(for: stage).count
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
        let origin: CoachingMoveOrigin?
        switch stage {
        case let .awaitingAdvice(storedOrigin):
            origin = storedOrigin
        case let .opponentCheck(_, storedOrigin),
             let .complete(_, storedOrigin, _):
            origin = storedOrigin
        default:
            origin = nil
        }
        guard let origin else { return }
        tentativeMove = nil
        latestAdvice = nil
        transition(to: .reviseMove(origin: origin))
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
        guard let prompt = promptOverride ?? prompt(for: stage) else {
            presentation = nil
            return
        }
        let hint = currentHint(for: stage)
        presentation = explainer.presentation(for: CoachingPresentationContext(
            prompt: prompt,
            feedback: feedback,
            learner: learner,
            hint: hint,
            missesAtCurrentLevel: missesAtCurrentLevel,
            routine: routine(for: stage),
            actions: actions(for: stage),
            boardTask: boardTask(for: stage),
            focus: focus(for: stage, hint: hint)
        ))
    }

    private func prompt(for stage: CoachingStage) -> CoachingPrompt? {
        switch stage {
        case .awaitingAdvice:
            return nil
        case .checkLocate:
            return .checkLocate
        case .checkResolve:
            return .checkResolve
        case .safeLocate:
            return .safeLocate
        case let .safeIdentifyAttacker(target):
            return .safeIdentifyAttacker(piece: pieceKind(at: target) ?? .pawn)
        case let .safeResolve(target):
            return .safeResolve(
                target: pieceKind(at: target) ?? .pawn,
                attacker: selectedSafeAttacker.flatMap { pieceKind(at: $0) } ?? .pawn
            )
        case .takeChooseMove:
            return .takeChooseMove
        case let .wakeChoosePiece(purpose):
            return .wakeChoosePiece(purpose: purpose)
        case let .wakeChooseMove(piece, purpose):
            return .wakeChooseMove(
                piece: pieceKind(at: piece) ?? .pawn,
                purpose: purpose
            )
        case .fallbackChooseMove:
            return .fallbackChooseMove
        case .opponentCheck:
            return .opponentReply(opponent: learner.opposite)
        case .reviseMove:
            return .reviseMove
        case let .complete(move, origin, concepts):
            return .complete(
                origin: origin,
                idea: completionIdea(for: move, concepts: concepts)
            )
        }
    }

    private func pieceKind(at square: Square) -> Piece.Kind? {
        latestAdvice?.evaluation.request.committedState.board[square]?.kind
    }

    private func routine(for stage: CoachingStage) -> [CoachingRoutineState] {
        switch stage {
        case .checkLocate, .checkResolve, .safeLocate,
             .safeIdentifyAttacker, .safeResolve:
            return [.safeCurrent, .takePending, .wakePending]
        case .takeChooseMove:
            return [.safeCleared, .takeCurrent, .wakePending]
        case .wakeChoosePiece, .wakeChooseMove:
            return [.safeCleared, .takeCleared, .wakeCurrent]
        case let .opponentCheck(_, origin), let .reviseMove(origin):
            return routine(for: origin, completed: false)
        case let .complete(_, origin, _):
            return routine(for: origin, completed: true)
        case .awaitingAdvice(origin: let origin?):
            return routine(for: origin, completed: false)
        case .awaitingAdvice(origin: nil), .fallbackChooseMove:
            return []
        }
    }

    private func routine(
        for origin: CoachingMoveOrigin,
        completed: Bool
    ) -> [CoachingRoutineState] {
        switch origin {
        case .check, .safe:
            return [completed ? .safeCleared : .safeCurrent, .takePending, .wakePending]
        case .take:
            return [.safeCleared, completed ? .takeCleared : .takeCurrent, .wakePending]
        case .wake:
            return [.safeCleared, .takeCleared, completed ? .wakeCleared : .wakeCurrent]
        case .preexisting, .fallback:
            return []
        }
    }

    private func boardTask(for stage: CoachingStage) -> CoachingBoardTask {
        switch stage {
        case .checkLocate, .safeLocate, .safeIdentifyAttacker, .wakeChoosePiece:
            return .identify(allowsMoveRevision: false)
        case .opponentCheck:
            return .identify(allowsMoveRevision: true)
        case .checkResolve, .safeResolve, .takeChooseMove, .wakeChooseMove,
             .fallbackChooseMove, .reviseMove:
            return .move
        case .awaitingAdvice, .complete:
            return .none
        }
    }

    private func actions(for stage: CoachingStage) -> [CoachingAction] {
        let hintActions: [CoachingAction] = hintLevel < hintSteps(for: stage).count
            ? [.hint]
            : []
        switch stage {
        case .safeLocate, .takeChooseMove:
            return [.noAnswer] + hintActions + [.stop]
        case .opponentCheck:
            return [.looksSafe] + hintActions + [.stop]
        case .complete:
            return [.done, .keepLooking, .stop]
        case .awaitingAdvice:
            return [.stop]
        default:
            return hintActions + [.stop]
        }
    }

    private func hintSteps(for stage: CoachingStage) -> [CoachingHint] {
        switch stage {
        case .checkLocate:
            return [.checkMarker, .candidatePieces]
        case .checkResolve:
            return candidateMoves(for: stage).isEmpty ? [] : [.candidatePieces, .candidateMoves]
        case .safeLocate:
            return [.dangerMarker, .candidatePieces]
        case .safeIdentifyAttacker:
            return [.attackerRelationship, .candidatePieces]
        case .safeResolve:
            return candidateMoves(for: stage).isEmpty
                ? [.safeResponseIdeas]
                : [.safeResponseIdeas, .candidateMoves]
        case .takeChooseMove:
            return candidateMoves(for: stage).isEmpty ? [] : [.candidatePieces, .candidateMoves]
        case let .wakeChoosePiece(purpose):
            guard let advice = latestAdvice,
                  !wakeSources(for: purpose, in: advice).isEmpty
            else { return [] }
            return [.candidatePieces, .candidateMoves]
        case .wakeChooseMove:
            return candidateMoves(for: stage).isEmpty
                ? [.movementMarkers]
                : [.movementMarkers, .candidateMoves]
        case .opponentCheck:
            return opponentIssueAnswerSquares(for: stage).isEmpty
                ? [.replyMarkers]
                : [.replyMarkers, .attackerRelationship]
        case .awaitingAdvice, .fallbackChooseMove, .reviseMove, .complete:
            return []
        }
    }

    private func currentHint(for stage: CoachingStage) -> CoachingHint? {
        let steps = hintSteps(for: stage)
        guard hintLevel > 0, hintLevel <= steps.count else { return nil }
        return steps[hintLevel - 1]
    }

    private func focus(
        for stage: CoachingStage,
        hint: CoachingHint?
    ) -> CoachFocusPresentation {
        let persistent = persistentFocus(for: stage)
        let hinted = hintFocus(for: stage, hint: hint)
        return CoachFocusPresentation(
            emphasizedSquares: persistent.emphasizedSquares.union(hinted.emphasizedSquares),
            candidateSquares: hinted.candidateSquares,
            paths: persistent.paths.union(hinted.paths),
            pulseID: pulseID
        )
    }

    private func hintFocus(
        for stage: CoachingStage,
        hint: CoachingHint?
    ) -> CoachFocusPresentation {
        guard let hint else { return .empty }
        switch hint {
        case .candidatePieces:
            return CoachFocusPresentation(
                emphasizedSquares: [],
                candidateSquares: candidateSourceSquares(for: stage),
                paths: [],
                pulseID: pulseID
            )
        case .candidateMoves:
            return CoachFocusPresentation(
                emphasizedSquares: [],
                candidateSquares: candidateDestinationSquares(for: stage),
                paths: candidatePaths(for: stage),
                pulseID: pulseID
            )
        case .attackerRelationship:
            let attackerSquares = opponentIssueAnswerSquares(for: stage)
            return CoachFocusPresentation(
                emphasizedSquares: [],
                candidateSquares: attackerSquares.isEmpty
                    ? candidateSourceSquares(for: stage)
                    : attackerSquares,
                paths: candidatePaths(for: stage),
                pulseID: pulseID
            )
        case .checkMarker, .dangerMarker, .replyMarkers,
             .safeResponseIdeas, .movementMarkers:
            return .empty
        }
    }

    private func persistentFocus(for stage: CoachingStage) -> CoachFocusPresentation {
        switch stage {
        case let .safeIdentifyAttacker(target):
            return CoachFocusPresentation(
                emphasizedSquares: [target],
                candidateSquares: [],
                paths: [],
                pulseID: pulseID
            )
        case let .safeResolve(target):
            guard let attacker = selectedSafeAttacker else {
                return CoachFocusPresentation(
                    emphasizedSquares: [target],
                    candidateSquares: [],
                    paths: [],
                    pulseID: pulseID
                )
            }
            return CoachFocusPresentation(
                emphasizedSquares: [target, attacker],
                candidateSquares: [],
                paths: [CoachFocusPath(source: attacker, destination: target, role: .attacker)],
                pulseID: pulseID
            )
        default:
            return .empty
        }
    }

    private func candidateSourceSquares(for stage: CoachingStage) -> Set<Square> {
        guard let advice = latestAdvice else { return [] }
        switch stage {
        case .checkLocate:
            return advice.checkingPieces
        case .safeLocate:
            return Set(advice.urgentProblems.map(\.target))
        case let .safeIdentifyAttacker(target):
            return Set(advice.urgentProblems
                .first(where: { $0.target == target })?
                .captures.map(\.move.from) ?? [])
        case .checkResolve, .takeChooseMove:
            return Set(candidateMoves(for: stage).map(\.from))
        case let .wakeChoosePiece(purpose):
            return wakeSources(for: purpose, in: advice)
        default:
            return []
        }
    }

    private func candidateDestinationSquares(for stage: CoachingStage) -> Set<Square> {
        Set(candidateMoves(for: stage).map(\.to))
    }

    private func candidatePaths(for stage: CoachingStage) -> Set<CoachFocusPath> {
        guard let advice = latestAdvice else { return [] }
        switch stage {
        case let .safeIdentifyAttacker(target):
            return Set(advice.urgentProblems
                .first(where: { $0.target == target })?
                .captures.map {
                    CoachFocusPath(source: $0.move.from, destination: target, role: .attacker)
                } ?? [])
        case let .opponentCheck(move, _):
            return Set(advice.moveAssessments[move]?.opponentIssues.map {
                CoachFocusPath(
                    source: $0.reply.from,
                    destination: $0.reply.to,
                    role: .attacker
                )
            } ?? [])
        case .checkResolve, .safeResolve, .takeChooseMove,
             .wakeChoosePiece, .wakeChooseMove:
            return Set(candidateMoves(for: stage).map {
                CoachFocusPath(source: $0.from, destination: $0.to, role: .candidate)
            })
        default:
            return []
        }
    }

    private func opponentIssueAnswerSquares(for stage: CoachingStage) -> Set<Square> {
        guard case let .opponentCheck(move, _) = stage else { return [] }
        return Set(latestAdvice?.moveAssessments[move]?.opponentIssues
            .flatMap(\.answerSquares) ?? [])
    }

    private func candidateMoves(for stage: CoachingStage) -> [Move] {
        guard let advice = latestAdvice else { return [] }
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
            return advice.wakeOpportunities
                .filter { wakePurpose(for: $0.concept, in: advice) == purpose }
                .flatMap(\.moves)
        case let .wakeChooseMove(piece, purpose):
            return advice.wakeOpportunities
                .filter { wakePurpose(for: $0.concept, in: advice) == purpose }
                .flatMap(\.moves)
                .filter { $0.from == piece }
        default:
            return []
        }
    }

    private func completionIdea(
        for move: Move,
        concepts: [CoachingConcept]
    ) -> CoachingCompletionIdea {
        for concept in concepts {
            switch concept {
            case .kingInCheck, .pieceNeedsHelp:
                return .resolvesDanger(piece: unresolvedPieceKindForCompletion())
            case .mateInOne:
                return .mate
            case .profitableCapture, .captureResolvesDanger:
                return .profitableCapture(captured: capturedKind(for: move) ?? .pawn)
            case .developsKnightOrBishop:
                return .develops(piece: pieceKind(at: move.from) ?? .knight)
            case .advancesCenterPawn:
                return .advancesCenterPawn
            case .castlesForKingSafety:
                return .castles
            case .addsUsefulDefender:
                return .addsDefender(piece: pieceKind(at: move.from) ?? .pawn)
            case .createsSafeImmediateThreat:
                return .createsThreat(piece: pieceKind(at: move.from) ?? .pawn)
            case .improvesCentralActivity:
                return .centralizes(piece: pieceKind(at: move.from) ?? .pawn)
            case .allowsCheck, .allowsMateInOne, .allowsMaterialLoss,
                 .checkingPiece, .profitableAttacker, .safeAfterReplyCheck:
                continue
            }
        }
        return .verifiedSafe
    }

    private func unresolvedPieceKindForCompletion() -> Piece.Kind {
        if let target = selectedSafeTarget {
            return pieceKind(at: target) ?? .king
        }
        return .king
    }

    private func capturedKind(for move: Move) -> Piece.Kind? {
        latestAdvice?.evaluation.learnerCaptureEstimates
            .first(where: { $0.move == move })?.capturedPiece.kind
            ?? latestAdvice?.evaluation.request.committedState.board[move.to]?.kind
    }
}

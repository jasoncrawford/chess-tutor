enum CoachingStage: Equatable, Sendable {
    case awaitingAdvice(origin: CoachingMoveOrigin?)
    case checkLocate
    case checkResolve
    case safeLocate
    case safeIdentifyAttacker(target: Square)
    case safeResolve(target: Square)
    case takeChooseMove
    case wakeChoosePiece(opening: Bool)
    case wakeChooseMove(piece: Square, opening: Bool)
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
    private var selectedWakePiece: Square?
    private var selectedWakeOpening = false
    private var tentativeMove: Move?
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
        switch advice.evaluation.request.context {
        case .start:
            tentativeMove = nil
            selectedSafeTarget = nil
            selectedWakePiece = nil
            selectedWakeOpening = false
            begin(with: advice)
        case let .tentativeMove(origin):
            receiveMoveAdvice(advice, origin: origin)
        }
        return []
    }

    mutating func receiveUnsupportedPosition() {
        latestAdvice = nil
        tentativeMove = nil
        selectedSafeTarget = nil
        selectedWakePiece = nil
        selectedWakeOpening = false
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
        case .positionChanged:
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
        guard let advice = latestAdvice, advice.confidence != .unsupported else {
            transition(to: .fallbackChooseMove, feedback: feedback)
            return
        }
        transition(
            to: .wakeChoosePiece(opening: advice.openingDevelopmentIsRelevant),
            feedback: feedback
        )
    }

    private mutating func handleSquareTap(_ square: Square) -> [CoachingDirective] {
        guard let advice = latestAdvice else { return [] }
        switch stage {
        case .checkLocate:
            if advice.checkingPieces.contains(square) {
                transition(to: .checkResolve, feedback: .correct)
            } else {
                recordMiss(.unrelatedTap)
            }
        case .safeLocate:
            if advice.urgentProblems.contains(where: { $0.target == square }) {
                selectedSafeTarget = square
                transition(to: .safeIdentifyAttacker(target: square), feedback: .correct)
            } else if let piece = advice.evaluation.request.committedState.board[square],
                      piece.color == learner,
                      advice.evaluation.opponentCaptureEstimates.contains(where: {
                          $0.capturedSquare == square
                      }) {
                recordMiss(.relevantButNonurgent(piece: piece.kind))
            } else {
                recordMiss(.unrelatedTap)
            }
        case let .safeIdentifyAttacker(target):
            guard let problem = advice.urgentProblems.first(where: { $0.target == target }) else {
                recordMiss(.unrelatedTap)
                return []
            }
            if problem.captures.contains(where: { $0.move.from == square }) {
                transition(to: .safeResolve(target: target), feedback: .correct)
            } else {
                recordMiss(.unrelatedTap)
            }
        case let .wakeChoosePiece(opening):
            let sources = wakeSources(in: advice)
            if sources.contains(square) {
                let preferred = advice.wakeOpportunities.first?.moves.first?.from
                selectedWakePiece = square
                selectedWakeOpening = opening
                transition(
                    to: .wakeChooseMove(piece: square, opening: opening),
                    feedback: square == preferred ? .correct : .correctAlternative
                )
                return [.selectSquare(square)]
            }
            recordMiss(.unrelatedTap)
        case let .opponentCheck(move, origin):
            guard let assessment = advice.moveAssessments[move],
                  let issue = assessment.opponentIssues.first(where: {
                      $0.answerSquares.contains(square)
                  })
            else {
                recordMiss(.unrelatedTap)
                return []
            }
            handleFoundIssue(issue, assessment: assessment, move: move, origin: origin)
        default:
            break
        }
        return []
    }

    private mutating func handleStagedMove(_ move: Move) -> [CoachingDirective] {
        let origin = moveOrigin(for: stage)
        guard let origin else { return [] }

        tentativeMove = move
        transition(to: .awaitingAdvice(origin: origin))
        return [.requestAdvice(context: .tentativeMove(origin: origin))]
    }

    private mutating func handleAction(_ action: CoachingAction) -> [CoachingDirective] {
        switch action {
        case .hint:
            guard presentation != nil else { return [] }
            hintLevel = min(hintLevel + 1, 4)
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
            returnToOrigin(origin, feedback: nil, prompt: .illegalKingSafety)
            return
        }

        if origin == .take && !hasTakePurpose(assessment.concepts) {
            returnToOrigin(
                origin,
                feedback: unprofitableCaptureFeedback(for: move, advice: advice)
            )
            return
        }

        if (origin == .safe || origin == .check) && !assessment.resolvesRequiredDanger {
            let piece = unresolvedPieceKind(for: origin, advice: advice)
            returnToOrigin(origin, feedback: .dangerStillPresent(piece: piece))
            return
        }

        if origin == .wake && !hasWakePurpose(assessment.concepts) {
            returnToOrigin(origin, feedback: .noRecognizedPurpose)
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
            returnToOrigin(origin, feedback: .noRecognizedPurpose)
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
        prompt: CoachingPrompt? = nil
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
            if let piece = selectedWakePiece {
                returnStage = .wakeChooseMove(piece: piece, opening: selectedWakeOpening)
            } else {
                returnStage = .reviseMove(origin: .wake)
            }
        case .fallback:
            returnStage = .fallbackChooseMove
        }
        transition(to: returnStage, feedback: feedback, prompt: prompt)
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

    private func unresolvedPieceKind(
        for origin: CoachingMoveOrigin,
        advice: CoachingAdvice
    ) -> Piece.Kind {
        if origin == .check { return .king }
        if let target = selectedSafeTarget,
           let problem = advice.urgentProblems.first(where: { $0.target == target }) {
            return problem.piece.kind
        }
        return advice.urgentProblems.first?.piece.kind ?? .king
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

    private mutating func transition(
        to newStage: CoachingStage,
        feedback newFeedback: CoachingFeedback? = nil,
        prompt: CoachingPrompt? = nil
    ) {
        stage = newStage
        hintLevel = 0
        missesAtCurrentLevel = 0
        feedback = newFeedback
        promptOverride = prompt
        rebuildPresentation()
    }

    private mutating func rebuildPresentation() {
        guard let prompt = promptOverride ?? prompt(for: stage) else {
            presentation = nil
            return
        }
        presentation = explainer.presentation(for: CoachingPresentationContext(
            prompt: prompt,
            feedback: feedback,
            learner: learner,
            hintLevel: hintLevel,
            missesAtCurrentLevel: missesAtCurrentLevel,
            routine: routine(for: stage),
            actions: actions(for: stage),
            boardTask: boardTask(for: stage),
            focus: focus(for: stage)
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
            return .safeResolve(piece: pieceKind(at: target) ?? .pawn)
        case .takeChooseMove:
            return .takeChooseMove
        case let .wakeChoosePiece(opening):
            return .wakeChoosePiece(opening: opening)
        case let .wakeChooseMove(piece, _):
            return .wakeChooseMove(piece: pieceKind(at: piece) ?? .pawn)
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
        switch stage {
        case .safeLocate, .takeChooseMove:
            return [.noAnswer, .hint, .stop]
        case .opponentCheck:
            return [.looksSafe, .hint, .stop]
        case .complete:
            return [.done, .keepLooking, .stop]
        case .awaitingAdvice:
            return [.stop]
        default:
            return [.hint, .stop]
        }
    }

    private func focus(for stage: CoachingStage) -> CoachFocusPresentation {
        guard hintLevel >= 2 else {
            return CoachFocusPresentation(
                emphasizedSquares: [],
                candidateSquares: [],
                paths: [],
                pulseID: pulseID
            )
        }
        let candidates = answerSquares(for: stage)
        let paths = hintLevel >= 3 ? focusPaths(for: stage) : []
        let emphasized = hintLevel >= 3
            ? candidates.union(paths.flatMap { [$0.source, $0.destination] })
            : []
        return CoachFocusPresentation(
            emphasizedSquares: emphasized,
            candidateSquares: candidates,
            paths: Set(paths),
            pulseID: pulseID
        )
    }

    private func answerSquares(for stage: CoachingStage) -> Set<Square> {
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
        case .wakeChoosePiece:
            return wakeSources(in: advice)
        case let .opponentCheck(move, _):
            return Set(advice.moveAssessments[move]?.opponentIssues
                .flatMap(\.answerSquares) ?? [])
        case .checkResolve, .safeResolve, .takeChooseMove, .wakeChooseMove:
            return Set(candidateMoves(for: stage).map(\.to))
        default:
            return []
        }
    }

    private func focusPaths(for stage: CoachingStage) -> [CoachFocusPath] {
        guard let advice = latestAdvice else { return [] }
        switch stage {
        case let .safeIdentifyAttacker(target):
            return advice.urgentProblems
                .first(where: { $0.target == target })?
                .captures.map {
                    CoachFocusPath(source: $0.move.from, destination: target, role: .attacker)
                } ?? []
        case let .opponentCheck(move, _):
            return advice.moveAssessments[move]?.opponentIssues.map {
                CoachFocusPath(
                    source: $0.reply.from,
                    destination: $0.reply.to,
                    role: .attacker
                )
            } ?? []
        case .checkResolve, .safeResolve, .takeChooseMove, .wakeChooseMove:
            return candidateMoves(for: stage).map {
                CoachFocusPath(source: $0.from, destination: $0.to, role: .candidate)
            }
        default:
            return []
        }
    }

    private func candidateMoves(for stage: CoachingStage) -> [Move] {
        guard let advice = latestAdvice else { return [] }
        switch stage {
        case .checkResolve:
            return advice.moveAssessments.values
                .filter { $0.isLegal && $0.resolvesRequiredDanger }
                .map(\.move)
        case .safeResolve:
            return advice.moveAssessments.values
                .filter { $0.isLegal && $0.resolvesRequiredDanger }
                .map(\.move)
        case .takeChooseMove:
            return advice.takeOpportunities.flatMap(\.moves)
        case let .wakeChooseMove(piece, _):
            return advice.wakeOpportunities.flatMap(\.moves).filter { $0.from == piece }
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

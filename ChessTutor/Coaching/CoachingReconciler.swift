struct CoachingReconciler: Sendable {
    func derive(
        learner: PieceColor,
        episode: CoachingEpisodeState
    ) -> CoachingDerivedState {
        if let move = episode.interaction.tentativeMove {
            return deriveTentativeMove(move, learner: learner, episode: episode)
        }
        guard let advice = applicablePositionAdvice(in: episode, learner: learner) else {
            return episode.knowledge.unsupportedContext == .start
                ? fallbackDerivation()
                : awaitingPositionAdviceDerivation(pending: episode.knowledge.pendingContext)
        }
        if !advice.checkingPieces.isEmpty {
            return deriveCheck(advice: advice, evidence: episode.evidence)
        }
        if requiresSafeScan(advice: advice, evidence: episode.evidence) {
            return deriveSafe(advice: advice, evidence: episode.evidence)
        }
        if requiresTakeScan(advice: advice, evidence: episode.evidence) {
            return deriveTake(
                learner: learner,
                advice: advice,
                interaction: episode.interaction
            )
        }
        if episode.evidence.confirmedTakeAbsence,
           !hasVerifiedWakeEvidence(in: advice) {
            return derived(
                stage: .fallbackChooseMove,
                questionID: .fallback,
                promptOverride: .unsupportedFallbackChooseMove
            )
        }
        return deriveWakeOrFallback(
            learner: learner,
            advice: advice,
            interaction: episode.interaction
        )
    }

    func applicablePositionAdvice(
        in episode: CoachingEpisodeState,
        learner: PieceColor
    ) -> CoachingAdvice? {
        guard let advice = episode.knowledge.positionAdvice else { return nil }
        let request = advice.evaluation.request
        guard request.context == .start,
              request.tentativeMove == nil,
              request.positionRevision == episode.interaction.positionRevision,
              request.learner == learner
        else {
            return nil
        }
        return advice
    }

    func applicableTentativeAdvice(
        for move: Move,
        origin: CoachingMoveOrigin,
        learner: PieceColor,
        episode: CoachingEpisodeState
    ) -> (CoachingAdvice, CoachingMoveAssessment)? {
        guard let advice = episode.knowledge.tentativeAdvice else { return nil }
        let request = advice.evaluation.request
        guard request.context == .tentativeMove(origin: origin),
              request.tentativeMove == move,
              request.positionRevision == episode.interaction.positionRevision,
              request.learner == learner,
              episode.knowledge.positionAdvice.map({
                  let positionRequest = $0.evaluation.request
                  return positionRequest.committedState == request.committedState
                      && positionRequest.positionRevision == request.positionRevision
              }) ?? true,
              advice.evaluation.moveAssessments[move]?.move == move,
              let assessment = advice.moveAssessments[move],
              assessment.move == move
        else {
            return nil
        }
        return (advice, assessment)
    }

    private func applicablePositionAdvice(
        for tentativeAdvice: CoachingAdvice,
        learner: PieceColor,
        episode: CoachingEpisodeState
    ) -> CoachingAdvice? {
        if let advice = applicablePositionAdvice(in: episode, learner: learner) {
            return advice
        }
        guard let advice = episode.knowledge.positionAdvice else { return nil }
        let positionRequest = advice.evaluation.request
        let tentativeRequest = tentativeAdvice.evaluation.request
        guard positionRequest.context == .start,
              positionRequest.tentativeMove == nil,
              positionRequest.learner == learner,
              positionRequest.committedState == tentativeRequest.committedState,
              positionRequest.positionRevision == tentativeRequest.positionRevision
        else {
            return nil
        }
        return advice
    }

    private func deriveCheck(
        advice: CoachingAdvice,
        evidence: CoachingPedagogicalEvidence
    ) -> CoachingDerivedState {
        guard let checker = evidence.checkingPiece,
              advice.checkingPieces.contains(checker)
        else {
            return derived(stage: .checkLocate, questionID: .checkLocate)
        }
        return derived(
            stage: .checkResolve,
            questionID: .checkResolve(checker: checker)
        )
    }

    private func requiresSafeScan(
        advice: CoachingAdvice,
        evidence: CoachingPedagogicalEvidence
    ) -> Bool {
        guard advice.evaluation.opponentHasAnyLegalCapture else { return false }
        let confirmedAbsenceIsValid = evidence.confirmedSafeAbsence
            && advice.dangerProblems.isEmpty
        return !confirmedAbsenceIsValid
    }

    private func deriveSafe(
        advice: CoachingAdvice,
        evidence: CoachingPedagogicalEvidence
    ) -> CoachingDerivedState {
        guard let target = evidence.safeTarget,
              let problem = advice.primaryDangerProblems.first(where: { $0.target == target })
        else {
            return derived(stage: .safeLocate, questionID: .safeLocate)
        }
        guard let attacker = evidence.safeAttacker,
              problem.captures.contains(where: { $0.move.from == attacker })
        else {
            return derived(
                stage: .safeIdentifyAttacker(target: target),
                questionID: .safeAttacker(target: target)
            )
        }
        return derived(
            stage: .safeResolve(target: target),
            questionID: .safeResolve(target: target, attacker: attacker)
        )
    }

    private func requiresTakeScan(
        advice: CoachingAdvice,
        evidence: CoachingPedagogicalEvidence
    ) -> Bool {
        let confirmedAbsenceIsValid = evidence.confirmedTakeAbsence
            && advice.takeOpportunities.isEmpty
        guard !confirmedAbsenceIsValid else { return false }
        return advice.evaluation.learnerHasAnyLegalCapture
            || evidence.confirmedSafeAbsence
    }

    private func takeDerivation() -> CoachingDerivedState {
        derived(stage: .takeChooseMove, questionID: .take)
    }

    private func deriveTake(
        learner: PieceColor,
        advice: CoachingAdvice,
        interaction: CoachingInteractionSnapshot
    ) -> CoachingDerivedState {
        guard let selectedSquare = interaction.selectedSquare else {
            return takeDerivation()
        }
        let safeCaptureSources = Set(advice.takeOpportunities.flatMap(\.moves).map(\.from))
        guard !safeCaptureSources.contains(selectedSquare) else {
            return takeDerivation()
        }
        let feedback: CoachingFeedback = advice.evaluation.request.committedState
            .board[selectedSquare]?.color == learner
            ? .noSafeCaptureForPiece
            : .expectedLearnerPiece
        return derived(
            stage: .takeChooseMove,
            questionID: .take,
            feedback: feedback
        )
    }

    private func deriveWakeOrFallback(
        learner: PieceColor,
        advice: CoachingAdvice,
        interaction: CoachingInteractionSnapshot
    ) -> CoachingDerivedState {
        guard advice.confidence != .unsupported,
              let initialPurpose = initialWakePurpose(in: advice)
        else {
            return fallbackDerivation()
        }

        guard let selectedSquare = interaction.selectedSquare else {
            return wakeSourceDerivation(purpose: initialPurpose)
        }

        if let task = advice.wakeTasks.first(where: {
            wakeMoves(in: $0).contains(where: { $0.from == selectedSquare })
        }) {
            let purpose = wakePurpose(for: task)
            return derived(
                stage: .wakeChooseMove(piece: selectedSquare, purpose: purpose),
                questionID: .wakeMove(source: selectedSquare, purpose: purpose)
            )
        }
        if advice.wakeTasks.isEmpty,
           let opportunity = advice.wakeOpportunities.first(where: {
               $0.moves.contains(where: { $0.from == selectedSquare })
           }) {
            let purpose = wakePurpose(for: opportunity.concept, in: advice)
            return derived(
                stage: .wakeChooseMove(piece: selectedSquare, purpose: purpose),
                questionID: .wakeMove(source: selectedSquare, purpose: purpose)
            )
        }

        let board = advice.evaluation.request.committedState.board
        guard let piece = board[selectedSquare], piece.color == learner else {
            return wakeSourceDerivation(
                purpose: initialPurpose,
                feedback: .expectedLearnerPiece
            )
        }
        let allowedMoves = LegalMoveGenerator.allowedMoves(
            for: selectedSquare,
            by: learner,
            in: advice.evaluation.request.committedState
        )
        let feedback: CoachingFeedback
        if allowedMoves.isEmpty,
           let blocker = firstSlidingBlocker(
               for: selectedSquare,
               piece: piece,
               in: board
           ) {
            feedback = .blockedWakePiece(piece: piece.kind, blocker: blocker.kind)
        } else {
            feedback = .notWakeCandidate(piece: piece.kind, purpose: initialPurpose)
        }
        return wakeSourceDerivation(purpose: initialPurpose, feedback: feedback)
    }

    private func deriveTentativeMove(
        _ move: Move,
        learner: PieceColor,
        episode: CoachingEpisodeState
    ) -> CoachingDerivedState {
        let origin = episode.evidence.tentativeOrigin ?? .preexisting
        let context = CoachingRequest.Context.tentativeMove(origin: origin)
        if episode.knowledge.unsupportedContext == context {
            return fallbackDerivation()
        }
        guard let (advice, assessment) = applicableTentativeAdvice(
            for: move,
            origin: origin,
            learner: learner,
            episode: episode
        ) else {
            return derived(
                stage: .awaitingAdvice(origin: origin),
                questionID: nil,
                requestedAdvice: episode.knowledge.pendingContext == context ? nil : context
            )
        }

        let positionAdvice = applicablePositionAdvice(
            for: advice,
            learner: learner,
            episode: episode
        )
        if !assessment.isLegal {
            return originDerivation(
                origin,
                move: move,
                episode: episode,
                positionAdvice: positionAdvice,
                promptOverride: .illegalKingSafety
            )
        }
        if origin == .take && !isActiveSafeCapture(
            move,
            assessment: assessment,
            tentativeAdvice: advice,
            positionAdvice: positionAdvice
        ) {
            return originDerivation(
                origin,
                move: move,
                episode: episode,
                positionAdvice: positionAdvice,
                feedback: unprofitableCaptureFeedback(
                    for: move,
                    advice: advice,
                    positionAdvice: positionAdvice
                )
            )
        }
        if origin == .safe && !assessment.resolvesRequiredDanger {
            return originDerivation(
                origin,
                move: move,
                episode: episode,
                positionAdvice: positionAdvice,
                feedback: unresolvedDangerFeedback(
                    for: assessment,
                    tentativeAdvice: advice,
                    positionAdvice: positionAdvice,
                    evidence: episode.evidence
                )
            )
        }
        if origin == .wake,
           !hasWakePurpose(assessment.concepts),
           !isWakeTaskMove(move, in: positionAdvice) {
            let purpose = wakePurpose(
                for: move.from,
                positionAdvice: positionAdvice,
                assessment: assessment,
                tentativeAdvice: advice
            )
            return originDerivation(
                origin,
                move: move,
                episode: episode,
                positionAdvice: positionAdvice,
                feedback: .noRecognizedPurpose(purpose: purpose)
            )
        }
        if origin == .check,
           assessment.isAcceptable {
            return completionDerivation(
                move: move,
                origin: origin,
                assessment: assessment
            )
        }

        return deriveReply(
            move: move,
            origin: origin,
            assessment: assessment,
            advice: advice,
            positionAdvice: positionAdvice,
            answer: episode.evidence.replyAnswer,
            episode: episode
        )
    }

    private func deriveReply(
        move: Move,
        origin: CoachingMoveOrigin,
        assessment: CoachingMoveAssessment,
        advice: CoachingAdvice,
        positionAdvice: CoachingAdvice?,
        answer: CoachingReplyAnswer?,
        episode: CoachingEpisodeState
    ) -> CoachingDerivedState {
        let opponentReply = derived(
            stage: .opponentCheck(move: move, origin: origin),
            questionID: .opponentReply(move: move, origin: origin)
        )
        guard let answer else { return opponentReply }

        switch answer {
        case let .looksSafe(answeredMove):
            guard answeredMove == move else { return opponentReply }
            if let issue = primaryOpponentIssue(in: assessment) {
                return derived(
                    stage: opponentReply.stage,
                    questionID: opponentReply.questionID,
                    feedback: .missedOpponentIssue(opponentReplyFact(
                        for: issue,
                        move: move,
                        advice: advice
                    ))
                )
            }
            if assessment.isAcceptable {
                return completionDerivation(
                    move: move,
                    origin: origin,
                    assessment: assessment,
                    feedback: .opponentReplyLooksSafe
                )
            }
            let purpose = origin == .wake
                ? wakePurpose(
                    for: move.from,
                    positionAdvice: positionAdvice,
                    assessment: assessment,
                    tentativeAdvice: advice
                )
                : nil
            return originDerivation(
                origin,
                move: move,
                episode: episode,
                positionAdvice: positionAdvice,
                feedback: .noRecognizedPurpose(purpose: purpose)
            )

        case let .issue(answeredMove, issue):
            guard answeredMove == move,
                  assessment.opponentIssues.contains(issue)
            else {
                return opponentReply
            }
            return deriveFoundIssue(
                issue,
                move: move,
                origin: origin,
                assessment: assessment,
                advice: advice
            )
        }
    }

    private func deriveFoundIssue(
        _ issue: CoachingOpponentIssue,
        move: Move,
        origin: CoachingMoveOrigin,
        assessment: CoachingMoveAssessment,
        advice: CoachingAdvice
    ) -> CoachingDerivedState {
        let replyFact = opponentReplyFact(
            for: issue,
            move: move,
            advice: advice
        )
        let concreteFeedback = CoachingFeedback.opponentIssue(replyFact)
        switch issue.severity {
        case .reviseMove:
            return derived(
                stage: .reviseMove(origin: origin),
                questionID: .revise(move: move, origin: origin),
                promptOverride: .opponentIssueRevise(
                    kind: issue.kind,
                    affectedPiece: replyFact.affectedPiece
                ),
                feedback: concreteFeedback
            )

        case .notice:
            if issue.kind == .check,
               assessment.opponentIssues.contains(where: { $0.severity == .reviseMove }) {
                return derived(
                    stage: .opponentCheck(move: move, origin: origin),
                    questionID: .opponentReply(move: move, origin: origin),
                    feedback: .checkFoundOtherDangerRemains
                )
            }
            if assessment.isAcceptable {
                return completionDerivation(
                    move: move,
                    origin: origin,
                    assessment: assessment,
                    feedback: concreteFeedback
                )
            }
            return derived(
                stage: .reviseMove(origin: origin),
                questionID: .revise(move: move, origin: origin),
                feedback: concreteFeedback
            )
        }
    }

    private func originDerivation(
        _ origin: CoachingMoveOrigin,
        move: Move,
        episode: CoachingEpisodeState,
        positionAdvice: CoachingAdvice?,
        promptOverride: CoachingPrompt? = nil,
        feedback: CoachingFeedback? = nil
    ) -> CoachingDerivedState {
        let base: CoachingDerivedState
        switch origin {
        case .preexisting:
            base = derived(
                stage: .reviseMove(origin: origin),
                questionID: .revise(move: move, origin: origin)
            )
        case .check:
            base = positionAdvice.map {
                deriveCheck(advice: $0, evidence: episode.evidence)
            } ?? derived(
                stage: .reviseMove(origin: origin),
                questionID: .revise(move: move, origin: origin)
            )
        case .safe:
            base = positionAdvice.map {
                deriveSafe(advice: $0, evidence: episode.evidence)
            } ?? derived(
                stage: .reviseMove(origin: origin),
                questionID: .revise(move: move, origin: origin)
            )
        case .take:
            base = takeDerivation()
        case .wake:
            let purpose = wakePurpose(
                for: move.from,
                positionAdvice: positionAdvice,
                assessment: nil,
                tentativeAdvice: episode.knowledge.tentativeAdvice
            ) ?? .centralActivity
            base = derived(
                stage: .wakeChooseMove(piece: move.from, purpose: purpose),
                questionID: .wakeMove(source: move.from, purpose: purpose)
            )
        case .fallback:
            base = fallbackDerivation()
        }
        return derived(
            stage: base.stage,
            questionID: base.questionID,
            promptOverride: promptOverride,
            feedback: feedback
        )
    }

    private func wakeSourceDerivation(
        purpose: CoachingWakePurpose,
        feedback: CoachingFeedback? = nil
    ) -> CoachingDerivedState {
        derived(
            stage: .wakeChoosePiece(purpose: purpose),
            questionID: .wakeSource(purpose: purpose),
            feedback: feedback
        )
    }

    private func fallbackDerivation() -> CoachingDerivedState {
        derived(stage: .fallbackChooseMove, questionID: .fallback)
    }

    private func awaitingPositionAdviceDerivation(
        pending: CoachingRequest.Context?
    ) -> CoachingDerivedState {
        derived(
            stage: .awaitingAdvice(origin: nil),
            questionID: nil,
            requestedAdvice: pending == .start ? nil : .start
        )
    }

    private func completionDerivation(
        move: Move,
        origin: CoachingMoveOrigin,
        assessment: CoachingMoveAssessment,
        feedback: CoachingFeedback? = nil
    ) -> CoachingDerivedState {
        derived(
            stage: .complete(
                move: move,
                origin: origin,
                concepts: assessment.concepts
            ),
            questionID: .complete(move: move, origin: origin),
            feedback: feedback
        )
    }

    private func derived(
        stage: CoachingStage,
        questionID: CoachingQuestionID?,
        promptOverride: CoachingPrompt? = nil,
        feedback: CoachingFeedback? = nil,
        requestedAdvice: CoachingRequest.Context? = nil
    ) -> CoachingDerivedState {
        CoachingDerivedState(
            stage: stage,
            questionID: questionID,
            promptOverride: promptOverride,
            derivedFeedback: feedback,
            requestedAdvice: requestedAdvice
        )
    }

    private func isActiveSafeCapture(
        _ move: Move,
        assessment: CoachingMoveAssessment,
        tentativeAdvice: CoachingAdvice,
        positionAdvice: CoachingAdvice?
    ) -> Bool {
        let isActiveOpportunity = positionAdvice?.takeOpportunities.contains(where: {
            $0.moves.contains(move)
        }) == true
        let hasPositiveCurrentEstimate = tentativeAdvice.evaluation
            .learnerCaptureEstimates
            .contains { $0.move == move && $0.netGainForMover > 0 }
        let hasRevisionIssue = assessment.opponentIssues.contains {
            $0.severity == .reviseMove
        }
        return isActiveOpportunity
            && hasPositiveCurrentEstimate
            && assessment.isLegal
            && assessment.resolvesRequiredDanger
            && !hasRevisionIssue
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

    private func initialWakePurpose(in advice: CoachingAdvice) -> CoachingWakePurpose? {
        if let task = advice.wakeTasks.first {
            return wakePurpose(for: task)
        }
        guard let opportunity = advice.wakeOpportunities.first,
              !opportunity.moves.isEmpty else {
            return nil
        }
        return wakePurpose(for: opportunity.concept, in: advice)
    }

    private func hasVerifiedWakeEvidence(in advice: CoachingAdvice) -> Bool {
        advice.confidence != .unsupported && initialWakePurpose(in: advice) != nil
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

    private func wakeMoves(in task: CoachingWakeTask) -> [Move] {
        switch task {
        case let .castle(move):
            return [move]
        default:
            return task.candidates.map(\.move)
        }
    }

    private func isWakeTaskMove(
        _ move: Move,
        in advice: CoachingAdvice?
    ) -> Bool {
        advice?.wakeTasks.contains { wakeMoves(in: $0).contains(move) } == true
    }

    private func firstSlidingBlocker(
        for source: Square,
        piece: Piece,
        in board: Board
    ) -> Piece? {
        let homeRank = piece.color == .white ? 1 : 8
        guard source.rank == homeRank else { return nil }
        let forward = piece.color == .white ? 1 : -1
        let directions: [(Int, Int)]
        switch piece.kind {
        case .bishop:
            directions = [(-1, forward), (1, forward), (-1, -forward), (1, -forward)]
        case .rook:
            directions = [(0, forward), (1, 0), (-1, 0), (0, -forward)]
        case .queen:
            directions = [
                (0, forward), (-1, forward), (1, forward),
                (1, 0), (-1, 0),
                (0, -forward), (-1, -forward), (1, -forward),
            ]
        case .pawn, .knight, .king:
            return nil
        }

        for direction in directions {
            var current = source
            while let next = current.offset(
                fileDelta: direction.0,
                rankDelta: direction.1
            ) {
                if let blocker = board[next] { return blocker }
                current = next
            }
        }
        return nil
    }

    private func wakePurpose(
        for source: Square,
        positionAdvice: CoachingAdvice?,
        assessment: CoachingMoveAssessment?,
        tentativeAdvice: CoachingAdvice?
    ) -> CoachingWakePurpose? {
        if let positionAdvice,
           let task = positionAdvice.wakeTasks.first(where: {
               wakeMoves(in: $0).contains(where: { $0.from == source })
           }) {
            return wakePurpose(for: task)
        }
        if let positionAdvice,
           let opportunity = positionAdvice.wakeOpportunities.first(where: {
               $0.moves.contains(where: { $0.from == source })
           }) {
            return wakePurpose(for: opportunity.concept, in: positionAdvice)
        }
        guard let concept = assessment?.concepts.first(where: isWakeConcept) else {
            return nil
        }
        let advice = positionAdvice ?? tentativeAdvice
        return wakePurpose(
            for: concept,
            firstMove: advice?.evaluation.request.committedState == GameState.startingPosition()
        )
    }

    private func wakePurpose(
        for concept: CoachingConcept,
        in advice: CoachingAdvice
    ) -> CoachingWakePurpose {
        wakePurpose(
            for: concept,
            firstMove: advice.evaluation.request.committedState == GameState.startingPosition()
        )
    }

    private func wakePurpose(
        for concept: CoachingConcept,
        firstMove: Bool
    ) -> CoachingWakePurpose {
        switch concept {
        case .developsKnightOrBishop, .advancesCenterPawn:
            return .openingDevelopment(firstMove: firstMove)
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

    private func isWakeConcept(_ concept: CoachingConcept) -> Bool {
        switch concept {
        case .developsKnightOrBishop, .advancesCenterPawn, .castlesForKingSafety,
             .addsUsefulDefender, .createsSafeImmediateThreat, .improvesCentralActivity:
            return true
        default:
            return false
        }
    }

    private func unprofitableCaptureFeedback(
        for move: Move,
        advice: CoachingAdvice,
        positionAdvice: CoachingAdvice?
    ) -> CoachingFeedback {
        if let fact = advice.exchangeFact(for: move)
            ?? positionAdvice?.exchangeFact(for: move) {
            return .unsafeCapture(fact)
        }
        return .noSafeCaptureForPiece
    }

    private func unresolvedDangerFeedback(
        for assessment: CoachingMoveAssessment,
        tentativeAdvice: CoachingAdvice,
        positionAdvice: CoachingAdvice?,
        evidence: CoachingPedagogicalEvidence
    ) -> CoachingFeedback {
        let committedState = tentativeAdvice.evaluation.request.committedState
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

        let board = positionAdvice?.evaluation.request.committedState.board
            ?? tentativeAdvice.evaluation.request.committedState.board
        let currentProblems = positionAdvice?.primaryDangerProblems
            ?? tentativeAdvice.primaryDangerProblems
        let validProblem = evidence.safeTarget.flatMap { target in
            currentProblems.first(where: { $0.target == target })
        }
        let target = validProblem?.piece.kind
            ?? currentProblems.first?.piece.kind
            ?? .king
        let validAttacker = evidence.safeAttacker.flatMap { attacker -> Square? in
            guard let validProblem,
                  validProblem.captures.contains(where: { $0.move.from == attacker })
            else {
                return nil
            }
            return attacker
        }
        let attacker = validAttacker.flatMap { board[$0]?.kind }
        return .dangerStillPresent(attacker: attacker, target: target)
    }

    private func primaryOpponentIssue(
        in assessment: CoachingMoveAssessment
    ) -> CoachingOpponentIssue? {
        assessment.opponentIssues.first(where: { $0.severity == .reviseMove })
            ?? assessment.opponentIssues.first
    }

    private func opponentReplyFact(
        for issue: CoachingOpponentIssue,
        move: Move,
        advice: CoachingAdvice
    ) -> CoachingOpponentReplyFact {
        let committedState = advice.evaluation.request.committedState
        let afterMove = committedState.applyingUnchecked(move)
        guard let opponentPiece = afterMove.board[issue.reply.from]?.kind else {
            preconditionFailure("Opponent reply source must contain the responding piece")
        }
        return CoachingOpponentReplyFact(
            issue: issue,
            opponentPiece: opponentPiece,
            affectedPiece: issue.affectedSquare.flatMap { afterMove.board[$0]?.kind },
            learnerPiece: committedState.board[move.from]?.kind
        )
    }
}

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
            return takeDerivation()
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
                  $0.evaluation.request.committedState == request.committedState
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
              positionRequest.committedState == tentativeRequest.committedState
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
            && advice.urgentProblems.isEmpty
        return !confirmedAbsenceIsValid
    }

    private func deriveSafe(
        advice: CoachingAdvice,
        evidence: CoachingPedagogicalEvidence
    ) -> CoachingDerivedState {
        guard let target = evidence.safeTarget,
              let problem = advice.urgentProblems.first(where: { $0.target == target })
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
        let scanIsRelevant = advice.evaluation.learnerHasAnyLegalCapture
            || !advice.evaluation.mateInOneMoves.isEmpty
        guard scanIsRelevant else { return false }
        let confirmedAbsenceIsValid = evidence.confirmedTakeAbsence
            && advice.takeOpportunities.isEmpty
            && advice.evaluation.mateInOneMoves.isEmpty
        return !confirmedAbsenceIsValid
    }

    private func takeDerivation() -> CoachingDerivedState {
        derived(stage: .takeChooseMove, questionID: .take)
    }

    private func deriveWakeOrFallback(
        learner: PieceColor,
        advice: CoachingAdvice,
        interaction: CoachingInteractionSnapshot
    ) -> CoachingDerivedState {
        guard advice.confidence != .unsupported,
              let firstOpportunity = advice.wakeOpportunities.first,
              !firstOpportunity.moves.isEmpty
        else {
            return fallbackDerivation()
        }

        let initialPurpose = wakePurpose(for: firstOpportunity.concept, in: advice)
        guard let selectedSquare = interaction.selectedSquare else {
            return wakeSourceDerivation(purpose: initialPurpose)
        }

        if let opportunity = advice.wakeOpportunities.first(where: {
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
        let feedback: CoachingFeedback = allowedMoves.isEmpty
            ? .blockedWakePiece(piece: piece.kind)
            : .notWakeCandidate(piece: piece.kind, purpose: initialPurpose)
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
        if origin == .take && !hasTakePurpose(assessment.concepts) {
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
        if origin == .wake && !hasWakePurpose(assessment.concepts) {
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
            if !assessment.opponentIssues.isEmpty {
                return derived(
                    stage: opponentReply.stage,
                    questionID: opponentReply.questionID,
                    feedback: .missedExistingAnswer
                )
            }
            if assessment.isAcceptable {
                return completionDerivation(
                    move: move,
                    origin: origin,
                    assessment: assessment
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
                advice: advice,
                positionAdvice: positionAdvice
            )
        }
    }

    private func deriveFoundIssue(
        _ issue: CoachingOpponentIssue,
        move: Move,
        origin: CoachingMoveOrigin,
        assessment: CoachingMoveAssessment,
        advice: CoachingAdvice,
        positionAdvice: CoachingAdvice?
    ) -> CoachingDerivedState {
        let concreteFeedback = CoachingFeedback.concreteFlaw(
            kind: issue.kind,
            affectedPiece: affectedPieceKind(
                for: issue,
                move: move,
                advice: positionAdvice ?? advice
            )
        )
        switch issue.severity {
        case .reviseMove:
            return derived(
                stage: .reviseMove(origin: origin),
                questionID: .revise(move: move, origin: origin),
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
            let feedback: CoachingFeedback = issue.kind == .check
                ? .harmlessCheckFound
                : concreteFeedback
            if assessment.isAcceptable {
                return completionDerivation(
                    move: move,
                    origin: origin,
                    assessment: assessment,
                    feedback: feedback
                )
            }
            return derived(
                stage: .reviseMove(origin: origin),
                questionID: .revise(move: move, origin: origin),
                feedback: feedback
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

    private func wakePurpose(
        for source: Square,
        positionAdvice: CoachingAdvice?,
        assessment: CoachingMoveAssessment?,
        tentativeAdvice: CoachingAdvice?
    ) -> CoachingWakePurpose? {
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
        let estimate = advice.evaluation.learnerCaptureEstimates.first { $0.move == move }
        let board = positionAdvice?.evaluation.request.committedState.board
            ?? advice.evaluation.request.committedState.board
        let movedPiece = board[move.from]?.kind
        let points = max(1, -(estimate?.netGainForMover ?? 0))
        return .concreteFlaw(kind: .materialLoss(points: points), affectedPiece: movedPiece)
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
        let currentProblems = positionAdvice?.urgentProblems
            ?? tentativeAdvice.urgentProblems
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

    private func affectedPieceKind(
        for issue: CoachingOpponentIssue,
        move: Move,
        advice: CoachingAdvice
    ) -> Piece.Kind? {
        let board = advice.evaluation.request.committedState.board
        if issue.reply.to == move.to {
            return board[move.from]?.kind
        }
        return board[issue.reply.to]?.kind
    }
}

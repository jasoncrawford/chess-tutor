struct LocalCoachingAdvisor: CoachingAdvising {
    private let evaluator: MaterialTacticalEvaluator
    private let insightSource: LocalCoachingInsightSource

    init(
        evaluator: MaterialTacticalEvaluator = MaterialTacticalEvaluator(),
        insightSource: LocalCoachingInsightSource = LocalCoachingInsightSource()
    ) {
        self.evaluator = evaluator
        self.insightSource = insightSource
    }

    func advice(for request: CoachingRequest) async throws -> CoachingAdvice {
        let evaluation = evaluator.evaluate(request)
        let insightSet = insightSource.insights(for: evaluation)
        let purposeConcepts: Set<CoachingConcept> = [
            .kingInCheck,
            .pieceNeedsHelp,
            .profitableCapture,
            .mateInOne,
            .captureResolvesDanger,
            .developsKnightOrBishop,
            .advancesCenterPawn,
            .castlesForKingSafety,
            .addsUsefulDefender,
            .createsSafeImmediateThreat,
            .improvesCentralActivity,
        ]
        let assessments = evaluation.moveAssessments.mapValues { assessment in
            let concepts = insightSet.ordered
                .filter { $0.candidateMoves.contains(assessment.move) }
                .map(\.concept)
            let hasRecognizedPurpose = concepts.contains { purposeConcepts.contains($0) }
            let hasRevisionIssue = assessment.opponentIssues.contains {
                $0.severity == .reviseMove
            }
            return CoachingMoveAssessment(
                move: assessment.move,
                isLegal: assessment.isLegal,
                resolvesRequiredDanger: assessment.resolvesRequiredDanger,
                opponentIssues: assessment.opponentIssues,
                concepts: concepts,
                isAcceptable: assessment.isLegal
                    && assessment.resolvesRequiredDanger
                    && !hasRevisionIssue
                    && (hasRecognizedPurpose || insightSet.confidence == .unsupported)
            )
        }
        return CoachingAdvice(
            evaluation: evaluation,
            insights: insightSet.ordered,
            dangerProblems: insightSet.dangerProblems,
            takeOpportunities: insightSet.takeOpportunities,
            wakeOpportunities: insightSet.wakeOpportunities,
            moveAssessments: assessments,
            openingDevelopmentIsRelevant: insightSet.openingDevelopmentIsRelevant,
            confidence: insightSet.confidence
        )
    }
}

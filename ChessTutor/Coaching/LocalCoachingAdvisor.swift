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
        let assessments = evaluation.moveAssessments.mapValues { assessment in
            let concepts = insightSet.ordered
                .filter { $0.candidateMoves.contains(assessment.move) }
                .map(\.concept)
            let hasRevisionIssue = assessment.opponentIssues.contains {
                $0.severity == .reviseMove
            }
            return CoachingMoveAssessment(
                move: assessment.move,
                isLegal: assessment.isLegal,
                resolvesRequiredDanger: assessment.resolvesRequiredDanger,
                opponentIssues: assessment.opponentIssues,
                opponentActivities: assessment.opponentActivities,
                concepts: concepts,
                isTacticallyAcceptable: assessment.isLegal
                    && assessment.resolvesRequiredDanger
                    && !hasRevisionIssue
            )
        }
        return CoachingAdvice(
            evaluation: evaluation,
            insights: insightSet.ordered,
            dangerProblems: insightSet.dangerProblems,
            takeOpportunities: insightSet.takeOpportunities,
            wakeOpportunities: insightSet.wakeOpportunities,
            wakeTasks: insightSet.wakeTasks,
            moveAssessments: assessments,
            openingDevelopmentIsRelevant: insightSet.openingDevelopmentIsRelevant,
            confidence: insightSet.confidence
        )
    }
}

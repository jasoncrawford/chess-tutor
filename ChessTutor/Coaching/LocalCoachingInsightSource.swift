protocol CoachingInsightSourcing: Sendable {
    func insights(for evaluation: CoachingEvaluation) -> CoachingInsightSet
}

struct CoachingInsightSet: Equatable, Sendable {
    let ordered: [CoachingInsight]
    let urgentProblems: [CoachingUrgentProblem]
    let takeOpportunities: [CoachingOpportunity]
    let wakeOpportunities: [CoachingOpportunity]
    let openingDevelopmentIsRelevant: Bool
    let confidence: CoachingConfidence
}

struct LocalCoachingInsightSource: CoachingInsightSourcing {
    func insights(for evaluation: CoachingEvaluation) -> CoachingInsightSet {
        var insights: [CoachingInsight] = []
        var takeOpportunities: [CoachingOpportunity] = []
        let resolvingMoves = evaluation.moveAssessments.values
            .filter { $0.isLegal && $0.resolvesRequiredDanger }
            .map(\.move)
            .sorted { stableMoveKey($0) < stableMoveKey($1) }

        if !evaluation.checkingPieces.isEmpty {
            insights.append(
                CoachingInsight(
                    concept: .kingInCheck,
                    subjectSquares: evaluation.checkingPieces,
                    candidateMoves: resolvingMoves,
                    priority: 1_000,
                    confidence: .high,
                    evidence: .check(attackers: evaluation.checkingPieces)
                )
            )

            for checkingPiece in evaluation.checkingPieces.sorted(by: stableSquareOrder) {
                insights.append(
                    CoachingInsight(
                        concept: .checkingPiece,
                        subjectSquares: [checkingPiece],
                        candidateMoves: resolvingMoves,
                        priority: 990,
                        confidence: .high,
                        evidence: .check(attackers: evaluation.checkingPieces)
                    )
                )
            }
        }

        for (index, problem) in evaluation.urgentProblems.enumerated() {
            insights.append(
                CoachingInsight(
                    concept: .pieceNeedsHelp,
                    subjectSquares: [problem.target],
                    candidateMoves: resolvingMoves,
                    priority: 900 - index,
                    confidence: .high,
                    evidence: .danger(
                        target: problem.target,
                        estimatedLoss: problem.worstEstimatedLoss
                    )
                )
            )

            for capture in problem.captures.sorted(by: stableCaptureOrder) {
                insights.append(
                    CoachingInsight(
                        concept: .profitableAttacker,
                        subjectSquares: [capture.move.from],
                        candidateMoves: [capture.move],
                        priority: 890 - index,
                        confidence: .high,
                        evidence: .capture(capture)
                    )
                )
            }
        }

        let profitableCaptures = evaluation.learnerCaptureEstimates
            .filter { $0.netGainForMover >= 1 }
            .sorted(by: profitableCaptureOrder)
        for capture in profitableCaptures {
            let subjectSquares: Set<Square> = [capture.move.from, capture.capturedSquare]
            insights.append(
                CoachingInsight(
                    concept: .profitableCapture,
                    subjectSquares: subjectSquares,
                    candidateMoves: [capture.move],
                    priority: 700 + capture.netGainForMover,
                    confidence: .high,
                    evidence: .capture(capture)
                )
            )

            if let assessment = evaluation.moveAssessments[capture.move],
               isTakeAnswer(assessment) {
                takeOpportunities.append(
                    CoachingOpportunity(
                        concept: .profitableCapture,
                        subjectSquares: subjectSquares,
                        moves: [capture.move],
                        priority: 700 + capture.netGainForMover,
                        evidence: .capture(capture)
                    )
                )
            }
        }

        if !evaluation.urgentProblems.isEmpty {
            for capture in evaluation.learnerCaptureEstimates.sorted(by: stableCaptureOrder) {
                guard let assessment = evaluation.moveAssessments[capture.move],
                      assessment.isLegal,
                      assessment.resolvesRequiredDanger else {
                    continue
                }
                let subjectSquares: Set<Square> = [capture.move.from, capture.capturedSquare]
                insights.append(
                    CoachingInsight(
                        concept: .captureResolvesDanger,
                        subjectSquares: subjectSquares,
                        candidateMoves: [capture.move],
                        priority: 800,
                        confidence: .high,
                        evidence: .capture(capture)
                    )
                )

                if isTakeAnswer(assessment) {
                    takeOpportunities.append(
                        CoachingOpportunity(
                            concept: .captureResolvesDanger,
                            subjectSquares: subjectSquares,
                            moves: [capture.move],
                            priority: 800,
                            evidence: .capture(capture)
                        )
                    )
                }
            }
        }

        for move in evaluation.mateInOneMoves.sorted(by: stableMoveOrder) {
            guard let assessment = evaluation.moveAssessments[move],
                  isTakeAnswer(assessment) else {
                continue
            }
            let subjectSquares: Set<Square> = [move.from, move.to]
            let matingState = evaluation.request.committedState.applyingUnchecked(move)
            let checkingPieces = LegalMoveGenerator.checkingPieceSquares(
                against: matingState.sideToMove,
                in: matingState.board
            )
            let evidence = CoachingEvidence.check(attackers: checkingPieces)
            insights.append(
                CoachingInsight(
                    concept: .mateInOne,
                    subjectSquares: subjectSquares,
                    candidateMoves: [move],
                    priority: 1_000,
                    confidence: .high,
                    evidence: evidence
                )
            )
            takeOpportunities.append(
                CoachingOpportunity(
                    concept: .mateInOne,
                    subjectSquares: subjectSquares,
                    moves: [move],
                    priority: 1_000,
                    evidence: evidence
                )
            )
        }

        for assessment in sortedAssessments(evaluation.moveAssessments) {
            for issue in assessment.opponentIssues {
                let concept: CoachingConcept
                switch issue.kind {
                case .mateInOne:
                    concept = .allowsMateInOne
                case .check:
                    concept = .allowsCheck
                case .materialLoss:
                    concept = .allowsMaterialLoss
                }
                insights.append(
                    CoachingInsight(
                        concept: concept,
                        subjectSquares: issue.answerSquares,
                        candidateMoves: [assessment.move],
                        priority: 100,
                        confidence: .high,
                        evidence: .opponentReply(issue)
                    )
                )
            }

            if assessment.isLegal,
               !assessment.opponentIssues.contains(where: { $0.severity == .reviseMove }) {
                insights.append(
                    CoachingInsight(
                        concept: .safeAfterReplyCheck,
                        subjectSquares: [assessment.move.from, assessment.move.to],
                        candidateMoves: [assessment.move],
                        priority: 50,
                        confidence: .high,
                        evidence: .verifiedSafe
                    )
                )
            }
        }

        takeOpportunities.sort(by: opportunityOrder)

        return CoachingInsightSet(
            ordered: insights,
            urgentProblems: evaluation.urgentProblems,
            takeOpportunities: takeOpportunities,
            wakeOpportunities: [],
            openingDevelopmentIsRelevant: false,
            confidence: .high
        )
    }

    private func stableMoveKey(_ move: Move) -> Int {
        let source = (move.from.rank - 1) * 8 + move.from.file.rawValue
        let destination = (move.to.rank - 1) * 8 + move.to.file.rawValue
        return source * 1_000 + destination * 10 + specialOrder(move.special)
    }

    private func stableSquareOrder(_ lhs: Square, _ rhs: Square) -> Bool {
        stableSquareKey(lhs) < stableSquareKey(rhs)
    }

    private func stableMoveOrder(_ lhs: Move, _ rhs: Move) -> Bool {
        stableMoveKey(lhs) < stableMoveKey(rhs)
    }

    private func stableCaptureOrder(
        _ lhs: CoachingCaptureEstimate,
        _ rhs: CoachingCaptureEstimate
    ) -> Bool {
        stableMoveKey(lhs.move) < stableMoveKey(rhs.move)
    }

    private func profitableCaptureOrder(
        _ lhs: CoachingCaptureEstimate,
        _ rhs: CoachingCaptureEstimate
    ) -> Bool {
        if lhs.netGainForMover != rhs.netGainForMover {
            return lhs.netGainForMover > rhs.netGainForMover
        }
        return stableMoveKey(lhs.move) < stableMoveKey(rhs.move)
    }

    private func isTakeAnswer(_ assessment: CoachingMoveAssessment) -> Bool {
        assessment.isLegal
            && assessment.resolvesRequiredDanger
            && !assessment.opponentIssues.contains { $0.severity == .reviseMove }
    }

    private func sortedAssessments(
        _ assessments: [Move: CoachingMoveAssessment]
    ) -> [CoachingMoveAssessment] {
        assessments.values.sorted { stableMoveKey($0.move) < stableMoveKey($1.move) }
    }

    private func opportunityOrder(
        _ lhs: CoachingOpportunity,
        _ rhs: CoachingOpportunity
    ) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        let lhsMove = lhs.moves.first.map(stableMoveKey) ?? Int.max
        let rhsMove = rhs.moves.first.map(stableMoveKey) ?? Int.max
        return lhsMove < rhsMove
    }

    private func stableSquareKey(_ square: Square) -> Int {
        (square.rank - 1) * 8 + square.file.rawValue
    }

    private func specialOrder(_ special: Move.Special?) -> Int {
        switch special {
        case nil: 0
        case .castleKingside: 1
        case .castleQueenside: 2
        case .enPassant: 3
        case .promotion(.queen): 4
        case .promotion(.rook): 5
        case .promotion(.bishop): 6
        case .promotion(.knight): 7
        case .promotion(.pawn), .promotion(.king): 8
        }
    }
}

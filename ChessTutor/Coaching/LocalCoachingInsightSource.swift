protocol CoachingInsightSourcing: Sendable {
    func insights(for evaluation: CoachingEvaluation) -> CoachingInsightSet
}

struct CoachingInsightSet: Equatable, Sendable {
    let ordered: [CoachingInsight]
    let dangerProblems: [CoachingDangerProblem]
    let takeOpportunities: [CoachingOpportunity]
    let wakeOpportunities: [CoachingOpportunity]
    let openingDevelopmentIsRelevant: Bool
    let confidence: CoachingConfidence
}

struct LocalCoachingInsightSource: CoachingInsightSourcing {
    private let materialEvaluator = MaterialTacticalEvaluator()
    private let centralSixteen = Set(
        Square.File.allCases
            .filter { (3...6).contains($0.rawValue) }
            .flatMap { file in (3...6).map { Square(file: file, rank: $0) } }
    )

    func insights(for evaluation: CoachingEvaluation) -> CoachingInsightSet {
        var insights: [CoachingInsight] = []
        var takeOpportunities: [CoachingOpportunity] = []
        var wakeOpportunities: [CoachingOpportunity] = []
        let state = evaluation.request.committedState
        let learner = evaluation.request.learner
        let legalMoves = evaluation.moveAssessments.values
            .filter(\.isLegal)
            .map(\.move)
            .sorted { stableMoveKey($0) < stableMoveKey($1) }
        let requiredDangerResolvingMoves = evaluation.moveAssessments.values
            .filter { $0.isLegal && $0.resolvesRequiredDanger }
            .map(\.move)
            .sorted { stableMoveKey($0) < stableMoveKey($1) }
        let wakeAssessments = sortedAssessments(evaluation.moveAssessments)
            .filter(isWakeAnswer)
        let capturableLearnerTargets = Set(
            evaluation.opponentCaptureEstimates.map(\.capturedSquare)
        )

        if !evaluation.checkingPieces.isEmpty {
            insights.append(
                CoachingInsight(
                    concept: .kingInCheck,
                    subjectSquares: evaluation.checkingPieces,
                    candidateMoves: legalMoves,
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
                        candidateMoves: legalMoves,
                        priority: 990,
                        confidence: .high,
                        evidence: .check(attackers: evaluation.checkingPieces)
                    )
                )
            }
        }

        for (index, problem) in evaluation.dangerProblems.enumerated() {
            insights.append(
                CoachingInsight(
                    concept: .pieceNeedsHelp,
                    subjectSquares: [problem.target],
                    candidateMoves: requiredDangerResolvingMoves,
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

        if !evaluation.dangerProblems.isEmpty {
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

        let openingDevelopmentIsRelevant = openingDevelopmentIsRelevant(
            in: state,
            learner: learner
        )
        if openingDevelopmentIsRelevant {
            for assessment in wakeAssessments {
                guard let opportunity = openingOpportunity(
                    for: assessment.move,
                    learner: learner,
                    in: state
                ) else {
                    continue
                }
                wakeOpportunities.append(opportunity)
            }
        }
        for assessment in wakeAssessments {
            guard assessment.move.special == .castleKingside
                    || assessment.move.special == .castleQueenside,
                  !wakeOpportunities.contains(where: { $0.moves.contains(assessment.move) }) else {
                continue
            }
            let opportunity = CoachingOpportunity(
                concept: .castlesForKingSafety,
                subjectSquares: [assessment.move.from, assessment.move.to],
                moves: [assessment.move],
                priority: 600,
                evidence: .castle(assessment.move)
            )
            wakeOpportunities.append(opportunity)
        }
        for assessment in wakeAssessments {
            guard let opportunity = defenderOpportunity(
                for: assessment.move,
                learner: learner,
                before: state,
                capturableTargets: capturableLearnerTargets
            ) else {
                continue
            }
            wakeOpportunities.append(opportunity)
        }
        for assessment in wakeAssessments {
            guard let opportunity = threatOpportunity(
                for: assessment.move,
                learner: learner,
                before: state
            ) else {
                continue
            }
            wakeOpportunities.append(opportunity)
        }
        for assessment in wakeAssessments {
            guard let opportunity = centralActivityOpportunity(
                for: assessment.move,
                learner: learner,
                before: state
            ) else {
                continue
            }
            wakeOpportunities.append(opportunity)
        }

        takeOpportunities.sort(by: opportunityOrder)
        wakeOpportunities.sort(by: opportunityOrder)
        insights.append(contentsOf: wakeOpportunities.map(insight(from:)))
        let confidence: CoachingConfidence = evaluation.checkingPieces.isEmpty
            && evaluation.dangerProblems.isEmpty
            && takeOpportunities.isEmpty
            && wakeOpportunities.isEmpty
            ? .unsupported
            : .high

        return CoachingInsightSet(
            ordered: insights,
            dangerProblems: evaluation.dangerProblems,
            takeOpportunities: takeOpportunities,
            wakeOpportunities: wakeOpportunities,
            openingDevelopmentIsRelevant: openingDevelopmentIsRelevant,
            confidence: confidence
        )
    }

    private func openingDevelopmentIsRelevant(
        in state: GameState,
        learner: PieceColor
    ) -> Bool {
        let learnerHomeRank = learner == .white ? 1 : 8
        let minorHomes = [
            Square(file: .b, rank: learnerHomeRank),
            Square(file: .c, rank: learnerHomeRank),
            Square(file: .f, rank: learnerHomeRank),
            Square(file: .g, rank: learnerHomeRank),
        ]
        let hasUndevelopedMinor = minorHomes.contains { square in
            guard let piece = state.board[square] else { return false }
            return piece.color == learner && (piece.kind == .knight || piece.kind == .bishop)
        }
        let bothQueensRemain = [PieceColor.white, .black].allSatisfy { color in
            state.board.pieces.values.contains(Piece(kind: .queen, color: color))
        }
        let bothSidesHaveThreeMajorOrMinorPieces = [PieceColor.white, .black].allSatisfy { color in
            state.board.pieces.values.filter {
                $0.color == color && $0.kind != .pawn && $0.kind != .king
            }.count >= 3
        }
        return hasUndevelopedMinor && bothQueensRemain && bothSidesHaveThreeMajorOrMinorPieces
    }

    private func openingOpportunity(
        for move: Move,
        learner: PieceColor,
        in state: GameState
    ) -> CoachingOpportunity? {
        guard let piece = state.board[move.from], piece.color == learner else {
            return nil
        }

        let homeRank = learner == .white ? 1 : 8
        let pawnHomeRank = learner == .white ? 2 : 7
        let direction = learner == .white ? 1 : -1
        let isOriginalMinorHome: Bool
        switch piece.kind {
        case .knight:
            isOriginalMinorHome = move.from.rank == homeRank
                && (move.from.file == .b || move.from.file == .g)
        case .bishop:
            isOriginalMinorHome = move.from.rank == homeRank
                && (move.from.file == .c || move.from.file == .f)
        default:
            isOriginalMinorHome = false
        }

        if isOriginalMinorHome {
            return CoachingOpportunity(
                concept: .developsKnightOrBishop,
                subjectSquares: [move.from, move.to],
                moves: [move],
                priority: 600,
                evidence: .development(source: move.from, destination: move.to)
            )
        }

        if piece.kind == .pawn,
           move.from.rank == pawnHomeRank,
           move.from.file == .d || move.from.file == .e,
           move.to.file == move.from.file,
           (move.to.rank - move.from.rank) * direction > 0 {
            return CoachingOpportunity(
                concept: .advancesCenterPawn,
                subjectSquares: [move.from, move.to],
                moves: [move],
                priority: 600,
                evidence: .centerPawn(source: move.from, destination: move.to)
            )
        }

        if move.special == .castleKingside || move.special == .castleQueenside {
            return CoachingOpportunity(
                concept: .castlesForKingSafety,
                subjectSquares: [move.from, move.to],
                moves: [move],
                priority: 600,
                evidence: .castle(move)
            )
        }

        return nil
    }

    private func insight(from opportunity: CoachingOpportunity) -> CoachingInsight {
        CoachingInsight(
            concept: opportunity.concept,
            subjectSquares: opportunity.subjectSquares,
            candidateMoves: opportunity.moves,
            priority: opportunity.priority,
            confidence: .high,
            evidence: opportunity.evidence
        )
    }

    private func defenderOpportunity(
        for move: Move,
        learner: PieceColor,
        before: GameState,
        capturableTargets: Set<Square>
    ) -> CoachingOpportunity? {
        guard !capturableTargets.isEmpty else { return nil }

        let beforeTargets = LegalMoveGenerator.legalSupportTargets(
            for: move.from,
            by: learner,
            in: before
        )
        let after = before.applyingUnchecked(move)
        let afterTargets = LegalMoveGenerator.legalSupportTargets(
            for: move.to,
            by: learner,
            in: after
        )
        let newlyDefendedTargets = afterTargets
            .subtracting(beforeTargets)
            .intersection(capturableTargets)
            .filter { after.board[$0]?.color == learner }
            .sorted(by: stableSquareOrder)
        guard let target = newlyDefendedTargets.first else { return nil }

        return CoachingOpportunity(
            concept: .addsUsefulDefender,
            subjectSquares: [move.from, target],
            moves: [move],
            priority: 500,
            evidence: .defender(source: move.from, target: target)
        )
    }

    private func threatOpportunity(
        for move: Move,
        learner: PieceColor,
        before: GameState
    ) -> CoachingOpportunity? {
        let capturesBefore = Set(
            LegalMoveGenerator.legalMoves(for: move.from, by: learner, in: before)
                .compactMap { LegalMoveGenerator.capture(for: $0, in: before)?.square }
        )
        let after = before.applyingUnchecked(move)
        guard let movedPiece = after.board[move.to], movedPiece.color == learner else {
            return nil
        }
        let afterAnalysis = PositionAnalyzer.analyze(after)
        let gainedThreats = LegalMoveGenerator.legalMoves(
            for: move.to,
            by: learner,
            in: after
        ).compactMap { candidate -> Square? in
            guard let capture = LegalMoveGenerator.capture(for: candidate, in: after),
                  capture.piece.color == learner.opposite,
                  !capturesBefore.contains(capture.square) else {
                return nil
            }
            let isUndefended = afterAnalysis.supporters(of: capture.square).isEmpty
            let isMoreValuable: Bool
            if let targetValue = materialEvaluator.pieceValue(capture.piece.kind),
               let moverValue = materialEvaluator.pieceValue(movedPiece.kind) {
                isMoreValuable = targetValue > moverValue
            } else {
                isMoreValuable = false
            }
            return isUndefended || isMoreValuable ? capture.square : nil
        }.sorted(by: stableSquareOrder)
        guard let target = gainedThreats.first else { return nil }

        return CoachingOpportunity(
            concept: .createsSafeImmediateThreat,
            subjectSquares: [move.from, target],
            moves: [move],
            priority: 400,
            evidence: .threat(source: move.from, target: target)
        )
    }

    private func centralActivityOpportunity(
        for move: Move,
        learner: PieceColor,
        before: GameState
    ) -> CoachingOpportunity? {
        guard let piece = before.board[move.from], piece.kind != .pawn else {
            return nil
        }

        let beforeDistance = distanceToCentralSixteen(move.from)
        let afterDistance = distanceToCentralSixteen(move.to)
        let beforeMobility = LegalMoveGenerator.legalMoves(
            for: move.from,
            by: learner,
            in: before
        ).count
        let after = before.applyingUnchecked(move)
        let afterMobility = LegalMoveGenerator.legalMoves(
            for: move.to,
            by: learner,
            in: after
        ).count
        guard afterDistance < beforeDistance,
              afterMobility >= beforeMobility + 2 else {
            return nil
        }

        return CoachingOpportunity(
            concept: .improvesCentralActivity,
            subjectSquares: [move.from, move.to],
            moves: [move],
            priority: 300,
            evidence: .mobility(
                source: move.from,
                destination: move.to,
                before: beforeMobility,
                after: afterMobility
            )
        )
    }

    private func distanceToCentralSixteen(_ square: Square) -> Int {
        centralSixteen.map { center in
            abs(center.file.rawValue - square.file.rawValue) + abs(center.rank - square.rank)
        }.min() ?? 0
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

    private func isWakeAnswer(_ assessment: CoachingMoveAssessment) -> Bool {
        isTakeAnswer(assessment)
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

struct MaterialTacticalEvaluator: Sendable {
    func evaluate(_ request: CoachingRequest) -> CoachingEvaluation {
        let state = request.committedState
        let opponentCaptureEstimates = opponentCaptureEstimates(
            against: request.learner,
            in: state
        )
        let urgentProblems = urgentProblems(
            from: opponentCaptureEstimates,
            learner: request.learner,
            in: state
        )
        let learnerCaptureEstimates = LegalMoveGenerator.allLegalMoves(in: state)
            .compactMap { captureEstimate(for: $0, in: state) }
            .sorted { stableMoveKey($0.move) < stableMoveKey($1.move) }
        let legalMoves = Set(LegalMoveGenerator.allLegalMoves(in: state))
        let mateInOneMoves = Set(legalMoves.filter { move in
            let next = state.applyingUnchecked(move)
            return LegalMoveGenerator.allLegalMoves(in: next).isEmpty
                && LegalMoveGenerator.isKingInCheck(next.sideToMove, in: next.board)
        })
        let allowedMoves = state.board.pieces
            .filter { $0.value.color == request.learner }
            .flatMap { LegalMoveGenerator.allowedMoves(for: $0.key, in: state) }
        let largestReplyLossByMove = Dictionary(uniqueKeysWithValues: legalMoves.map { move in
            (move, largestOpponentMaterialLoss(after: move, in: state))
        })
        let smallestWorstLoss = largestReplyLossByMove.values.min()
        let dangerIsUnavoidable = smallestWorstLoss.map { $0 >= 2 } ?? false
        let moveAssessments = Dictionary(uniqueKeysWithValues: allowedMoves.map { move in
            let isLegal = legalMoves.contains(move)
            let largestReplyLoss = largestReplyLossByMove[move] ?? 0
            let isBestUnavoidableDefense = isLegal
                && dangerIsUnavoidable
                && largestReplyLoss == smallestWorstLoss
            var opponentIssues = isLegal ? opponentIssues(after: move, in: state) : []
            if isBestUnavoidableDefense {
                opponentIssues = opponentIssues.map { issue in
                    guard case .materialLoss = issue.kind else { return issue }
                    return CoachingOpponentIssue(
                        reply: issue.reply,
                        kind: issue.kind,
                        severity: .notice,
                        answerSquares: issue.answerSquares
                    )
                }
            }
            let resolvesRequiredDanger: Bool
            if !isLegal {
                resolvesRequiredDanger = false
            } else if urgentProblems.isEmpty {
                resolvesRequiredDanger = true
            } else {
                resolvesRequiredDanger = largestReplyLoss < 2 || isBestUnavoidableDefense
            }
            return (
                move,
                CoachingMoveAssessment(
                    move: move,
                    isLegal: isLegal,
                    resolvesRequiredDanger: resolvesRequiredDanger,
                    opponentIssues: opponentIssues,
                    concepts: [],
                    isAcceptable: false
                )
            )
        })

        return CoachingEvaluation(
            request: request,
            checkingPieces: LegalMoveGenerator.checkingPieceSquares(
                against: request.learner,
                in: state.board
            ),
            opponentHasAnyLegalCapture: !opponentCaptureEstimates.isEmpty,
            learnerHasAnyLegalCapture: !learnerCaptureEstimates.isEmpty,
            opponentCaptureEstimates: opponentCaptureEstimates,
            urgentProblems: urgentProblems,
            learnerCaptureEstimates: learnerCaptureEstimates,
            mateInOneMoves: mateInOneMoves,
            moveAssessments: moveAssessments
        )
    }

    func pieceValue(_ kind: Piece.Kind) -> Int? {
        switch kind {
        case .pawn: 1
        case .knight, .bishop: 3
        case .rook: 5
        case .queen: 9
        case .king: nil
        }
    }

    func captureEstimate(for move: Move, in state: GameState) -> CoachingCaptureEstimate? {
        guard let capture = LegalMoveGenerator.capture(for: move, in: state),
              let mover = state.board[move.from],
              LegalMoveGenerator.legalMoves(for: move.from, in: state).contains(move) else {
            return nil
        }

        let next = state.applyingUnchecked(move)
        let recaptures = LegalMoveGenerator.allLegalMoves(in: next).filter { reply in
            LegalMoveGenerator.capture(for: reply, in: next)?.square == move.to
        }
        let recapture = recaptures.sorted { lhs, rhs in
            let lhsGain = recaptureGain(lhs, in: next)
            let rhsGain = recaptureGain(rhs, in: next)
            if lhsGain != rhsGain { return lhsGain > rhsGain }
            return stableMoveKey(lhs) < stableMoveKey(rhs)
        }.first
        let movedKind: Piece.Kind
        if case let .promotion(kind) = move.special {
            movedKind = kind
        } else {
            movedKind = mover.kind
        }
        let net = pieceValue(capture.piece.kind)! - (recapture == nil ? 0 : pieceValue(movedKind)!)

        return CoachingCaptureEstimate(
            move: move,
            capturedPiece: capture.piece,
            capturedSquare: capture.square,
            immediateRecapture: recapture,
            netGainForMover: net
        )
    }

    private func recaptureGain(_ move: Move, in state: GameState) -> Int {
        guard let capture = LegalMoveGenerator.capture(for: move, in: state),
              let value = pieceValue(capture.piece.kind) else {
            return Int.min
        }
        return value
    }

    private func opponentCaptureEstimates(
        against learner: PieceColor,
        in state: GameState
    ) -> [CoachingCaptureEstimate] {
        var opponentState = state
        opponentState.sideToMove = learner.opposite
        opponentState.enPassantTarget = nil

        return PositionAnalyzer.analyze(state).threatsByTarget.values
            .flatMap { $0 }
            .filter { $0.color == learner.opposite }
            .compactMap { threat in
                captureEstimate(
                    for: Move(from: threat.source, to: threat.destination),
                    in: opponentState
                )
            }
            .sorted { stableMoveKey($0.move) < stableMoveKey($1.move) }
    }

    private func opponentIssues(after move: Move, in state: GameState) -> [CoachingOpponentIssue] {
        let opponentState = state.applyingUnchecked(move)
        return LegalMoveGenerator.allLegalMoves(in: opponentState)
            .sorted { stableMoveKey($0) < stableMoveKey($1) }
            .flatMap { reply -> [CoachingOpponentIssue] in
                let replyState = opponentState.applyingUnchecked(reply)
                let checkingPieces = LegalMoveGenerator.checkingPieceSquares(
                    against: replyState.sideToMove,
                    in: replyState.board
                )
                if LegalMoveGenerator.allLegalMoves(in: replyState).isEmpty,
                   !checkingPieces.isEmpty {
                    return [
                        CoachingOpponentIssue(
                            reply: reply,
                            kind: .mateInOne,
                            severity: .reviseMove,
                            answerSquares: checkingPieces
                        )
                    ]
                }

                var issues: [CoachingOpponentIssue] = []
                if !checkingPieces.isEmpty {
                    issues.append(
                        CoachingOpponentIssue(
                            reply: reply,
                            kind: .check,
                            severity: .notice,
                            answerSquares: checkingPieces.union([reply.from])
                        )
                    )
                }
                if let estimate = captureEstimate(for: reply, in: opponentState),
                   estimate.netGainForMover >= 2 {
                    issues.append(
                        CoachingOpponentIssue(
                            reply: reply,
                            kind: .materialLoss(points: estimate.netGainForMover),
                            severity: .reviseMove,
                            answerSquares: [estimate.capturedSquare]
                        )
                    )
                }
                return issues
            }
    }

    private func largestOpponentMaterialLoss(after move: Move, in state: GameState) -> Int {
        let opponentState = state.applyingUnchecked(move)
        return LegalMoveGenerator.allLegalMoves(in: opponentState)
            .compactMap { captureEstimate(for: $0, in: opponentState)?.netGainForMover }
            .max() ?? 0
    }

    private func urgentProblems(
        from estimates: [CoachingCaptureEstimate],
        learner: PieceColor,
        in state: GameState
    ) -> [CoachingUrgentProblem] {
        Dictionary(grouping: estimates, by: \.capturedSquare).compactMap { target, captures in
            guard let piece = state.board[target], piece.color == learner else {
                return nil
            }
            let worstEstimatedLoss = captures.map(\.netGainForMover).max() ?? 0
            guard worstEstimatedLoss >= 2 else { return nil }
            return CoachingUrgentProblem(
                target: target,
                piece: piece,
                captures: captures,
                worstEstimatedLoss: worstEstimatedLoss
            )
        }.sorted { lhs, rhs in
            if lhs.worstEstimatedLoss != rhs.worstEstimatedLoss {
                return lhs.worstEstimatedLoss > rhs.worstEstimatedLoss
            }
            let lhsValue = pieceValue(lhs.piece.kind) ?? 0
            let rhsValue = pieceValue(rhs.piece.kind) ?? 0
            if lhsValue != rhsValue { return lhsValue > rhsValue }
            return stableSquareKey(lhs.target) < stableSquareKey(rhs.target)
        }
    }

    private func stableSquareKey(_ square: Square) -> Int {
        square.rank * 10 + square.file.rawValue
    }

    private func stableMoveKey(_ move: Move) -> Int {
        let source = (move.from.rank - 1) * 8 + move.from.file.rawValue
        let destination = (move.to.rank - 1) * 8 + move.to.file.rawValue
        return source * 1_000 + destination * 10 + specialOrder(move.special)
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

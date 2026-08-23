struct MaterialTacticalEvaluator: Sendable {
    func evaluate(_ request: CoachingRequest) -> CoachingEvaluation {
        let state = request.committedState
        let opponentCaptureEstimates = opponentCaptureEstimates(
            against: request.learner,
            in: state
        )
        let dangerProblems = dangerProblems(
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
        let dangerIsUnavoidable = smallestWorstLoss.map { $0 >= 1 } ?? false
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
            } else if dangerProblems.isEmpty {
                resolvesRequiredDanger = true
            } else {
                resolvesRequiredDanger = largestReplyLoss < 1 || isBestUnavoidableDefense
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
            dangerProblems: dangerProblems,
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

        return LegalMoveGenerator.allLegalMoves(in: opponentState)
            .compactMap { captureEstimate(for: $0, in: opponentState) }
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
                let checkingAnswerSquares = visibleCheckingSquares(
                    for: checkingPieces,
                    after: reply
                )
                if LegalMoveGenerator.allLegalMoves(in: replyState).isEmpty,
                   !checkingPieces.isEmpty {
                    return [
                        CoachingOpponentIssue(
                            reply: reply,
                            kind: .mateInOne,
                            severity: .reviseMove,
                            answerSquares: checkingAnswerSquares
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
                            answerSquares: checkingAnswerSquares
                        )
                    )
                }
                if let estimate = captureEstimate(for: reply, in: opponentState),
                   estimate.netGainForMover >= 1 {
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

    private func visibleCheckingSquares(
        for checkingPieces: Set<Square>,
        after reply: Move
    ) -> Set<Square> {
        let secondaryMove: (from: Square, to: Square)?
        switch reply.special {
        case .castleKingside:
            secondaryMove = (
                Square(file: .h, rank: reply.from.rank),
                Square(file: .f, rank: reply.from.rank)
            )
        case .castleQueenside:
            secondaryMove = (
                Square(file: .a, rank: reply.from.rank),
                Square(file: .d, rank: reply.from.rank)
            )
        case nil, .enPassant, .promotion:
            secondaryMove = nil
        }

        return Set(checkingPieces.map { checker in
            if checker == reply.to {
                return reply.from
            }
            if let secondaryMove, checker == secondaryMove.to {
                return secondaryMove.from
            }
            return checker
        })
    }

    private func largestOpponentMaterialLoss(after move: Move, in state: GameState) -> Int {
        let opponentState = state.applyingUnchecked(move)
        return LegalMoveGenerator.allLegalMoves(in: opponentState)
            .compactMap { captureEstimate(for: $0, in: opponentState)?.netGainForMover }
            .max() ?? 0
    }

    private func dangerProblems(
        from estimates: [CoachingCaptureEstimate],
        learner: PieceColor,
        in state: GameState
    ) -> [CoachingDangerProblem] {
        Dictionary(grouping: estimates, by: \.capturedSquare).compactMap { target, captures in
            guard let piece = state.board[target], piece.color == learner else {
                return nil
            }
            let worstEstimatedLoss = captures.map(\.netGainForMover).max() ?? 0
            guard worstEstimatedLoss >= 1,
                  let pieceValue = pieceValue(piece.kind) else { return nil }
            return CoachingDangerProblem(
                target: target,
                piece: piece,
                pieceValue: pieceValue,
                captures: captures,
                worstEstimatedLoss: worstEstimatedLoss
            )
        }.sorted { lhs, rhs in
            if lhs.worstEstimatedLoss != rhs.worstEstimatedLoss {
                return lhs.worstEstimatedLoss > rhs.worstEstimatedLoss
            }
            if lhs.pieceValue != rhs.pieceValue {
                return lhs.pieceValue > rhs.pieceValue
            }
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

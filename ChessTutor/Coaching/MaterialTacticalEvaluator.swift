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
        let checkingPieces = LegalMoveGenerator.checkingPieceSquares(
            against: request.learner,
            in: state.board
        )
        let mateInOneMoves = Set(legalMoves.filter { move in
            let next = state.applyingUnchecked(move)
            return LegalMoveGenerator.allLegalMoves(in: next).isEmpty
                && LegalMoveGenerator.isKingInCheck(next.sideToMove, in: next.board)
        })
        let allowedMoves = state.board.pieces
            .filter { $0.value.color == request.learner }
            .flatMap { LegalMoveGenerator.allowedMoves(for: $0.key, in: state) }
        let opponentActivitiesByMove = Dictionary(uniqueKeysWithValues: legalMoves.map { move in
            (move, opponentActivities(after: move, in: state))
        })
        let largestReplyLossByMove = opponentActivitiesByMove.mapValues { activities in
            activities.compactMap(\.netGainForOpponent).max() ?? 0
        }
        let smallestWorstLoss = largestReplyLossByMove.values.min()
        let dangerIsUnavoidable = smallestWorstLoss.map { $0 >= 1 } ?? false
        let moveAssessments = Dictionary(uniqueKeysWithValues: allowedMoves.map { move in
            let isLegal = legalMoves.contains(move)
            let largestReplyLoss = largestReplyLossByMove[move] ?? 0
            let isBestUnavoidableDefense = isLegal
                && dangerIsUnavoidable
                && largestReplyLoss == smallestWorstLoss
            let opponentActivities = opponentActivitiesByMove[move] ?? []
            var opponentIssues = opponentIssues(
                from: opponentActivities,
                after: move,
                in: state
            )
            if let exchange = learnerCaptureEstimates.first(where: {
                $0.move == move
                    && $0.netGainForMover >= 1
                    && $0.immediateRecapture != nil
            }),
               let expectedRecapture = exchange.immediateRecapture {
                opponentIssues = opponentIssues.map { issue in
                    guard issue.reply == expectedRecapture,
                          issue.severity == .reviseMove,
                          case .materialLoss = issue.kind else {
                        return issue
                    }
                    return CoachingOpponentIssue(
                        reply: issue.reply,
                        kind: issue.kind,
                        severity: .notice,
                        affectedSquare: issue.affectedSquare,
                        checkingSquares: issue.checkingSquares
                    )
                }
            }
            if isBestUnavoidableDefense {
                opponentIssues = opponentIssues.map { issue in
                    guard case .materialLoss = issue.kind else { return issue }
                    return CoachingOpponentIssue(
                        reply: issue.reply,
                        kind: issue.kind,
                        severity: .notice,
                        affectedSquare: issue.affectedSquare,
                        checkingSquares: issue.checkingSquares
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
                    opponentActivities: opponentActivities,
                    checkResolution: isLegal ? checkResolution(
                        for: move,
                        in: state,
                        learner: request.learner,
                        checkingSquares: checkingPieces
                    ) : nil,
                    checkingPiece: checkingPieces.count == 1
                        ? checkingPieces.first.flatMap { state.board[$0]?.kind }
                        : nil,
                    dangerResolutionFacts: isLegal
                        ? dangerResolutionFacts(
                            for: move,
                            problems: dangerProblems,
                            in: state
                        )
                        : [],
                    concepts: [],
                    isTacticallyAcceptable: false
                )
            )
        })

        return CoachingEvaluation(
            request: request,
            checkingPieces: checkingPieces,
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

    func exchangeFact(
        for estimate: CoachingCaptureEstimate,
        in committedState: GameState,
        opponentIssue: CoachingOpponentIssue?
    ) -> CoachingExchangeFact? {
        guard let originalMover = committedState.board[estimate.move.from] else { return nil }
        let mover: Piece.Kind
        if case let .promotion(promotedKind) = estimate.move.special {
            mover = promotedKind
        } else {
            mover = originalMover.kind
        }
        let stateAfterMove = committedState.applyingUnchecked(estimate.move)
        let immediateRecapture = opponentIssue?.reply ?? estimate.immediateRecapture
        let immediateRecapturer = immediateRecapture.flatMap {
            stateAfterMove.board[$0.from]?.kind
        }
        return CoachingExchangeFact(
            move: estimate.move,
            mover: mover,
            captured: estimate.capturedPiece.kind,
            immediateRecapture: immediateRecapture,
            immediateRecapturer: immediateRecapturer,
            netGainForLearner: estimate.netGainForMover
        )
    }

    func checkResolution(
        for move: Move,
        in state: GameState,
        learner: PieceColor,
        checkingSquares: Set<Square>
    ) -> CoachingCheckResolution? {
        guard LegalMoveGenerator.legalMoves(for: move.from, in: state).contains(move),
              let mover = state.board[move.from] else {
            return nil
        }
        let after = state.applyingUnchecked(move)
        guard !LegalMoveGenerator.isKingInCheck(learner, in: after.board) else {
            return nil
        }
        if mover.kind == .king {
            return .movedKing
        }
        guard checkingSquares.count == 1,
              let checkerSquare = checkingSquares.first,
              let checker = state.board[checkerSquare] else {
            return nil
        }
        if move.to == checkerSquare {
            return .capturedChecker(checker: checker.kind, capturer: mover.kind)
        }
        return .blocked(attacker: checker.kind, blocker: mover.kind)
    }

    private func dangerResolutionFacts(
        for move: Move,
        problems: [CoachingDangerProblem],
        in state: GameState
    ) -> [CoachingDangerResolutionFact] {
        problems.flatMap { problem in
            problem.captures.compactMap { capture in
                dangerResolutionFact(
                    for: move,
                    targetSquare: problem.target,
                    attackerSquare: capture.move.from,
                    in: state
                )
            }
        }
    }

    private func dangerResolutionFact(
        for move: Move,
        targetSquare: Square,
        attackerSquare: Square,
        in state: GameState
    ) -> CoachingDangerResolutionFact? {
        guard let target = state.board[targetSquare],
              let attacker = state.board[attackerSquare] else {
            return nil
        }

        let resolution: CoachingDangerResolution
        if LegalMoveGenerator.capture(for: move, in: state)?.square == attackerSquare,
           let capturer = state.board[move.from] {
            resolution = .capturedAttacker(
                capturer: capturer.kind,
                target: target.kind,
                attacker: attacker.kind
            )
        } else if move.from == targetSquare {
            resolution = .movedTarget(target: target.kind, attacker: attacker.kind)
        } else {
            let stateAfterMove = state.applyingUnchecked(move)
            guard let attackMove = LegalMoveGenerator.legalMoves(
                for: attackerSquare,
                in: stateAfterMove
            ).first(where: {
                LegalMoveGenerator.capture(for: $0, in: stateAfterMove)?.square
                    == targetSquare
            }),
            let estimate = captureEstimate(for: attackMove, in: stateAfterMove),
            estimate.netGainForMover <= 0,
            let recapture = estimate.immediateRecapture,
            recapture.from == move.to,
            let defender = stateAfterMove.board[recapture.from] else {
                return nil
            }
            resolution = .addedDefender(
                defender: defender.kind,
                target: target.kind,
                attacker: attacker.kind
            )
        }

        return CoachingDangerResolutionFact(
            targetSquare: targetSquare,
            attackerSquare: attackerSquare,
            resolution: resolution
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

    private func opponentActivities(after move: Move, in state: GameState) -> [CoachingOpponentActivity] {
        let afterMove = state.applyingUnchecked(move)
        return LegalMoveGenerator.allLegalMoves(in: afterMove)
            .compactMap { reply in
                let afterReply = afterMove.applyingUnchecked(reply)
                let postReplyCheckingSquares = LegalMoveGenerator.checkingPieceSquares(
                    against: afterReply.sideToMove,
                    in: afterReply.board
                )
                let estimate = captureEstimate(for: reply, in: afterMove)
                guard !postReplyCheckingSquares.isEmpty || estimate != nil,
                      let opponentPiece = afterMove.board[reply.from]?.kind else {
                    return nil
                }
                return CoachingOpponentActivity(
                    reply: reply,
                    opponentPiece: opponentPiece,
                    checkingSquares: visibleCheckingSquares(
                        for: postReplyCheckingSquares,
                        after: reply
                    ),
                    capturedSquare: estimate?.capturedSquare,
                    capturedPiece: estimate?.capturedPiece.kind,
                    netGainForOpponent: estimate?.netGainForMover,
                    immediateRecapture: estimate?.immediateRecapture,
                    isMate: !postReplyCheckingSquares.isEmpty
                        && LegalMoveGenerator.allLegalMoves(in: afterReply).isEmpty
                )
            }
            .sorted { stableMoveKey($0.reply) < stableMoveKey($1.reply) }
    }

    private func opponentIssues(
        from activities: [CoachingOpponentActivity],
        after move: Move,
        in state: GameState
    ) -> [CoachingOpponentIssue] {
        let afterMove = state.applyingUnchecked(move)
        return activities.flatMap { activity -> [CoachingOpponentIssue] in
            let replyState = afterMove.applyingUnchecked(activity.reply)
            let affectedKingSquare = replyState.board.pieces.first(where: {
                $0.value.color == replyState.sideToMove && $0.value.kind == .king
            })?.key
            if activity.isMate {
                return [
                    CoachingOpponentIssue(
                        reply: activity.reply,
                        kind: .mateInOne,
                        severity: .reviseMove,
                        affectedSquare: affectedKingSquare,
                        checkingSquares: activity.checkingSquares
                    )
                ]
            }

            var issues: [CoachingOpponentIssue] = []
            if activity.isCheck {
                issues.append(
                    CoachingOpponentIssue(
                        reply: activity.reply,
                        kind: .check,
                        severity: .notice,
                        affectedSquare: affectedKingSquare,
                        checkingSquares: activity.checkingSquares
                    )
                )
            }
            if activity.canWinPiece,
               let netGainForOpponent = activity.netGainForOpponent {
                issues.append(
                    CoachingOpponentIssue(
                        reply: activity.reply,
                        kind: .materialLoss(points: netGainForOpponent),
                        severity: .reviseMove,
                        affectedSquare: activity.capturedSquare,
                        checkingSquares: []
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

extension CoachingEvaluation {
    var exchangeFacts: [Move: CoachingExchangeFact] {
        let evaluator = MaterialTacticalEvaluator()
        return Dictionary(uniqueKeysWithValues: learnerCaptureEstimates.compactMap { estimate in
            let opponentIssue = moveAssessments[estimate.move]?.opponentIssues.first {
                $0.reply == estimate.immediateRecapture
            }
            guard let fact = evaluator.exchangeFact(
                for: estimate,
                in: request.committedState,
                opponentIssue: opponentIssue
            ) else {
                return nil
            }
            return (estimate.move, fact)
        })
    }
}

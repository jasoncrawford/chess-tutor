struct ModelCoachingSnapshot: Equatable, Sendable {
    let coachingRequest: CoachingRequest
    let interaction: CoachingInteractionSnapshot
    let latestEvent: ModelCoachingLearnerEvent
    let currentTurnHistory: [ModelCoachingHistoryEntry]
    let availableOperations: [ModelCoachingOperation]
}

enum ModelCoachingRequestBuilder {
    static func build(
        snapshot: ModelCoachingSnapshot,
        requestID: String,
        promptVersion: String
    ) -> ModelCoachingRequest {
        let request = snapshot.coachingRequest
        let state = request.committedState
        let evaluator = MaterialTacticalEvaluator()
        let evaluation = evaluator.evaluate(request)
        let pieces = pieceReferences(in: state)
        let pieceIDsBySquare = Dictionary(uniqueKeysWithValues: pieces.map { ($0.square, $0.id) })
        let moves = moveReferences(
            in: state,
            learner: request.learner,
            tentativeMove: tentativeMove(from: snapshot)
        )
        let relationships = relationshipReferences(in: state, pieceIDsBySquare: pieceIDsBySquare)
        let replies = immediateReplies(
            after: moves,
            in: state,
            learner: request.learner,
            tentativeMoveID: tentativeMove(from: snapshot).map(ModelCoachingPositionEncoder.moveID),
            evaluator: evaluator
        )
        let tacticalFacts = tacticalFacts(
            for: evaluation,
            in: state,
            pieceIDsBySquare: pieceIDsBySquare
        )
        let moveConsequences = moveConsequences(
            for: moves,
            evaluation: evaluation,
            in: state,
            learner: request.learner
        )

        return ModelCoachingRequest(
            schemaVersion: "model-coaching-request.v1",
            promptVersion: promptVersion,
            requestID: requestID,
            positionRevision: request.positionRevision,
            currentPosition: ModelCoachingPosition(
                fen: ModelCoachingPositionEncoder.fen(for: state),
                sideToMove: state.sideToMove.rawValue,
                status: status(for: state.result)
            ),
            fullGameHistory: gameHistory(from: state.moveHistory),
            currentInteraction: interaction(
                snapshot: snapshot,
                state: state,
                pieceIDsBySquare: pieceIDsBySquare
            ),
            currentTurnCoachingHistory: snapshot.currentTurnHistory,
            chessEvidence: ModelCoachingEvidenceBundle(
                scope: ModelCoachingEvidenceScope(
                    legalMoves: .exhaustive,
                    relationships: .exhaustive,
                    immediateReplies: .bounded,
                    immediateRepliesDescription: "one legal opponent ply after each legal or staged learner move"
                ),
                pieces: pieces,
                legalMoves: moves,
                relationships: relationships,
                immediateReplies: replies,
                moveConsequences: moveConsequences,
                tacticalFacts: tacticalFacts
            ),
            permittedReferences: permittedReferences(
                operations: snapshot.availableOperations,
                pieces: pieces,
                moves: moves,
                relationships: relationships,
                replies: replies,
                tacticalFacts: tacticalFacts
            )
        )
    }

    private static func pieceReferences(in state: GameState) -> [ModelCoachingPieceReference] {
        state.board.pieces.keys.compactMap { square in
            guard let piece = state.board[square] else { return nil }
            return ModelCoachingPieceReference(
                id: ModelCoachingPositionEncoder.pieceID(piece, at: square),
                color: piece.color.rawValue,
                kind: piece.kind.rawValue,
                square: ModelCoachingPositionEncoder.squareName(square)
            )
        }.sorted { $0.id < $1.id }
    }

    private static func moveReferences(
        in state: GameState,
        learner: PieceColor,
        tentativeMove: Move?
    ) -> [ModelCoachingMoveReference] {
        let allowed = state.board.pieces.keys.flatMap {
            LegalMoveGenerator.allowedMoves(for: $0, by: learner, in: state)
        }
        let legal = Set(state.board.pieces.keys.flatMap {
            LegalMoveGenerator.legalMoves(for: $0, by: learner, in: state)
        })
        let candidates = Set(allowed).union(tentativeMove.map { [$0] } ?? [])

        return ModelCoachingPositionEncoder.orderedMoves(candidates).compactMap { move in
            guard let sourcePiece = state.board[move.from] else { return nil }
            let capture = LegalMoveGenerator.capture(for: move, in: state)
            return ModelCoachingMoveReference(
                id: ModelCoachingPositionEncoder.moveID(move),
                canonicalMove: ModelCoachingPositionEncoder.canonicalMove(move),
                sourcePieceReference: ModelCoachingPositionEncoder.pieceID(sourcePiece, at: move.from),
                destinationSquare: ModelCoachingPositionEncoder.squareName(move.to),
                capturePieceReference: capture.map {
                    ModelCoachingPositionEncoder.pieceID($0.piece, at: $0.square)
                },
                special: specialName(for: move.special),
                isLegal: legal.contains(move)
            )
        }
    }

    private static func relationshipReferences(
        in state: GameState,
        pieceIDsBySquare: [String: String]
    ) -> [ModelCoachingRelationshipReference] {
        var relationships: [ModelCoachingRelationshipReference] = []

        for square in ModelCoachingPositionEncoder.orderedSquares(state.board.pieces.keys) {
            guard let sourcePiece = state.board[square] else { continue }
            let sourceID = ModelCoachingPositionEncoder.pieceID(sourcePiece, at: square)

            for target in ModelCoachingPositionEncoder.orderedSquares(
                LegalMoveGenerator.controlledSquares(from: square, in: state)
            ) {
                guard let targetPiece = state.board[target],
                      let targetID = pieceIDsBySquare[ModelCoachingPositionEncoder.squareName(target)] else {
                    continue
                }
                let kind: ModelCoachingRelationshipKind = targetPiece.color == sourcePiece.color
                    ? .defends
                    : .attacks
                relationships.append(relationship(kind: kind, source: sourceID, target: targetID))
                if targetPiece.kind == .king, targetPiece.color != sourcePiece.color {
                    relationships.append(relationship(kind: .checks, source: sourceID, target: targetID))
                }
            }
        }

        return relationships.sorted { $0.id < $1.id }
    }

    private static func relationship(
        kind: ModelCoachingRelationshipKind,
        source: String,
        target: String
    ) -> ModelCoachingRelationshipReference {
        ModelCoachingRelationshipReference(
            id: ModelCoachingPositionEncoder.relationshipID(kind: kind, source: source, target: target),
            kind: kind,
            sourceReference: source,
            targetReference: target
        )
    }

    private static func immediateReplies(
        after moves: [ModelCoachingMoveReference],
        in state: GameState,
        learner: PieceColor,
        tentativeMoveID: String?,
        evaluator: MaterialTacticalEvaluator
    ) -> [ModelCoachingReplyReference] {
        moves.filter { $0.isLegal || $0.id == tentativeMoveID }.flatMap { moveReference -> [ModelCoachingReplyReference] in
            guard let move = move(from: moveReference, learner: learner, in: state) else { return [] }
            let afterMove = state.applyingUnchecked(move)
            return ModelCoachingPositionEncoder.orderedMoves(LegalMoveGenerator.allLegalMoves(in: afterMove)).map { reply in
                let afterReply = afterMove.applyingUnchecked(reply)
                let checkingPieces = ModelCoachingPositionEncoder.orderedSquares(
                    LegalMoveGenerator.checkingPieceSquares(against: learner, in: afterReply.board)
                ).compactMap { checkerSquare -> String? in
                    checkingPieceReference(
                        at: checkerSquare,
                        after: reply,
                        in: afterMove
                    )
                }.sorted()
                let estimate = evaluator.captureEstimate(for: reply, in: afterMove)
                let capturedPieceReference = estimate.map {
                    ModelCoachingPositionEncoder.pieceID($0.capturedPiece, at: $0.capturedSquare)
                }
                let replyID = ModelCoachingPositionEncoder.moveID(reply)
                return ModelCoachingReplyReference(
                    id: "reply:\(moveReference.id)->\(replyID)",
                    afterMoveReference: moveReference.id,
                    replyMoveReference: replyID,
                    checkingPieceReferences: checkingPieces,
                    capturedPieceReference: capturedPieceReference,
                    netMaterialGain: estimate?.netGainForMover
                )
            }
        }.sorted { $0.id < $1.id }
    }

    private static func tacticalFacts(
        for evaluation: CoachingEvaluation,
        in state: GameState,
        pieceIDsBySquare: [String: String]
    ) -> [ModelCoachingTacticalFact] {
        var facts: [ModelCoachingTacticalFact] = []
        let checkingPieces = ModelCoachingPositionEncoder.orderedSquares(evaluation.checkingPieces).compactMap {
            pieceIDsBySquare[ModelCoachingPositionEncoder.squareName($0)]
        }.sorted()
        if !checkingPieces.isEmpty {
            facts.append(ModelCoachingTacticalFact(
                id: "fact:in-check",
                kind: .inCheck,
                subjectReferences: checkingPieces,
                integerValue: nil
            ))
        }

        switch state.result {
        case .checkmate(let winner):
            facts.append(ModelCoachingTacticalFact(
                id: "fact:checkmate:\(winner.rawValue)",
                kind: .checkmate,
                subjectReferences: [],
                integerValue: nil
            ))
        case .stalemate:
            facts.append(ModelCoachingTacticalFact(
                id: "fact:stalemate",
                kind: .stalemate,
                subjectReferences: [],
                integerValue: nil
            ))
        case .ongoing:
            break
        }

        for problem in evaluation.dangerProblems {
            guard let targetID = pieceIDsBySquare[ModelCoachingPositionEncoder.squareName(problem.target)] else {
                continue
            }
            facts.append(ModelCoachingTacticalFact(
                id: "fact:danger-loss:\(targetID)",
                kind: .dangerLoss,
                subjectReferences: [targetID],
                integerValue: -problem.worstEstimatedLoss
            ))
        }

        if evaluation.dangerProblems.isEmpty {
            facts.append(ModelCoachingTacticalFact(
                id: "fact:no-immediate-danger",
                kind: .noImmediateDanger,
                subjectReferences: [],
                integerValue: nil
            ))
        }

        for estimate in evaluation.learnerCaptureEstimates where estimate.netGainForMover != 0 {
            let moveID = ModelCoachingPositionEncoder.moveID(estimate.move)
            let captureID = ModelCoachingPositionEncoder.pieceID(
                estimate.capturedPiece,
                at: estimate.capturedSquare
            )
            facts.append(ModelCoachingTacticalFact(
                id: "fact:exchange-gain:\(moveID)",
                kind: .exchangeGain,
                subjectReferences: [moveID, captureID].sorted(),
                integerValue: estimate.netGainForMover
            ))
        }
        if !evaluation.learnerCaptureEstimates.contains(where: { $0.netGainForMover >= 1 }) {
            facts.append(ModelCoachingTacticalFact(
                id: "fact:no-useful-safe-capture",
                kind: .noUsefulSafeCapture,
                subjectReferences: [],
                integerValue: nil
            ))
        }

        for move in ModelCoachingPositionEncoder.orderedMoves(evaluation.mateInOneMoves) {
            let moveID = ModelCoachingPositionEncoder.moveID(move)
            facts.append(ModelCoachingTacticalFact(
                id: "fact:mate-in-one:\(moveID)",
                kind: .mateInOne,
                subjectReferences: [moveID],
                integerValue: nil
            ))
        }

        return facts.sorted { $0.id < $1.id }
    }

    private static func moveConsequences(
        for moveReferences: [ModelCoachingMoveReference],
        evaluation: CoachingEvaluation,
        in state: GameState,
        learner: PieceColor
    ) -> [ModelCoachingMoveConsequence] {
        moveReferences.compactMap { moveReference in
            guard let move = move(from: moveReference, learner: learner, in: state),
                  let assessment = evaluation.moveAssessments[move] else {
                return nil
            }
            let revisableIssues = assessment.opponentIssues.filter {
                $0.severity == .reviseMove
            }
            let categorizedReplies = revisableIssues.map { issue in
                (
                    kind: modelIssueKind(for: issue),
                    reference: "reply:\(moveReference.id)->\(ModelCoachingPositionEncoder.moveID(issue.reply))"
                )
            }.sorted {
                ($0.kind.rawValue, $0.reference) < ($1.kind.rawValue, $1.reference)
            }
            let issueKinds = Array(Set(categorizedReplies.map(\.kind))).sorted {
                $0.rawValue < $1.rawValue
            }
            var seenReplyReferences: Set<String> = []
            let replyReferences = categorizedReplies.compactMap { categorized in
                seenReplyReferences.insert(categorized.reference).inserted
                    ? categorized.reference
                    : nil
            }
            let worstEstimatedLoss = assessment.opponentActivities
                .compactMap(\.netGainForOpponent)
                .filter { $0 > 0 }
                .max() ?? 0

            return ModelCoachingMoveConsequence(
                id: "consequence:\(moveReference.id)",
                moveReference: moveReference.id,
                isLegal: assessment.isLegal,
                issueKinds: issueKinds,
                criticalReplyReferences: Array(replyReferences.prefix(2)),
                worstEstimatedLoss: worstEstimatedLoss
            )
        }.sorted { $0.id < $1.id }
    }

    private static func modelIssueKind(
        for issue: CoachingOpponentIssue
    ) -> ModelCoachingMoveIssueKind {
        switch issue.kind {
        case .materialLoss:
            return .materialLoss
        case .check:
            return .allowsCheck
        case .mateInOne:
            return .allowsMateInOne
        }
    }

    private static func gameHistory(from moves: [Move]) -> [ModelCoachingHistoryMove] {
        let notation = MoveHistoryFormatter.notation(for: moves)
        return zip(moves, notation).enumerated().map { index, pair in
            ModelCoachingHistoryMove(
                ply: index + 1,
                canonicalMove: ModelCoachingPositionEncoder.canonicalMove(pair.0),
                displayNotation: pair.1
            )
        }
    }

    private static func interaction(
        snapshot: ModelCoachingSnapshot,
        state: GameState,
        pieceIDsBySquare: [String: String]
    ) -> ModelCoachingInteraction {
        let currentTentativeMove = tentativeMove(from: snapshot)
        let selectedSquare = currentTentativeMove?.from ?? snapshot.interaction.selectedSquare
        let selectedPiece = selectedSquare.flatMap {
            pieceIDsBySquare[ModelCoachingPositionEncoder.squareName($0)]
        }
        let tentativeMove = currentTentativeMove.flatMap { move in
            state.board[move.from] == nil ? nil : ModelCoachingPositionEncoder.moveID(move)
        }
        return ModelCoachingInteraction(
            selectedPieceReference: selectedPiece,
            tentativeMoveReference: tentativeMove,
            latestEvent: snapshot.latestEvent,
            availableOperationReferences: snapshot.availableOperations
        )
    }

    private static func checkingPieceReference(
        at checkerSquare: Square,
        after move: Move,
        in stateBeforeMove: GameState
    ) -> String? {
        let sourceSquare: Square
        if checkerSquare == move.to {
            sourceSquare = move.from
        } else {
            switch move.special {
            case .castleKingside where checkerSquare == Square(file: .f, rank: move.from.rank):
                sourceSquare = Square(file: .h, rank: move.from.rank)
            case .castleQueenside where checkerSquare == Square(file: .d, rank: move.from.rank):
                sourceSquare = Square(file: .a, rank: move.from.rank)
            case .castleKingside, .castleQueenside, .enPassant, .promotion, nil:
                sourceSquare = checkerSquare
            }
        }

        guard let checkerPiece = stateBeforeMove.board[sourceSquare] else { return nil }
        return ModelCoachingPositionEncoder.pieceID(checkerPiece, at: sourceSquare)
    }

    private static func permittedReferences(
        operations: [ModelCoachingOperation],
        pieces: [ModelCoachingPieceReference],
        moves: [ModelCoachingMoveReference],
        relationships: [ModelCoachingRelationshipReference],
        replies: [ModelCoachingReplyReference],
        tacticalFacts: [ModelCoachingTacticalFact]
    ) -> ModelCoachingPermittedReferences {
        ModelCoachingPermittedReferences(
            actions: operations.compactMap(permittedAction(for:)),
            boardTasks: operations.compactMap(permittedBoardTask(for:)),
            boardFocus: pieces.map(\.id).sorted(),
            relationships: relationships.map(\.id).sorted(),
            evidence: (moves.map(\.id) + replies.map(\.id) + tacticalFacts.map(\.id)).sorted()
        )
    }

    private static func permittedAction(
        for operation: ModelCoachingOperation
    ) -> ModelCoachingPermittedAction? {
        let kind: ModelCoachingActionKind
        switch operation {
        case .hint: kind = .hint
        case .noPieceNeedsHelp: kind = .noPieceNeedsHelp
        case .noSafeCapture: kind = .noSafeCapture
        case .looksSafe: kind = .looksSafe
        case .playMove: kind = .playMove
        case .tryAnotherMove: kind = .tryAnotherMove
        case .closeHelp: kind = .closeHelp
        case .selectBoardPiece, .inspectSquare, .stageMove, .replaceMove, .removeMove:
            return nil
        }
        return ModelCoachingPermittedAction(
            id: "action:\(operation.rawValue)",
            kind: kind,
            title: operation.rawValue
        )
    }

    private static func permittedBoardTask(
        for operation: ModelCoachingOperation
    ) -> ModelCoachingPermittedBoardTask? {
        let kind: ModelCoachingBoardTaskKind
        switch operation {
        case .selectBoardPiece: kind = .identifyPiece
        case .inspectSquare: kind = .inspectRelationship
        case .stageMove, .replaceMove, .removeMove: kind = .movePiece
        case .playMove: kind = .confirmMove
        case .hint, .noPieceNeedsHelp, .noSafeCapture, .looksSafe, .tryAnotherMove, .closeHelp:
            return nil
        }
        return ModelCoachingPermittedBoardTask(id: "task:\(operation.rawValue)", kind: kind)
    }

    private static func tentativeMove(from snapshot: ModelCoachingSnapshot) -> Move? {
        snapshot.interaction.tentativeMove ?? snapshot.coachingRequest.tentativeMove
    }

    private static func move(
        from reference: ModelCoachingMoveReference,
        learner: PieceColor,
        in state: GameState
    ) -> Move? {
        state.board.pieces.keys.flatMap {
            LegalMoveGenerator.allowedMoves(for: $0, by: learner, in: state)
        }.first { ModelCoachingPositionEncoder.moveID($0) == reference.id }
    }

    private static func specialName(for special: Move.Special?) -> String {
        switch special {
        case .castleKingside: return "castle-kingside"
        case .castleQueenside: return "castle-queenside"
        case .enPassant: return "en-passant"
        case .promotion(let kind): return "promote-\(kind.rawValue)"
        case nil: return "none"
        }
    }

    private static func status(for result: GameResult) -> String {
        switch result {
        case .ongoing: return "active"
        case .checkmate: return "checkmate"
        case .stalemate: return "stalemate"
        }
    }
}

enum ModelCoachingNeutralRequestBuilder {
    static func build(
        snapshot: ModelCoachingNeutralSnapshot,
        requestID: String
    ) -> ModelCoachingNeutralRequest {
        let state = snapshot.committedState
        let selectedPiece = selectedCommittedPiece(for: snapshot, in: state)
        let pieces = pieceReferences(in: state)
        let pieceIDsBySquare = Dictionary(uniqueKeysWithValues: pieces.map { ($0.square, $0.id) })
        let legalMoves = moveReferences(
            moves: LegalMoveGenerator.allLegalMoves(in: state).filter { move in
                state.board[move.from]?.color == snapshot.learner
            },
            in: state
        )
        let tentativeMove = tentativeMoveReference(from: snapshot, in: state)

        return ModelCoachingNeutralRequest(
            schemaVersion: "model-coaching-neutral-request.v1",
            requestID: requestID,
            positionRevision: snapshot.positionRevision,
            position: ModelCoachingPosition(
                fen: ModelCoachingPositionEncoder.fen(for: state),
                sideToMove: state.sideToMove.rawValue,
                status: status(for: state.result)
            ),
            gameHistory: gameHistory(from: state.moveHistory),
            interaction: ModelCoachingNeutralInteraction(
                selectedSquare: snapshot.selectedSquare.map(ModelCoachingPositionEncoder.squareName),
                selectedPieceReference: selectedPiece.map { ModelCoachingPositionEncoder.pieceID($0.piece, at: $0.square) },
                tentativeMove: tentativeMove,
                latestEvent: snapshot.latestEvent,
                episodeEvents: snapshot.episodeEvents.sorted { $0.sequence < $1.sequence }
            ),
            pieces: pieces,
            legalMoves: legalMoves,
            occupiedSquareRelationships: relationshipReferences(
                in: state,
                pieceIDsBySquare: pieceIDsBySquare
            ),
            tentativeReplies: tentativeReplies(for: snapshot, in: state),
            capabilities: capabilities(
                selectedPiece: selectedPiece,
                learner: snapshot.learner,
                hasTentativeMove: tentativeMove != nil
            )
        )
    }

    private static func pieceReferences(in state: GameState) -> [ModelCoachingNeutralPiece] {
        state.board.pieces.keys.compactMap { square in
            guard let piece = state.board[square] else { return nil }
            return ModelCoachingNeutralPiece(
                id: ModelCoachingPositionEncoder.pieceID(piece, at: square),
                color: piece.color.rawValue,
                kind: piece.kind.rawValue,
                square: ModelCoachingPositionEncoder.squareName(square)
            )
        }.sorted { $0.id < $1.id }
    }

    private static func moveReferences(
        moves: [Move],
        in state: GameState
    ) -> [ModelCoachingNeutralMove] {
        moves.compactMap { move in
            moveReference(for: move, in: state, isLegal: true)
        }.sorted { $0.id < $1.id }
    }

    private static func tentativeMoveReference(
        from snapshot: ModelCoachingNeutralSnapshot,
        in state: GameState
    ) -> ModelCoachingNeutralMove? {
        guard let move = snapshot.tentativeMove else {
            return nil
        }
        let isLegal = LegalMoveGenerator.legalMoves(
            for: move.from,
            by: snapshot.learner,
            in: state
        ).contains(move)
        return moveReference(for: move, in: state, isLegal: isLegal)
    }

    private static func moveReference(
        for move: Move,
        in state: GameState,
        isLegal: Bool
    ) -> ModelCoachingNeutralMove? {
        guard let sourcePiece = state.board[move.from] else {
            return nil
        }
        let capture = LegalMoveGenerator.capture(for: move, in: state)
        let outcome = appliedOutcome(for: move, in: state)

        return ModelCoachingNeutralMove(
            id: ModelCoachingPositionEncoder.moveID(move),
            san: notation(for: move, in: state),
            canonicalMove: ModelCoachingPositionEncoder.canonicalMove(move),
            sourcePieceReference: ModelCoachingPositionEncoder.pieceID(sourcePiece, at: move.from),
            destinationSquare: ModelCoachingPositionEncoder.squareName(move.to),
            capturePieceReference: capture.map {
                ModelCoachingPositionEncoder.pieceID($0.piece, at: $0.square)
            },
            special: specialName(for: move.special),
            isLegal: isLegal,
            givesCheck: outcome.givesCheck,
            givesCheckmate: outcome.givesCheckmate
        )
    }

    private static func relationshipReferences(
        in state: GameState,
        pieceIDsBySquare: [String: String]
    ) -> [ModelCoachingNeutralRelationship] {
        var relationships: [ModelCoachingNeutralRelationship] = []

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
                relationships.append(
                    relationship(
                        kind: kind,
                        source: sourceID,
                        target: targetID
                    )
                )
                if targetPiece.kind == .king, targetPiece.color != sourcePiece.color {
                    relationships.append(
                        relationship(
                            kind: .checks,
                            source: sourceID,
                            target: targetID
                        )
                    )
                }
            }
        }

        return relationships.sorted { $0.id < $1.id }
    }

    private static func relationship(
        kind: ModelCoachingRelationshipKind,
        source: String,
        target: String
    ) -> ModelCoachingNeutralRelationship {
        ModelCoachingNeutralRelationship(
            id: ModelCoachingPositionEncoder.relationshipID(kind: kind, source: source, target: target),
            kind: kind,
            sourcePieceReference: source,
            targetPieceReference: target
        )
    }

    private static func tentativeReplies(
        for snapshot: ModelCoachingNeutralSnapshot,
        in state: GameState
    ) -> [ModelCoachingNeutralReply] {
        guard let tentativeMove = snapshot.tentativeMove,
              LegalMoveGenerator.legalMoves(
                for: tentativeMove.from,
                by: snapshot.learner,
                in: state
              ).contains(tentativeMove) else {
            return []
        }

        let afterTentative = state.applyingUnchecked(tentativeMove)
        return LegalMoveGenerator.allLegalMoves(in: afterTentative).compactMap { reply in
                guard let reference = moveReference(for: reply, in: afterTentative, isLegal: true) else {
                    return nil
                }
                if reference.capturePieceReference != nil || reference.givesCheck || reference.givesCheckmate {
                    return reference
                }
                return nil
            }.sorted { $0.id < $1.id }
    }

    private static func capabilities(
        selectedPiece: (square: Square, piece: Piece)?,
        learner: PieceColor,
        hasTentativeMove: Bool
    ) -> ModelCoachingNeutralCapabilities {
        ModelCoachingNeutralCapabilities(
            canSelectBoardPiece: true,
            canInspectSquare: true,
            canStageMove: selectedPiece?.piece.color == learner && !hasTentativeMove,
            canReplaceMove: hasTentativeMove,
            canRemoveMove: hasTentativeMove
        )
    }

    private static func selectedCommittedPiece(
        for snapshot: ModelCoachingNeutralSnapshot,
        in state: GameState
    ) -> (square: Square, piece: Piece)? {
        let lookupSquare = snapshot.tentativeMove?.from ?? snapshot.selectedSquare
        guard let lookupSquare,
              let piece = state.board[lookupSquare] else {
            return nil
        }
        return (lookupSquare, piece)
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

    private static func status(for result: GameResult) -> String {
        switch result {
        case .ongoing:
            return "ongoing"
        case .checkmate(let winner):
            return "checkmate:\(winner.rawValue)"
        case .stalemate:
            return "stalemate"
        }
    }

    private static func appliedOutcome(
        for move: Move,
        in state: GameState
    ) -> (givesCheck: Bool, givesCheckmate: Bool) {
        var next = state
        next.apply(move)
        let givesCheckmate: Bool
        if case .checkmate = next.result {
            givesCheckmate = true
        } else {
            givesCheckmate = false
        }
        let givesCheck = givesCheckmate || LegalMoveGenerator.isKingInCheck(next.sideToMove, in: next.board)
        return (givesCheck, givesCheckmate)
    }

    private static func specialName(for special: Move.Special?) -> String {
        switch special {
        case .castleKingside:
            return "castle-kingside"
        case .castleQueenside:
            return "castle-queenside"
        case .enPassant:
            return "en-passant"
        case .promotion(let kind):
            return "promote-\(kind.rawValue)"
        case nil:
            return "none"
        }
    }

    private static func notation(
        for move: Move,
        in state: GameState
    ) -> String {
        MoveHistoryFormatter.notation(for: state.moveHistory + [move]).last
            ?? ModelCoachingPositionEncoder.canonicalMove(move)
    }
}

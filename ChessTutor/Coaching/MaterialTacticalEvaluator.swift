struct MaterialTacticalEvaluator: Sendable {
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

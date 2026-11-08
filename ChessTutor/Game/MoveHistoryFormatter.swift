struct MoveHistoryRow: Equatable, Identifiable, Sendable {
    let number: Int
    let whiteMove: String
    let blackMove: String?

    var id: Int { number }

    var displayText: String {
        if let blackMove {
            return "\(number). \(whiteMove)  \(blackMove)"
        }
        return "\(number). \(whiteMove)"
    }
}

enum MoveHistoryFormatter {
    static func notation(for moves: [Move]) -> [String] {
        notationByMove(for: moves)
    }

    static func notation(for move: Move, in state: GameState) -> String {
        switch move.special {
        case .castleKingside:
            return "O-O\(checkSuffix(after: move, in: state))"
        case .castleQueenside:
            return "O-O-O\(checkSuffix(after: move, in: state))"
        case .promotion, .enPassant, nil:
            break
        }

        guard let piece = state.board[move.from] else {
            return "\(move.from.notation)-\(move.to.notation)"
        }

        let isCapture = LegalMoveGenerator.capture(for: move, in: state) != nil
        let piecePrefix = piece.kind == .pawn ? "" : pieceLetter(for: piece.kind)
        let disambiguation = piece.kind == .pawn
            ? (isCapture ? "\(move.from.file)" : "")
            : disambiguation(for: move, piece: piece, in: state)
        let capture = isCapture ? "x" : ""
        let promotion = promotionSuffix(for: move.special)

        return "\(piecePrefix)\(disambiguation)\(capture)\(move.to.notation)\(promotion)\(checkSuffix(after: move, in: state))"
    }

    static func rows(for moves: [Move]) -> [MoveHistoryRow] {
        let notation = notationByMove(for: moves)

        return stride(from: 0, to: moves.count, by: 2).map { index in
            MoveHistoryRow(
                number: (index / 2) + 1,
                whiteMove: notation[index],
                blackMove: notation.indices.contains(index + 1) ? notation[index + 1] : nil
            )
        }
    }

    private static func notationByMove(for moves: [Move]) -> [String] {
        var state = GameState.startingPosition()
        return moves.map { move in
            let notation = notation(for: move, in: state)
            state.apply(move)
            return notation
        }
    }

    private static func disambiguation(for move: Move, piece: Piece, in state: GameState) -> String {
        let competingMoves = LegalMoveGenerator.allLegalMoves(in: state).filter { candidate in
            guard candidate.from != move.from,
                  candidate.to == move.to,
                  let candidatePiece = state.board[candidate.from] else {
                return false
            }
            return candidatePiece == piece
        }

        guard !competingMoves.isEmpty else {
            return ""
        }

        let sameFileExists = competingMoves.contains { $0.from.file == move.from.file }
        let sameRankExists = competingMoves.contains { $0.from.rank == move.from.rank }

        if !sameFileExists {
            return "\(move.from.file)"
        }
        if !sameRankExists {
            return "\(move.from.rank)"
        }
        return "\(move.from.file)\(move.from.rank)"
    }

    private static func promotionSuffix(for special: Move.Special?) -> String {
        guard case .promotion(let kind) = special else {
            return ""
        }
        return "=\(pieceLetter(for: kind))"
    }

    private static func checkSuffix(after move: Move, in state: GameState) -> String {
        var next = state
        next.apply(move)
        switch next.result {
        case .checkmate:
            return "#"
        case .stalemate:
            return ""
        case .ongoing:
            return LegalMoveGenerator.isKingInCheck(next.sideToMove, in: next.board) ? "+" : ""
        }
    }

    private static func pieceLetter(for kind: Piece.Kind) -> String {
        switch kind {
        case .king: "K"
        case .queen: "Q"
        case .rook: "R"
        case .bishop: "B"
        case .knight: "N"
        case .pawn: ""
        }
    }
}

private extension Square {
    var notation: String {
        "\(file)\(rank)"
    }
}

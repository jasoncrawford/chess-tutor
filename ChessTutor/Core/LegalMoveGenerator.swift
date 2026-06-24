enum LegalMoveGenerator {
    static func legalMoves(for square: Square, in state: GameState) -> [Move] {
        guard let piece = state.board[square], piece.color == state.sideToMove else {
            return []
        }
        return pseudoLegalMoves(for: square, piece: piece, board: state.board)
            .filter { move in
                let nextState = state.applyingUnchecked(move)
                return !isKingInCheck(piece.color, in: nextState.board)
            }
    }

    static func allLegalMoves(in state: GameState) -> [Move] {
        state.board.pieces.keys.flatMap { legalMoves(for: $0, in: state) }
    }

    static func isKingInCheck(_ color: PieceColor, in board: Board) -> Bool {
        guard let kingSquare = board.pieces.first(where: { $0.value == Piece(kind: .king, color: color) })?.key else {
            return false
        }
        return board.pieces.contains { square, piece in
            piece.color != color && pseudoLegalMoves(for: square, piece: piece, board: board).contains { $0.to == kingSquare }
        }
    }

    private static func pseudoLegalMoves(for square: Square, piece: Piece, board: Board) -> [Move] {
        switch piece.kind {
        case .pawn:
            return pawnMoves(from: square, piece: piece, board: board)
        case .knight:
            return jumpMoves(from: square, piece: piece, board: board, deltas: [
                (1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)
            ])
        case .bishop:
            return slidingMoves(from: square, piece: piece, board: board, directions: [(1, 1), (1, -1), (-1, 1), (-1, -1)])
        case .rook:
            return slidingMoves(from: square, piece: piece, board: board, directions: [(1, 0), (-1, 0), (0, 1), (0, -1)])
        case .queen:
            return slidingMoves(from: square, piece: piece, board: board, directions: [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)])
        case .king:
            return jumpMoves(from: square, piece: piece, board: board, deltas: [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)])
        }
    }

    private static func pawnMoves(from square: Square, piece: Piece, board: Board) -> [Move] {
        let direction = piece.color == .white ? 1 : -1
        let startRank = piece.color == .white ? 2 : 7
        var moves: [Move] = []

        if let oneForward = square.offset(fileDelta: 0, rankDelta: direction), board[oneForward] == nil {
            moves.append(Move(from: square, to: oneForward))
            if square.rank == startRank,
               let twoForward = square.offset(fileDelta: 0, rankDelta: direction * 2),
               board[twoForward] == nil {
                moves.append(Move(from: square, to: twoForward))
            }
        }

        for fileDelta in [-1, 1] {
            guard let capture = square.offset(fileDelta: fileDelta, rankDelta: direction),
                  let target = board[capture],
                  target.color != piece.color else { continue }
            moves.append(Move(from: square, to: capture))
        }

        return moves
    }

    private static func jumpMoves(from square: Square, piece: Piece, board: Board, deltas: [(Int, Int)]) -> [Move] {
        deltas.compactMap { fileDelta, rankDelta in
            guard let target = square.offset(fileDelta: fileDelta, rankDelta: rankDelta) else { return nil }
            if let occupant = board[target], occupant.color == piece.color { return nil }
            return Move(from: square, to: target)
        }
    }

    private static func slidingMoves(from square: Square, piece: Piece, board: Board, directions: [(Int, Int)]) -> [Move] {
        var moves: [Move] = []
        for direction in directions {
            var current = square
            while let next = current.offset(fileDelta: direction.0, rankDelta: direction.1) {
                if let occupant = board[next] {
                    if occupant.color != piece.color {
                        moves.append(Move(from: square, to: next))
                    }
                    break
                }
                moves.append(Move(from: square, to: next))
                current = next
            }
        }
        return moves
    }
}

enum LegalMoveGenerator {
    private static let knightDeltas = [
        (1, 2), (2, 1), (2, -1), (1, -2),
        (-1, -2), (-2, -1), (-2, 1), (-1, 2),
    ]
    private static let bishopDirections = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    private static let rookDirections = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    private static let kingDeltas = [
        (1, 0), (-1, 0), (0, 1), (0, -1),
        (1, 1), (1, -1), (-1, 1), (-1, -1),
    ]

    static func capture(for move: Move, in state: GameState) -> MoveCapture? {
        let capturedSquare: Square
        if move.special == .enPassant {
            capturedSquare = Square(file: move.to.file, rank: move.from.rank)
        } else {
            capturedSquare = move.to
        }

        return state.board[capturedSquare].map {
            MoveCapture(square: capturedSquare, piece: $0)
        }
    }

    static func allowedMoves(for square: Square, in state: GameState) -> [Move] {
        allowedMoves(for: square, by: state.sideToMove, in: state)
    }

    static func allowedMoves(
        for square: Square,
        by color: PieceColor,
        in state: GameState
    ) -> [Move] {
        guard let piece = state.board[square], piece.color == color else {
            return []
        }
        return pseudoLegalMoves(for: square, piece: piece, in: state)
    }

    static func legalMoves(for square: Square, in state: GameState) -> [Move] {
        legalMoves(for: square, by: state.sideToMove, in: state)
    }

    static func legalMoves(
        for square: Square,
        by color: PieceColor,
        in state: GameState
    ) -> [Move] {
        guard state.board[square]?.color == color else {
            return []
        }
        return allowedMoves(for: square, by: color, in: state).filter { move in
            !isKingInCheck(color, in: state.applyingUnchecked(move).board)
        }
    }

    static func allLegalMoves(in state: GameState) -> [Move] {
        state.board.pieces.keys.flatMap { legalMoves(for: $0, in: state) }
    }

    static func kingSquare(for color: PieceColor, in board: Board) -> Square? {
        board.pieces.first(where: { $0.value == Piece(kind: .king, color: color) })?.key
    }

    static func isKingInCheck(_ color: PieceColor, in board: Board) -> Bool {
        !checkingPieceSquares(against: color, in: board).isEmpty
    }

    static func checkingPieceSquares(against color: PieceColor, in board: Board) -> Set<Square> {
        guard let kingSquare = kingSquare(for: color, in: board) else {
            preconditionFailure("Cannot determine check state: missing \(color.rawValue) king")
        }
        return Set(board.pieces.compactMap { square, piece in
            piece.color != color
                && attacks(square: kingSquare, from: square, piece: piece, board: board)
                ? square
                : nil
        })
    }

    static func controlledSquares(
        for square: Square,
        by color: PieceColor,
        in state: GameState
    ) -> Set<Square> {
        guard let piece = state.board[square], piece.color == color else {
            return []
        }
        return controlledSquares(from: square, piece: piece, board: state.board)
    }

    static func controlledSquares(from square: Square, in state: GameState) -> Set<Square> {
        guard let piece = state.board[square] else {
            return []
        }
        return controlledSquares(from: square, piece: piece, board: state.board)
    }

    static func legalSupportTargets(
        for square: Square,
        by color: PieceColor,
        in state: GameState
    ) -> Set<Square> {
        guard state.board[square]?.color == color else {
            return []
        }

        return Set(controlledSquares(for: square, by: color, in: state).filter { target in
            guard let occupant = state.board[target],
                  occupant.color == color,
                  occupant.kind != .king else {
                return false
            }

            var captureState = state
            captureState.board[target] = Piece(kind: occupant.kind, color: color.opposite)
            return legalMoves(for: square, by: color, in: captureState).contains { move in
                move.to == target
            }
        })
    }

    private static func pseudoLegalMoves(for square: Square, piece: Piece, in state: GameState) -> [Move] {
        var moves = pseudoLegalMoves(for: square, piece: piece, board: state.board)
        if piece.kind == .pawn, piece.color == state.sideToMove {
            moves += enPassantMoves(from: square, piece: piece, state: state)
        }
        if piece.kind == .king {
            moves += castlingMoves(from: square, piece: piece, state: state)
        }
        return moves
    }

    private static func pseudoLegalMoves(for square: Square, piece: Piece, board: Board, includesKingTargets: Bool = false) -> [Move] {
        switch piece.kind {
        case .pawn:
            return pawnMoves(from: square, piece: piece, board: board, includesKingTargets: includesKingTargets)
        case .knight:
            return jumpMoves(
                from: square,
                piece: piece,
                board: board,
                deltas: knightDeltas,
                includesKingTargets: includesKingTargets
            )
        case .bishop:
            return slidingMoves(
                from: square,
                piece: piece,
                board: board,
                directions: bishopDirections,
                includesKingTargets: includesKingTargets
            )
        case .rook:
            return slidingMoves(
                from: square,
                piece: piece,
                board: board,
                directions: rookDirections,
                includesKingTargets: includesKingTargets
            )
        case .queen:
            return slidingMoves(
                from: square,
                piece: piece,
                board: board,
                directions: rookDirections + bishopDirections,
                includesKingTargets: includesKingTargets
            )
        case .king:
            return jumpMoves(
                from: square,
                piece: piece,
                board: board,
                deltas: kingDeltas,
                includesKingTargets: includesKingTargets
            )
        }
    }

    private static func controlledSquares(from square: Square, piece: Piece, board: Board) -> Set<Square> {
        switch piece.kind {
        case .pawn:
            let direction = piece.color == .white ? 1 : -1
            return Set([-1, 1].compactMap { fileDelta in
                square.offset(fileDelta: fileDelta, rankDelta: direction)
            })
        case .knight:
            return jumpControlSquares(from: square, deltas: knightDeltas)
        case .bishop:
            return slidingControlSquares(from: square, board: board, directions: bishopDirections)
        case .rook:
            return slidingControlSquares(from: square, board: board, directions: rookDirections)
        case .queen:
            return slidingControlSquares(
                from: square,
                board: board,
                directions: rookDirections + bishopDirections
            )
        case .king:
            return jumpControlSquares(from: square, deltas: kingDeltas)
        }
    }

    private static func jumpControlSquares(
        from square: Square,
        deltas: [(Int, Int)]
    ) -> Set<Square> {
        Set(deltas.compactMap { fileDelta, rankDelta in
            square.offset(fileDelta: fileDelta, rankDelta: rankDelta)
        })
    }

    private static func slidingControlSquares(
        from square: Square,
        board: Board,
        directions: [(Int, Int)]
    ) -> Set<Square> {
        var controlled: Set<Square> = []
        for direction in directions {
            var current = square
            while let next = current.offset(fileDelta: direction.0, rankDelta: direction.1) {
                controlled.insert(next)
                if board[next] != nil {
                    break
                }
                current = next
            }
        }
        return controlled
    }

    private static func pawnMoves(from square: Square, piece: Piece, board: Board, includesKingTargets: Bool = false) -> [Move] {
        let direction = piece.color == .white ? 1 : -1
        let startRank = piece.color == .white ? 2 : 7
        var moves: [Move] = []

        if let oneForward = square.offset(fileDelta: 0, rankDelta: direction), board[oneForward] == nil {
            appendPawnMove(from: square, to: oneForward, piece: piece, moves: &moves)
            if square.rank == startRank,
               let twoForward = square.offset(fileDelta: 0, rankDelta: direction * 2),
               board[twoForward] == nil {
                moves.append(Move(from: square, to: twoForward))
            }
        }

        for fileDelta in [-1, 1] {
            guard let capture = square.offset(fileDelta: fileDelta, rankDelta: direction),
                  let target = board[capture],
                  canCapture(target, with: piece, includesKingTargets: includesKingTargets) else { continue }
            appendPawnMove(from: square, to: capture, piece: piece, moves: &moves)
        }

        return moves
    }

    private static func appendPawnMove(from: Square, to: Square, piece: Piece, moves: inout [Move]) {
        let promotionRank = piece.color == .white ? 8 : 1
        guard to.rank == promotionRank else {
            moves.append(Move(from: from, to: to))
            return
        }
        for promotedKind in [Piece.Kind.queen, .rook, .bishop, .knight] {
            moves.append(Move(from: from, to: to, special: .promotion(promotedKind)))
        }
    }

    private static func enPassantMoves(from square: Square, piece: Piece, state: GameState) -> [Move] {
        guard let target = state.enPassantTarget else { return [] }
        let direction = piece.color == .white ? 1 : -1
        let requiredRank = piece.color == .white ? 5 : 4
        let capturedPawnSquare = Square(file: target.file, rank: square.rank)
        guard square.rank == requiredRank,
              state.board[target] == nil,
              state.board[capturedPawnSquare] == Piece(kind: .pawn, color: piece.color.opposite) else {
            return []
        }

        for fileDelta in [-1, 1] where square.offset(fileDelta: fileDelta, rankDelta: direction) == target {
            return [Move(from: square, to: target, special: .enPassant)]
        }
        return []
    }

    private static func castlingMoves(from square: Square, piece: Piece, state: GameState) -> [Move] {
        guard square == Square(file: .e, rank: piece.color == .white ? 1 : 8),
              !isKingInCheck(piece.color, in: state.board) else {
            return []
        }

        let rank = square.rank
        var moves: [Move] = []
        if canCastleKingside(piece: piece, rank: rank, state: state) {
            moves.append(Move(from: square, to: Square(file: .g, rank: rank), special: .castleKingside))
        }
        if canCastleQueenside(piece: piece, rank: rank, state: state) {
            moves.append(Move(from: square, to: Square(file: .c, rank: rank), special: .castleQueenside))
        }
        return moves
    }

    private static func canCastleKingside(piece: Piece, rank: Int, state: GameState) -> Bool {
        let hasRight = piece.color == .white ? state.castlingRights.whiteKingside : state.castlingRights.blackKingside
        guard hasRight,
              state.board[Square(file: .h, rank: rank)] == Piece(kind: .rook, color: piece.color),
              state.board[Square(file: .f, rank: rank)] == nil,
              state.board[Square(file: .g, rank: rank)] == nil else {
            return false
        }
        return !isSquareAttacked(Square(file: .f, rank: rank), by: piece.color.opposite, board: state.board)
            && !isSquareAttacked(Square(file: .g, rank: rank), by: piece.color.opposite, board: state.board)
    }

    private static func canCastleQueenside(piece: Piece, rank: Int, state: GameState) -> Bool {
        let hasRight = piece.color == .white ? state.castlingRights.whiteQueenside : state.castlingRights.blackQueenside
        guard hasRight,
              state.board[Square(file: .a, rank: rank)] == Piece(kind: .rook, color: piece.color),
              state.board[Square(file: .b, rank: rank)] == nil,
              state.board[Square(file: .c, rank: rank)] == nil,
              state.board[Square(file: .d, rank: rank)] == nil else {
            return false
        }
        return !isSquareAttacked(Square(file: .d, rank: rank), by: piece.color.opposite, board: state.board)
            && !isSquareAttacked(Square(file: .c, rank: rank), by: piece.color.opposite, board: state.board)
    }

    private static func jumpMoves(from square: Square, piece: Piece, board: Board, deltas: [(Int, Int)], includesKingTargets: Bool = false) -> [Move] {
        deltas.compactMap { fileDelta, rankDelta in
            guard let target = square.offset(fileDelta: fileDelta, rankDelta: rankDelta) else { return nil }
            if let occupant = board[target], !canCapture(occupant, with: piece, includesKingTargets: includesKingTargets) { return nil }
            return Move(from: square, to: target)
        }
    }

    private static func slidingMoves(from square: Square, piece: Piece, board: Board, directions: [(Int, Int)], includesKingTargets: Bool = false) -> [Move] {
        var moves: [Move] = []
        for direction in directions {
            var current = square
            while let next = current.offset(fileDelta: direction.0, rankDelta: direction.1) {
                if let occupant = board[next] {
                    if canCapture(occupant, with: piece, includesKingTargets: includesKingTargets) {
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

    private static func canCapture(_ target: Piece, with piece: Piece, includesKingTargets: Bool = false) -> Bool {
        target.color != piece.color && (includesKingTargets || target.kind != .king)
    }

    private static func isSquareAttacked(_ square: Square, by color: PieceColor, board: Board) -> Bool {
        board.pieces.contains { attackerSquare, piece in
            piece.color == color && attacks(square: square, from: attackerSquare, piece: piece, board: board)
        }
    }

    private static func attacks(square target: Square, from square: Square, piece: Piece, board: Board) -> Bool {
        controlledSquares(from: square, piece: piece, board: board).contains(target)
    }
}

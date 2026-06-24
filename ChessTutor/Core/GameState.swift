struct GameState: Equatable, Sendable {
    var board: Board
    var sideToMove: PieceColor
    var moveHistory: [Move]
    var result: GameResult

    init(board: Board, sideToMove: PieceColor, moveHistory: [Move] = [], result: GameResult = .ongoing) {
        self.board = board
        self.sideToMove = sideToMove
        self.moveHistory = moveHistory
        self.result = result
    }

    static func startingPosition() -> GameState {
        GameState(board: .startingPosition(), sideToMove: .white)
    }

    func applyingUnchecked(_ move: Move) -> GameState {
        var next = self
        let movingPiece = next.board[move.from]
        next.board[move.from] = nil
        next.board[move.to] = movingPiece
        next.moveHistory.append(move)
        next.sideToMove = sideToMove.opposite
        return next
    }

    mutating func apply(_ move: Move) {
        self = applyingUnchecked(move)
        let legalReplies = LegalMoveGenerator.allLegalMoves(in: self)
        if legalReplies.isEmpty {
            if LegalMoveGenerator.isKingInCheck(sideToMove, in: board) {
                result = .checkmate(winner: sideToMove.opposite)
            } else {
                result = .stalemate
            }
        } else {
            result = .ongoing
        }
    }
}

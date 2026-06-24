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
}

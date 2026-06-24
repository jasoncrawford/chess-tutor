enum GameResult: Equatable, Sendable {
    case ongoing
    case checkmate(winner: PieceColor)
    case stalemate
}

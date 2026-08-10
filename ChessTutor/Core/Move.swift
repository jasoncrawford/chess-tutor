struct Move: Equatable, Hashable, Sendable {
    enum Special: Equatable, Hashable, Sendable {
        case castleKingside
        case castleQueenside
        case enPassant
        case promotion(Piece.Kind)
    }

    let from: Square
    let to: Square
    let special: Special?

    init(from: Square, to: Square, special: Special? = nil) {
        self.from = from
        self.to = to
        self.special = special
    }
}

struct MoveCapture: Equatable, Hashable, Sendable {
    let square: Square
    let piece: Piece
}

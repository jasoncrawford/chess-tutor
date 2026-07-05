struct Piece: Equatable, Hashable, Sendable {
    enum Kind: String, Equatable, Hashable, Codable, Sendable {
        case king
        case queen
        case rook
        case bishop
        case knight
        case pawn
    }

    let kind: Kind
    let color: PieceColor
}

extension Piece {
    var assetName: String {
        "Piece\(color.assetNameComponent)\(kind.assetNameComponent)"
    }
}

private extension PieceColor {
    var assetNameComponent: String {
        switch self {
        case .white:
            "White"
        case .black:
            "Black"
        }
    }
}

private extension Piece.Kind {
    var assetNameComponent: String {
        switch self {
        case .king:
            "King"
        case .queen:
            "Queen"
        case .rook:
            "Rook"
        case .bishop:
            "Bishop"
        case .knight:
            "Knight"
        case .pawn:
            "Pawn"
        }
    }
}

enum PieceColor: String, Codable, Equatable, Hashable, Sendable {
    case white
    case black

    var opposite: PieceColor {
        self == .white ? .black : .white
    }
}

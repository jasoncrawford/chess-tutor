struct Board: Equatable, Sendable {
    private var storage: [Square: Piece]

    var pieces: [Square: Piece] {
        storage
    }

    init(pieces: [Square: Piece] = [:]) {
        self.storage = pieces
    }

    subscript(square: Square) -> Piece? {
        get { storage[square] }
        set { storage[square] = newValue }
    }

    static func startingPosition() -> Board {
        var board = Board()
        let backRank: [Piece.Kind] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
        for (index, file) in Square.File.allCases.enumerated() {
            board[Square(file: file, rank: 1)] = Piece(kind: backRank[index], color: .white)
            board[Square(file: file, rank: 2)] = Piece(kind: .pawn, color: .white)
            board[Square(file: file, rank: 7)] = Piece(kind: .pawn, color: .black)
            board[Square(file: file, rank: 8)] = Piece(kind: backRank[index], color: .black)
        }
        return board
    }
}

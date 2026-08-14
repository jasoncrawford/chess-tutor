@testable import ChessTutor

enum CoachingTestFixtures {
    static func state(
        sideToMove: PieceColor,
        pieces: [Square: Piece],
        castlingRights: CastlingRights = CastlingRights(),
        enPassantTarget: Square? = nil
    ) -> GameState {
        var pieces = pieces

        if !pieces.values.contains(where: { $0 == Piece(kind: .king, color: .white) }) {
            pieces[Square(file: .a, rank: 1)] = Piece(kind: .king, color: .white)
        }
        if !pieces.values.contains(where: { $0 == Piece(kind: .king, color: .black) }) {
            pieces[Square(file: .h, rank: 8)] = Piece(kind: .king, color: .black)
        }

        return GameState(
            board: Board(pieces: pieces),
            sideToMove: sideToMove,
            castlingRights: castlingRights,
            enPassantTarget: enPassantTarget
        )
    }
}

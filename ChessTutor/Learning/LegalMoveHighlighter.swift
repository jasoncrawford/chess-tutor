enum LegalMoveHighlighter {
    static func destinations(for moves: [Move]) -> Set<Square> {
        Set(moves.map(\.to))
    }
}

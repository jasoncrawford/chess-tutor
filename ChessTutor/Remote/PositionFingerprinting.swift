enum PositionFingerprinting {
    static func fingerprint(for state: GameState) -> PositionFingerprint {
        PositionFingerprint(rawValue: components(for: state).joined(separator: "|"))
    }

    private static func components(for state: GameState) -> [String] {
        [
            boardComponent(for: state.board),
            "turn:\(state.sideToMove.rawValue)",
            "castle:\(castlingComponent(for: state.castlingRights))",
            "ep:\(state.enPassantTarget.map(squareComponent) ?? "-")",
            "result:\(resultComponent(for: state.result))",
            "moves:\(state.moveHistory.count)",
        ]
    }

    private static func boardComponent(for board: Board) -> String {
        Square.File.allCases.flatMap { file in
            (1...8).map { rank in
                let square = Square(file: file, rank: rank)
                guard let piece = board[square] else {
                    return "\(squareComponent(square))=empty"
                }
                return "\(squareComponent(square))=\(piece.color.rawValue)-\(piece.kind.rawValue)"
            }
        }
        .joined(separator: ",")
    }

    private static func castlingComponent(for rights: CastlingRights) -> String {
        [
            rights.whiteKingside ? "K" : "-",
            rights.whiteQueenside ? "Q" : "-",
            rights.blackKingside ? "k" : "-",
            rights.blackQueenside ? "q" : "-",
        ].joined()
    }

    private static func resultComponent(for result: GameResult) -> String {
        switch result {
        case .ongoing:
            return "ongoing"
        case .checkmate(let winner):
            return "checkmate-\(winner.rawValue)"
        case .stalemate:
            return "stalemate"
        }
    }

    private static func squareComponent(_ square: Square) -> String {
        RemoteMoveCodec.encodeSquare(square)
    }
}

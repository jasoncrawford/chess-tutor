enum ModelCoachingPositionEncoder {
    static func fen(for state: GameState) -> String {
        let board = (1...8).reversed().map { rank in
            var emptySquares = 0
            var encoded = ""

            for file in Square.File.allCases {
                let square = Square(file: file, rank: rank)
                guard let piece = state.board[square] else {
                    emptySquares += 1
                    continue
                }
                if emptySquares > 0 {
                    encoded += "\(emptySquares)"
                    emptySquares = 0
                }
                encoded.append(fenToken(for: piece))
            }

            if emptySquares > 0 {
                encoded += "\(emptySquares)"
            }
            return encoded
        }.joined(separator: "/")

        let sideToMove = state.sideToMove == .white ? "w" : "b"
        let castling = castlingRights(for: state.castlingRights)
        let enPassant = state.enPassantTarget.map(squareName) ?? "-"
        let halfmove = halfmoveClock(for: state.moveHistory)
        let fullmove = (state.moveHistory.count / 2) + 1

        return "\(board) \(sideToMove) \(castling) \(enPassant) \(halfmove) \(fullmove)"
    }

    static func moveID(_ move: Move) -> String {
        let special: String
        switch move.special {
        case .castleKingside:
            special = ":castle-kingside"
        case .castleQueenside:
            special = ":castle-queenside"
        case .enPassant:
            special = ":en-passant"
        case .promotion(let kind):
            special = ":promote-\(kind.rawValue)"
        case nil:
            special = ""
        }
        return "move:\(squareName(move.from))-\(squareName(move.to))\(special)"
    }

    static func canonicalMove(_ move: Move) -> String {
        "\(squareName(move.from))\(squareName(move.to))\(promotionSuffix(for: move.special))"
    }

    static func pieceID(_ piece: Piece, at square: Square) -> String {
        "piece:\(piece.color.rawValue):\(piece.kind.rawValue):\(squareName(square))"
    }

    static func relationshipID(
        kind: ModelCoachingRelationshipKind,
        source: String,
        target: String
    ) -> String {
        "relationship:\(relationshipToken(for: kind)):\(source)->\(target)"
    }

    static func squareName(_ square: Square) -> String {
        "\(fileName(square.file))\(square.rank)"
    }

    static func orderedSquares(_ squares: some Sequence<Square>) -> [Square] {
        squares.sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return lhs.file.rawValue < rhs.file.rawValue
        }
    }

    static func orderedMoves(_ moves: some Sequence<Move>) -> [Move] {
        moves.sorted { lhs, rhs in
            let lhsKey = (lhs.from.rank, lhs.from.file.rawValue, lhs.to.rank, lhs.to.file.rawValue, moveID(lhs))
            let rhsKey = (rhs.from.rank, rhs.from.file.rawValue, rhs.to.rank, rhs.to.file.rawValue, moveID(rhs))
            return lhsKey < rhsKey
        }
    }

    private static func fenToken(for piece: Piece) -> Character {
        let token: Character
        switch piece.kind {
        case .king: token = "k"
        case .queen: token = "q"
        case .rook: token = "r"
        case .bishop: token = "b"
        case .knight: token = "n"
        case .pawn: token = "p"
        }
        return piece.color == .white ? Character(token.uppercased()) : token
    }

    private static func castlingRights(for rights: CastlingRights) -> String {
        let tokens = [
            rights.whiteKingside ? "K" : nil,
            rights.whiteQueenside ? "Q" : nil,
            rights.blackKingside ? "k" : nil,
            rights.blackQueenside ? "q" : nil,
        ].compactMap { $0 }.joined()
        return tokens.isEmpty ? "-" : tokens
    }

    private static func halfmoveClock(for moves: [Move]) -> Int {
        guard !moves.isEmpty else { return 0 }

        var replay = GameState.startingPosition()
        var clock = 0
        for move in moves {
            guard let movingPiece = replay.board[move.from] else {
                return 0
            }
            if movingPiece.kind == .pawn || LegalMoveGenerator.capture(for: move, in: replay) != nil {
                clock = 0
            } else {
                clock += 1
            }
            replay = replay.applyingUnchecked(move)
        }
        return clock
    }

    private static func fileName(_ file: Square.File) -> String {
        String(UnicodeScalar(file.rawValue + 96)!)
    }

    private static func promotionSuffix(for special: Move.Special?) -> String {
        guard case let .promotion(kind) = special else { return "" }
        switch kind {
        case .queen: return "q"
        case .rook: return "r"
        case .bishop: return "b"
        case .knight: return "n"
        case .king, .pawn: return ""
        }
    }

    private static func relationshipToken(for kind: ModelCoachingRelationshipKind) -> String {
        switch kind {
        case .attacks: return "attack"
        case .defends: return "defend"
        case .checks: return "check"
        case .canCapture: return "can-capture"
        case .canRecapture: return "can-recapture"
        }
    }
}

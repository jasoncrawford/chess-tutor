struct ThreatRelation: Equatable, Hashable, Sendable {
    let source: Square
    let target: Square
    let destination: Square
    let color: PieceColor
}

struct PositionAnalysis: Equatable, Sendable {
    let allowedMovesBySource: [Square: [Move]]
    let threatsByTarget: [Square: Set<ThreatRelation>]
    let supportersByTarget: [Square: Set<Square>]
    let coverageByColor: [PieceColor: Set<Square>]

    func allowedMoves(from square: Square) -> [Move] {
        allowedMovesBySource[square] ?? []
    }

    func threats(targeting square: Square) -> Set<ThreatRelation> {
        threatsByTarget[square] ?? []
    }

    func threats(from square: Square) -> Set<ThreatRelation> {
        Set(threatsByTarget.values.flatMap { $0 }.filter { $0.source == square })
    }

    func supporters(of square: Square) -> Set<Square> {
        supportersByTarget[square] ?? []
    }

    func coverage(for color: PieceColor) -> Set<Square> {
        coverageByColor[color] ?? []
    }

    var threatenedSquares: Set<Square> {
        Set(threatsByTarget.keys)
    }

    var defendedSquares: Set<Square> {
        Set(supportersByTarget.keys)
    }
}

enum PositionAnalyzer {
    static func analyze(_ state: GameState) -> PositionAnalysis {
        var allowedMovesBySource: [Square: [Move]] = [:]
        var threatsByTarget: [Square: Set<ThreatRelation>] = [:]
        var supportersByTarget: [Square: Set<Square>] = [:]
        var coverageByColor: [PieceColor: Set<Square>] = [
            .white: [],
            .black: [],
        ]

        for (source, piece) in state.board.pieces {
            let allowedMoves = LegalMoveGenerator.allowedMoves(
                for: source,
                by: piece.color,
                in: state
            )
            allowedMovesBySource[source] = allowedMoves
            coverageByColor[piece.color, default: []].formUnion(allowedMoves.map(\.to))
            coverageByColor[piece.color, default: []].formUnion(
                LegalMoveGenerator.controlledSquares(for: source, by: piece.color, in: state)
            )

            for move in LegalMoveGenerator.legalMoves(for: source, by: piece.color, in: state) {
                guard let capture = LegalMoveGenerator.capture(for: move, in: state) else {
                    continue
                }
                threatsByTarget[capture.square, default: []].insert(
                    ThreatRelation(
                        source: source,
                        target: capture.square,
                        destination: move.to,
                        color: piece.color
                    )
                )
            }

            for target in LegalMoveGenerator.legalSupportTargets(
                for: source,
                by: piece.color,
                in: state
            ) {
                supportersByTarget[target, default: []].insert(source)
            }
        }

        for kingColor in [PieceColor.white, .black] {
            guard let kingSquare = LegalMoveGenerator.kingSquare(for: kingColor, in: state.board) else {
                preconditionFailure("Cannot analyze position: missing \(kingColor.rawValue) king")
            }
            for source in LegalMoveGenerator.checkingPieceSquares(against: kingColor, in: state.board) {
                guard let attacker = state.board[source] else {
                    preconditionFailure("Cannot analyze check source without a piece")
                }
                threatsByTarget[kingSquare, default: []].insert(
                    ThreatRelation(
                        source: source,
                        target: kingSquare,
                        destination: kingSquare,
                        color: attacker.color
                    )
                )
            }
        }

        return PositionAnalysis(
            allowedMovesBySource: allowedMovesBySource,
            threatsByTarget: threatsByTarget,
            supportersByTarget: supportersByTarget,
            coverageByColor: coverageByColor
        )
    }
}

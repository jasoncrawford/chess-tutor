struct BoardGuidancePath: Equatable, Hashable, Sendable {
    enum Role: Equatable, Hashable, Sendable {
        case allowed
        case attacker
    }

    let source: Square
    let destination: Square
    let captureSquare: Square?
    let color: PieceColor
    let role: Role
}

struct BoardCoveragePresentation: Equatable, Sendable {
    let sideToMove: PieceColor
    let sideToMoveSquares: Set<Square>
    let otherSideSquares: Set<Square>
}

struct BoardGuidancePresentation: Equatable, Sendable {
    let sideToMove: PieceColor
    let threatenedSquares: Set<Square>
    let defendedSquares: Set<Square>
    let selectedSquare: Square?
    let selectedPaths: Set<BoardGuidancePath>
    let supporterSquares: Set<Square>
    let coverage: BoardCoveragePresentation?
    let emphasizedSquares: Set<Square>

    func markerOpacity(at square: Square) -> Double {
        selectedSquare == nil || emphasizedSquares.contains(square) ? 1 : 0.20
    }

    static func empty(sideToMove: PieceColor) -> BoardGuidancePresentation {
        BoardGuidancePresentation(
            sideToMove: sideToMove,
            threatenedSquares: [],
            defendedSquares: [],
            selectedSquare: nil,
            selectedPaths: [],
            supporterSquares: [],
            coverage: nil,
            emphasizedSquares: []
        )
    }

    static func make(
        state: GameState,
        analysis: PositionAnalysis,
        selectedSquare: Square?,
        showsSelectedReach: Bool,
        showsCoverage: Bool,
        keepsOnlyCheckmateKingThreat: Bool
    ) -> BoardGuidancePresentation {
        if keepsOnlyCheckmateKingThreat {
            let losingKing = LegalMoveGenerator.kingSquare(
                for: state.sideToMove,
                in: state.board
            )
            let threatenedSquares = losingKing.map { Set([$0]) } ?? []
            return BoardGuidancePresentation(
                sideToMove: state.sideToMove,
                threatenedSquares: threatenedSquares,
                defendedSquares: [],
                selectedSquare: selectedSquare,
                selectedPaths: [],
                supporterSquares: [],
                coverage: nil,
                emphasizedSquares: threatenedSquares
            )
        }

        var selectedPaths: Set<BoardGuidancePath> = []
        var supporterSquares: Set<Square> = []

        if let selectedSquare, let selectedPiece = state.board[selectedSquare] {
            if showsSelectedReach {
                for move in analysis.allowedMoves(from: selectedSquare) {
                    selectedPaths.insert(
                        BoardGuidancePath(
                            source: selectedSquare,
                            destination: move.to,
                            captureSquare: LegalMoveGenerator.capture(for: move, in: state)?.square,
                            color: selectedPiece.color,
                            role: .allowed
                        )
                    )
                }
            }

            for threat in analysis.threats(targeting: selectedSquare) {
                selectedPaths.insert(
                    BoardGuidancePath(
                        source: threat.source,
                        destination: threat.destination,
                        captureSquare: threat.target,
                        color: threat.color,
                        role: .attacker
                    )
                )
            }
            supporterSquares = analysis.supporters(of: selectedSquare)
        }

        var defendedSquares = analysis.defendedSquares
        for (square, piece) in state.board.pieces where piece.kind == .king {
            defendedSquares.remove(square)
        }

        var emphasizedSquares: Set<Square> = []
        if let selectedSquare {
            emphasizedSquares.insert(selectedSquare)
        }
        for path in selectedPaths {
            emphasizedSquares.insert(path.source)
            emphasizedSquares.insert(path.destination)
            if let captureSquare = path.captureSquare {
                emphasizedSquares.insert(captureSquare)
            }
        }
        emphasizedSquares.formUnion(supporterSquares)

        let coverage = showsCoverage
            ? BoardCoveragePresentation(
                sideToMove: state.sideToMove,
                sideToMoveSquares: analysis.coverage(for: state.sideToMove),
                otherSideSquares: analysis.coverage(for: state.sideToMove.opposite)
            )
            : nil

        return BoardGuidancePresentation(
            sideToMove: state.sideToMove,
            threatenedSquares: analysis.threatenedSquares,
            defendedSquares: defendedSquares,
            selectedSquare: selectedSquare,
            selectedPaths: selectedPaths,
            supporterSquares: supporterSquares,
            coverage: coverage,
            emphasizedSquares: emphasizedSquares
        )
    }
}

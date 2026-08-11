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
    let prominentThreatSquares: Set<Square>
    let defendedSquares: Set<Square>
    let visibleDefenseSquares: Set<Square>
    let selectedSquare: Square?
    let selectedPaths: Set<BoardGuidancePath>
    let supporterSquares: Set<Square>
    let coverage: BoardCoveragePresentation?

    func markerOpacity(at square: Square) -> Double {
        selectedSquare == nil
            || prominentThreatSquares.contains(square)
            || visibleDefenseSquares.contains(square)
            ? 1
            : 0.20
    }

    func accessibilityLabel(for square: Square, piece: Piece) -> String {
        let identity = "\(piece.color.rawValue.capitalized) \(piece.kind.rawValue) on \(squareName(square))"
        let isThreatened = threatenedSquares.contains(square)
        let isDefended = defendedSquares.contains(square)

        switch (isThreatened, isDefended) {
        case (true, true):
            return "\(identity), threatened and defended"
        case (true, false):
            return "\(identity), threatened"
        case (false, true):
            return "\(identity), defended"
        case (false, false):
            return identity
        }
    }

    func coverageAccessibilityLabel(for square: Square) -> String {
        let identity = squareName(square)
        guard let coverage else {
            return identity
        }

        let sideToMoveCovers = coverage.sideToMoveSquares.contains(square)
        let otherSideCovers = coverage.otherSideSquares.contains(square)
        switch (sideToMoveCovers, otherSideCovers) {
        case (true, true):
            return "\(identity), covered by \(coverage.sideToMove.rawValue.capitalized) and \(coverage.sideToMove.opposite.rawValue.capitalized)"
        case (true, false):
            return "\(identity), covered by \(coverage.sideToMove.rawValue.capitalized)"
        case (false, true):
            return "\(identity), covered by \(coverage.sideToMove.opposite.rawValue.capitalized)"
        case (false, false):
            return identity
        }
    }

    static func empty(sideToMove: PieceColor) -> BoardGuidancePresentation {
        BoardGuidancePresentation(
            sideToMove: sideToMove,
            threatenedSquares: [],
            prominentThreatSquares: [],
            defendedSquares: [],
            visibleDefenseSquares: [],
            selectedSquare: nil,
            selectedPaths: [],
            supporterSquares: [],
            coverage: nil
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
                prominentThreatSquares: threatenedSquares,
                defendedSquares: [],
                visibleDefenseSquares: [],
                selectedSquare: selectedSquare,
                selectedPaths: [],
                supporterSquares: [],
                coverage: nil
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

                for threat in analysis.threats(from: selectedSquare) where
                    !selectedPaths.contains(where: {
                        $0.source == selectedSquare && $0.destination == threat.destination
                    }) {
                    selectedPaths.insert(
                        BoardGuidancePath(
                            source: selectedSquare,
                            destination: threat.destination,
                            captureSquare: threat.target,
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

        var relevantSquares: Set<Square> = []
        if let selectedSquare, state.board[selectedSquare] != nil {
            relevantSquares.insert(selectedSquare)
            relevantSquares.formUnion(
                analysis.threats(from: selectedSquare).map(\.target)
            )
        }
        let prominentThreatSquares = analysis.threatenedSquares.intersection(relevantSquares)
        let visibleDefenseSquares = defendedSquares.intersection(relevantSquares)

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
            prominentThreatSquares: prominentThreatSquares,
            defendedSquares: defendedSquares,
            visibleDefenseSquares: visibleDefenseSquares,
            selectedSquare: selectedSquare,
            selectedPaths: selectedPaths,
            supporterSquares: supporterSquares,
            coverage: coverage
        )
    }

    private func squareName(_ square: Square) -> String {
        "\(square.file)\(square.rank)"
    }
}

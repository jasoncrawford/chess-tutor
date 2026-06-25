import Observation

@Observable
final class GameSession {
    var state: GameState
    var selectedSquare: Square?
    var legalMovesForSelection: [Move] = []
    var assistSettings = BeginnerAssistSettings()
    var whitePlayer: PlayerSeat = .humanLocal
    var blackPlayer: PlayerSeat = .humanLocal
    var boardOrientation: PieceColor = .white
    var message: String?

    var legalDestinations: Set<Square> {
        LegalMoveHighlighter.destinations(for: legalMovesForSelection)
    }

    init(state: GameState = .startingPosition()) {
        self.state = state
    }

    func select(_ square: Square) {
        guard state.board[square]?.color == state.sideToMove else {
            selectedSquare = nil
            legalMovesForSelection = []
            message = "Choose a \(state.sideToMove.rawValue) piece."
            return
        }

        selectedSquare = square
        legalMovesForSelection = assistSettings.showLegalMovesOnSelection
            ? LegalMoveGenerator.legalMoves(for: square, in: state)
            : []
        message = nil
    }

    func moveSelectedPiece(to destination: Square) -> MoveAttemptResult {
        guard let selectedSquare else {
            message = "Choose a piece first."
            return .illegal("Choose a piece first.")
        }

        let legalMoves = LegalMoveGenerator.legalMoves(for: selectedSquare, in: state)
        guard let move = legalMoves.first(where: { $0.to == destination }) else {
            message = "That piece can't move there."
            return .illegal("That piece can't move there.")
        }

        if case .promotion = move.special {
            message = nil
            return .needsPromotion(from: selectedSquare, to: destination)
        }

        state.apply(move)
        self.selectedSquare = nil
        legalMovesForSelection = []
        message = nil
        return .moved
    }

    func promote(from: Square, to: Square, to kind: Piece.Kind) {
        let move = Move(from: from, to: to, special: .promotion(kind))
        state.apply(move)
        selectedSquare = nil
        legalMovesForSelection = []
        message = nil
    }

    func newGame() {
        state = .startingPosition()
        selectedSquare = nil
        legalMovesForSelection = []
        message = nil
    }

    func flipBoard() {
        boardOrientation = boardOrientation.opposite
    }
}

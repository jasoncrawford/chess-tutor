import Observation

struct CapturedPiece: Equatable, Identifiable, Sendable {
    enum State: Equatable, Sendable {
        case tentative
        case committed
    }

    let id: String
    let piece: Piece
    let capturedAt: Square
    let state: State
}

@Observable
final class GameSession {
    private var committedState: GameState
    private var tentativeMove: Move?
    private var committedCapturedPieces: [CapturedPiece] = []
    var selectedSquare: Square?
    var legalMovesForSelection: [Move] = []
    var assistSettings = BeginnerAssistSettings()
    var whitePlayer: PlayerSeat = .humanLocal
    var blackPlayer: PlayerSeat = .humanLocal
    var boardOrientation: PieceColor = .white
    var message: String?

    var state: GameState {
        guard let tentativeMove else {
            return committedState
        }

        var displayState = committedState.applyingUnchecked(tentativeMove)
        displayState.sideToMove = committedState.sideToMove
        displayState.moveHistory = committedState.moveHistory
        displayState.result = committedState.result
        return displayState
    }

    var canFinishTurn: Bool {
        tentativeMove != nil
    }

    var hasGameInProgress: Bool {
        tentativeMove != nil || !committedState.moveHistory.isEmpty
    }

    var capturedPieces: [CapturedPiece] {
        guard let tentativeMove,
              let capturedPiece = capturedPiece(for: tentativeMove, in: committedState) else {
            return committedCapturedPieces
        }

        return committedCapturedPieces + [
            CapturedPiece(
                id: capturedID(for: capturedPiece.piece, at: capturedPiece.square),
                piece: capturedPiece.piece,
                capturedAt: capturedPiece.square,
                state: .tentative
            )
        ]
    }

    var legalDestinations: Set<Square> {
        var destinations = LegalMoveHighlighter.destinations(for: legalMovesForSelection)
        if let tentativeMove, selectedSquare == tentativeMove.to {
            destinations.insert(tentativeMove.from)
        }
        return destinations
    }

    var statusText: String {
        switch committedState.result {
        case .ongoing:
            return "\(committedState.sideToMove.rawValue.capitalized)'s turn"
        case .checkmate(let winner):
            return "Checkmate. \(winner.rawValue.capitalized) wins."
        case .stalemate:
            return "Stalemate."
        }
    }

    var guidanceText: String? {
        guard committedState.result == .ongoing else {
            return nil
        }
        if let message {
            return message
        }
        if LegalMoveGenerator.isKingInCheck(committedState.sideToMove, in: committedState.board) {
            return "Check! You must move to defend."
        }
        return nil
    }

    init(state: GameState = .startingPosition()) {
        self.committedState = state
    }

    func select(_ square: Square) {
        guard committedState.result == .ongoing else {
            selectedSquare = nil
            legalMovesForSelection = []
            message = statusText
            return
        }

        if let tentativeMove, square != tentativeMove.to {
            self.tentativeMove = nil
        }

        guard state.board[square]?.color == committedState.sideToMove else {
            selectedSquare = nil
            legalMovesForSelection = []
            message = "Choose a \(committedState.sideToMove.rawValue) piece."
            return
        }

        selectedSquare = square
        legalMovesForSelection = assistSettings.showLegalMovesOnSelection
            ? legalMoves(forSelectionAt: square)
            : []
        message = nil
    }

    func moveSelectedPiece(to destination: Square) -> MoveAttemptResult {
        guard committedState.result == .ongoing else {
            selectedSquare = nil
            legalMovesForSelection = []
            message = statusText
            return .illegal(statusText)
        }

        guard let selectedSquare else {
            message = "Choose a piece first."
            return .illegal("Choose a piece first.")
        }

        if let tentativeMove, selectedSquare == tentativeMove.to, destination == tentativeMove.from {
            self.tentativeMove = nil
            self.selectedSquare = nil
            legalMovesForSelection = []
            message = nil
            return .moved
        }

        let legalMoves = legalMoves(forSelectionAt: selectedSquare)
        guard let move = legalMoves.first(where: { $0.to == destination }) else {
            message = "That piece can't move there."
            return .illegal("That piece can't move there.")
        }

        if case .promotion = move.special {
            message = nil
            return .needsPromotion(from: move.from, to: destination)
        }

        tentativeMove = move
        self.selectedSquare = nil
        legalMovesForSelection = []
        message = nil
        return .moved
    }

    func promote(from: Square, to: Square, to kind: Piece.Kind) {
        let move = Move(from: from, to: to, special: .promotion(kind))
        tentativeMove = move
        selectedSquare = nil
        legalMovesForSelection = []
        message = nil
    }

    func finishTurn() {
        guard let tentativeMove else {
            message = "Make a move first."
            return
        }

        if let capturedPiece = capturedPiece(for: tentativeMove, in: committedState) {
            committedCapturedPieces.append(
                CapturedPiece(
                    id: capturedID(for: capturedPiece.piece, at: capturedPiece.square),
                    piece: capturedPiece.piece,
                    capturedAt: capturedPiece.square,
                    state: .committed
                )
            )
        }
        committedState.apply(tentativeMove)
        self.tentativeMove = nil
        selectedSquare = nil
        legalMovesForSelection = []
        message = committedState.result == .ongoing ? nil : statusText
    }

    func newGame() {
        committedState = .startingPosition()
        tentativeMove = nil
        committedCapturedPieces = []
        selectedSquare = nil
        legalMovesForSelection = []
        message = nil
    }

    func flipBoard() {
        boardOrientation = boardOrientation.opposite
    }

    private func legalMoves(forSelectionAt square: Square) -> [Move] {
        if let tentativeMove, square == tentativeMove.to {
            return LegalMoveGenerator.legalMoves(for: tentativeMove.from, in: committedState)
        }
        return LegalMoveGenerator.legalMoves(for: square, in: committedState)
    }

    private func capturedPiece(for move: Move, in state: GameState) -> (square: Square, piece: Piece)? {
        if case .enPassant = move.special {
            let capturedSquare = Square(file: move.to.file, rank: move.from.rank)
            return state.board[capturedSquare].map { (capturedSquare, $0) }
        }

        return state.board[move.to].map { (move.to, $0) }
    }

    private func capturedID(for piece: Piece, at square: Square) -> String {
        pieceAnimationID(for: piece, at: square)
    }

    func pieceAnimationID(for piece: Piece, at square: Square) -> String {
        "\(committedState.moveHistory.count)-\(square.file.rawValue)\(square.rank)-\(piece.color.rawValue)-\(piece.kind.rawValue)"
    }
}

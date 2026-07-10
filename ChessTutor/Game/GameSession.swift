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

struct SelectedPieceInfo: Equatable, Sendable {
    let piece: Piece
    let square: Square
    let squareID: String
    let title: String
    let movementSummary: String
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
    var message: String?
    private var boardLockMessage: String?

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
        guard let tentativeMove else {
            return false
        }
        return isLegal(tentativeMove)
    }

    var localCanActForCurrentTurn: Bool {
        guard boardLockMessage == nil else {
            return false
        }
        return playerSeat(for: committedState.sideToMove).isLocal
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

    var selectedPieceInfo: SelectedPieceInfo? {
        guard let selectedSquare,
              let piece = state.board[selectedSquare] else {
            return nil
        }

        return SelectedPieceInfo(
            piece: piece,
            square: selectedSquare,
            squareID: "\(selectedSquare.file)\(selectedSquare.rank)",
            title: "\(piece.color.rawValue.capitalized) \(piece.kind.rawValue)",
            movementSummary: movementSummary(for: piece.kind)
        )
    }

    var legalDestinations: Set<Square> {
        var destinations = LegalMoveHighlighter.destinations(for: legalMovesForSelection)
        if let tentativeMove, selectedSquare == tentativeMove.to {
            destinations.insert(tentativeMove.from)
        }
        return destinations
    }

    var captureIndicatorSquares: Set<Square> {
        Set(
            legalMovesForSelection.compactMap { move in
                capturedPiece(for: move, in: committedState)?.square
            }
        )
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
        if let boardLockMessage {
            return boardLockMessage
        }
        if let checkRuleViolationMessage {
            return checkRuleViolationMessage
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

    convenience init(replayingCommittedMoves moves: [Move]) {
        self.init()
        for move in moves {
            commitRestoredMove(move)
        }
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

        guard let piece = state.board[square] else {
            selectedSquare = nil
            legalMovesForSelection = []
            message = "Choose a \(committedState.sideToMove.rawValue) piece."
            return
        }

        selectedSquare = square
        legalMovesForSelection = piece.color == committedState.sideToMove
            && localCanActForCurrentTurn
            && assistSettings.showLegalMovesOnSelection
            ? allowedMoves(forSelectionAt: square)
            : []
        message = boardLockMessage
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

        if let boardLockMessage {
            message = boardLockMessage
            return .illegal(boardLockMessage)
        }

        guard localCanActForCurrentTurn else {
            message = "It's not your turn."
            return .illegal("It's not your turn.")
        }

        if let tentativeMove, selectedSquare == tentativeMove.to, destination == tentativeMove.from {
            self.tentativeMove = nil
            self.selectedSquare = nil
            legalMovesForSelection = []
            message = nil
            return .moved
        }

        let allowedMoves = allowedMoves(forSelectionAt: selectedSquare)
        guard let move = allowedMoves.first(where: { $0.to == destination }) else {
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

    @discardableResult
    func finishTurn() -> Move? {
        guard let tentativeMove else {
            message = "Make a move first."
            return nil
        }
        guard isLegal(tentativeMove) else {
            message = checkRuleViolationMessage
            return nil
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
        return tentativeMove
    }

    @discardableResult
    func commitRemoteMove(_ move: Move) -> Bool {
        guard committedState.result == .ongoing else {
            selectedSquare = nil
            legalMovesForSelection = []
            message = statusText
            return false
        }

        guard !localCanActForCurrentTurn,
              LegalMoveGenerator.allLegalMoves(in: committedState).contains(move) else {
            message = "Something went wrong syncing this game."
            return false
        }

        if let capturedPiece = capturedPiece(for: move, in: committedState) {
            committedCapturedPieces.append(
                CapturedPiece(
                    id: capturedID(for: capturedPiece.piece, at: capturedPiece.square),
                    piece: capturedPiece.piece,
                    capturedAt: capturedPiece.square,
                    state: .committed
                )
            )
        }
        committedState.apply(move)
        tentativeMove = nil
        selectedSquare = nil
        legalMovesForSelection = []
        message = committedState.result == .ongoing ? nil : statusText
        return true
    }

    func newGame() {
        committedState = .startingPosition()
        tentativeMove = nil
        committedCapturedPieces = []
        selectedSquare = nil
        legalMovesForSelection = []
        boardLockMessage = nil
        message = nil
    }

    func endRemoteGame(message: String) {
        boardLockMessage = message
        tentativeMove = nil
        legalMovesForSelection = []
        self.message = message
    }

    private func commitRestoredMove(_ move: Move) {
        if let capturedPiece = capturedPiece(for: move, in: committedState) {
            committedCapturedPieces.append(
                CapturedPiece(
                    id: capturedID(for: capturedPiece.piece, at: capturedPiece.square),
                    piece: capturedPiece.piece,
                    capturedAt: capturedPiece.square,
                    state: .committed
                )
            )
        }
        committedState.apply(move)
        tentativeMove = nil
        selectedSquare = nil
        legalMovesForSelection = []
        message = committedState.result == .ongoing ? nil : statusText
    }

    #if DEBUG
    func captureForTesting(at square: Square) {
        guard let piece = state.board[square] else {
            return
        }

        tentativeMove = nil
        committedState.board[square] = nil
        committedCapturedPieces.append(
            CapturedPiece(
                id: capturedID(for: piece, at: square),
                piece: piece,
                capturedAt: square,
                state: .committed
            )
        )
        selectedSquare = nil
        legalMovesForSelection = []
        message = nil
    }

    func promoteForTesting(at square: Square, to kind: Piece.Kind) {
        guard let piece = committedState.board[square],
              piece.kind == .pawn else {
            return
        }

        tentativeMove = nil
        committedState.board[square] = Piece(kind: kind, color: piece.color)
        selectedSquare = nil
        legalMovesForSelection = []
        message = nil
    }
    #endif

    private func legalMoves(forSelectionAt square: Square) -> [Move] {
        if let tentativeMove, square == tentativeMove.to {
            return LegalMoveGenerator.legalMoves(for: tentativeMove.from, in: committedState)
        }
        return LegalMoveGenerator.legalMoves(for: square, in: committedState)
    }

    private func allowedMoves(forSelectionAt square: Square) -> [Move] {
        if let tentativeMove, square == tentativeMove.to {
            return LegalMoveGenerator.allowedMoves(for: tentativeMove.from, in: committedState)
        }
        return LegalMoveGenerator.allowedMoves(for: square, in: committedState)
    }

    private func playerSeat(for color: PieceColor) -> PlayerSeat {
        switch color {
        case .white:
            return whitePlayer
        case .black:
            return blackPlayer
        }
    }

    private func movementSummary(for kind: Piece.Kind) -> String {
        switch kind {
        case .king:
            return "Moves one square in any direction."
        case .queen:
            return "Moves in straight lines and diagonals."
        case .rook:
            return "Moves in straight lines."
        case .bishop:
            return "Moves diagonally."
        case .knight:
            return "Moves in an L shape."
        case .pawn:
            return "Moves forward and captures diagonally."
        }
    }

    private func isLegal(_ move: Move) -> Bool {
        legalMoves(forSelectionAt: move.to).contains(move)
    }

    private var checkRuleViolationMessage: String? {
        guard let tentativeMove, !isLegal(tentativeMove) else {
            return nil
        }

        if LegalMoveGenerator.isKingInCheck(committedState.sideToMove, in: committedState.board) {
            return "Your king would still be in check. Move to defend your king."
        }
        return "That move would put your king in check."
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

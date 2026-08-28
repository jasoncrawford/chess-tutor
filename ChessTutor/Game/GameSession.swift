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
    private var displayedAnalysis: PositionAnalysis
    private var actionableMovesForSelection: [Move] = []
    var selectedSquare: Square?
    private(set) var analysisRevision = 0
    var isCoverageVisible = false
    var assistSettings = BeginnerAssistSettings()
    var whitePlayer: PlayerSeat = .humanLocal
    var blackPlayer: PlayerSeat = .humanLocal
    var message: String?
    private var boardLockMessage: String?
    private var boardLockStatusText: String?

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

    var isRemoteGameEnded: Bool {
        boardLockMessage != nil
    }

    var hasGameInProgress: Bool {
        tentativeMove != nil || !committedState.moveHistory.isEmpty
    }

    var capturedPieces: [CapturedPiece] {
        guard let tentativeMove,
              let capturedPiece = LegalMoveGenerator.capture(for: tentativeMove, in: committedState) else {
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
        var destinations = assistSettings.showLegalMovesOnSelection
            ? LegalMoveHighlighter.destinations(for: actionableMovesForSelection)
            : []
        if let tentativeMove, selectedSquare == tentativeMove.to {
            destinations.insert(tentativeMove.from)
        }
        return destinations
    }

    var captureIndicatorSquares: Set<Square> {
        guard assistSettings.showLegalMovesOnSelection else {
            return []
        }
        return Set(
            actionableMovesForSelection.compactMap { move in
                LegalMoveGenerator.capture(for: move, in: committedState)?.square
            }
        )
    }

    var boardGuidance: BoardGuidancePresentation {
        guard boardLockMessage == nil else {
            return .empty(sideToMove: state.sideToMove)
        }

        switch committedState.result {
        case .ongoing:
            return BoardGuidancePresentation.make(
                state: state,
                analysis: displayedAnalysis,
                selectedSquare: selectedSquare,
                showsSelectedReach: assistSettings.showLegalMovesOnSelection,
                showsCoverage: isCoverageVisible,
                keepsOnlyCheckmateKingThreat: false
            )
        case .checkmate:
            return BoardGuidancePresentation.make(
                state: state,
                analysis: displayedAnalysis,
                selectedSquare: selectedSquare,
                showsSelectedReach: false,
                showsCoverage: false,
                keepsOnlyCheckmateKingThreat: true
            )
        case .stalemate:
            return .empty(sideToMove: state.sideToMove)
        }
    }

    var statusText: String {
        if boardLockMessage != nil {
            return boardLockStatusText ?? "Game forfeit."
        }

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
        self.displayedAnalysis = Self.makeAnalysis(for: state)
    }

    convenience init(replayingCommittedMoves moves: [Move]) {
        self.init()
        for move in moves {
            commitRestoredMove(move)
        }
    }

    func select(_ square: Square) {
        guard committedState.result == .ongoing else {
            selectedSquare = state.board[square] == nil ? nil : square
            actionableMovesForSelection = []
            message = statusText
            return
        }

        if let tentativeMove, square != tentativeMove.to {
            self.tentativeMove = nil
            refreshDisplayedAnalysis()
        }

        guard let piece = state.board[square] else {
            clearSelection()
            return
        }

        selectedSquare = square
        actionableMovesForSelection = piece.color == committedState.sideToMove
            && localCanActForCurrentTurn
            && tentativeMove == nil
            ? displayedAnalysis.allowedMoves(from: square)
            : []
        message = boardLockMessage
    }

    func tapEmptySquare(at square: Square) -> MoveAttemptResult? {
        guard state.board[square] == nil else {
            return nil
        }

        if let tentativeMove {
            guard let replacementMove = allowedMoves(forSelectionAt: tentativeMove.from)
                .first(where: { $0.to == square }) else {
                restoreCommittedPosition()
                return nil
            }

            return stage(replacementMove)
        }

        guard actionableMovesForSelection.contains(where: { $0.to == square }) else {
            clearSelection()
            return nil
        }

        return moveSelectedPiece(to: square)
    }

    func toggleCoverage() {
        guard committedState.result == .ongoing, boardLockMessage == nil else {
            return
        }
        isCoverageVisible.toggle()
    }

    func prepareDrag(from square: Square) -> Square? {
        guard committedState.result == .ongoing,
              localCanActForCurrentTurn,
              let piece = state.board[square],
              piece.color == committedState.sideToMove else {
            return nil
        }

        if let tentativeMove, square == tentativeMove.to {
            let originalSquare = tentativeMove.from
            restoreCommittedPosition()
            select(originalSquare)
            return selectedSquare
        }

        select(square)
        return selectedSquare
    }

    func moveSelectedPiece(to destination: Square) -> MoveAttemptResult {
        guard committedState.result == .ongoing else {
            actionableMovesForSelection = []
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

        if tentativeMove != nil {
            restoreCommittedPosition()
            return .moved
        }

        guard let selectedPiece = state.board[selectedSquare],
              selectedPiece.color == committedState.sideToMove else {
            let message = "Choose a \(committedState.sideToMove.rawValue) piece."
            self.message = message
            return .illegal(message)
        }

        let allowedMoves = allowedMoves(forSelectionAt: selectedSquare)
        guard let move = allowedMoves.first(where: { $0.to == destination }) else {
            message = "That piece can't move there."
            return .illegal("That piece can't move there.")
        }

        return stage(move)
    }

    func promote(from: Square, to: Square, to kind: Piece.Kind) {
        let move = Move(from: from, to: to, special: .promotion(kind))
        tentativeMove = move
        selectedSquare = to
        actionableMovesForSelection = []
        message = nil
        refreshDisplayedAnalysis()
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

        if let capturedPiece = LegalMoveGenerator.capture(for: tentativeMove, in: committedState) {
            committedCapturedPieces.append(
                CapturedPiece(
                    id: capturedID(for: capturedPiece.piece, at: capturedPiece.square),
                    piece: capturedPiece.piece,
                    capturedAt: capturedPiece.square,
                    state: .committed
                )
            )
        }
        let committedMove = tentativeMove
        committedState.apply(committedMove)
        self.tentativeMove = nil
        selectedSquare = nil
        actionableMovesForSelection = []
        isCoverageVisible = false
        refreshDisplayedAnalysis()
        message = committedState.result == .ongoing ? nil : statusText
        return committedMove
    }

    @discardableResult
    func commitRemoteMove(_ move: Move) -> Bool {
        guard committedState.result == .ongoing else {
            message = statusText
            return false
        }

        guard !localCanActForCurrentTurn,
              LegalMoveGenerator.allLegalMoves(in: committedState).contains(move) else {
            message = "Something went wrong syncing this game."
            return false
        }

        if let capturedPiece = LegalMoveGenerator.capture(for: move, in: committedState) {
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
        actionableMovesForSelection = []
        isCoverageVisible = false
        refreshDisplayedAnalysis()
        message = committedState.result == .ongoing ? nil : statusText
        return true
    }

    func newGame() {
        committedState = .startingPosition()
        tentativeMove = nil
        committedCapturedPieces = []
        selectedSquare = nil
        actionableMovesForSelection = []
        isCoverageVisible = false
        boardLockMessage = nil
        boardLockStatusText = nil
        message = nil
        refreshDisplayedAnalysis()
    }

    func endRemoteGame(message: String) {
        lockBoard(message: message, statusText: "Game forfeit.")
    }

    func lockBoard(message: String, statusText: String) {
        let wasShowingTentativePosition = tentativeMove != nil
        boardLockMessage = message
        boardLockStatusText = statusText
        tentativeMove = nil
        actionableMovesForSelection = []
        isCoverageVisible = false
        if wasShowingTentativePosition {
            refreshDisplayedAnalysis()
        }
        self.message = message
    }

    func clearMessage(matching expectedMessage: String) {
        guard message == expectedMessage else {
            return
        }
        message = nil
    }

    private func commitRestoredMove(_ move: Move) {
        if let capturedPiece = LegalMoveGenerator.capture(for: move, in: committedState) {
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
        actionableMovesForSelection = []
        isCoverageVisible = false
        refreshDisplayedAnalysis()
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
        actionableMovesForSelection = []
        message = nil
        refreshDisplayedAnalysis()
    }

    func promoteForTesting(at square: Square, to kind: Piece.Kind) {
        guard let piece = committedState.board[square],
              piece.kind == .pawn else {
            return
        }

        tentativeMove = nil
        committedState.board[square] = Piece(kind: kind, color: piece.color)
        selectedSquare = nil
        actionableMovesForSelection = []
        message = nil
        refreshDisplayedAnalysis()
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

    private func refreshDisplayedAnalysis() {
        displayedAnalysis = Self.makeAnalysis(for: state)
        analysisRevision += 1
    }

    private func restoreCommittedPosition() {
        tentativeMove = nil
        clearSelection()
        refreshDisplayedAnalysis()
    }

    private func stage(_ move: Move) -> MoveAttemptResult {
        if case .promotion = move.special {
            message = nil
            return .needsPromotion(from: move.from, to: move.to)
        }

        tentativeMove = move
        selectedSquare = move.to
        actionableMovesForSelection = []
        message = nil
        refreshDisplayedAnalysis()
        return .moved
    }

    private func clearSelection() {
        selectedSquare = nil
        actionableMovesForSelection = []
        message = nil
    }

    private static func makeAnalysis(for state: GameState) -> PositionAnalysis {
        guard LegalMoveGenerator.kingSquare(for: .white, in: state.board) != nil,
              LegalMoveGenerator.kingSquare(for: .black, in: state.board) != nil else {
            return PositionAnalysis(
                allowedMovesBySource: [:],
                threatsByTarget: [:],
                supportersByTarget: [:],
                coverageByColor: [:]
            )
        }
        return PositionAnalyzer.analyze(state)
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

    private func capturedID(for piece: Piece, at square: Square) -> String {
        pieceAnimationID(for: piece, at: square)
    }

    func pieceAnimationID(for piece: Piece, at square: Square) -> String {
        "\(committedState.moveHistory.count)-\(square.file.rawValue)\(square.rank)-\(piece.color.rawValue)-\(piece.kind.rawValue)"
    }
}

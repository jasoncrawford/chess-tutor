import Foundation
import Observation

private enum CoachingSquareInteractionIntent {
    case tap
    case dragStart
}

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
    struct CoachingRequestIdentity: Hashable {
        let session: ObjectIdentifier
        let requestID: Int?
    }

    private struct PendingCoachingRequest: Equatable, Sendable {
        let id: Int
        let request: CoachingRequest
        let mismatchRetryCount: Int
    }

    private struct PendingHostedCoachingRequest: Sendable {
        let id: Int
        let request: ModelCoachingNeutralRequest
        let contract: ModelCoachingChessNativeResponseContract
        let continuationID: String?
        let correlation: HostedCoachingCorrelation
        let committedState: GameState
        let tentativeMove: Move?
        let scheduledAt: TimeInterval
        let notBefore: TimeInterval
        let burstStartedAt: TimeInterval
        let coalescedCount: Int
        var previousFlightFinishedAt: TimeInterval?
    }

    private var committedState: GameState
    private var tentativeMove: Move?
    private var committedCapturedPieces: [CapturedPiece] = []
    private var displayedAnalysis: PositionAnalysis
    private var actionableMovesForSelection: [Move] = []
    private let coachingAdvisor: any CoachingAdvising
    private let hostedCoachingProvider: (any HostedCoachingTurning)?
    private let coachingIdentifierFactory: () -> String
    private var hostedCoachingGameID: String
    private var coachingSession: CoachingSession?
    private var pendingCoachingRequest: PendingCoachingRequest?
    private var hostedCoachingSession: HostedCoachingSession?
    private var pendingHostedCoachingRequest: PendingHostedCoachingRequest?
    // This identity survives pending-input replacements, so SwiftUI does not
    // cancel an already-dispatched HTTP request for every new board interaction.
    private var hostedCoachingWorkID: Int?
    @ObservationIgnored private var hostedResolverIsRunning = false
    @ObservationIgnored private var hostedResolverWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var hostedInFlightRequestID: Int?
    private let hostedCoachingTiming: HostedCoachingTiming
    private let coachingDiagnosticSink: @Sendable (DiagnosticsEvent) -> Void
    @ObservationIgnored private var coachingDiagnosticSequence = 0
    private var nextCoachingRequestID = 0
    private var coachingPositionRevision = 0
    var selectedSquare: Square?
    private(set) var analysisRevision = 0
    private(set) var isAwaitingPromotionChoice = false
    var assistSettings = BeginnerAssistSettings()
    var whitePlayer: PlayerSeat = .humanLocal {
        didSet {
            stopCoachingIfCurrentSeatBecameRemote(
                color: .white,
                previous: oldValue,
                current: whitePlayer
            )
        }
    }
    var blackPlayer: PlayerSeat = .humanLocal {
        didSet {
            stopCoachingIfCurrentSeatBecameRemote(
                color: .black,
                previous: oldValue,
                current: blackPlayer
            )
        }
    }
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

    var coachingPresentation: CoachingPresentation? {
        if let hostedCoachingSession {
            return HostedCoachingPresentationProjector().presentation(
                for: hostedCoachingSession, board: committedState.board, tentativeMove: tentativeMove
            )
        }
        return coachingSession?.presentation
    }

    var isCoachingActive: Bool {
        coachingSession != nil || hostedCoachingSession != nil
    }

    var isCoachingPanelVisible: Bool {
        isCoachingActive
    }

    var authoritativeCoachingBoardTask: CoachingBoardTask {
        if hostedCoachingSession != nil {
            return coachingPresentation?.boardTask ?? .none
        }
        return coachingSession?.authoritativeBoardTask ?? .none
    }

    var pendingCoachingRequestID: Int? {
        pendingHostedCoachingRequest?.id ?? pendingCoachingRequest?.id
    }

    var coachingRequestIdentity: CoachingRequestIdentity {
        CoachingRequestIdentity(session: ObjectIdentifier(self), requestID: hostedCoachingWorkID ?? pendingCoachingRequest?.id)
    }

    var currentCoachingGameID: String? {
        hostedCoachingProvider == nil ? nil : hostedCoachingGameID
    }

    private var coachingInteractionSnapshot: CoachingInteractionSnapshot {
        CoachingInteractionSnapshot(
            selectedSquare: selectedSquare,
            tentativeMove: tentativeMove,
            positionRevision: coachingPositionRevision
        )
    }

    var canRequestCoaching: Bool {
        committedState.result == .ongoing
            && localCanActForCurrentTurn
            && !isAwaitingPromotionChoice
            && coachingSession == nil
            && hostedCoachingSession == nil
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
            let guidance = BoardGuidancePresentation.make(
                state: state,
                analysis: displayedAnalysis,
                selectedSquare: selectedSquare,
                showsSelectedReach: assistSettings.showLegalMovesOnSelection,
                keepsOnlyCheckmateKingThreat: false
            )
            return hostedCoachingSession == nil ? guidance : guidance.quietForCoaching(in: state.board)
        case .checkmate:
            return BoardGuidancePresentation.make(
                state: state,
                analysis: displayedAnalysis,
                selectedSquare: selectedSquare,
                showsSelectedReach: false,
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

    init(
        state: GameState = .startingPosition(),
        coachingAdvisor: any CoachingAdvising = LocalCoachingAdvisor(),
        hostedCoachingProvider: (any HostedCoachingTurning)? = nil,
        hostedCoachingTiming: HostedCoachingTiming = HostedCoachingTiming(),
        coachingDiagnosticSink: @escaping @Sendable (DiagnosticsEvent) -> Void = HostedCoachingDiagnostics.record,
        coachingGameID: UUID? = nil,
        coachingIdentifierFactory: @escaping () -> String = {
            UUID().uuidString.lowercased()
        }
    ) {
        self.committedState = state
        self.displayedAnalysis = Self.makeAnalysis(for: state)
        self.coachingAdvisor = coachingAdvisor
        self.hostedCoachingProvider = hostedCoachingProvider
        self.hostedCoachingTiming = hostedCoachingTiming
        self.coachingDiagnosticSink = coachingDiagnosticSink
        self.coachingIdentifierFactory = coachingIdentifierFactory
        self.hostedCoachingGameID = coachingGameID?.uuidString.lowercased() ?? coachingIdentifierFactory()
    }

    convenience init(
        replayingCommittedMoves moves: [Move],
        hostedCoachingProvider: (any HostedCoachingTurning)? = nil,
        coachingGameID: UUID? = nil
    ) {
        self.init(hostedCoachingProvider: hostedCoachingProvider, coachingGameID: coachingGameID)
        for move in moves {
            commitRestoredMove(move)
        }
    }

    func select(_ square: Square) {
        selectWithoutSynchronizing(square)
        _ = synchronizeCoachingInteraction()
    }

    private func selectWithoutSynchronizing(_ square: Square) {
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
                _ = synchronizeCoachingInteraction()
                return nil
            }

            let result = stage(replacementMove)
            _ = synchronizeCoachingInteraction()
            return result
        }

        guard actionableMovesForSelection.contains(where: { $0.to == square }) else {
            clearSelection()
            _ = synchronizeCoachingInteraction()
            return nil
        }

        let result = moveSelectedPieceWithoutSynchronizing(to: square)
        _ = synchronizeCoachingInteraction()
        return result
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
            selectWithoutSynchronizing(originalSquare)
            _ = synchronizeCoachingInteraction()
            return selectedSquare
        }

        selectWithoutSynchronizing(square)
        _ = synchronizeCoachingInteraction()
        return selectedSquare
    }

    func moveSelectedPiece(to destination: Square) -> MoveAttemptResult {
        let result = moveSelectedPieceWithoutSynchronizing(to: destination)
        _ = synchronizeCoachingInteraction()
        return result
    }

    private func moveSelectedPieceWithoutSynchronizing(
        to destination: Square
    ) -> MoveAttemptResult {
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
        isAwaitingPromotionChoice = false
        refreshDisplayedAnalysis()
        _ = synchronizeCoachingInteraction()
    }

    func cancelPromotionChoice() {
        isAwaitingPromotionChoice = false
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
        coachingPositionRevision += 1
        self.tentativeMove = nil
        isAwaitingPromotionChoice = false
        selectedSquare = nil
        actionableMovesForSelection = []
        refreshDisplayedAnalysis()
        message = committedState.result == .ongoing ? nil : statusText
        stopCoaching()
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
        coachingPositionRevision += 1
        tentativeMove = nil
        isAwaitingPromotionChoice = false
        selectedSquare = nil
        actionableMovesForSelection = []
        refreshDisplayedAnalysis()
        message = committedState.result == .ongoing ? nil : statusText
        stopCoaching()
        return true
    }

    func newGame() {
        stopCoaching()
        hostedCoachingGameID = coachingIdentifierFactory()
        committedState = .startingPosition()
        coachingPositionRevision += 1
        tentativeMove = nil
        committedCapturedPieces = []
        selectedSquare = nil
        actionableMovesForSelection = []
        boardLockMessage = nil
        boardLockStatusText = nil
        message = nil
        isAwaitingPromotionChoice = false
        refreshDisplayedAnalysis()
    }

    /// Associates a newly accepted remote board with its persistent library entry.
    func bindCoachingGame(to gameID: UUID) {
        stopCoaching()
        hostedCoachingGameID = gameID.uuidString.lowercased()
    }

    func endRemoteGame(message: String) {
        lockBoard(message: message, statusText: "Game forfeit.")
    }

    func lockBoard(message: String, statusText: String) {
        stopCoaching()
        let wasShowingTentativePosition = tentativeMove != nil
        boardLockMessage = message
        boardLockStatusText = statusText
        tentativeMove = nil
        actionableMovesForSelection = []
        if wasShowingTentativePosition {
            refreshDisplayedAnalysis()
        }
        isAwaitingPromotionChoice = false
        self.message = message
    }

    func clearMessage(matching expectedMessage: String) {
        guard message == expectedMessage else {
            return
        }
        message = nil
    }

    private func commitRestoredMove(_ move: Move) {
        stopCoaching()
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
        coachingPositionRevision += 1
        tentativeMove = nil
        selectedSquare = nil
        actionableMovesForSelection = []
        refreshDisplayedAnalysis()
        message = committedState.result == .ongoing ? nil : statusText
        isAwaitingPromotionChoice = false
    }

    #if DEBUG
    func captureForTesting(at square: Square) {
        guard let piece = state.board[square] else {
            return
        }

        stopCoaching()
        tentativeMove = nil
        committedState.board[square] = nil
        coachingPositionRevision += 1
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
        isAwaitingPromotionChoice = false
        refreshDisplayedAnalysis()
    }

    func promoteForTesting(at square: Square, to kind: Piece.Kind) {
        guard let piece = committedState.board[square],
              piece.kind == .pawn else {
            return
        }

        stopCoaching()
        tentativeMove = nil
        committedState.board[square] = Piece(kind: kind, color: piece.color)
        coachingPositionRevision += 1
        selectedSquare = nil
        actionableMovesForSelection = []
        message = nil
        isAwaitingPromotionChoice = false
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
            isAwaitingPromotionChoice = true
            return .needsPromotion(from: move.from, to: move.to)
        }

        tentativeMove = move
        selectedSquare = move.to
        actionableMovesForSelection = []
        message = nil
        refreshDisplayedAnalysis()
        return .moved
    }

    func startCoaching() {
        guard canRequestCoaching else { return }

        if hostedCoachingProvider != nil {
            var hostedSession = HostedCoachingSession(
                learner: committedState.sideToMove,
                episodeID: coachingIdentifierFactory()
            )
            hostedSession.openHelp(
                selectedSquare: selectedSquare,
                tentativeMove: tentativeMove
            )
            hostedCoachingSession = hostedSession
            queueHostedCoachingRequest()
            return
        }

        let context: CoachingRequest.Context
        if tentativeMove != nil {
            context = .tentativeMove(origin: .preexisting)
        } else {
            context = .start
        }
        coachingSession = CoachingSession(
            learner: committedState.sideToMove,
            interaction: coachingInteractionSnapshot,
            initialContext: context
        )
        queueCoachingRequest(context: context)
    }

    @MainActor
    func resolvePendingCoachingAdvice() async {
        if let hostedCoachingProvider {
            await resolveHostedCoachingAdvice(using: hostedCoachingProvider)
            return
        }

        guard let pending = pendingCoachingRequest,
              coachingSession != nil else { return }

        do {
            let advice = try await coachingAdvisor.advice(for: pending.request)
            receiveCoachingAdvice(advice, for: pending)
        } catch is CancellationError {
            receiveUnsupportedCoachingPosition(for: pending)
        } catch {
            receiveUnsupportedCoachingPosition(for: pending)
        }
    }

    @discardableResult
    func handleCoachingSquareTap(_ square: Square) -> Bool {
        handleCoachingSquareInteraction(square, intent: .tap)
    }

    @discardableResult
    func handleCoachingSquareDragStart(_ square: Square) -> Bool {
        handleCoachingSquareInteraction(square, intent: .dragStart)
    }

    private func handleCoachingSquareInteraction(
        _ square: Square,
        intent: CoachingSquareInteractionIntent
    ) -> Bool {
        if var hostedSession = hostedCoachingSession {
            if intent == .dragStart, hostedSession.isAnswering {
                playInsteadOfAnswering()
                return false
            }
            // A destination tap is a move, even while the tutor asks the player
            // to identify a piece. Use allowed moves, independent of visible
            // hints and of whether the move will ultimately pass check rules.
            if intent == .tap,
               localCanActForCurrentTurn,
               tentativeMove == nil,
               actionableMovesForSelection.contains(where: { $0.to == square }) {
                logCoachingEvent("board_input", fields: ["intent": "tap", "square": ModelCoachingPositionEncoder.squareName(square), "disposition": "move_destination"])
                return false
            }
            guard intent == .tap,
                  hostedSession.recordPieceSelectionAnswer(
                      at: square,
                      in: committedState
                  ) else {
                logCoachingEvent("board_input", fields: ["intent": intent == .tap ? "tap" : "drag", "square": ModelCoachingPositionEncoder.squareName(square), "disposition": "local"])
                return hostedSession.isAnswering && intent == .tap
            }
            hostedCoachingSession = hostedSession
            logCoachingEvent("board_input", fields: ["intent": "tap", "square": ModelCoachingPositionEncoder.squareName(square), "disposition": "answer"])
            queueHostedCoachingRequest(debounced: true)
            return true
        }

        guard case let .identify(allowsMoveRevision) = authoritativeCoachingBoardTask else {
            return false
        }

        if allowsMoveRevision {
            switch intent {
            case .tap:
                if !isAcceptedCoachingAnswer(square),
                   isActionableCoachingTapRevision(at: square) {
                    return false
                }
            case .dragStart:
                if !isAcceptedCoachingAnswer(square),
                   isActionableCoachingDragRevision(at: square) {
                    return false
                }
            }
        }

        let directives = coachingSession?.handle(.identificationTapped(square)) ?? []
        _ = applyCoachingDirectives(directives)
        return true
    }

    @discardableResult
    func chooseCoachingAction(_ action: CoachingAction) -> Move? {
        if hostedCoachingSession != nil {
            switch action {
            case .hint:
                guard var hostedSession = hostedCoachingSession else { return nil }
                if hostedSession.phase == .failed || hostedSession.phase == .timedOut {
                    hostedSession.recordRetry()
                } else {
                    hostedSession.recordHintAction()
                }
                hostedCoachingSession = hostedSession
                queueHostedCoachingRequest()
                return nil
            case .noAnswer:
                guard var hostedSession = hostedCoachingSession,
                      hostedSession.recordNegativeAnswer() else { return nil }
                hostedCoachingSession = hostedSession
                queueHostedCoachingRequest()
                return nil
            case .looksSafe:
                guard var hostedSession = hostedCoachingSession,
                      hostedSession.recordAction("looksSafe") else { return nil }
                hostedCoachingSession = hostedSession
                queueHostedCoachingRequest()
                return nil
            case .keepLooking:
                guard tentativeMove != nil else { return nil }
                restoreCommittedPosition()
                _ = synchronizeCoachingInteraction(debounced: false)
                return nil
            case .done:
                return finishTurn()
            case .stop:
                stopCoaching()
                return nil
            }
        }

        let directives = coachingSession?.handle(.actionChosen(action)) ?? []
        return applyCoachingDirectives(directives)
    }

    func stopCoaching() {
        if let pending = pendingHostedCoachingRequest {
            logCoachingEvent("request_cancelled", pending: pending, fields: [
                "reason": "help_closed", "was_dispatched": String(hostedInFlightRequestID == pending.id)
            ])
        }
        coachingSession = nil
        pendingCoachingRequest = nil
        hostedCoachingSession = nil
        pendingHostedCoachingRequest = nil
        hostedCoachingWorkID = nil
    }

    func replayCoachingReference(at runIndex: Int) {
        let previousPulse = hostedCoachingSession?.pulseID
        hostedCoachingSession?.replayReference(at: runIndex)
        if hostedCoachingSession?.pulseID != previousPulse {
            logCoachingEvent("visual_reference", fields: ["run_index": String(runIndex), "disposition": "local"])
        }
    }

    var coachingReferenceReplayID: String? { hostedCoachingSession?.referenceReplayID }

    func expireCoachingReference(replayID: String?) {
        hostedCoachingSession?.expireReference(replayID: replayID)
    }

    func replayCoachingVisual() {
        let previousPulse = hostedCoachingSession?.pulseID
        hostedCoachingSession?.replayVisual()
        if hostedCoachingSession?.pulseID != previousPulse {
            logCoachingEvent("visual_replay", fields: ["disposition": "local"])
        }
    }

    func playInsteadOfAnswering() {
        guard hostedCoachingSession?.isAnswering == true else { return }
        if let pending = pendingHostedCoachingRequest {
            logCoachingEvent("request_cancelled", pending: pending, fields: [
                "reason": "play_instead", "was_dispatched": String(hostedInFlightRequestID == pending.id)
            ])
        }
        pendingHostedCoachingRequest = nil
        hostedCoachingWorkID = nil
        hostedCoachingSession?.playInstead()
        logCoachingEvent("play_instead", fields: ["disposition": "local"])
    }

    private func queueHostedCoachingRequest(debounced: Bool = false) {
        guard var hostedSession = hostedCoachingSession else { return }
        let now = hostedCoachingTiming.now()
        let replaced = pendingHostedCoachingRequest.flatMap { $0.id == hostedInFlightRequestID ? nil : $0 }
        nextCoachingRequestID += 1
        let id = nextCoachingRequestID
        let request = hostedSession.request(
            committedState: committedState,
            selectedSquare: selectedSquare,
            tentativeMove: tentativeMove,
            positionRevision: coachingPositionRevision,
            requestID: "hosted-\(id)"
        )
        let correlation = HostedCoachingCorrelation(
            gameID: hostedCoachingGameID,
            episodeID: hostedSession.episodeID
        )
        hostedCoachingSession = hostedSession
        pendingHostedCoachingRequest = PendingHostedCoachingRequest(
            id: id,
            request: request,
            contract: ModelCoachingChessNativeContextCompiler.responseContract(
                for: request,
                promptVersion: "tutor-v13"
            ),
            continuationID: hostedSession.continuationID,
            correlation: correlation,
            committedState: committedState,
            tentativeMove: tentativeMove,
            scheduledAt: now,
            notBefore: now + (debounced ? hostedCoachingTiming.debounceSeconds : 0),
            burstStartedAt: replaced?.burstStartedAt ?? now,
            coalescedCount: (replaced?.coalescedCount ?? -1) + 1,
            previousFlightFinishedAt: replaced?.previousFlightFinishedAt
        )
        if hostedCoachingWorkID == nil { hostedCoachingWorkID = id }
        logCoachingEvent(replaced == nil ? "request_scheduled" : "request_coalesced", pending: pendingHostedCoachingRequest, fields: [
            "replaced_request_id": replaced?.request.requestID ?? "none",
            "interaction": request.interaction.latestEvent.kind.rawValue,
            "debounced": String(debounced),
            "waiting_for_request": hostedInFlightRequestID.map { "hosted-\($0)" } ?? "none"
        ])
    }

    private func receiveHostedCoachingResponse(
        _ response: HostedCoachingResponse,
        for pending: PendingHostedCoachingRequest
    ) {
        guard pendingHostedCoachingRequestIsApplicable(pending),
              response.requestID == pending.request.requestID,
              response.positionRevision == pending.request.positionRevision,
              var hostedSession = hostedCoachingSession else {
            logCoachingEvent("response_discarded", pending: pending, fields: ["reason": "superseded"])
            return
        }
        pendingHostedCoachingRequest = nil
        hostedCoachingWorkID = nil
        hostedSession.receive(
            response.turn,
            continuationID: response.continuationID
        )
        hostedCoachingSession = hostedSession
        logCoachingEvent("response_applied", pending: pending, fields: [
            "interaction_to_advice_ms": Self.coachingMilliseconds(hostedCoachingTiming.now() - pending.scheduledAt)
        ])
    }

    private func failHostedCoachingRequest(
        _ pending: PendingHostedCoachingRequest,
        error: HostedCoachingTransportError
    ) {
        guard pendingHostedCoachingRequestIsApplicable(pending),
              var hostedSession = hostedCoachingSession else {
            logCoachingEvent("response_discarded", pending: pending, fields: ["reason": "superseded_error"])
            return
        }
        pendingHostedCoachingRequest = nil
        hostedCoachingWorkID = nil
        hostedSession.fail(error)
        hostedCoachingSession = hostedSession
        logCoachingEvent("failure_applied", pending: pending)
    }

    private func pendingHostedCoachingRequestIsApplicable(
        _ pending: PendingHostedCoachingRequest
    ) -> Bool {
        pendingHostedCoachingRequest?.id == pending.id
            && pending.committedState == committedState
            && pending.tentativeMove == tentativeMove
            && pending.request.positionRevision == coachingPositionRevision
            && hostedCoachingSession != nil
    }

    @MainActor
    private func resolveHostedCoachingAdvice(using provider: any HostedCoachingTurning) async {
        guard let workID = hostedCoachingWorkID else { return }
        // A reopened episode can start its SwiftUI task before the cancelled old
        // one unwinds. Wait for that resolver as well as ordinary in-flight work.
        while hostedResolverIsRunning {
            await withCheckedContinuation { hostedResolverWaiters.append($0) }
            guard !Task.isCancelled, hostedCoachingWorkID == workID else { return }
        }
        guard hostedCoachingWorkID == workID else { return }
        hostedResolverIsRunning = true
        var activePending = pendingHostedCoachingRequest
        defer {
            if Task.isCancelled, hostedCoachingWorkID == workID,
               let latest = pendingHostedCoachingRequest {
                if latest.id == activePending?.id {
                    // The view's task ended without an applicable result. Leave
                    // an explicit retry, not a stranded Thinking state or an
                    // automatic second attempt of an already-sent request.
                    failHostedCoachingRequest(latest, error: .serverUnavailable)
                } else {
                    // Preserve genuinely newer input, but give SwiftUI a fresh
                    // task identity so it can resume after this owner exits.
                    hostedCoachingWorkID = latest.id
                }
            }
            hostedResolverIsRunning = false
            let waiters = hostedResolverWaiters
            hostedResolverWaiters = []
            for waiter in waiters { waiter.resume() }
        }

        while !Task.isCancelled, hostedCoachingWorkID == workID,
              let pending = pendingHostedCoachingRequest, hostedCoachingSession != nil {
            activePending = pending
            let remaining = pending.notBefore - hostedCoachingTiming.now()
            if remaining > 0.000001 {
                do {
                    try await hostedCoachingTiming.sleep(remaining)
                } catch {
                    logCoachingEvent("request_cancelled", pending: pending, fields: ["reason": "debounce_cancelled", "was_dispatched": "false"])
                    if !Task.isCancelled {
                        failHostedCoachingRequest(pending, error: .serverUnavailable)
                    }
                    return
                }
                // Input may have replaced this snapshot while the timer slept.
                continue
            }

            let started = hostedCoachingTiming.now()
            hostedInFlightRequestID = pending.id
            logCoachingEvent("request_dispatched", pending: pending, fields: [
                "coalesced_count": String(pending.coalescedCount),
                "selected_square": pending.request.interaction.selectedSquare ?? "none",
                "staged_move": pending.request.interaction.tentativeMove?.canonicalMove ?? "none",
                "wait_ms": Self.coachingMilliseconds(started - pending.scheduledAt),
                "burst_ms": Self.coachingMilliseconds(started - pending.burstStartedAt),
                "debounce_wait_ms": Self.coachingMilliseconds(pending.notBefore - pending.scheduledAt),
                "in_flight_wait_ms": Self.coachingMilliseconds((pending.previousFlightFinishedAt ?? pending.notBefore) - pending.notBefore)
            ])
            do {
                let response = try await provider.turn(
                    for: pending.request, contract: pending.contract,
                    continuationID: pending.continuationID, correlation: pending.correlation
                )
                finishHostedCoachingFlight(pending)
                logCoachingEvent("request_completed", pending: pending, fields: ["duration_ms": Self.coachingMilliseconds(hostedCoachingTiming.now() - started)])
                guard !Task.isCancelled else {
                    logCoachingEvent("response_discarded", pending: pending, fields: ["reason": "resolver_cancelled"])
                    return
                }
                receiveHostedCoachingResponse(response, for: pending)
            } catch {
                finishHostedCoachingFlight(pending)
                if Task.isCancelled {
                    logCoachingEvent("request_cancelled", pending: pending, fields: ["reason": "resolver_cancelled", "was_dispatched": "true"])
                    return
                }
                let safeError = error as? HostedCoachingTransportError ?? .serverUnavailable
                logCoachingEvent("request_failed", pending: pending, fields: [
                    "category": String(describing: safeError),
                    "duration_ms": Self.coachingMilliseconds(hostedCoachingTiming.now() - started)
                ])
                failHostedCoachingRequest(pending, error: safeError)
            }
            // Only a genuinely newer input may produce another call. A rejected
            // response must never cause an automatic retry of the same snapshot.
            if pendingHostedCoachingRequest?.id == pending.id { return }
        }
    }

    private func finishHostedCoachingFlight(_ pending: PendingHostedCoachingRequest) {
        hostedInFlightRequestID = nil
        if pendingHostedCoachingRequest?.id != pending.id {
            pendingHostedCoachingRequest?.previousFlightFinishedAt = hostedCoachingTiming.now()
        }
    }

    private func logCoachingEvent(
        _ name: String,
        pending: PendingHostedCoachingRequest? = nil,
        fields: [String: String] = [:]
    ) {
        guard hostedCoachingProvider != nil,
              let episodeID = pending?.correlation.episodeID ?? hostedCoachingSession?.episodeID else { return }
        coachingDiagnosticSequence += 1
        var fields = fields
        fields["schema_version"] = "coaching-client.v1"
        fields["game_id"] = pending?.correlation.gameID ?? hostedCoachingGameID
        fields["episode_id"] = episodeID
        fields["event_sequence"] = String(coachingDiagnosticSequence)
        fields["uptime_ms"] = Self.coachingMilliseconds(hostedCoachingTiming.now())
        fields["debounce_ms"] = Self.coachingMilliseconds(hostedCoachingTiming.debounceSeconds)
        if let pending { fields["request_id"] = pending.request.requestID }
        coachingDiagnosticSink(DiagnosticsEvent(category: "coaching", name: name, fields: fields))
    }

    private static func coachingMilliseconds(_ seconds: TimeInterval) -> String {
        String(Int((max(0, seconds) * 1000).rounded()))
    }

    private func queueCoachingRequest(
        context: CoachingRequest.Context,
        mismatchRetryCount: Int = 0
    ) {
        guard coachingSession != nil else { return }
        let requestedTentativeMove: Move?
        switch context {
        case .start:
            requestedTentativeMove = nil
        case .tentativeMove:
            requestedTentativeMove = tentativeMove
        }
        nextCoachingRequestID += 1
        let pending = PendingCoachingRequest(
            id: nextCoachingRequestID,
            request: CoachingRequest(
                committedState: committedState,
                tentativeMove: requestedTentativeMove,
                learner: committedState.sideToMove,
                positionRevision: coachingPositionRevision,
                context: context
            ),
            mismatchRetryCount: mismatchRetryCount
        )
        pendingCoachingRequest = pending
    }

    private func receiveCoachingAdvice(
        _ advice: CoachingAdvice,
        for pending: PendingCoachingRequest
    ) {
        guard pendingCoachingRequestIsApplicable(pending) else { return }
        guard advice.evaluation.request == pending.request else {
            if pending.mismatchRetryCount == 0 {
                pendingCoachingRequest = nil
                queueCoachingRequest(
                    context: pending.request.context,
                    mismatchRetryCount: 1
                )
            } else {
                receiveUnsupportedCoachingPosition(for: pending)
            }
            return
        }
        pendingCoachingRequest = nil
        let directives = coachingSession?.receive(
            advice,
            interaction: coachingInteractionSnapshot
        ) ?? []
        _ = applyCoachingDirectives(directives)
    }

    private func receiveUnsupportedCoachingPosition(
        for pending: PendingCoachingRequest
    ) {
        guard pendingCoachingRequestIsApplicable(pending) else { return }
        pendingCoachingRequest = nil
        let directives = coachingSession?.receiveUnsupportedPosition(
            for: pending.request.context,
            interaction: coachingInteractionSnapshot
        ) ?? []
        _ = applyCoachingDirectives(directives)
    }

    private func pendingCoachingRequestIsApplicable(
        _ pending: PendingCoachingRequest
    ) -> Bool {
        pendingCoachingRequest?.id == pending.id
            && pending.request.committedState == committedState
            && pending.request.tentativeMove == tentativeMove
            && pending.request.positionRevision == coachingPositionRevision
            && coachingSession != nil
    }

    @discardableResult
    private func applyCoachingDirectives(_ directives: [CoachingDirective]) -> Move? {
        var committedMove: Move?
        for directive in directives {
            switch directive {
            case let .requestAdvice(context):
                queueCoachingRequest(context: context)
            case .discardTentativeMove:
                restoreCommittedPosition()
            case .stop:
                stopCoaching()
            case .commitWithExistingDonePath:
                committedMove = finishTurn()
            }
        }
        return committedMove
    }

    @discardableResult
    private func synchronizeCoachingInteraction(debounced: Bool = true) -> Move? {
        if var hostedSession = hostedCoachingSession {
            let changed = hostedSession.recordInteraction(
                committedState: committedState,
                selectedSquare: selectedSquare,
                tentativeMove: tentativeMove
            )
            hostedCoachingSession = hostedSession
            logCoachingEvent("interaction", fields: [
                "disposition": changed ? "coaching" : "local",
                "selected_square": selectedSquare.map(ModelCoachingPositionEncoder.squareName) ?? "none",
                "kind": changed ? hostedSession.latestEvent.kind.rawValue : "selection"
            ])
            if changed {
                queueHostedCoachingRequest(debounced: debounced)
            }
            return nil
        }

        guard coachingSession != nil else { return nil }
        let directives = coachingSession?.handle(
            .interactionChanged(coachingInteractionSnapshot)
        ) ?? []
        return applyCoachingDirectives(directives)
    }

    private func isAcceptedCoachingAnswer(_ square: Square) -> Bool {
        guard var probe = coachingSession else { return false }
        let currentStage = probe.stage
        _ = probe.handle(.identificationTapped(square))
        return probe.stage != currentStage
    }

    private func isActionableCoachingTapRevision(at square: Square) -> Bool {
        guard localCanActForCurrentTurn,
              let tentativeMove else { return false }

        if legalDestinations.contains(square) {
            return true
        }

        let replacementMoves = allowedMoves(forSelectionAt: tentativeMove.from)
        if state.board[square] == nil {
            return replacementMoves.contains(where: { $0.to == square })
        }

        guard committedState.board[square]?.color == committedState.sideToMove else {
            return false
        }
        return !LegalMoveGenerator.allowedMoves(for: square, in: committedState).isEmpty
    }

    private func isActionableCoachingDragRevision(at square: Square) -> Bool {
        guard localCanActForCurrentTurn,
              let tentativeMove,
              state.board[square]?.color == committedState.sideToMove else {
            return false
        }

        if square == tentativeMove.to {
            return !allowedMoves(forSelectionAt: square).isEmpty
        }

        return !LegalMoveGenerator.allowedMoves(for: square, in: committedState).isEmpty
    }

    private func stopCoachingIfCurrentSeatBecameRemote(
        color: PieceColor,
        previous: PlayerSeat,
        current: PlayerSeat
    ) {
        guard committedState.sideToMove == color,
              previous.isLocal,
              !current.isLocal,
              isCoachingActive else { return }
        stopCoaching()
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
                supportersByTarget: [:]
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

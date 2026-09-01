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
        let committedState: GameState
        let tentativeMove: Move?
    }

    private var committedState: GameState
    private var tentativeMove: Move?
    private var committedCapturedPieces: [CapturedPiece] = []
    private var displayedAnalysis: PositionAnalysis
    private var actionableMovesForSelection: [Move] = []
    private let coachingAdvisor: any CoachingAdvising
    private let hostedCoachingProvider: (any HostedCoachingTurning)?
    private var coachingSession: CoachingSession?
    private var pendingCoachingRequest: PendingCoachingRequest?
    private var hostedCoachingSession: HostedCoachingSession?
    private var pendingHostedCoachingRequest: PendingHostedCoachingRequest?
    private var nextCoachingRequestID = 0
    private var coachingPositionRevision = 0
    var selectedSquare: Square?
    private(set) var analysisRevision = 0
    private(set) var isAwaitingPromotionChoice = false
    var isCoverageVisible = false
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
                for: hostedCoachingSession.phase,
                pulseID: hostedCoachingSession.pulseID
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
        if let hostedCoachingSession {
            return HostedCoachingPresentationProjector().presentation(
                for: hostedCoachingSession.phase,
                pulseID: hostedCoachingSession.pulseID
            ).boardTask
        }
        return coachingSession?.authoritativeBoardTask ?? .none
    }

    var pendingCoachingRequestID: Int? {
        pendingHostedCoachingRequest?.id ?? pendingCoachingRequest?.id
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
            return "Game forfeit."
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
        hostedCoachingProvider: (any HostedCoachingTurning)? = nil
    ) {
        self.committedState = state
        self.displayedAnalysis = Self.makeAnalysis(for: state)
        self.coachingAdvisor = coachingAdvisor
        self.hostedCoachingProvider = hostedCoachingProvider
    }

    convenience init(
        replayingCommittedMoves moves: [Move],
        hostedCoachingProvider: (any HostedCoachingTurning)? = nil
    ) {
        self.init(hostedCoachingProvider: hostedCoachingProvider)
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
        isCoverageVisible = false
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
        isCoverageVisible = false
        refreshDisplayedAnalysis()
        message = committedState.result == .ongoing ? nil : statusText
        stopCoaching()
        return true
    }

    func newGame() {
        stopCoaching()
        committedState = .startingPosition()
        coachingPositionRevision += 1
        tentativeMove = nil
        committedCapturedPieces = []
        selectedSquare = nil
        actionableMovesForSelection = []
        isCoverageVisible = false
        boardLockMessage = nil
        message = nil
        isAwaitingPromotionChoice = false
        refreshDisplayedAnalysis()
    }

    func endRemoteGame(message: String) {
        stopCoaching()
        let wasShowingTentativePosition = tentativeMove != nil
        boardLockMessage = message
        tentativeMove = nil
        actionableMovesForSelection = []
        isCoverageVisible = false
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
        isCoverageVisible = false
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
            var hostedSession = HostedCoachingSession(learner: committedState.sideToMove)
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
        if let pending = pendingHostedCoachingRequest,
           let hostedCoachingProvider,
           hostedCoachingSession != nil {
            do {
                let response = try await hostedCoachingProvider.turn(
                    for: pending.request,
                    contract: pending.contract,
                    continuationID: pending.continuationID
                )
                receiveHostedCoachingResponse(response, for: pending)
            } catch is CancellationError {
                return
            } catch {
                failHostedCoachingRequest(pending)
            }
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
            guard intent == .tap,
                  hostedSession.recordPieceSelectionAnswer(
                      at: square,
                      in: committedState
                  ) else { return false }
            selectWithoutSynchronizing(square)
            hostedCoachingSession = hostedSession
            queueHostedCoachingRequest()
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
                if hostedSession.phase == .failed {
                    hostedSession.recordRetry()
                } else {
                    hostedSession.recordHintAction()
                }
                hostedCoachingSession = hostedSession
                queueHostedCoachingRequest()
                return nil
            case .noAnswer:
                guard var hostedSession = hostedCoachingSession,
                      hostedSession.recordAction("noPieceNeedsHelp") else { return nil }
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
                _ = synchronizeCoachingInteraction()
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
        coachingSession = nil
        pendingCoachingRequest = nil
        hostedCoachingSession = nil
        pendingHostedCoachingRequest = nil
    }

    private func queueHostedCoachingRequest() {
        guard var hostedSession = hostedCoachingSession else { return }
        nextCoachingRequestID += 1
        let id = nextCoachingRequestID
        let request = hostedSession.request(
            committedState: committedState,
            selectedSquare: selectedSquare,
            tentativeMove: tentativeMove,
            positionRevision: coachingPositionRevision,
            requestID: "hosted-\(id)"
        )
        hostedCoachingSession = hostedSession
        pendingHostedCoachingRequest = PendingHostedCoachingRequest(
            id: id,
            request: request,
            contract: ModelCoachingChessNativeContextCompiler.responseContract(
                for: request,
                promptVersion: "tutor-v10"
            ),
            continuationID: hostedSession.continuationID,
            committedState: committedState,
            tentativeMove: tentativeMove
        )
    }

    private func receiveHostedCoachingResponse(
        _ response: HostedCoachingResponse,
        for pending: PendingHostedCoachingRequest
    ) {
        guard pendingHostedCoachingRequestIsApplicable(pending),
              response.requestID == pending.request.requestID,
              response.positionRevision == pending.request.positionRevision,
              var hostedSession = hostedCoachingSession else { return }
        pendingHostedCoachingRequest = nil
        hostedSession.receive(
            response.turn,
            continuationID: response.continuationID
        )
        hostedCoachingSession = hostedSession
    }

    private func failHostedCoachingRequest(_ pending: PendingHostedCoachingRequest) {
        guard pendingHostedCoachingRequestIsApplicable(pending),
              var hostedSession = hostedCoachingSession else { return }
        pendingHostedCoachingRequest = nil
        hostedSession.fail()
        hostedCoachingSession = hostedSession
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
    private func synchronizeCoachingInteraction() -> Move? {
        if var hostedSession = hostedCoachingSession {
            let changed = hostedSession.recordInteraction(
                committedState: committedState,
                selectedSquare: selectedSquare,
                tentativeMove: tentativeMove
            )
            hostedCoachingSession = hostedSession
            if changed {
                queueHostedCoachingRequest()
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

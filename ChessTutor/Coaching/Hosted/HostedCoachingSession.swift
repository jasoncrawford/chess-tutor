import Foundation

struct HostedCoachingSession: Equatable, Sendable {
    let learner: PieceColor
    let episodeID: String
    private(set) var phase: HostedCoachingPhase = .thinking
    private(set) var events: [ModelCoachingNeutralEpisodeEvent] = []
    private(set) var pulseID = 0
    private(set) var continuationID: String?

    private var lastSelectedSquare: Square?
    private var lastTentativeMove: Move?
    private var pendingSelectionQuestion: ModelCoachingChessNativeExpectedResponse?

    // Retain board input semantics independently of the visible thinking panel.
    var isAwaitingPieceAnswer: Bool { pendingSelectionQuestion != nil }

    var latestEvent: ModelCoachingNeutralEpisodeEvent {
        precondition(!events.isEmpty, "Hosted coaching must be opened before use")
        return events[events.count - 1]
    }

    init(
        learner: PieceColor,
        episodeID: String = UUID().uuidString.lowercased()
    ) {
        self.learner = learner
        self.episodeID = episodeID
    }

    mutating func openHelp(selectedSquare: Square?, tentativeMove: Move?) {
        events = []
        continuationID = nil
        pendingSelectionQuestion = nil
        lastSelectedSquare = selectedSquare
        lastTentativeMove = tentativeMove
        append(kind: .helpOpened, referencedIDs: [])
        phase = .thinking
    }

    @discardableResult
    mutating func recordInteraction(
        committedState: GameState,
        selectedSquare: Square?,
        tentativeMove: Move?
    ) -> Bool {
        defer {
            lastSelectedSquare = selectedSquare
            lastTentativeMove = tentativeMove
        }

        if tentativeMove != lastTentativeMove {
            pendingSelectionQuestion = nil
            if let tentativeMove {
                append(
                    kind: lastTentativeMove == nil ? .moveStaged : .moveReplaced,
                    referencedIDs: [ModelCoachingPositionEncoder.moveID(tentativeMove)]
                )
            } else if let removed = lastTentativeMove {
                append(
                    kind: .moveRemoved,
                    referencedIDs: [ModelCoachingPositionEncoder.moveID(removed)]
                )
            }
            phase = .thinking
            return true
        }

        _ = committedState
        return false
    }

    mutating func recordHintAction() {
        pendingSelectionQuestion = nil
        append(kind: .actionChosen, referencedIDs: ["action:hint"])
        phase = .thinking
    }

    @discardableResult
    mutating func recordAction(_ action: String) -> Bool {
        guard case .ready(let turn) = phase,
              turn.actions.contains(action)
                || (turn.expects == .judgeMoveSafety && action == "looksSafe") else {
            return false
        }
        append(kind: .actionChosen, referencedIDs: ["action:\(action)"])
        pendingSelectionQuestion = nil
        phase = .thinking
        return true
    }

    @discardableResult
    mutating func recordNegativeAnswer() -> Bool {
        guard case .ready(let turn) = phase else { return false }
        let action: String
        switch turn.expects {
        case .findEndangeredPiece:
            action = "noPieceNeedsHelp"
        case .findSafeCapture:
            action = "noSafeCapture"
        default:
            return false
        }
        append(kind: .actionChosen, referencedIDs: ["action:\(action)"])
        pendingSelectionQuestion = nil
        phase = .thinking
        return true
    }

    @discardableResult
    mutating func recordPieceSelectionAnswer(
        at square: Square,
        in committedState: GameState
    ) -> Bool {
        let expected: ModelCoachingChessNativeExpectedResponse?
        if case .ready(let turn) = phase {
            expected = turn.expects
        } else if phase == .thinking {
            expected = pendingSelectionQuestion
        } else {
            expected = nil
        }
        guard expected == .selectPiece
                || expected == .findEndangeredPiece
                || expected == .findSafeCapture,
              let piece = committedState.board[square] else { return false }
        let pieceID = ModelCoachingPositionEncoder.pieceID(piece, at: square)
        if phase == .thinking, latestEvent.kind == .pieceSelected,
           latestEvent.referencedIDs == [pieceID] {
            return false
        }
        pendingSelectionQuestion = expected
        append(
            kind: .pieceSelected,
            referencedIDs: [pieceID]
        )
        phase = .thinking
        return true
    }

    mutating func recordRetry() {
        pendingSelectionQuestion = nil
        append(kind: .helpReopened, referencedIDs: [])
        phase = .thinking
    }

    mutating func request(
        committedState: GameState,
        selectedSquare: Square?,
        tentativeMove: Move?,
        positionRevision: Int,
        requestID: String
    ) -> ModelCoachingNeutralRequest {
        phase = .thinking
        return ModelCoachingNeutralRequestBuilder.build(
            snapshot: ModelCoachingNeutralSnapshot(
                committedState: committedState,
                learner: learner,
                positionRevision: positionRevision,
                selectedSquare: selectedSquare,
                tentativeMove: tentativeMove,
                latestEvent: latestEvent,
                episodeEvents: events
            ),
            requestID: requestID
        )
    }

    mutating func receive(
        _ turn: ModelCoachingChessNativeTurn,
        continuationID: String
    ) {
        self.continuationID = continuationID
        pendingSelectionQuestion = nil
        phase = .ready(turn)
        pulseID += 1
    }

    mutating func fail(_ error: HostedCoachingTransportError = .serverUnavailable) {
        pendingSelectionQuestion = nil
        phase = error == .timedOut ? .timedOut : .failed
        pulseID += 1
    }

    private mutating func append(
        kind: ModelCoachingLearnerEventKind,
        referencedIDs: [String]
    ) {
        events.append(
            ModelCoachingNeutralEpisodeEvent(
                sequence: (events.last?.sequence ?? 0) + 1,
                kind: kind,
                referencedIDs: referencedIDs
            )
        )
    }
}

enum HostedCoachingPhase: Equatable, Sendable {
    case thinking
    case ready(ModelCoachingChessNativeTurn)
    case failed
    case timedOut
}

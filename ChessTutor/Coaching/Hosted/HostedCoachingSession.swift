struct HostedCoachingSession: Equatable, Sendable {
    let learner: PieceColor
    private(set) var phase: HostedCoachingPhase = .thinking
    private(set) var events: [ModelCoachingNeutralEpisodeEvent] = []
    private(set) var pulseID = 0

    private var lastSelectedSquare: Square?
    private var lastTentativeMove: Move?

    var latestEvent: ModelCoachingNeutralEpisodeEvent {
        precondition(!events.isEmpty, "Hosted coaching must be opened before use")
        return events[events.count - 1]
    }

    init(learner: PieceColor) {
        self.learner = learner
    }

    mutating func openHelp(selectedSquare: Square?, tentativeMove: Move?) {
        events = []
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

        guard selectedSquare != lastSelectedSquare,
              let selectedSquare,
              let piece = committedState.board[selectedSquare] else {
            return false
        }
        append(
            kind: piece.color == learner ? .pieceSelected : .squareInspected,
            referencedIDs: [ModelCoachingPositionEncoder.pieceID(piece, at: selectedSquare)]
        )
        phase = .thinking
        return true
    }

    mutating func recordHintAction() {
        append(kind: .actionChosen, referencedIDs: ["action:hint"])
        phase = .thinking
    }

    mutating func recordRetry() {
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

    mutating func receive(_ turn: ModelCoachingChessNativeTurn) {
        phase = .ready(turn)
        pulseID += 1
    }

    mutating func fail() {
        phase = .failed
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
}

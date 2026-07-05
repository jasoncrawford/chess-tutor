import Foundation

struct RemoteGameCoordinator {
    enum Error: Swift.Error, Equatable {
        case transportFailed
        case moveLogRejected
        case localMoveRejected
    }

    enum SyncStatus: Equatable {
        case current
        case uploading
        case fetching
        case failed(Error)
    }

    private let descriptor: RemoteGameDescriptor
    private let transport: any RemoteGameTransport
    private(set) var projectedState: GameState
    private(set) var acceptedEvents: [RemoteMoveEvent]
    private(set) var outbox: RemoteOutbox
    private(set) var lastAppliedSequence: Int
    private(set) var syncStatus: SyncStatus

    init(
        descriptor: RemoteGameDescriptor,
        transport: any RemoteGameTransport,
        initialState: GameState,
        acceptedEvents: [RemoteMoveEvent] = [],
        outbox: RemoteOutbox = RemoteOutbox(),
        lastAppliedSequence: Int = 0
    ) {
        self.descriptor = descriptor
        self.transport = transport
        self.projectedState = initialState
        self.acceptedEvents = acceptedEvents
        self.outbox = outbox
        self.lastAppliedSequence = lastAppliedSequence
        self.syncStatus = .current
    }

    @discardableResult
    mutating func recordLocalMove(
        _ move: Move,
        createdAt: Date = Date()
    ) throws -> RemoteMoveEvent {
        let localPlayerID = descriptor.localPlayerID
        guard localPlayerID == expectedActor(for: projectedState.sideToMove),
              LegalMoveGenerator.allLegalMoves(in: projectedState).contains(move) else {
            syncStatus = .failed(.localMoveRejected)
            throw Error.localMoveRejected
        }

        let previousFingerprint = PositionFingerprinting.fingerprint(for: projectedState)
        var resultingState = projectedState
        resultingState.apply(move)
        let resultingFingerprint = PositionFingerprinting.fingerprint(for: resultingState)

        let event = RemoteMoveEvent(
            id: RemoteMoveEventID(rawValue: "\(descriptor.id.rawValue)-\(lastAppliedSequence + 1)-\(localPlayerID.rawValue)"),
            gameID: descriptor.id,
            sequenceNumber: lastAppliedSequence + 1,
            actorPlayerID: localPlayerID,
            move: RemoteMoveCodec.encode(move),
            createdAt: createdAt,
            protocolVersion: descriptor.protocolVersion,
            previousPositionFingerprint: previousFingerprint,
            resultingPositionFingerprint: resultingFingerprint,
            notificationSummary: notificationSummary(for: move, in: projectedState)
        )

        projectedState = resultingState
        acceptedEvents.append(event)
        outbox.append(event)
        lastAppliedSequence = event.sequenceNumber
        syncStatus = .current
        return event
    }

    private func expectedActor(for color: PieceColor) -> RemotePlayerID {
        switch color {
        case .white:
            return descriptor.whitePlayer.id
        case .black:
            return descriptor.blackPlayer.id
        }
    }

    private func notificationSummary(for move: Move, in state: GameState) -> String {
        guard let piece = state.board[move.from] else {
            return "Move"
        }
        return "\(piece.color.rawValue.capitalized) \(piece.kind.rawValue) to \(RemoteMoveCodec.encodeSquare(move.to))"
    }
}

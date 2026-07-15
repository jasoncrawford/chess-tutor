import Foundation

@MainActor
final class RemoteGameSessionController {
    enum Error: Swift.Error, Equatable {
        case remoteMoveRejected
        case invalidSnapshot
    }

    private var coordinator: RemoteGameCoordinator
    let gameID: RemoteGameID

    var syncStatus: RemoteGameCoordinator.SyncStatus {
        coordinator.syncStatus
    }

    var hasPendingUploads: Bool {
        coordinator.hasPendingUploads
    }

    var snapshot: ActiveRemoteGameSnapshot {
        coordinator.snapshot
    }

    init(
        descriptor: RemoteGameDescriptor,
        transport: any RemoteGameTransport,
        initialState: GameState
    ) {
        self.gameID = descriptor.id
        self.coordinator = RemoteGameCoordinator(
            descriptor: descriptor,
            transport: transport,
            initialState: initialState
        )
    }

    init(
        snapshot: ActiveRemoteGameSnapshot,
        transport: any RemoteGameTransport
    ) throws {
        let projectedState = try Self.projectedState(from: snapshot)
        self.gameID = snapshot.descriptor.id
        self.coordinator = RemoteGameCoordinator(
            descriptor: snapshot.descriptor,
            transport: transport,
            initialState: projectedState,
            acceptedEvents: snapshot.acceptedEvents,
            outbox: snapshot.outbox,
            lastAppliedSequence: snapshot.lastAppliedSequence
        )
    }

    func recordCommittedLocalMove(
        _ move: Move,
        createdAt: Date = Date()
    ) throws {
        try coordinator.recordLocalMove(move, createdAt: createdAt)
    }

    func uploadPendingMoves() async throws {
        var nextCoordinator = coordinator
        do {
            try await nextCoordinator.uploadPendingMoves()
            coordinator = nextCoordinator
        } catch {
            coordinator = nextCoordinator
            throw error
        }
    }

    @discardableResult
    func fetchAndApplyRemoteMoves(to session: GameSession) async throws -> [Move] {
        var nextCoordinator = coordinator
        let events: [RemoteMoveEvent]
        do {
            events = try await nextCoordinator.fetchAndApplyRemoteMoves()
        } catch {
            coordinator = nextCoordinator
            throw error
        }
        var appliedMoves: [Move] = []

        for event in events {
            let move = try RemoteMoveCodec.decode(event.move)
            guard session.commitRemoteMove(move) else {
                throw Error.remoteMoveRejected
            }
            appliedMoves.append(move)
        }

        coordinator = nextCoordinator
        return appliedMoves
    }

    static func projectedState(from snapshot: ActiveRemoteGameSnapshot) throws -> GameState {
        let result = try RemoteMoveLog.apply(
            events: snapshot.acceptedEvents,
            to: .startingPosition(),
            gameID: snapshot.descriptor.id,
            protocolVersion: snapshot.descriptor.protocolVersion,
            whitePlayerID: snapshot.descriptor.whitePlayer.id,
            blackPlayerID: snapshot.descriptor.blackPlayer.id
        )
        guard result.lastAppliedSequence == snapshot.lastAppliedSequence else {
            throw Error.invalidSnapshot
        }
        return result.state
    }
}

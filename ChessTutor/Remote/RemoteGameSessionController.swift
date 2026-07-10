import Foundation

@MainActor
final class RemoteGameSessionController {
    enum Error: Swift.Error, Equatable {
        case remoteMoveRejected
    }

    private var coordinator: RemoteGameCoordinator
    let gameID: RemoteGameID

    var syncStatus: RemoteGameCoordinator.SyncStatus {
        coordinator.syncStatus
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
}

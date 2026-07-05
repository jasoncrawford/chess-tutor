#if DEBUG
import Foundation
import Observation

@Observable
@MainActor
final class FakeRemoteGameLab {
    enum Error: Swift.Error, Equatable {
        case inactive
        case noRemoteMoveAvailable
        case remoteMoveRejected
        case syncFailed
    }

    private let gameID = RemoteGameID(rawValue: "fake-remote-game")
    private let localPlayerID = RemotePlayerID(rawValue: "local")
    private let remotePlayerID = RemotePlayerID(rawValue: "maya")
    private let transport = InMemoryRemoteGameTransport()
    private var coordinator: RemoteGameCoordinator?
    private var localPlayerColor: PieceColor = .white

    private(set) var isActive = false
    private(set) var statusText = "Local game"
    private(set) var lastRemoteMove: Move?

    var canRemotePlay: Bool {
        guard let coordinator else {
            return false
        }
        return isActive && coordinator.projectedState.sideToMove != localPlayerColor
    }

    func start(session: GameSession, localPlayerColor: PieceColor = .white) {
        session.newGame()
        self.localPlayerColor = localPlayerColor
        switch localPlayerColor {
        case .white:
            session.whitePlayer = .humanLocal
            session.blackPlayer = .remote(playerID: "maya")
        case .black:
            session.whitePlayer = .remote(playerID: "maya")
            session.blackPlayer = .humanLocal
        }
        coordinator = RemoteGameCoordinator(
            descriptor: descriptor(),
            transport: transport,
            initialState: session.state
        )
        isActive = true
        statusText = "Fake remote game"
        lastRemoteMove = nil
    }

    func stop(session: GameSession) {
        session.whitePlayer = .humanLocal
        session.blackPlayer = .humanLocal
        coordinator = nil
        localPlayerColor = .white
        isActive = false
        statusText = "Local game"
        lastRemoteMove = nil
    }

    func recordCommittedLocalMove(_ move: Move) async throws {
        guard isActive, var coordinator else {
            return
        }

        do {
            try coordinator.recordLocalMove(move)
            try await coordinator.uploadPendingMoves()
            self.coordinator = coordinator
            statusText = "Waiting for Maya"
        } catch {
            self.coordinator = coordinator
            statusText = "Fake sync failed"
            throw Error.syncFailed
        }
    }

    @discardableResult
    func remotePlaysNextMove(session: GameSession) async throws -> Bool {
        guard isActive, var coordinator else {
            throw Error.inactive
        }

        let legalMoves = LegalMoveGenerator.allLegalMoves(in: coordinator.projectedState)
        guard let move = preferredRemoteMove(from: legalMoves) else {
            statusText = "Maya has no move"
            throw Error.noRemoteMoveAvailable
        }

        let event = makeRemoteEvent(
            move: move,
            sequenceNumber: coordinator.lastAppliedSequence + 1,
            from: coordinator.projectedState
        )
        await transport.storeForTesting(event)

        let fetchedEvents: [RemoteMoveEvent]
        do {
            fetchedEvents = try await coordinator.fetchAndApplyRemoteMoves()
        } catch {
            self.coordinator = coordinator
            statusText = "Fake sync failed"
            throw Error.syncFailed
        }

        for event in fetchedEvents.sorted(by: { $0.sequenceNumber < $1.sequenceNumber }) {
            let fetchedMove = try RemoteMoveCodec.decode(event.move)
            guard session.commitRemoteMove(fetchedMove) else {
                self.coordinator = coordinator
                statusText = "Remote move rejected"
                throw Error.remoteMoveRejected
            }
            lastRemoteMove = fetchedMove
        }

        self.coordinator = coordinator
        statusText = "Maya moved"
        return !fetchedEvents.isEmpty
    }

    private func descriptor() -> RemoteGameDescriptor {
        let whitePlayer: RemotePlayerRef
        let blackPlayer: RemotePlayerRef
        switch localPlayerColor {
        case .white:
            whitePlayer = RemotePlayerRef(id: localPlayerID, displayName: "You")
            blackPlayer = RemotePlayerRef(id: remotePlayerID, displayName: "Maya")
        case .black:
            whitePlayer = RemotePlayerRef(id: remotePlayerID, displayName: "Maya")
            blackPlayer = RemotePlayerRef(id: localPlayerID, displayName: "You")
        }

        return RemoteGameDescriptor(
            id: gameID,
            protocolVersion: 1,
            status: .active,
            whitePlayer: whitePlayer,
            blackPlayer: blackPlayer,
            localPlayerID: localPlayerID
        )
    }

    private func preferredRemoteMove(from legalMoves: [Move]) -> Move? {
        let preferredMove: Move
        switch localPlayerColor {
        case .white:
            preferredMove = Move(
                from: Square(file: .e, rank: 7),
                to: Square(file: .e, rank: 5)
            )
        case .black:
            preferredMove = Move(
                from: Square(file: .e, rank: 2),
                to: Square(file: .e, rank: 4)
            )
        }
        return legalMoves.first { $0 == preferredMove } ?? legalMoves.first
    }

    private func makeRemoteEvent(
        move: Move,
        sequenceNumber: Int,
        from state: GameState
    ) -> RemoteMoveEvent {
        var nextState = state
        nextState.apply(move)
        return RemoteMoveEvent(
            id: RemoteMoveEventID(rawValue: "\(gameID.rawValue)-\(sequenceNumber)-\(remotePlayerID.rawValue)"),
            gameID: gameID,
            sequenceNumber: sequenceNumber,
            actorPlayerID: remotePlayerID,
            move: RemoteMoveCodec.encode(move),
            createdAt: Date(),
            protocolVersion: 1,
            previousPositionFingerprint: PositionFingerprinting.fingerprint(for: state),
            resultingPositionFingerprint: PositionFingerprinting.fingerprint(for: nextState),
            notificationSummary: "Maya moved"
        )
    }
}
#endif

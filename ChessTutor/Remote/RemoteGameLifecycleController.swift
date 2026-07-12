import Observation

struct RemoteGameStartResult: Equatable {
    let descriptor: RemoteGameDescriptor
    let shouldStartSyncImmediately: Bool
}

@MainActor
@Observable
final class RemoteGameLifecycleController {
    private let session: GameSession
    private let remotePlayFlow: RemotePlayFlow
    private let remoteGameTransport: any RemoteGameTransport

    var pendingRemoteStartAnnouncement: RemoteGameStartAnnouncement?
    var pendingRemoteInviteConfirmation: RemoteInviteConfirmation?
    var pendingRemoteInviteAcceptance: RemotePendingInvite?
    var activeRemoteGameController: RemoteGameSessionController?
    var remoteOpponentPresence: RemotePresenceUpdate?

    init(
        session: GameSession,
        remotePlayFlow: RemotePlayFlow,
        remoteGameTransport: any RemoteGameTransport,
        activeRemoteGameController: RemoteGameSessionController? = nil
    ) {
        self.session = session
        self.remotePlayFlow = remotePlayFlow
        self.remoteGameTransport = remoteGameTransport
        self.activeRemoteGameController = activeRemoteGameController
    }

    var activeRemoteGameOpponent: KnownRemotePlayer? {
        guard let descriptor = activeRemoteGameController?.snapshot.descriptor else {
            return nil
        }

        let opponent = Self.opponent(from: descriptor)
        return KnownRemotePlayer(id: opponent.id, displayName: opponent.displayName)
    }

    @discardableResult
    func inviteActiveRemoteOpponentAgain() -> Bool {
        guard let opponent = activeRemoteGameOpponent else {
            return false
        }
        remotePlayFlow.open()
        remotePlayFlow.invite(opponent)
        return true
    }

    func showRemoteInviteConfirmation(
        _ confirmation: RemoteInviteConfirmation,
        invite: RemotePendingInvite? = nil
    ) {
        pendingRemoteInviteConfirmation = confirmation
        pendingRemoteInviteAcceptance = invite
    }

    func selectRemoteInviteColor(_ color: PieceColor) {
        pendingRemoteInviteConfirmation = pendingRemoteInviteConfirmation?.selectColor(color)
    }

    func cancelRemoteInviteConfirmation() {
        pendingRemoteInviteConfirmation = nil
        pendingRemoteInviteAcceptance = nil
    }

    func dismissRemoteStartAnnouncement() {
        pendingRemoteStartAnnouncement = nil
    }

    func startRemoteGame(
        context: RemoteGameStartContext,
        role: RemoteGameStartRole
    ) -> RemoteGameStartResult {
        clearRemoteGameState()
        session.newGame()
        Self.applyRemoteSeats(from: context.descriptor, to: session)
        activeRemoteGameController = RemoteGameSessionController(
            descriptor: context.descriptor,
            transport: remoteGameTransport,
            initialState: .startingPosition()
        )
        remotePlayFlow.cancel()

        if RemoteGameStartPresentationPolicy.shouldShowAnnouncement(for: role) {
            pendingRemoteStartAnnouncement = RemoteGameStartAnnouncement(
                opponentName: context.opponent.displayName,
                localPlayerColor: context.localPlayerColor
            )
            return RemoteGameStartResult(descriptor: context.descriptor, shouldStartSyncImmediately: false)
        }

        return RemoteGameStartResult(descriptor: context.descriptor, shouldStartSyncImmediately: true)
    }

    func clearRemoteGameState() {
        remoteOpponentPresence = nil
        activeRemoteGameController = nil
    }

    func endRemoteGameAfterOpponentEnded(descriptor: RemoteGameDescriptor) {
        clearRemoteGameState()
        session.endRemoteGame(message: "\(Self.opponent(from: descriptor).displayName) ended this game.")
    }

    static func applyRemoteSeats(from descriptor: RemoteGameDescriptor, to session: GameSession) {
        if descriptor.localPlayerID == descriptor.whitePlayer.id {
            session.whitePlayer = .humanLocal
            session.blackPlayer = .remote(playerID: descriptor.blackPlayer.id.rawValue)
        } else {
            session.whitePlayer = .remote(playerID: descriptor.whitePlayer.id.rawValue)
            session.blackPlayer = .humanLocal
        }
    }

    static func opponent(from descriptor: RemoteGameDescriptor) -> RemotePlayerRef {
        if descriptor.localPlayerID == descriptor.whitePlayer.id {
            return descriptor.blackPlayer
        }
        return descriptor.whitePlayer
    }
}

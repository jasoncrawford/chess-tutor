import Foundation

@MainActor
enum GameLifecycle {
    static func startNewGame(
        session: GameSession,
        remotePlayFlow: RemotePlayFlow
    ) {
        remotePlayFlow.cancel()
        session.whitePlayer = .humanLocal
        session.blackPlayer = .humanLocal
        session.newGame()
    }

    #if DEBUG
    static func startNewGame(
        session: GameSession,
        remotePlayFlow: RemotePlayFlow,
        fakeRemoteLab: FakeRemoteGameLab?
    ) {
        fakeRemoteLab?.stop(session: session)
        startNewGame(session: session, remotePlayFlow: remotePlayFlow)
    }
    #endif
}

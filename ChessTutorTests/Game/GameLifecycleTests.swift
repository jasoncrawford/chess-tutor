import XCTest
@testable import ChessTutor

@MainActor
final class GameLifecycleTests: XCTestCase {
    #if DEBUG
    func testNewGameStopsFakeRemoteGameAndRestoresLocalSeats() {
        let session = GameSession()
        let flow = RemotePlayFlow()
        let fakeRemoteLab = FakeRemoteGameLab()
        fakeRemoteLab.start(session: session, localPlayerColor: .black)

        GameLifecycle.startNewGame(
            session: session,
            remotePlayFlow: flow,
            fakeRemoteLab: fakeRemoteLab
        )

        XCTAssertFalse(fakeRemoteLab.isActive)
        XCTAssertEqual(session.whitePlayer, .humanLocal)
        XCTAssertEqual(session.blackPlayer, .humanLocal)
        XCTAssertFalse(session.hasGameInProgress)
    }
    #endif
}

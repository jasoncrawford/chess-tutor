import XCTest
@testable import ChessTutor

@MainActor
final class GameLifecycleTests: XCTestCase {
    func testNewLocalGameAfterRealRemoteGameRestoresLocalSeats() {
        let session = GameSession()
        let flow = RemotePlayFlow()
        session.whitePlayer = .humanLocal
        session.blackPlayer = .remote(playerID: "maya")

        GameLifecycle.startNewGame(session: session, remotePlayFlow: flow)

        XCTAssertEqual(session.whitePlayer, .humanLocal)
        XCTAssertEqual(session.blackPlayer, .humanLocal)
        XCTAssertFalse(session.hasGameInProgress)
    }

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

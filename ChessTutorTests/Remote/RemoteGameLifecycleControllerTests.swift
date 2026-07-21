import XCTest
@testable import ChessTutor

@MainActor
final class RemoteGameLifecycleControllerTests: XCTestCase {
    func testStartingRemoteGameAsInviterResetsBoardClosesInviteFlowAndShowsAnnouncement() {
        let session = GameSession()
        session.select(Square(file: .e, rank: 2))
        XCTAssertEqual(session.moveSelectedPiece(to: Square(file: .e, rank: 4)), .moved)
        XCTAssertNotNil(session.finishTurn())

        let flow = RemotePlayFlow(localDisplayName: "Jason")
        flow.open()
        let controller = RemoteGameLifecycleController(
            session: session,
            remotePlayFlow: flow,
            remoteGameTransport: InMemoryRemoteGameTransport()
        )

        let result = controller.startRemoteGame(context: Self.startContext(localPlayerColor: .white), role: .inviter)

        XCTAssertEqual(session.state.moveHistory, [])
        XCTAssertEqual(session.whitePlayer, .humanLocal)
        XCTAssertEqual(session.blackPlayer, .remote(playerID: "maya"))
        XCTAssertNotNil(controller.activeRemoteGameController)
        XCTAssertEqual(flow.stage, .closed)
        XCTAssertEqual(
            controller.pendingRemoteStartAnnouncement,
            RemoteGameStartAnnouncement(opponentName: "Maya", localPlayerColor: .white)
        )
        XCTAssertFalse(result.shouldStartSyncImmediately)
    }

    func testStartingRemoteGameAsJoinerStartsWithoutSecondAnnouncement() {
        let session = GameSession()
        let flow = RemotePlayFlow(localDisplayName: "Jason")
        flow.open()
        let controller = RemoteGameLifecycleController(
            session: session,
            remotePlayFlow: flow,
            remoteGameTransport: InMemoryRemoteGameTransport()
        )

        let result = controller.startRemoteGame(context: Self.startContext(localPlayerColor: .black), role: .joiner)

        XCTAssertEqual(session.whitePlayer, .remote(playerID: "jason"))
        XCTAssertEqual(session.blackPlayer, .humanLocal)
        XCTAssertNotNil(controller.activeRemoteGameController)
        XCTAssertEqual(flow.stage, .closed)
        XCTAssertNil(controller.pendingRemoteStartAnnouncement)
        XCTAssertTrue(result.shouldStartSyncImmediately)
    }

    func testInviteActiveRemoteOpponentAgainOpensInviteFlowForKnownOpponent() {
        let session = GameSession()
        let flow = RemotePlayFlow(localDisplayName: "Jason")
        let controller = RemoteGameLifecycleController(
            session: session,
            remotePlayFlow: flow,
            remoteGameTransport: InMemoryRemoteGameTransport()
        )
        _ = controller.startRemoteGame(context: Self.startContext(localPlayerColor: .white), role: .joiner)

        XCTAssertTrue(controller.inviteActiveRemoteOpponentAgain())

        XCTAssertEqual(flow.stage, .choosingWhite(.known(KnownRemotePlayer(id: Self.maya.id, displayName: "Maya"))))
    }

    func testCancelRemoteInviteConfirmationClearsPendingAcceptanceAndTaskState() {
        let session = GameSession()
        let flow = RemotePlayFlow(localDisplayName: "Jason")
        let controller = RemoteGameLifecycleController(
            session: session,
            remotePlayFlow: flow,
            remoteGameTransport: InMemoryRemoteGameTransport()
        )
        let invite = Self.pendingInvite()

        controller.showRemoteInviteConfirmation(
            RemoteInviteConfirmation(opponentName: "Maya", localPlayerColor: nil),
            invite: invite
        )
        controller.selectRemoteInviteColor(.black)
        controller.cancelRemoteInviteConfirmation()

        XCTAssertNil(controller.pendingRemoteInviteConfirmation)
        XCTAssertNil(controller.pendingRemoteInviteAcceptance)
    }

    func testCancelRemoteInviteConfirmationCanExplainTerminalInviteState() {
        let session = GameSession()
        let flow = RemotePlayFlow(localDisplayName: "Jason")
        let controller = RemoteGameLifecycleController(
            session: session,
            remotePlayFlow: flow,
            remoteGameTransport: InMemoryRemoteGameTransport()
        )
        controller.showRemoteInviteConfirmation(
            RemoteInviteConfirmation(opponentName: "Maya", localPlayerColor: .white),
            invite: Self.pendingInvite()
        )

        controller.cancelRemoteInviteConfirmation(message: "Sorry, Maya left this game.")

        XCTAssertNil(controller.pendingRemoteInviteConfirmation)
        XCTAssertNil(controller.pendingRemoteInviteAcceptance)
        XCTAssertEqual(session.message, "Sorry, Maya left this game.")
    }

    func testEndingAfterOpponentEndedClearsActiveGameAndLocksBoardWithMessage() {
        let session = GameSession()
        let flow = RemotePlayFlow(localDisplayName: "Jason")
        let controller = RemoteGameLifecycleController(
            session: session,
            remotePlayFlow: flow,
            remoteGameTransport: InMemoryRemoteGameTransport()
        )
        let context = Self.startContext(localPlayerColor: .white)
        _ = controller.startRemoteGame(context: context, role: .joiner)

        controller.endRemoteGameAfterOpponentEnded(descriptor: context.descriptor)

        XCTAssertNil(controller.activeRemoteGameController)
        XCTAssertFalse(session.localCanActForCurrentTurn)
        XCTAssertEqual(session.message, "Maya ended this game.")
    }

    private static let jason = RemotePlayerRef(
        id: RemotePlayerID(rawValue: "jason"),
        displayName: "Jason"
    )

    private static let maya = RemotePlayerRef(
        id: RemotePlayerID(rawValue: "maya"),
        displayName: "Maya"
    )

    private static func startContext(localPlayerColor: PieceColor) -> RemoteGameStartContext {
        let localPlayerID = localPlayerColor == .white ? jason.id : maya.id
        let descriptor = RemoteGameDescriptor(
            id: RemoteGameID(rawValue: "game-1"),
            protocolVersion: 1,
            status: .active,
            whitePlayer: jason,
            blackPlayer: maya,
            localPlayerID: localPlayerID
        )
        return RemoteGameStartContext(
            descriptor: descriptor,
            opponent: localPlayerColor == .white ? maya : jason,
            localPlayerColor: localPlayerColor
        )
    }

    private static func pendingInvite() -> RemotePendingInvite {
        RemotePendingInvite(
            id: RemoteInviteID(rawValue: "invite-1"),
            code: InviteCode(rawValue: "428193"),
            token: RemoteInviteToken(rawValue: "token-1"),
            inviter: maya,
            inviteeDisplayName: "Jason",
            whiteAssignment: .inviteeChooses,
            status: .pending,
            createdAt: Date(timeIntervalSince1970: 0),
            expiresAt: Date(timeIntervalSince1970: 600),
            protocolVersion: 1
        )
    }
}

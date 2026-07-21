import XCTest
@testable import ChessTutor

final class RemotePushNotificationRoutingTests: XCTestCase {
    func testRoutesRemoteGameMoveSubscriptionToMoveEventAndNotification() throws {
        let routed = try XCTUnwrap(
            RemotePushNotificationRouting.route(subscriptionID: "remote-game-moves-game-1")
        )

        XCTAssertEqual(routed.event, .remoteGameMove(RemoteGameID(rawValue: "game-1")))
        XCTAssertEqual(routed.name, .remoteGameMovesMayHaveChanged)
        XCTAssertEqual(routed.userInfo[RemoteGameMovePushUserInfoKey.gameID], "game-1")
        XCTAssertEqual(routed.diagnosticsName, "remoteGameMove")
        XCTAssertEqual(routed.diagnosticsFields["gameID"], "game-1")
    }

    func testRoutesRemoteGameStatusSubscriptionToStatusEventAndNotification() throws {
        let routed = try XCTUnwrap(
            RemotePushNotificationRouting.route(subscriptionID: "remote-game-status-game-1")
        )

        XCTAssertEqual(routed.event, .remoteGameStatus(RemoteGameID(rawValue: "game-1")))
        XCTAssertEqual(routed.name, .remoteGameStatusMayHaveChanged)
        XCTAssertEqual(routed.userInfo[RemoteGameStatusPushUserInfoKey.gameID], "game-1")
        XCTAssertEqual(routed.diagnosticsName, "remoteGameStatus")
        XCTAssertEqual(routed.diagnosticsFields["gameID"], "game-1")
    }

    func testRoutesInviteStatusSubscriptionThroughInviteAcceptanceNotification() throws {
        let routed = try XCTUnwrap(
            RemotePushNotificationRouting.route(subscriptionID: "pending-invite-status-invite-1")
        )

        XCTAssertEqual(routed.event, .remoteInviteAcceptance(RemoteInviteID(rawValue: "invite-1")))
        XCTAssertEqual(routed.name, .remoteInviteAcceptanceMayHaveChanged)
        XCTAssertEqual(routed.userInfo[RemoteInviteAcceptancePushUserInfoKey.inviteID], "invite-1")
        XCTAssertEqual(routed.diagnosticsName, "remoteInviteStatus")
        XCTAssertEqual(routed.diagnosticsFields["inviteID"], "invite-1")
    }

    func testRoutesIncomingInviteSubscriptionToPendingInviteNotification() throws {
        let routed = try XCTUnwrap(
            RemotePushNotificationRouting.route(subscriptionID: "pending-invite-for-player-1")
        )

        XCTAssertEqual(routed.event, .remotePendingInvite(RemotePlayerID(rawValue: "player-1")))
        XCTAssertEqual(routed.name, .remotePendingInvitesMayHaveChanged)
        XCTAssertEqual(routed.userInfo[RemotePendingInvitePushUserInfoKey.playerID], "player-1")
        XCTAssertEqual(routed.diagnosticsName, "remotePendingInvite")
        XCTAssertEqual(routed.diagnosticsFields["playerID"], "player-1")
    }

    func testUnknownSubscriptionDoesNotRoute() {
        XCTAssertNil(RemotePushNotificationRouting.route(subscriptionID: "something-else"))
    }

    func testLaunchMoveNotificationIsBufferedForReplay() throws {
        _ = RemotePushNotificationInbox.shared.drain()

        let routed = try XCTUnwrap(
            RemotePushNotificationRouting.recordLaunchNotification(
                subscriptionID: "remote-game-moves-game-1"
            )
        )

        XCTAssertEqual(routed.event, .remoteGameMove(RemoteGameID(rawValue: "game-1")))
        XCTAssertEqual(
            RemotePushNotificationInbox.shared.drain(),
            [.remoteGameMove(RemoteGameID(rawValue: "game-1"))]
        )
    }

    func testUnknownLaunchNotificationIsNotBuffered() {
        _ = RemotePushNotificationInbox.shared.drain()

        XCTAssertNil(
            RemotePushNotificationRouting.recordLaunchNotification(subscriptionID: "something-else")
        )

        XCTAssertEqual(RemotePushNotificationInbox.shared.drain(), [])
    }
}

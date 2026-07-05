import XCTest
@testable import ChessTutor

final class RemotePlayFlowTests: XCTestCase {
    func testKnownPlayerInviteCreatesPendingInviteWithWhiteChoice() {
        let maya = KnownRemotePlayer(id: RemotePlayerID(rawValue: "maya"), displayName: "Maya")
        let flow = RemotePlayFlow(knownPlayers: [maya], nextInviteCode: "428193")

        flow.open()
        flow.invite(maya)
        flow.chooseWhite(.invitee)

        let pendingInvite = flow.sendInvite()

        XCTAssertEqual(flow.stage, .waitingForInvitee(pendingInvite))
        XCTAssertEqual(pendingInvite.target, .known(maya))
        XCTAssertEqual(pendingInvite.whiteChoice, .invitee)
        XCTAssertEqual(pendingInvite.code, "428193")
        XCTAssertEqual(pendingInvite.formattedCode, "428 193")
    }

    func testCancelClosesFlowAndClearsPendingInvite() {
        let flow = RemotePlayFlow(knownPlayers: [], nextInviteCode: "428193")

        flow.open()
        flow.inviteSomeoneNew()
        _ = flow.sendInvite()

        flow.cancel()

        XCTAssertEqual(flow.stage, .closed)
    }

    func testBackFromWhiteChoiceReturnsToInviteeSelection() {
        let maya = KnownRemotePlayer(id: RemotePlayerID(rawValue: "maya"), displayName: "Maya")
        let flow = RemotePlayFlow(knownPlayers: [maya], nextInviteCode: "428193")

        flow.open()
        flow.invite(maya)
        flow.chooseWhite(.invitee)

        flow.goBack()

        XCTAssertEqual(flow.stage, .choosing)
        XCTAssertEqual(flow.selectedWhiteChoice, .localPlayer)
    }

    func testInviteEntryPointIsOnlyAvailableBeforeLocalPlayBegins() {
        let flow = RemotePlayFlow()
        let session = GameSession()

        XCTAssertTrue(flow.canShowEntryPoint(for: session))

        session.select(Square(file: .e, rank: 2))
        _ = session.moveSelectedPiece(to: Square(file: .e, rank: 4))

        XCTAssertFalse(flow.canShowEntryPoint(for: session))
    }
}

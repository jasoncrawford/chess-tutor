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

    func testJoinCodeEnablesAtSixDigitsAndRejectsWrongCode() {
        let flow = RemotePlayFlow(nextInviteCode: "428193")

        flow.open()
        flow.updateJoinCode("12a34 5")

        XCTAssertEqual(flow.joinCode, "12345")
        XCTAssertFalse(flow.canSubmitJoinCode)

        flow.updateJoinCode("12a34 56")

        XCTAssertEqual(flow.joinCode, "123456")
        XCTAssertTrue(flow.canSubmitJoinCode)
        XCTAssertFalse(flow.acceptJoinCode())
        XCTAssertEqual(flow.joinErrorMessage, "That code did not match an open invite.")
    }

    func testAcceptJoinCodeWaitsForInviterApproval() {
        let flow = RemotePlayFlow(nextInviteCode: "428193")

        flow.open()
        flow.updateJoinCode("428 193")

        XCTAssertTrue(flow.acceptJoinCode())
        XCTAssertEqual(
            flow.stage,
            .waitingForInviterApproval(
                RemotePlayFlow.OutgoingJoinRequest(code: "428193", inviterDisplayName: "the inviter")
            )
        )
        XCTAssertEqual(flow.joinCode, "")
        XCTAssertNil(flow.joinErrorMessage)
    }

    func testJoinRequestRequiresInviterApproval() {
        let maya = KnownRemotePlayer(id: RemotePlayerID(rawValue: "maya"), displayName: "Maya")
        let flow = RemotePlayFlow(knownPlayers: [maya], nextInviteCode: "428193")

        flow.open()
        flow.invite(maya)
        let pendingInvite = flow.sendInvite()

        let pendingJoinRequest = flow.receiveJoinRequest(displayName: "Maya")

        XCTAssertEqual(
            flow.stage,
            .reviewingJoinRequest(pendingJoinRequest)
        )
        XCTAssertEqual(pendingJoinRequest.invite, pendingInvite)
        XCTAssertEqual(pendingJoinRequest.joinerDisplayName, "Maya")

        XCTAssertEqual(flow.approveJoinRequest(), pendingJoinRequest)
        XCTAssertEqual(flow.stage, .closed)
    }

    func testDecliningJoinRequestReturnsToWaitingForInvitee() {
        let flow = RemotePlayFlow(nextInviteCode: "428193")

        flow.open()
        flow.inviteSomeoneNew()
        let pendingInvite = flow.sendInvite()
        _ = flow.receiveJoinRequest(displayName: "Maya")

        flow.declineJoinRequest()

        XCTAssertEqual(flow.stage, .waitingForInvitee(pendingInvite))
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

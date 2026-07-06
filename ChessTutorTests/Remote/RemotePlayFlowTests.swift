import XCTest
@testable import ChessTutor

final class RemotePlayFlowTests: XCTestCase {
    func testKnownPlayerInviteCreatesPendingInviteWithWhiteChoice() throws {
        let maya = KnownRemotePlayer(id: RemotePlayerID(rawValue: "maya"), displayName: "Maya")
        let flow = RemotePlayFlow(
            knownPlayers: [maya],
            localDisplayName: "Jason",
            nextInviteCode: "428193"
        )

        flow.open()
        flow.invite(maya)
        flow.chooseWhite(.invitee)

        let pendingInvite = try XCTUnwrap(flow.requestSendInvite())
        XCTAssertEqual(flow.stage, .waitingForInvitee(pendingInvite))
        XCTAssertEqual(pendingInvite.target, .known(maya))
        XCTAssertEqual(pendingInvite.whiteChoice, .invitee)
        XCTAssertEqual(pendingInvite.code, "428193")
        XCTAssertEqual(pendingInvite.formattedCode, "428 193")
    }

    func testSendInviteRequiresLocalDisplayName() {
        let maya = KnownRemotePlayer(id: RemotePlayerID(rawValue: "maya"), displayName: "Maya")
        let flow = RemotePlayFlow(knownPlayers: [maya], nextInviteCode: "428193")

        flow.open()
        flow.invite(maya)
        flow.chooseWhite(.invitee)

        XCTAssertNil(flow.requestSendInvite())
        XCTAssertEqual(flow.stage, .enteringLocalName(.sendInvite))

        flow.updateLocalNameDraft("  Jason  ")
        let result = flow.saveLocalNameAndContinue()

        XCTAssertEqual(flow.localDisplayName, "Jason")
        XCTAssertEqual(
            result,
            .sentInvite(
                RemotePlayFlow.PendingInvite(
                    target: .known(maya),
                    whiteChoice: .invitee,
                    code: "428193"
                )
            )
        )
    }

    func testRememberKnownPlayerUpdatesExistingPlayer() {
        let maya = KnownRemotePlayer(id: RemotePlayerID(rawValue: "maya"), displayName: "Maya")
        let flow = RemotePlayFlow(knownPlayers: [maya])

        flow.rememberKnownPlayer(KnownRemotePlayer(id: maya.id, displayName: "Maya Crawford"))

        XCTAssertEqual(
            flow.knownPlayers,
            [KnownRemotePlayer(id: maya.id, displayName: "Maya Crawford")]
        )
    }

    func testCancelClosesFlowAndClearsPendingInvite() {
        let flow = RemotePlayFlow(
            knownPlayers: [],
            localDisplayName: "Jason",
            nextInviteCode: "428193"
        )

        flow.open()
        flow.inviteSomeoneNew()
        _ = flow.requestSendInvite()

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
        let flow = RemotePlayFlow(localDisplayName: "Jason", nextInviteCode: "428193")

        flow.open()
        flow.updateJoinCode("12a34 5")

        XCTAssertEqual(flow.joinCode, "12345")
        XCTAssertFalse(flow.canSubmitJoinCode)

        flow.updateJoinCode("12a34 56")

        XCTAssertEqual(flow.joinCode, "123456")
        XCTAssertTrue(flow.canSubmitJoinCode)
        XCTAssertFalse(flow.requestJoinCode())
        XCTAssertEqual(flow.joinErrorMessage, "That code did not match an open invite.")
    }

    func testAcceptJoinCodeClearsFlowForMatchingCode() {
        let flow = RemotePlayFlow(localDisplayName: "Jason", nextInviteCode: "428193")

        flow.open()
        flow.updateJoinCode("428 193")

        XCTAssertTrue(flow.requestJoinCode())
        XCTAssertEqual(flow.stage, .closed)
        XCTAssertEqual(flow.joinCode, "")
        XCTAssertNil(flow.joinErrorMessage)
    }

    func testJoinCodeRequiresLocalDisplayName() {
        let flow = RemotePlayFlow(nextInviteCode: "428193")

        flow.open()
        flow.updateJoinCode("428 193")

        XCTAssertFalse(flow.requestJoinCode())
        XCTAssertEqual(flow.stage, .enteringLocalName(.joinWithCode))

        flow.updateLocalNameDraft("Jason")

        XCTAssertEqual(flow.saveLocalNameAndContinue(), .joined)
        XCTAssertEqual(flow.stage, .closed)
        XCTAssertEqual(flow.localDisplayName, "Jason")
    }

    func testEditLocalDisplayNamePrefillsCurrentNameAndReturnsToChoosing() {
        let flow = RemotePlayFlow(localDisplayName: "Jason")

        flow.open()
        flow.editLocalDisplayName()

        XCTAssertEqual(flow.stage, .enteringLocalName(.edit))
        XCTAssertEqual(flow.localNameDraft, "Jason")

        flow.updateLocalNameDraft("  Jay  ")

        XCTAssertEqual(flow.saveLocalNameAndContinue(), .saved)
        XCTAssertEqual(flow.localDisplayName, "Jay")
        XCTAssertEqual(flow.stage, .choosing)
    }

    func testEditLocalDisplayNameReturnsToWhiteChoice() {
        let maya = KnownRemotePlayer(id: RemotePlayerID(rawValue: "maya"), displayName: "Maya")
        let flow = RemotePlayFlow(
            knownPlayers: [maya],
            localDisplayName: "Jason",
            nextInviteCode: "428193"
        )

        flow.open()
        flow.invite(maya)
        flow.chooseWhite(.invitee)
        flow.editLocalDisplayName()

        XCTAssertEqual(flow.stage, .enteringLocalName(.edit))

        flow.updateLocalNameDraft("Jay")

        XCTAssertEqual(flow.saveLocalNameAndContinue(), .saved)
        XCTAssertEqual(flow.localDisplayName, "Jay")
        XCTAssertEqual(flow.stage, .choosingWhite(.known(maya)))
        XCTAssertEqual(flow.selectedWhiteChoice, .invitee)
    }

    func testLocalIdentitySummaryOnlyShowsBeforeChoosingInvitee() {
        let maya = KnownRemotePlayer(id: RemotePlayerID(rawValue: "maya"), displayName: "Maya")
        let flow = RemotePlayFlow(knownPlayers: [maya], localDisplayName: "Jason")

        XCTAssertFalse(flow.showsLocalIdentitySummary)

        flow.open()

        XCTAssertTrue(flow.showsLocalIdentitySummary)

        flow.invite(maya)

        XCTAssertFalse(flow.showsLocalIdentitySummary)
    }

    func testSheetTitleFocusesOnInviteeWhileChoosingWhite() {
        let maya = KnownRemotePlayer(id: RemotePlayerID(rawValue: "maya"), displayName: "Maya")
        let flow = RemotePlayFlow(knownPlayers: [maya], localDisplayName: "Jason")

        XCTAssertEqual(flow.sheetTitle, "Play Remotely")

        flow.open()

        XCTAssertEqual(flow.sheetTitle, "Play Remotely")

        flow.invite(maya)

        XCTAssertEqual(flow.sheetTitle, "Invite Maya")

        flow.goBack()
        flow.inviteSomeoneNew()

        XCTAssertEqual(flow.sheetTitle, "Invite Someone New")
    }

    func testWhiteChoicePromptDoesNotRepeatInviteeTitle() {
        let flow = RemotePlayFlow(localDisplayName: "Jason")

        flow.open()
        flow.inviteSomeoneNew()

        XCTAssertEqual(flow.sheetTitle, "Invite Someone New")
        XCTAssertEqual(flow.whiteChoicePromptTitle, "Who plays White and goes first?")
    }

    func testInviteSharePresentationExplainsCodeAndLink() throws {
        let maya = KnownRemotePlayer(id: RemotePlayerID(rawValue: "maya"), displayName: "Maya")
        let flow = RemotePlayFlow(
            knownPlayers: [maya],
            localDisplayName: "Jason",
            nextInviteCode: "428193"
        )

        flow.open()
        flow.invite(maya)

        let pendingInvite = try XCTUnwrap(flow.requestSendInvite())
        let presentation = flow.inviteSharePresentation(for: pendingInvite)

        XCTAssertEqual(flow.sheetTitle, "Share invite")
        XCTAssertEqual(presentation.codeSectionTitle, "Join code")
        XCTAssertEqual(presentation.code, "428 193")
        XCTAssertEqual(
            presentation.codeInstructions,
            "Maya can join by tapping Play Remotely and entering this code."
        )
        XCTAssertEqual(presentation.linkSectionTitle, "Invite link")
        XCTAssertEqual(presentation.copyLinkButtonTitle, "Copy link")
        XCTAssertEqual(presentation.inviteURL.absoluteString, "chesstutor://invite?code=428193")
        XCTAssertEqual(
            presentation.linkInstructions,
            "You can send the link by Messages, Mail, or another app."
        )
    }

    func testJoinInviteLinkUsesSameCodePath() {
        let flow = RemotePlayFlow(localDisplayName: "Jason", nextInviteCode: "428193")

        XCTAssertTrue(flow.requestJoinInvite(from: URL(string: "chesstutor://invite?code=428193")!))
        XCTAssertEqual(flow.stage, .closed)
        XCTAssertEqual(flow.joinCode, "")
        XCTAssertNil(flow.joinErrorMessage)
    }

    func testJoinInviteLinkRequiresLocalDisplayName() {
        let flow = RemotePlayFlow(nextInviteCode: "428193")

        XCTAssertFalse(flow.requestJoinInvite(from: URL(string: "chesstutor://invite?code=428193")!))
        XCTAssertEqual(flow.stage, .enteringLocalName(.joinWithCode))

        flow.updateLocalNameDraft("Jason")

        XCTAssertEqual(flow.saveLocalNameAndContinue(), .joined)
        XCTAssertEqual(flow.stage, .closed)
    }

    func testRejectsInvalidInviteLink() {
        let flow = RemotePlayFlow(localDisplayName: "Jason", nextInviteCode: "428193")

        XCTAssertFalse(flow.requestJoinInvite(from: URL(string: "chesstutor://invite?code=111111")!))
        XCTAssertEqual(flow.stage, .choosing)
        XCTAssertEqual(flow.joinErrorMessage, "That code did not match an open invite.")

        XCTAssertFalse(flow.requestJoinInvite(from: URL(string: "https://example.com/invite?code=428193")!))
        XCTAssertEqual(flow.stage, .choosing)
        XCTAssertEqual(flow.joinErrorMessage, "That link did not match an open invite.")
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

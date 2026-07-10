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
        XCTAssertNil(flow.requestJoinCode())
        XCTAssertEqual(flow.joinErrorMessage, "That code did not match an open invite.")
    }

    func testAcceptJoinCodeShowsConfirmationWithJoinerBlackWhenInviterPlaysWhite() {
        let flow = RemotePlayFlow(localDisplayName: "Jason", nextInviteCode: "428193")

        flow.open()
        flow.updateJoinCode("428 193")

        XCTAssertEqual(
            flow.requestJoinCode(),
            .needsConfirmation(RemoteInviteConfirmation(opponentName: "Maya", localPlayerColor: .black))
        )
        XCTAssertEqual(flow.stage, .closed)
        XCTAssertEqual(flow.joinCode, "")
        XCTAssertNil(flow.joinErrorMessage)
    }

    func testAcceptJoinCodeShowsConfirmationWithJoinerWhiteWhenInviteePlaysWhite() {
        let flow = RemotePlayFlow(
            localDisplayName: "Jason",
            nextInviteCode: "428193",
            nextJoinWhiteChoice: .invitee
        )

        flow.open()
        flow.updateJoinCode("428 193")

        XCTAssertEqual(
            flow.requestJoinCode(),
            .needsConfirmation(RemoteInviteConfirmation(opponentName: "Maya", localPlayerColor: .white))
        )
        XCTAssertEqual(flow.stage, .closed)
    }

    func testAcceptJoinCodeShowsConfirmationRequiringColorChoiceWhenInviteeChooses() {
        let flow = RemotePlayFlow(
            localDisplayName: "Jason",
            nextInviteCode: "428193",
            nextJoinWhiteChoice: .inviteeChooses
        )

        flow.open()
        flow.updateJoinCode("428 193")

        XCTAssertEqual(
            flow.requestJoinCode(),
            .needsConfirmation(RemoteInviteConfirmation(opponentName: "Maya", localPlayerColor: nil))
        )
        XCTAssertEqual(flow.stage, .closed)
        XCTAssertEqual(flow.joinCode, "")
        XCTAssertNil(flow.joinErrorMessage)
    }

    func testJoinCodeUsesWhiteChoiceFromCreatedInviteRecord() throws {
        let flow = RemotePlayFlow(localDisplayName: "Jason", nextInviteCode: "428193")

        flow.open()
        flow.inviteSomeoneNew()
        flow.chooseWhite(.inviteeChooses)
        _ = try XCTUnwrap(flow.requestSendInvite())
        flow.updateJoinCode("428 193")

        XCTAssertEqual(
            flow.requestJoinCode(),
            .needsConfirmation(RemoteInviteConfirmation(opponentName: "Maya", localPlayerColor: nil))
        )
    }

    func testInviteLinkUsesWhiteChoiceFromCreatedInviteRecord() throws {
        let flow = RemotePlayFlow(localDisplayName: "Jason", nextInviteCode: "428193")

        flow.open()
        flow.inviteSomeoneNew()
        flow.chooseWhite(.invitee)
        let pendingInvite = try XCTUnwrap(flow.requestSendInvite())
        let inviteURL = flow.inviteSharePresentation(for: pendingInvite).inviteURL

        XCTAssertEqual(
            flow.requestJoinInvite(from: inviteURL),
            .needsConfirmation(RemoteInviteConfirmation(opponentName: "Maya", localPlayerColor: .white))
        )
    }

    func testCreatedRemoteInvitePresentationUsesTransportInviteCodeAndLinkToken() {
        let flow = RemotePlayFlow(localDisplayName: "Jason")
        let invite = RemotePendingInvite(
            id: RemoteInviteID(rawValue: "428193"),
            code: InviteCode(rawValue: "428193"),
            token: RemoteInviteToken(rawValue: "token-1"),
            inviter: RemotePlayerRef(id: RemotePlayerID(rawValue: "jason"), displayName: "Jason"),
            inviteeDisplayName: "Maya",
            whiteAssignment: .inviteeChooses,
            status: .pending,
            createdAt: Date(timeIntervalSince1970: 10),
            expiresAt: Date(timeIntervalSince1970: 70),
            protocolVersion: 1
        )

        flow.open()
        flow.inviteSomeoneNew()
        flow.showCreatedRemoteInvite(invite, target: .newPlayer)

        guard case .waitingForInvitee(let pendingInvite) = flow.stage else {
            return XCTFail("Expected waiting state")
        }
        let presentation = flow.inviteSharePresentation(for: pendingInvite)
        XCTAssertEqual(presentation.code, "428 193")
        XCTAssertEqual(presentation.inviteURL.absoluteString, "chesstutor://invite?code=428193&token=token-1")
    }

    func testJoinCodeRequiresLocalDisplayName() {
        let flow = RemotePlayFlow(nextInviteCode: "428193")

        flow.open()
        flow.updateJoinCode("428 193")

        XCTAssertNil(flow.requestJoinCode())
        XCTAssertEqual(flow.stage, .enteringLocalName(.joinWithCode))

        flow.updateLocalNameDraft("Jason")

        XCTAssertEqual(
            flow.saveLocalNameAndContinue(),
            .needsConfirmation(RemoteInviteConfirmation(opponentName: "Maya", localPlayerColor: .black))
        )
        XCTAssertEqual(flow.stage, .closed)
        XCTAssertEqual(flow.localDisplayName, "Jason")
    }

    func testJoinCodeAfterLocalDisplayNameCanShowConfirmationRequiringColorChoice() {
        let flow = RemotePlayFlow(
            nextInviteCode: "428193",
            nextJoinWhiteChoice: .inviteeChooses
        )

        flow.open()
        flow.updateJoinCode("428 193")

        XCTAssertNil(flow.requestJoinCode())
        XCTAssertEqual(flow.stage, .enteringLocalName(.joinWithCode))

        flow.updateLocalNameDraft("Jason")

        XCTAssertEqual(
            flow.saveLocalNameAndContinue(),
            .needsConfirmation(RemoteInviteConfirmation(opponentName: "Maya", localPlayerColor: nil))
        )
        XCTAssertEqual(flow.stage, .closed)
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
        flow.chooseWhite(.inviteeChooses)

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
        XCTAssertEqual(
            presentation.inviteURL.absoluteString,
            "chesstutor://invite?code=428193"
        )
        XCTAssertEqual(
            presentation.linkInstructions,
            "You can send the link by Messages, Mail, or another app."
        )
    }

    func testInviteSharePresentationShowsCopiedFeedbackForCopiedLink() throws {
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

        XCTAssertEqual(presentation.copyLinkButtonTitle, "Copy link")
        XCTAssertTrue(presentation.isCopyLinkButtonEnabled)

        flow.markInviteLinkCopied(presentation.inviteURL)

        let copiedPresentation = flow.inviteSharePresentation(for: pendingInvite)
        XCTAssertEqual(copiedPresentation.copyLinkButtonTitle, "Copied!")
        XCTAssertFalse(copiedPresentation.isCopyLinkButtonEnabled)

        flow.clearCopiedInviteLink()

        let resetPresentation = flow.inviteSharePresentation(for: pendingInvite)
        XCTAssertEqual(resetPresentation.copyLinkButtonTitle, "Copy link")
        XCTAssertTrue(resetPresentation.isCopyLinkButtonEnabled)
    }

    func testJoinInviteLinkUsesSameCodePath() {
        let flow = RemotePlayFlow(localDisplayName: "Jason", nextInviteCode: "428193")

        XCTAssertEqual(
            flow.requestJoinInvite(from: URL(string: "chesstutor://invite?code=428193")!),
            .needsConfirmation(RemoteInviteConfirmation(opponentName: "Maya", localPlayerColor: .black))
        )
        XCTAssertEqual(flow.stage, .closed)
        XCTAssertEqual(flow.joinCode, "")
        XCTAssertNil(flow.joinErrorMessage)
    }

    func testJoinInviteLinkUsesInviteRecordWhiteChoice() {
        let flow = RemotePlayFlow(
            localDisplayName: "Jason",
            nextInviteCode: "428193",
            nextJoinWhiteChoice: .invitee
        )

        XCTAssertEqual(
            flow.requestJoinInvite(from: URL(string: "chesstutor://invite?code=428193")!),
            .needsConfirmation(RemoteInviteConfirmation(opponentName: "Maya", localPlayerColor: .white))
        )
        XCTAssertEqual(flow.stage, .closed)
    }

    func testJoinInviteLinkCanUseInviteRecordToRequireColorChoice() {
        let flow = RemotePlayFlow(
            localDisplayName: "Jason",
            nextInviteCode: "428193",
            nextJoinWhiteChoice: .inviteeChooses
        )

        XCTAssertEqual(
            flow.requestJoinInvite(from: URL(string: "chesstutor://invite?code=428193")!),
            .needsConfirmation(RemoteInviteConfirmation(opponentName: "Maya", localPlayerColor: nil))
        )
        XCTAssertEqual(flow.stage, .closed)
    }

    func testJoinInviteLinkRequiresLocalDisplayName() {
        let flow = RemotePlayFlow(nextInviteCode: "428193")

        XCTAssertNil(flow.requestJoinInvite(from: URL(string: "chesstutor://invite?code=428193")!))
        XCTAssertEqual(flow.stage, .enteringLocalName(.joinWithCode))

        flow.updateLocalNameDraft("Jason")

        XCTAssertEqual(
            flow.saveLocalNameAndContinue(),
            .needsConfirmation(RemoteInviteConfirmation(opponentName: "Maya", localPlayerColor: .black))
        )
        XCTAssertEqual(flow.stage, .closed)
    }

    func testJoinInviteLinkAfterLocalDisplayNameCanShowConfirmationRequiringColorChoice() {
        let flow = RemotePlayFlow(
            nextInviteCode: "428193",
            nextJoinWhiteChoice: .inviteeChooses
        )

        XCTAssertNil(flow.requestJoinInvite(from: URL(string: "chesstutor://invite?code=428193")!))
        XCTAssertEqual(flow.stage, .enteringLocalName(.joinWithCode))

        flow.updateLocalNameDraft("Jason")

        XCTAssertEqual(
            flow.saveLocalNameAndContinue(),
            .needsConfirmation(RemoteInviteConfirmation(opponentName: "Maya", localPlayerColor: nil))
        )
        XCTAssertEqual(flow.stage, .closed)
    }

    func testRejectsInvalidInviteLink() {
        let flow = RemotePlayFlow(localDisplayName: "Jason", nextInviteCode: "428193")

        XCTAssertNil(flow.requestJoinInvite(from: URL(string: "chesstutor://invite?code=111111")!))
        XCTAssertEqual(flow.stage, .choosing)
        XCTAssertEqual(flow.joinErrorMessage, "That code did not match an open invite.")

        XCTAssertNil(flow.requestJoinInvite(from: URL(string: "https://example.com/invite?code=428193")!))
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

import XCTest
@testable import ChessTutor

final class RemoteGameStartContextTests: XCTestCase {
    func testJoinerContextUsesAcceptedInviteColorAndInviterOpponent() {
        let acceptedInvite = makeAcceptedInvite(joinerColor: .black)

        let context = RemoteGameStartContext.joiner(from: acceptedInvite)

        XCTAssertEqual(context.opponent, inviter)
        XCTAssertEqual(context.localPlayerColor, .black)
        XCTAssertEqual(context.descriptor.id, RemoteGameID(rawValue: inviteID.rawValue))
        XCTAssertEqual(context.descriptor.whitePlayer, inviter)
        XCTAssertEqual(context.descriptor.blackPlayer, joiner)
        XCTAssertEqual(context.descriptor.localPlayerID, joiner.id)
    }

    func testInviterContextUsesOppositeAcceptedInviteColorAndJoinerOpponent() {
        let acceptedInvite = makeAcceptedInvite(joinerColor: .white)

        let context = RemoteGameStartContext.inviter(from: acceptedInvite)

        XCTAssertEqual(context.opponent, joiner)
        XCTAssertEqual(context.localPlayerColor, .black)
        XCTAssertEqual(context.descriptor.id, RemoteGameID(rawValue: inviteID.rawValue))
        XCTAssertEqual(context.descriptor.whitePlayer, joiner)
        XCTAssertEqual(context.descriptor.blackPlayer, inviter)
        XCTAssertEqual(context.descriptor.localPlayerID, inviter.id)
    }

    private let inviteID = RemoteInviteID(rawValue: "123456")
    private let inviter = RemotePlayerRef(id: RemotePlayerID(rawValue: "inviter"), displayName: "Jason")
    private let joiner = RemotePlayerRef(id: RemotePlayerID(rawValue: "joiner"), displayName: "Maya")

    private func makeAcceptedInvite(joinerColor: PieceColor) -> RemoteAcceptedInvite {
        RemoteAcceptedInvite(
            invite: RemotePendingInvite(
                id: inviteID,
                code: InviteCode(rawValue: inviteID.rawValue),
                token: RemoteInviteToken(rawValue: "token"),
                inviter: inviter,
                inviteeDisplayName: joiner.displayName,
                whiteAssignment: .inviteeChooses,
                status: .accepted,
                createdAt: Date(timeIntervalSince1970: 10),
                expiresAt: Date(timeIntervalSince1970: 610),
                protocolVersion: 1
            ),
            joiner: joiner,
            joinerColor: joinerColor
        )
    }
}

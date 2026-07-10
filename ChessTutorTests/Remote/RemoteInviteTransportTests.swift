import XCTest
@testable import ChessTutor

final class RemoteInviteTransportTests: XCTestCase {
    func testCreatedInviteCanBeFetchedByCode() async throws {
        let transport = makeTransport()

        let invite = try await transport.createInvite(
            CreateRemoteInviteRequest(
                inviter: Self.inviter,
                inviteeDisplayName: "Maya",
                whiteAssignment: .inviteeChooses,
                now: Self.createdAt,
                expiresAt: Self.expiresAt
            )
        )
        let fetched = try await transport.fetchInvite(code: Self.code, token: nil, now: Self.joinedAt)

        XCTAssertEqual(fetched, invite)
        XCTAssertEqual(fetched.whiteAssignment, .inviteeChooses)
    }

    func testLinkTokenMustMatchWhenPresent() async throws {
        let transport = makeTransport()
        _ = try await transport.createInvite(
            CreateRemoteInviteRequest(
                inviter: Self.inviter,
                inviteeDisplayName: nil,
                whiteAssignment: .inviter,
                now: Self.createdAt,
                expiresAt: Self.expiresAt
            )
        )

        await XCTAssertThrowsRemoteInviteTransportErrorAsync(.tokenMismatch,
            try await transport.fetchInvite(
                code: Self.code,
                token: RemoteInviteToken(rawValue: "wrong"),
                now: Self.joinedAt
            )
        )
    }

    func testInviteeChoosesAcceptsChosenWhiteAndPreventsSecondAccess() async throws {
        let transport = makeTransport()
        let invite = try await createInvite(on: transport, whiteAssignment: .inviteeChooses)
        let request = JoinRemoteInviteRequest(
            code: invite.code,
            token: invite.token,
            joiner: Self.joiner,
            now: Self.joinedAt
        )

        let accepted = try await transport.acceptInvite(request, chosenColor: .white)

        XCTAssertEqual(accepted.joinerColor, .white)
        XCTAssertEqual(accepted.invite.status, .accepted)
        await XCTAssertThrowsRemoteInviteTransportErrorAsync(.notPending,
            try await transport.fetchInvite(code: invite.code, token: invite.token, now: Self.joinedAt)
        )
        await XCTAssertThrowsRemoteInviteTransportErrorAsync(.notPending,
            try await transport.acceptInvite(request, chosenColor: .white)
        )
    }

    func testAcceptedInviteCanBeFetchedByInviter() async throws {
        let transport = makeTransport()
        let invite = try await createInvite(on: transport, whiteAssignment: .inviteeChooses)
        let request = JoinRemoteInviteRequest(
            code: invite.code,
            token: invite.token,
            joiner: Self.joiner,
            now: Self.joinedAt
        )

        let beforeAcceptance = try await transport.acceptedInvite(id: invite.id, now: Self.joinedAt)
        XCTAssertNil(beforeAcceptance)
        let accepted = try await transport.acceptInvite(request, chosenColor: .white)
        let fetchedAcceptance = try await transport.acceptedInvite(id: invite.id, now: Self.joinedAt)

        XCTAssertEqual(fetchedAcceptance, accepted)
    }

    func testFixedWhiteAssignmentRejectsIncompatibleChosenColor() async throws {
        let transport = makeTransport()
        let invite = try await createInvite(on: transport, whiteAssignment: .invitee)
        let request = JoinRemoteInviteRequest(
            code: invite.code,
            token: invite.token,
            joiner: Self.joiner,
            now: Self.joinedAt
        )

        await XCTAssertThrowsRemoteInviteTransportErrorAsync(.colorChoiceNotAllowed,
            try await transport.acceptInvite(request, chosenColor: .black)
        )
    }

    func testInviteeChoosesRequiresChosenColor() async throws {
        let transport = makeTransport()
        let invite = try await createInvite(on: transport, whiteAssignment: .inviteeChooses)
        let request = JoinRemoteInviteRequest(
            code: invite.code,
            token: invite.token,
            joiner: Self.joiner,
            now: Self.joinedAt
        )

        await XCTAssertThrowsRemoteInviteTransportErrorAsync(.colorChoiceRequired,
            try await transport.acceptInvite(request, chosenColor: nil)
        )
    }

    func testCancelPreventsSubsequentFetch() async throws {
        let transport = makeTransport()
        let invite = try await createInvite(on: transport, whiteAssignment: .inviter)

        try await transport.cancelInvite(id: invite.id)

        await XCTAssertThrowsRemoteInviteTransportErrorAsync(.notPending,
            try await transport.fetchInvite(code: invite.code, token: invite.token, now: Self.joinedAt)
        )
    }

    private static let code = InviteCode(rawValue: "428193")
    private static let token = RemoteInviteToken(rawValue: "token-1")
    private static let inviter = RemotePlayerRef(id: RemotePlayerID(rawValue: "jason"), displayName: "Jason")
    private static let joiner = RemotePlayerRef(id: RemotePlayerID(rawValue: "maya"), displayName: "Maya")
    private static let createdAt = Date(timeIntervalSince1970: 10)
    private static let joinedAt = Date(timeIntervalSince1970: 20)
    private static let expiresAt = Date(timeIntervalSince1970: 70)

    private func makeTransport() -> InMemoryRemoteInviteTransport {
        InMemoryRemoteInviteTransport(
            codeGenerator: { Self.code },
            tokenGenerator: { Self.token }
        )
    }

    private func createInvite(
        on transport: InMemoryRemoteInviteTransport,
        whiteAssignment: RemoteInviteWhiteAssignment
    ) async throws -> RemotePendingInvite {
        try await transport.createInvite(
            CreateRemoteInviteRequest(
                inviter: Self.inviter,
                inviteeDisplayName: nil,
                whiteAssignment: whiteAssignment,
                now: Self.createdAt,
                expiresAt: Self.expiresAt
            )
        )
    }
}

private func XCTAssertThrowsRemoteInviteTransportErrorAsync<T>(
    _ expectedError: RemoteInviteTransportError,
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch let error as RemoteInviteTransportError {
        XCTAssertEqual(error, expectedError, file: file, line: line)
    } catch {
        XCTFail("Expected \(expectedError), got \(error)", file: file, line: line)
    }
}

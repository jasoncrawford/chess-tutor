import XCTest
@testable import ChessTutor

final class RemoteInviteTransportTests: XCTestCase {
    func testCreatedInviteCanBeFetchedByCode() async throws {
        let transport = InMemoryRemoteInviteTransport(
            codeGenerator: { InviteCode(rawValue: "428193") },
            tokenGenerator: { RemoteInviteToken(rawValue: "token-1") }
        )
        let inviter = RemotePlayerRef(id: RemotePlayerID(rawValue: "jason"), displayName: "Jason")

        let invite = try await transport.createInvite(
            CreateRemoteInviteRequest(
                inviter: inviter,
                inviteeDisplayName: "Maya",
                whiteAssignment: .inviteeChooses,
                now: Date(timeIntervalSince1970: 10),
                expiresAt: Date(timeIntervalSince1970: 70)
            )
        )
        let fetched = try await transport.fetchInvite(code: InviteCode(rawValue: "428193"), token: nil, now: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(fetched, invite)
        XCTAssertEqual(fetched.whiteAssignment, .inviteeChooses)
    }

    func testLinkTokenMustMatchWhenPresent() async throws {
        let transport = InMemoryRemoteInviteTransport(
            codeGenerator: { InviteCode(rawValue: "428193") },
            tokenGenerator: { RemoteInviteToken(rawValue: "token-1") }
        )
        let inviter = RemotePlayerRef(id: RemotePlayerID(rawValue: "jason"), displayName: "Jason")
        _ = try await transport.createInvite(
            CreateRemoteInviteRequest(
                inviter: inviter,
                inviteeDisplayName: nil,
                whiteAssignment: .inviter,
                now: Date(timeIntervalSince1970: 10),
                expiresAt: Date(timeIntervalSince1970: 70)
            )
        )

        await XCTAssertThrowsErrorAsync(
            try await transport.fetchInvite(
                code: InviteCode(rawValue: "428193"),
                token: RemoteInviteToken(rawValue: "wrong"),
                now: Date(timeIntervalSince1970: 20)
            )
        )
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
    }
}

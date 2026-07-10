import CloudKit
import XCTest
@testable import ChessTutor

final class CloudKitPendingInviteRecordCodecTests: XCTestCase {
    func testRecordNameIsInviteCodeAndFieldsRoundTrip() throws {
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

        let record = CloudKitPendingInviteRecordCodec.record(from: invite)
        let decoded = try CloudKitPendingInviteRecordCodec.invite(from: record)

        XCTAssertEqual(record.recordID.recordName, "428193")
        XCTAssertEqual(decoded, invite)
    }
}

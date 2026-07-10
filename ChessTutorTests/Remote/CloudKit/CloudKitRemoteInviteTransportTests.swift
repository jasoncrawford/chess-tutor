import CloudKit
import XCTest
@testable import ChessTutor

final class CloudKitRemoteInviteTransportTests: XCTestCase {
    func testCreateInviteSavesRecordByCodeAndFetchesItBack() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        let transport = CloudKitRemoteInviteTransport(
            database: database,
            codeGenerator: { InviteCode(rawValue: "428193") },
            tokenGenerator: { RemoteInviteToken(rawValue: "token-1") }
        )

        let invite = try await transport.createInvite(
            CreateRemoteInviteRequest(
                inviter: RemotePlayerRef(id: RemotePlayerID(rawValue: "jason"), displayName: "Jason"),
                inviteeDisplayName: "Maya",
                whiteAssignment: .invitee,
                now: Date(timeIntervalSince1970: 10),
                expiresAt: Date(timeIntervalSince1970: 70)
            )
        )
        let fetched = try await transport.fetchInvite(
            code: InviteCode(rawValue: "428193"),
            token: nil,
            now: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(invite, fetched)
        let savedRecord = await database.record(withID: CKRecord.ID(recordName: "428193"))
        XCTAssertNotNil(savedRecord)
    }
}

private actor InMemoryCloudKitInviteDatabase: CloudKitInviteDatabase {
    var records: [CKRecord.ID: CKRecord] = [:]

    func record(withID id: CKRecord.ID) -> CKRecord? {
        records[id]
    }

    func records(
        for ids: [CKRecord.ID],
        desiredKeys: [CKRecord.FieldKey]?
    ) async throws -> [CKRecord.ID: Result<CKRecord, any Error>] {
        Dictionary(uniqueKeysWithValues: ids.map { id in
            if let record = records[id] {
                return (id, .success(record))
            } else {
                return (id, .failure(CKError(.unknownItem)))
            }
        })
    }

    func modifyRecords(
        saving recordsToSave: [CKRecord],
        deleting recordIDsToDelete: [CKRecord.ID],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        atomically: Bool
    ) async throws -> (
        saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
        deleteResults: [CKRecord.ID: Result<Void, any Error>]
    ) {
        for record in recordsToSave {
            records[record.recordID] = record
        }
        for id in recordIDsToDelete {
            records.removeValue(forKey: id)
        }
        return (
            saveResults: Dictionary(uniqueKeysWithValues: recordsToSave.map { ($0.recordID, .success($0)) }),
            deleteResults: Dictionary(uniqueKeysWithValues: recordIDsToDelete.map { ($0, .success(())) })
        )
    }
}

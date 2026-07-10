import CloudKit
import XCTest
@testable import ChessTutor

final class CloudKitRemoteInviteTransportTests: XCTestCase {
    func testCreateInviteSavesRecordByCodeAndFetchesItBack() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        let transport = makeTransport(database: database)

        let invite = try await transport.createInvite(
            CreateRemoteInviteRequest(
                inviter: Self.inviter,
                inviteeDisplayName: "Maya",
                whiteAssignment: .invitee,
                now: Self.createdAt,
                expiresAt: Self.expiresAt
            )
        )
        let fetched = try await transport.fetchInvite(
            code: Self.code,
            token: nil,
            now: Self.joinedAt
        )

        XCTAssertEqual(invite, fetched)
        let savedRecord = await database.record(withID: Self.recordID)
        XCTAssertNotNil(savedRecord)
        let lastRequest = await database.lastModifyRequest()
        let request = try XCTUnwrap(lastRequest)
        XCTAssertEqual(request.savePolicy, .ifServerRecordUnchanged)
        XCTAssertTrue(request.atomically)
    }

    func testCreateInviteRecordLevelSaveFailureMapsToCodeCollision() async {
        let database = InMemoryCloudKitInviteDatabase()
        await database.failSaves(for: [Self.recordID])
        let transport = makeTransport(database: database)

        await XCTAssertThrowsRemoteInviteTransportErrorAsync(.codeCollision,
            try await transport.createInvite(
                CreateRemoteInviteRequest(
                    inviter: Self.inviter,
                    inviteeDisplayName: nil,
                    whiteAssignment: .invitee,
                    now: Self.createdAt,
                    expiresAt: Self.expiresAt
                )
            )
        )
    }

    func testFetchInviteTokenMismatchMapsToTokenMismatch() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        let transport = makeTransport(database: database)
        _ = try await createInvite(on: transport, whiteAssignment: .inviter)

        await XCTAssertThrowsRemoteInviteTransportErrorAsync(.tokenMismatch,
            try await transport.fetchInvite(
                code: Self.code,
                token: RemoteInviteToken(rawValue: "wrong-token"),
                now: Self.joinedAt
            )
        )
    }

    func testFetchInviteExpiredMapsToExpired() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        let transport = makeTransport(database: database)
        _ = try await createInvite(on: transport, whiteAssignment: .inviter)

        await XCTAssertThrowsRemoteInviteTransportErrorAsync(.expired,
            try await transport.fetchInvite(
                code: Self.code,
                token: Self.token,
                now: Self.expiresAt
            )
        )
    }

    func testFetchAcceptedInviteMapsToNotPending() async {
        let database = InMemoryCloudKitInviteDatabase()
        await database.store(makeInvite(status: .accepted))
        let transport = makeTransport(database: database)

        await XCTAssertThrowsRemoteInviteTransportErrorAsync(.notPending,
            try await transport.fetchInvite(
                code: Self.code,
                token: Self.token,
                now: Self.joinedAt
            )
        )
    }

    func testAcceptInviteeChoosesChosenWhiteSavesAcceptedStatusAndUsesConditionalPolicy() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        let transport = makeTransport(database: database)
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
        let storedRecord = await database.record(withID: Self.recordID)
        let savedRecord = try XCTUnwrap(storedRecord)
        let savedInvite = try CloudKitPendingInviteRecordCodec.invite(from: savedRecord)
        XCTAssertEqual(savedInvite.status, .accepted)
        let lastRequest = await database.lastModifyRequest()
        let requestMetadata = try XCTUnwrap(lastRequest)
        XCTAssertEqual(requestMetadata.savedRecordIDs, [Self.recordID])
        XCTAssertEqual(requestMetadata.savePolicy, .ifServerRecordUnchanged)
        XCTAssertTrue(requestMetadata.atomically)
    }

    func testAcceptInviteRecordLevelSaveFailureMapsToNotPending() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        let transport = makeTransport(database: database)
        let invite = try await createInvite(on: transport, whiteAssignment: .inviteeChooses)
        await database.failSaves(for: [Self.recordID])

        await XCTAssertThrowsRemoteInviteTransportErrorAsync(.notPending,
            try await transport.acceptInvite(
                JoinRemoteInviteRequest(
                    code: invite.code,
                    token: invite.token,
                    joiner: Self.joiner,
                    now: Self.joinedAt
                ),
                chosenColor: .white
            )
        )
    }

    func testCancelInviteDeleteFailureOrMissingIDMapsToNotFound() async throws {
        let failingDeleteDatabase = InMemoryCloudKitInviteDatabase()
        let failingDeleteTransport = makeTransport(database: failingDeleteDatabase)
        let invite = try await createInvite(on: failingDeleteTransport, whiteAssignment: .inviter)
        await failingDeleteDatabase.failDeletes(for: [Self.recordID])

        await XCTAssertThrowsRemoteInviteTransportErrorAsync(.notFound,
            try await failingDeleteTransport.cancelInvite(id: invite.id)
        )

        let missingDeleteDatabase = InMemoryCloudKitInviteDatabase()
        let missingDeleteTransport = makeTransport(database: missingDeleteDatabase)
        await XCTAssertThrowsRemoteInviteTransportErrorAsync(.notFound,
            try await missingDeleteTransport.cancelInvite(id: RemoteInviteID(rawValue: "missing"))
        )
    }

    private static let code = InviteCode(rawValue: "428193")
    private static let recordID = CKRecord.ID(recordName: code.rawValue)
    private static let token = RemoteInviteToken(rawValue: "token-1")
    private static let inviter = RemotePlayerRef(id: RemotePlayerID(rawValue: "jason"), displayName: "Jason")
    private static let joiner = RemotePlayerRef(id: RemotePlayerID(rawValue: "maya"), displayName: "Maya")
    private static let createdAt = Date(timeIntervalSince1970: 10)
    private static let joinedAt = Date(timeIntervalSince1970: 20)
    private static let expiresAt = Date(timeIntervalSince1970: 70)

    private func makeTransport(database: InMemoryCloudKitInviteDatabase) -> CloudKitRemoteInviteTransport {
        CloudKitRemoteInviteTransport(
            database: database,
            codeGenerator: { Self.code },
            tokenGenerator: { Self.token }
        )
    }

    private func createInvite(
        on transport: CloudKitRemoteInviteTransport,
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

    private func makeInvite(
        whiteAssignment: RemoteInviteWhiteAssignment = .inviteeChooses,
        status: RemoteInviteStatus = .pending
    ) -> RemotePendingInvite {
        RemotePendingInvite(
            id: RemoteInviteID(rawValue: Self.code.rawValue),
            code: Self.code,
            token: Self.token,
            inviter: Self.inviter,
            inviteeDisplayName: nil,
            whiteAssignment: whiteAssignment,
            status: status,
            createdAt: Self.createdAt,
            expiresAt: Self.expiresAt,
            protocolVersion: 1
        )
    }
}

private struct ModifyRecordsRequest: Equatable {
    let savedRecordIDs: [CKRecord.ID]
    let deletedRecordIDs: [CKRecord.ID]
    let savePolicy: CKModifyRecordsOperation.RecordSavePolicy
    let atomically: Bool
}

private actor InMemoryCloudKitInviteDatabase: CloudKitInviteDatabase {
    private var records: [CKRecord.ID: CKRecord] = [:]
    private var failingSaveIDs: Set<CKRecord.ID> = []
    private var failingDeleteIDs: Set<CKRecord.ID> = []
    private var requests: [ModifyRecordsRequest] = []

    func record(withID id: CKRecord.ID) -> CKRecord? {
        records[id]
    }

    func store(_ invite: RemotePendingInvite) {
        let record = CloudKitPendingInviteRecordCodec.record(from: invite)
        records[record.recordID] = record
    }

    func failSaves(for ids: [CKRecord.ID]) {
        failingSaveIDs.formUnion(ids)
    }

    func failDeletes(for ids: [CKRecord.ID]) {
        failingDeleteIDs.formUnion(ids)
    }

    func lastModifyRequest() -> ModifyRecordsRequest? {
        requests.last
    }

    func records(
        for ids: [CKRecord.ID],
        desiredKeys: [CKRecord.FieldKey]?
    ) async throws -> [CKRecord.ID: Result<CKRecord, any Error>] {
        var results: [CKRecord.ID: Result<CKRecord, any Error>] = [:]
        for id in ids {
            if let record = records[id] {
                results[id] = .success(record)
            } else {
                results[id] = .failure(CKError(.unknownItem))
            }
        }
        return results
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
        requests.append(
            ModifyRecordsRequest(
                savedRecordIDs: recordsToSave.map(\.recordID),
                deletedRecordIDs: recordIDsToDelete,
                savePolicy: savePolicy,
                atomically: atomically
            )
        )

        var saveResults: [CKRecord.ID: Result<CKRecord, any Error>] = [:]
        for record in recordsToSave {
            if failingSaveIDs.contains(record.recordID) {
                saveResults[record.recordID] = .failure(CKError(.serverRecordChanged))
            } else {
                records[record.recordID] = record
                saveResults[record.recordID] = .success(record)
            }
        }

        var deleteResults: [CKRecord.ID: Result<Void, any Error>] = [:]
        for id in recordIDsToDelete {
            if failingDeleteIDs.contains(id) || records[id] == nil {
                deleteResults[id] = .failure(CKError(.unknownItem))
            } else {
                records.removeValue(forKey: id)
                deleteResults[id] = .success(())
            }
        }

        return (saveResults: saveResults, deleteResults: deleteResults)
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

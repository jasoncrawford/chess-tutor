import CloudKit
import Foundation

protocol CloudKitInviteDatabase: Sendable {
    func records(
        for ids: [CKRecord.ID],
        desiredKeys: [CKRecord.FieldKey]?
    ) async throws -> [CKRecord.ID: Result<CKRecord, any Error>]

    func modifyRecords(
        saving recordsToSave: [CKRecord],
        deleting recordIDsToDelete: [CKRecord.ID],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        atomically: Bool
    ) async throws -> (
        saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
        deleteResults: [CKRecord.ID: Result<Void, any Error>]
    )
}

extension CKDatabase: CloudKitInviteDatabase {}

actor CloudKitRemoteInviteTransport: RemoteInviteTransport {
    private let database: any CloudKitInviteDatabase
    private let codeGenerator: @Sendable () -> InviteCode
    private let tokenGenerator: @Sendable () -> RemoteInviteToken

    init(
        database: any CloudKitInviteDatabase = CKContainer(identifier: "iCloud.org.jasoncrawford.chesstutor").publicCloudDatabase,
        codeGenerator: @escaping @Sendable () -> InviteCode = {
            InviteCode(rawValue: String(format: "%06d", Int.random(in: 0...999_999)))
        },
        tokenGenerator: @escaping @Sendable () -> RemoteInviteToken = {
            RemoteInviteToken(rawValue: UUID().uuidString)
        }
    ) {
        self.database = database
        self.codeGenerator = codeGenerator
        self.tokenGenerator = tokenGenerator
    }

    func createInvite(_ request: CreateRemoteInviteRequest) async throws -> RemotePendingInvite {
        let code = codeGenerator()
        let invite = RemotePendingInvite(
            id: RemoteInviteID(rawValue: code.rawValue),
            code: code,
            token: tokenGenerator(),
            inviter: request.inviter,
            inviteeDisplayName: request.inviteeDisplayName,
            whiteAssignment: request.whiteAssignment,
            status: .pending,
            createdAt: request.now,
            expiresAt: request.expiresAt,
            protocolVersion: 1
        )
        let record = CloudKitPendingInviteRecordCodec.record(from: invite)
        let result = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .ifServerRecordUnchanged,
            atomically: true
        )
        guard savedRecord(record.recordID, in: result.saveResults) != nil else {
            throw RemoteInviteTransportError.codeCollision
        }
        return invite
    }

    func fetchInvite(code: InviteCode, token: RemoteInviteToken?, now: Date) async throws -> RemotePendingInvite {
        try await fetchPendingInviteRecord(code: code, token: token, now: now).invite
    }

    private func fetchPendingInviteRecord(
        code: InviteCode,
        token: RemoteInviteToken?,
        now: Date
    ) async throws -> (invite: RemotePendingInvite, record: CKRecord) {
        let recordID = CKRecord.ID(recordName: code.rawValue)
        let results = try await database.records(for: [recordID], desiredKeys: nil)
        guard case .success(let record) = results[recordID] else {
            throw RemoteInviteTransportError.notFound
        }
        let invite = try CloudKitPendingInviteRecordCodec.invite(from: record)
        if let token, token != invite.token {
            throw RemoteInviteTransportError.tokenMismatch
        }
        guard invite.status == .pending else {
            throw RemoteInviteTransportError.notPending
        }
        guard invite.expiresAt > now else {
            throw RemoteInviteTransportError.expired
        }
        return (invite, record)
    }

    func acceptInvite(_ request: JoinRemoteInviteRequest, chosenColor: PieceColor?) async throws -> RemoteAcceptedInvite {
        let fetched = try await fetchPendingInviteRecord(code: request.code, token: request.token, now: request.now)
        let invite = fetched.invite
        let joinerColor: PieceColor
        if let fixedColor = invite.whiteAssignment.localPlayerColorForJoiner {
            guard chosenColor == nil || chosenColor == fixedColor else {
                throw RemoteInviteTransportError.colorChoiceNotAllowed
            }
            joinerColor = fixedColor
        } else {
            guard let chosenColor else {
                throw RemoteInviteTransportError.colorChoiceRequired
            }
            joinerColor = chosenColor
        }

        let acceptedInviteRecord = RemotePendingInvite(
            id: invite.id,
            code: invite.code,
            token: invite.token,
            inviter: invite.inviter,
            inviteeDisplayName: invite.inviteeDisplayName,
            whiteAssignment: invite.whiteAssignment,
            status: .accepted,
            createdAt: invite.createdAt,
            expiresAt: invite.expiresAt,
            protocolVersion: invite.protocolVersion
        )
        let acceptedInvite = RemoteAcceptedInvite(
            invite: acceptedInviteRecord,
            joiner: request.joiner,
            joinerColor: joinerColor
        )
        CloudKitPendingInviteRecordCodec.apply(acceptedInvite, to: fetched.record)
        let result = try await database.modifyRecords(
            saving: [fetched.record],
            deleting: [],
            savePolicy: .ifServerRecordUnchanged,
            atomically: true
        )
        guard savedRecord(fetched.record.recordID, in: result.saveResults) != nil else {
            throw RemoteInviteTransportError.notPending
        }
        return acceptedInvite
    }

    func acceptedInvite(id: RemoteInviteID, now: Date) async throws -> RemoteAcceptedInvite? {
        let recordID = CKRecord.ID(recordName: id.rawValue)
        let results = try await database.records(for: [recordID], desiredKeys: nil)
        guard case .success(let record) = results[recordID] else {
            throw RemoteInviteTransportError.notFound
        }
        let invite = try CloudKitPendingInviteRecordCodec.invite(from: record)
        guard invite.status == .accepted else {
            return nil
        }
        guard invite.expiresAt > now else {
            throw RemoteInviteTransportError.expired
        }
        return try CloudKitPendingInviteRecordCodec.acceptedInvite(from: record)
    }

    func cancelInvite(id: RemoteInviteID) async throws {
        let recordID = CKRecord.ID(recordName: id.rawValue)
        let result = try await database.modifyRecords(
            saving: [],
            deleting: [recordID],
            savePolicy: .changedKeys,
            atomically: true
        )
        guard deletedRecord(recordID, in: result.deleteResults) else {
            throw RemoteInviteTransportError.notFound
        }
    }

    private func savedRecord(
        _ recordID: CKRecord.ID,
        in results: [CKRecord.ID: Result<CKRecord, any Error>]
    ) -> CKRecord? {
        guard case .success(let record) = results[recordID] else {
            return nil
        }
        return record
    }

    private func deletedRecord(
        _ recordID: CKRecord.ID,
        in results: [CKRecord.ID: Result<Void, any Error>]
    ) -> Bool {
        guard case .success = results[recordID] else {
            return false
        }
        return true
    }
}

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
        guard case .success = result.saveResults[record.recordID] else {
            throw RemoteInviteTransportError.codeCollision
        }
        return invite
    }

    func fetchInvite(code: InviteCode, token: RemoteInviteToken?, now: Date) async throws -> RemotePendingInvite {
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
        return invite
    }

    func acceptInvite(_ request: JoinRemoteInviteRequest, chosenColor: PieceColor?) async throws -> RemoteAcceptedInvite {
        let invite = try await fetchInvite(code: request.code, token: request.token, now: request.now)
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

        let accepted = RemotePendingInvite(
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
        let record = CloudKitPendingInviteRecordCodec.record(from: accepted)
        _ = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .changedKeys,
            atomically: true
        )
        return RemoteAcceptedInvite(invite: accepted, joiner: request.joiner, joinerColor: joinerColor)
    }

    func cancelInvite(id: RemoteInviteID) async throws {
        let recordID = CKRecord.ID(recordName: id.rawValue)
        _ = try await database.modifyRecords(
            saving: [],
            deleting: [recordID],
            savePolicy: .changedKeys,
            atomically: true
        )
    }
}

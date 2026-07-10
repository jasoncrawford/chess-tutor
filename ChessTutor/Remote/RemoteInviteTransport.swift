import Foundation

protocol RemoteInviteTransport: Sendable {
    func createInvite(_ request: CreateRemoteInviteRequest) async throws -> RemotePendingInvite
    func fetchInvite(code: InviteCode, token: RemoteInviteToken?, now: Date) async throws -> RemotePendingInvite
    func acceptInvite(_ request: JoinRemoteInviteRequest, chosenColor: PieceColor?) async throws -> RemoteAcceptedInvite
    func acceptedInvite(id: RemoteInviteID, now: Date) async throws -> RemoteAcceptedInvite?
    func cancelInvite(id: RemoteInviteID) async throws
}

enum RemoteInviteTransportError: Error, Equatable {
    case notFound
    case tokenMismatch
    case expired
    case notPending
    case colorChoiceRequired
    case colorChoiceNotAllowed
    case codeCollision
}

actor InMemoryRemoteInviteTransport: RemoteInviteTransport {
    private var invitesByCode: [InviteCode: RemotePendingInvite] = [:]
    private var acceptedInvitesByID: [RemoteInviteID: RemoteAcceptedInvite] = [:]
    private let codeGenerator: @Sendable () -> InviteCode
    private let tokenGenerator: @Sendable () -> RemoteInviteToken

    init(
        codeGenerator: @escaping @Sendable () -> InviteCode = {
            InviteCode(rawValue: String(format: "%06d", Int.random(in: 0...999_999)))
        },
        tokenGenerator: @escaping @Sendable () -> RemoteInviteToken = {
            RemoteInviteToken(rawValue: UUID().uuidString)
        }
    ) {
        self.codeGenerator = codeGenerator
        self.tokenGenerator = tokenGenerator
    }

    func createInvite(_ request: CreateRemoteInviteRequest) async throws -> RemotePendingInvite {
        let code = codeGenerator()
        guard invitesByCode[code] == nil else {
            throw RemoteInviteTransportError.codeCollision
        }
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
        invitesByCode[code] = invite
        return invite
    }

    func fetchInvite(code: InviteCode, token: RemoteInviteToken?, now: Date) async throws -> RemotePendingInvite {
        guard let invite = invitesByCode[code] else {
            throw RemoteInviteTransportError.notFound
        }
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
        invitesByCode[request.code] = accepted
        let acceptedInvite = RemoteAcceptedInvite(invite: accepted, joiner: request.joiner, joinerColor: joinerColor)
        acceptedInvitesByID[accepted.id] = acceptedInvite
        return acceptedInvite
    }

    func acceptedInvite(id: RemoteInviteID, now: Date) async throws -> RemoteAcceptedInvite? {
        guard let acceptedInvite = acceptedInvitesByID[id] else {
            return nil
        }
        guard acceptedInvite.invite.expiresAt > now else {
            throw RemoteInviteTransportError.expired
        }
        return acceptedInvite
    }

    func cancelInvite(id: RemoteInviteID) async throws {
        guard let code = invitesByCode.first(where: { $0.value.id == id })?.key,
              let invite = invitesByCode[code] else {
            throw RemoteInviteTransportError.notFound
        }
        invitesByCode[code] = RemotePendingInvite(
            id: invite.id,
            code: invite.code,
            token: invite.token,
            inviter: invite.inviter,
            inviteeDisplayName: invite.inviteeDisplayName,
            whiteAssignment: invite.whiteAssignment,
            status: .cancelled,
            createdAt: invite.createdAt,
            expiresAt: invite.expiresAt,
            protocolVersion: invite.protocolVersion
        )
    }
}

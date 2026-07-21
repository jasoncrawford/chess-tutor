import Foundation

struct RemoteGameID: Codable, Equatable, Hashable, Sendable {
    let rawValue: String
}

struct RemotePlayerID: Codable, Equatable, Hashable, Sendable {
    let rawValue: String
}

struct RemoteMoveEventID: Codable, Equatable, Hashable, Sendable {
    let rawValue: String
}

struct RemotePlayerRef: Codable, Equatable, Sendable {
    let id: RemotePlayerID
    let displayName: String
}

enum RemoteGameStatus: String, Codable, Equatable, Sendable {
    case active
    case ended
    case error
}

struct RemoteGameDescriptor: Codable, Equatable, Sendable {
    let id: RemoteGameID
    let protocolVersion: Int
    let status: RemoteGameStatus
    let whitePlayer: RemotePlayerRef
    let blackPlayer: RemotePlayerRef
    let localPlayerID: RemotePlayerID
}

struct PositionFingerprint: Codable, Equatable, Hashable, Sendable {
    let rawValue: String
}

struct RemoteMoveEvent: Codable, Equatable, Sendable {
    let id: RemoteMoveEventID
    let gameID: RemoteGameID
    let sequenceNumber: Int
    let actorPlayerID: RemotePlayerID
    let move: RemoteEncodedMove
    let createdAt: Date
    let protocolVersion: Int
    let previousPositionFingerprint: PositionFingerprint
    let resultingPositionFingerprint: PositionFingerprint
    let notificationSummary: String
}

struct RemoteMoveAck: Codable, Equatable, Sendable {
    let eventID: RemoteMoveEventID
    let gameID: RemoteGameID
    let sequenceNumber: Int
}

struct RemoteInviteID: Codable, Equatable, Hashable, Sendable {
    let rawValue: String
}

struct InviteCode: Codable, Equatable, Hashable, Sendable {
    let rawValue: String

    var formatted: String {
        guard rawValue.count == 6 else {
            return rawValue
        }
        let splitIndex = rawValue.index(rawValue.startIndex, offsetBy: 3)
        return "\(rawValue[..<splitIndex]) \(rawValue[splitIndex...])"
    }
}

struct RemoteInviteToken: Codable, Equatable, Hashable, Sendable {
    let rawValue: String
}

enum RemoteInviteWhiteAssignment: String, Codable, Equatable, Sendable {
    case inviter
    case invitee
    case inviteeChooses

    var localPlayerColorForJoiner: PieceColor? {
        switch self {
        case .inviter:
            return .black
        case .invitee:
            return .white
        case .inviteeChooses:
            return nil
        }
    }
}

enum RemoteInviteStatus: String, Codable, Equatable, Sendable {
    case pending
    case accepted
    case cancelled
    case declined
    case expired
}

struct RemotePendingInvite: Codable, Equatable, Sendable {
    let id: RemoteInviteID
    let code: InviteCode
    let token: RemoteInviteToken
    let inviter: RemotePlayerRef
    let inviteePlayerID: RemotePlayerID?
    let inviteeDisplayName: String?
    let whiteAssignment: RemoteInviteWhiteAssignment
    let status: RemoteInviteStatus
    let createdAt: Date
    let expiresAt: Date
    let protocolVersion: Int

    init(
        id: RemoteInviteID,
        code: InviteCode,
        token: RemoteInviteToken,
        inviter: RemotePlayerRef,
        inviteePlayerID: RemotePlayerID? = nil,
        inviteeDisplayName: String?,
        whiteAssignment: RemoteInviteWhiteAssignment,
        status: RemoteInviteStatus,
        createdAt: Date,
        expiresAt: Date,
        protocolVersion: Int
    ) {
        self.id = id
        self.code = code
        self.token = token
        self.inviter = inviter
        self.inviteePlayerID = inviteePlayerID
        self.inviteeDisplayName = inviteeDisplayName
        self.whiteAssignment = whiteAssignment
        self.status = status
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.protocolVersion = protocolVersion
    }
}

struct CreateRemoteInviteRequest: Equatable, Sendable {
    let inviter: RemotePlayerRef
    let inviteePlayerID: RemotePlayerID?
    let inviteeDisplayName: String?
    let whiteAssignment: RemoteInviteWhiteAssignment
    let notificationBody: String
    let now: Date
    let expiresAt: Date

    init(
        inviter: RemotePlayerRef,
        inviteePlayerID: RemotePlayerID? = nil,
        inviteeDisplayName: String?,
        whiteAssignment: RemoteInviteWhiteAssignment,
        notificationBody: String? = nil,
        now: Date,
        expiresAt: Date
    ) {
        self.inviter = inviter
        self.inviteePlayerID = inviteePlayerID
        self.inviteeDisplayName = inviteeDisplayName
        self.whiteAssignment = whiteAssignment
        self.notificationBody = notificationBody ?? "\(inviter.displayName) wants to play."
        self.now = now
        self.expiresAt = expiresAt
    }
}

struct JoinRemoteInviteRequest: Equatable, Sendable {
    let code: InviteCode
    let token: RemoteInviteToken?
    let joiner: RemotePlayerRef
    let now: Date
}

struct RemoteAcceptedInvite: Equatable, Sendable {
    let invite: RemotePendingInvite
    let joiner: RemotePlayerRef
    let joinerColor: PieceColor
}

struct ActiveRemoteGameSnapshot: Codable, Equatable, Sendable {
    let descriptor: RemoteGameDescriptor
    let acceptedEvents: [RemoteMoveEvent]
    let outbox: RemoteOutbox
    let lastAppliedSequence: Int
}

struct RemoteGameStatusUpdate: Codable, Equatable, Sendable {
    let gameID: RemoteGameID
    let status: RemoteGameStatus
    let updatedByPlayerID: RemotePlayerID
    let updatedByDisplayName: String?
    let updatedAt: Date

    init(
        gameID: RemoteGameID,
        status: RemoteGameStatus,
        updatedByPlayerID: RemotePlayerID,
        updatedByDisplayName: String? = nil,
        updatedAt: Date
    ) {
        self.gameID = gameID
        self.status = status
        self.updatedByPlayerID = updatedByPlayerID
        self.updatedByDisplayName = updatedByDisplayName
        self.updatedAt = updatedAt
    }
}

enum RemotePresenceState: String, Codable, Equatable, Sendable {
    case activeMoving
    case foregroundIdle
    case away
}

struct RemotePresenceUpdate: Codable, Equatable, Sendable {
    let gameID: RemoteGameID
    let playerID: RemotePlayerID
    let state: RemotePresenceState
    let updatedAt: Date
    let expiresAt: Date
}

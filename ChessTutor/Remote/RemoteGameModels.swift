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
    case expired
}

struct RemotePendingInvite: Codable, Equatable, Sendable {
    let id: RemoteInviteID
    let code: InviteCode
    let token: RemoteInviteToken
    let inviter: RemotePlayerRef
    let inviteeDisplayName: String?
    let whiteAssignment: RemoteInviteWhiteAssignment
    let status: RemoteInviteStatus
    let createdAt: Date
    let expiresAt: Date
    let protocolVersion: Int
}

struct CreateRemoteInviteRequest: Equatable, Sendable {
    let inviter: RemotePlayerRef
    let inviteeDisplayName: String?
    let whiteAssignment: RemoteInviteWhiteAssignment
    let now: Date
    let expiresAt: Date
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

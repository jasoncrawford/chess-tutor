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

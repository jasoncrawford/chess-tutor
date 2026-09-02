import Foundation

struct HostedCoachingMetrics: Codable, Equatable, Sendable {
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let reasoningTokens: Int
    let totalTokens: Int
    let latencyMilliseconds: Double
}

struct HostedCoachingResponse: Equatable, Sendable {
    let schemaVersion: String
    let requestID: String
    let positionRevision: Int
    let promptVersion: String
    let continuationID: String
    let turn: ModelCoachingChessNativeTurn
    let metrics: HostedCoachingMetrics
}

struct HostedCoachingCorrelation: Codable, Equatable, Sendable {
    let gameID: String
    let episodeID: String
}

protocol HostedCoachingTurning: Sendable {
    func turn(
        for request: ModelCoachingNeutralRequest,
        contract: ModelCoachingChessNativeResponseContract,
        continuationID: String?,
        correlation: HostedCoachingCorrelation
    ) async throws -> HostedCoachingResponse
}

enum HostedCoachingTransportError: Error, Equatable, Sendable {
    case invalidRequest
    case serverUnavailable
    case invalidResponse
    case staleResponse
}

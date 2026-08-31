import Foundation

protocol HostedCoachingHTTPDataLoading: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HostedCoachingHTTPDataLoading {}

struct URLSessionHostedCoachingTransport: HostedCoachingTurning, Sendable {
    private static let maximumResponseBytes = 64 * 1024
    private static let responseFields: Set<String> = [
        "schemaVersion",
        "requestID",
        "positionRevision",
        "promptVersion",
        "turn",
        "metrics",
    ]
    private static let metricsFields: Set<String> = [
        "inputTokens",
        "outputTokens",
        "reasoningTokens",
        "totalTokens",
        "latencyMilliseconds",
    ]

    private let endpoint: URL
    private let accessToken: String
    private let loader: any HostedCoachingHTTPDataLoading

    init(
        baseURL: URL,
        accessToken: String,
        loader: any HostedCoachingHTTPDataLoading = URLSession.shared
    ) {
        precondition(!accessToken.isEmpty)
        endpoint = baseURL.appendingPathComponent("v1/coaching-turn")
        self.accessToken = accessToken
        self.loader = loader
    }

    func turn(
        for request: ModelCoachingNeutralRequest,
        contract: ModelCoachingChessNativeResponseContract
    ) async throws -> HostedCoachingResponse {
        let body: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            body = try encoder.encode(request)
        } catch {
            throw HostedCoachingTransportError.invalidRequest
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = body
        urlRequest.timeoutInterval = 35
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await loader.data(for: urlRequest)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            throw HostedCoachingTransportError.serverUnavailable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HostedCoachingTransportError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw HostedCoachingTransportError.serverUnavailable
        }
        guard data.count <= Self.maximumResponseBytes else {
            throw HostedCoachingTransportError.invalidResponse
        }

        return try decodeResponse(
            data,
            for: request,
            contract: contract
        )
    }

    private func decodeResponse(
        _ data: Data,
        for request: ModelCoachingNeutralRequest,
        contract: ModelCoachingChessNativeResponseContract
    ) throws -> HostedCoachingResponse {
        do {
            var rawValidator = ModelCoachingRawJSONValidator(data: data)
            try rawValidator.validate()
            let raw = try JSONSerialization.jsonObject(with: data)
            guard let object = raw as? [String: Any],
                  Set(object.keys) == Self.responseFields,
                  let rawTurn = object["turn"] as? [String: Any],
                  let rawMetrics = object["metrics"] as? [String: Any],
                  Set(rawMetrics.keys) == Self.metricsFields else {
                throw HostedCoachingTransportError.invalidResponse
            }

            let wire = try JSONDecoder().decode(HostedCoachingWireResponse.self, from: data)
            guard wire.schemaVersion == "hosted-coaching-turn.v1",
                  wire.promptVersion == "tutor-v6" else {
                throw HostedCoachingTransportError.invalidResponse
            }
            guard wire.requestID == request.requestID,
                  wire.positionRevision == request.positionRevision else {
                throw HostedCoachingTransportError.staleResponse
            }
            guard wire.metrics.isBounded else {
                throw HostedCoachingTransportError.invalidResponse
            }

            let turnData = try JSONSerialization.data(
                withJSONObject: rawTurn,
                options: [.sortedKeys]
            )
            let turn = try ModelCoachingChessNativeTurnDecoder.decodeAndValidate(
                turnData,
                contract: contract
            )
            return HostedCoachingResponse(
                schemaVersion: wire.schemaVersion,
                requestID: wire.requestID,
                positionRevision: wire.positionRevision,
                promptVersion: wire.promptVersion,
                turn: turn,
                metrics: wire.metrics
            )
        } catch let error as HostedCoachingTransportError {
            throw error
        } catch {
            throw HostedCoachingTransportError.invalidResponse
        }
    }
}

private struct HostedCoachingWireResponse: Decodable {
    let schemaVersion: String
    let requestID: String
    let positionRevision: Int
    let promptVersion: String
    let turn: ModelCoachingChessNativeTurn
    let metrics: HostedCoachingMetrics
}

private extension HostedCoachingMetrics {
    var isBounded: Bool {
        let counts = [inputTokens, outputTokens, reasoningTokens, totalTokens]
        return counts.allSatisfy { (0...1_000_000_000).contains($0) }
            && latencyMilliseconds.isFinite
            && (0...120_000).contains(latencyMilliseconds)
    }
}

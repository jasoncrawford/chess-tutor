import Foundation

protocol HostedCoachingHTTPDataLoading: Sendable {
    func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, URLResponse)
}

enum HostedCoachingHTTPDataLoadingError: Error, Equatable {
    case responseTooLarge
}

struct HostedCoachingResponseBuffer {
    let maximumBytes: Int
    private(set) var data = Data()

    init(maximumBytes: Int, expectedBytes: Int = 0) {
        self.maximumBytes = maximumBytes
        data.reserveCapacity(min(max(0, expectedBytes), maximumBytes))
    }

    mutating func append(_ byte: UInt8) throws {
        guard data.count < maximumBytes else {
            throw HostedCoachingHTTPDataLoadingError.responseTooLarge
        }
        data.append(byte)
    }
}

extension URLSession: HostedCoachingHTTPDataLoading {
    func data(
        for request: URLRequest,
        maximumBytes: Int
    ) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await bytes(for: request)
        let expectedLength = response.expectedContentLength
        guard expectedLength < 0 || expectedLength <= maximumBytes else {
            throw HostedCoachingHTTPDataLoadingError.responseTooLarge
        }

        var buffer = HostedCoachingResponseBuffer(
            maximumBytes: maximumBytes,
            expectedBytes: expectedLength > 0 ? Int(expectedLength) : 0
        )
        for try await byte in bytes {
            try buffer.append(byte)
        }
        return (buffer.data, response)
    }
}

struct URLSessionHostedCoachingTransport: HostedCoachingTurning, Sendable {
    private static let maximumResponseBytes = 64 * 1024
    private static let responseFields: Set<String> = [
        "schemaVersion",
        "requestID",
        "positionRevision",
        "promptVersion",
        "continuationID",
        "turn",
        "metrics",
    ]
    private static let metricsFields: Set<String> = [
        "inputTokens",
        "cachedInputTokens",
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
        contract: ModelCoachingChessNativeResponseContract,
        continuationID: String?
    ) async throws -> HostedCoachingResponse {
        guard continuationID == nil || Self.isValidContinuationID(continuationID!) else {
            throw HostedCoachingTransportError.invalidRequest
        }
        let body: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            body = try encoder.encode(
                HostedCoachingWireRequest(
                    schemaVersion: "hosted-coaching-request.v2",
                    request: request,
                    previousResponseID: continuationID
                )
            )
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
            (data, response) = try await loader.data(
                for: urlRequest,
                maximumBytes: Self.maximumResponseBytes
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch HostedCoachingHTTPDataLoadingError.responseTooLarge {
            throw HostedCoachingTransportError.invalidResponse
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
            guard wire.schemaVersion == "hosted-coaching-turn.v3",
                  wire.promptVersion == "tutor-v12",
                  Self.isValidContinuationID(wire.continuationID) else {
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
                contract: contract,
                requiresExpectedResponse: true
            )
            return HostedCoachingResponse(
                schemaVersion: wire.schemaVersion,
                requestID: wire.requestID,
                positionRevision: wire.positionRevision,
                promptVersion: wire.promptVersion,
                continuationID: wire.continuationID,
                turn: turn,
                metrics: wire.metrics
            )
        } catch let error as HostedCoachingTransportError {
            throw error
        } catch {
            throw HostedCoachingTransportError.invalidResponse
        }
    }

    private static func isValidContinuationID(_ value: String) -> Bool {
        guard value.utf8.count <= 256,
              value.hasPrefix("resp_") else { return false }
        let suffix = value.dropFirst(5)
        return !suffix.isEmpty && suffix.utf8.allSatisfy { byte in
            (48...57).contains(byte)
                || (65...90).contains(byte)
                || (97...122).contains(byte)
                || byte == 45
                || byte == 95
        }
    }
}

private struct HostedCoachingWireRequest: Encodable {
    let schemaVersion: String
    let request: ModelCoachingNeutralRequest
    let previousResponseID: String?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case request
        case previousResponseID
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(request, forKey: .request)
        if let previousResponseID {
            try container.encode(previousResponseID, forKey: .previousResponseID)
        } else {
            try container.encodeNil(forKey: .previousResponseID)
        }
    }
}

private struct HostedCoachingWireResponse: Decodable {
    let schemaVersion: String
    let requestID: String
    let positionRevision: Int
    let promptVersion: String
    let continuationID: String
    let turn: ModelCoachingChessNativeTurn
    let metrics: HostedCoachingMetrics
}

private extension HostedCoachingMetrics {
    var isBounded: Bool {
        let counts = [
            inputTokens,
            cachedInputTokens,
            outputTokens,
            reasoningTokens,
            totalTokens,
        ]
        return counts.allSatisfy { (0...1_000_000_000).contains($0) }
            && latencyMilliseconds.isFinite
            && (0...120_000).contains(latencyMilliseconds)
    }
}

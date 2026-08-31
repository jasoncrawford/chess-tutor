import Foundation
import XCTest
@testable import ChessTutor

final class HostedCoachingTransportTests: XCTestCase {
    func testSendsCanonicalAuthenticatedRequestAndValidatesResponseAgainOnDevice() async throws {
        let request = try sharedRequest()
        let contract = ModelCoachingChessNativeContextCompiler.responseContract(for: request)
        let responseData = try hostedResponseData(
            request: request,
            turn: [
                "message": "Where could this knight help in the center?",
                "actions": ["hint"],
                "focus": [["type": "square", "square": "b1"]],
            ]
        )
        let loader = RecordingHostedLoader(
            data: responseData,
            response: HTTPURLResponse(
                url: URL(string: "https://coach.example/v1/coaching-turn")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
        )
        let transport = URLSessionHostedCoachingTransport(
            baseURL: URL(string: "https://coach.example")!,
            accessToken: "private-token",
            loader: loader
        )

        let response = try await transport.turn(for: request, contract: contract)

        XCTAssertEqual(request.requestID, response.requestID)
        XCTAssertEqual(request.positionRevision, response.positionRevision)
        XCTAssertEqual("Where could this knight help in the center?", response.turn.message)
        let sent = try XCTUnwrap(loader.requests.first)
        XCTAssertEqual(URL(string: "https://coach.example/v1/coaching-turn"), sent.url)
        XCTAssertEqual("POST", sent.httpMethod)
        XCTAssertEqual("Bearer private-token", sent.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual("application/json", sent.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertEqual(35, sent.timeoutInterval)
        XCTAssertEqual([64 * 1024], loader.maximumByteCounts)
        let expected = try JSONEncoder.canonical.encode(request)
        XCTAssertEqual(expected, sent.httpBody)
    }

    func testRejectsHTTPFailuresIdentityMismatchUnknownFieldsAndInvalidTurn() async throws {
        let request = try sharedRequest()
        let contract = ModelCoachingChessNativeContextCompiler.responseContract(for: request)
        let validTurn: [String: Any] = [
            "message": "Look at the knight.",
            "actions": [],
            "focus": [],
        ]
        let cases: [(status: Int, response: [String: Any], expected: HostedCoachingTransportError)] = [
            (503, try hostedResponseObject(request: request, turn: validTurn), .serverUnavailable),
            (200, try hostedResponseObject(request: request, requestID: "stale", turn: validTurn), .staleResponse),
            (200, try hostedResponseObject(request: request, revision: 999, turn: validTurn), .staleResponse),
            (200, try hostedResponseObject(request: request, turn: ["message": "Look.", "actions": ["playMove"], "focus": []]), .invalidResponse),
        ]

        for item in cases {
            let data = try JSONSerialization.data(withJSONObject: item.response)
            let loader = RecordingHostedLoader(
                data: data,
                response: HTTPURLResponse(
                    url: URL(string: "https://coach.example/v1/coaching-turn")!,
                    statusCode: item.status,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
            let transport = URLSessionHostedCoachingTransport(
                baseURL: URL(string: "https://coach.example")!,
                accessToken: "token",
                loader: loader
            )
            do {
                _ = try await transport.turn(for: request, contract: contract)
                XCTFail("Expected \(item.expected)")
            } catch let error as HostedCoachingTransportError {
                XCTAssertEqual(item.expected, error)
            }
        }

        var extra = try hostedResponseObject(request: request, turn: validTurn)
        extra["providerID"] = "private"
        let duplicate = #"{"schemaVersion":"hosted-coaching-turn.v1","schemaVersion":"hosted-coaching-turn.v1"}"#
        for data in [
            try JSONSerialization.data(withJSONObject: extra),
            Data(duplicate.utf8),
        ] {
            let transport = makeTransport(data: data, status: 200)
            do {
                _ = try await transport.turn(for: request, contract: contract)
                XCTFail("Expected invalid response")
            } catch let error as HostedCoachingTransportError {
                XCTAssertEqual(.invalidResponse, error)
            }
        }
    }

    func testCancellationPropagates() async throws {
        let request = try sharedRequest()
        let loader = RecordingHostedLoader(error: CancellationError())
        let transport = URLSessionHostedCoachingTransport(
            baseURL: URL(string: "https://coach.example")!,
            accessToken: "token",
            loader: loader
        )

        do {
            _ = try await transport.turn(
                for: request,
                contract: ModelCoachingChessNativeContextCompiler.responseContract(for: request)
            )
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }
    }

    func testRejectsStreamingResponseWhenLoaderStopsAtByteLimit() async throws {
        let request = try sharedRequest()
        let loader = RecordingHostedLoader(error: HostedCoachingHTTPDataLoadingError.responseTooLarge)
        let transport = URLSessionHostedCoachingTransport(
            baseURL: URL(string: "https://coach.example")!,
            accessToken: "token",
            loader: loader
        )

        do {
            _ = try await transport.turn(
                for: request,
                contract: ModelCoachingChessNativeContextCompiler.responseContract(for: request)
            )
            XCTFail("Expected an invalid response")
        } catch let error as HostedCoachingTransportError {
            XCTAssertEqual(.invalidResponse, error)
        }
        XCTAssertEqual([64 * 1024], loader.maximumByteCounts)
    }

    func testStreamingBufferNeverStoresTheByteBeyondItsLimit() throws {
        var buffer = HostedCoachingResponseBuffer(maximumBytes: 64 * 1024)

        for _ in 0..<(64 * 1024) {
            try buffer.append(0)
        }

        XCTAssertEqual(64 * 1024, buffer.data.count)
        XCTAssertThrowsError(try buffer.append(0)) { error in
            XCTAssertEqual(
                .responseTooLarge,
                error as? HostedCoachingHTTPDataLoadingError
            )
        }
        XCTAssertEqual(64 * 1024, buffer.data.count)
    }

    private func makeTransport(data: Data, status: Int) -> URLSessionHostedCoachingTransport {
        URLSessionHostedCoachingTransport(
            baseURL: URL(string: "https://coach.example")!,
            accessToken: "token",
            loader: RecordingHostedLoader(
                data: data,
                response: HTTPURLResponse(
                    url: URL(string: "https://coach.example/v1/coaching-turn")!,
                    statusCode: status,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        )
    }

    private func sharedRequest() throws -> ModelCoachingNeutralRequest {
        let url = repositoryRoot.appendingPathComponent(
            "Tools/CoachingEval/fixtures/chess-native-context-v1.json"
        )
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        return try JSONDecoder().decode(
            ModelCoachingNeutralRequest.self,
            from: JSONSerialization.data(withJSONObject: try XCTUnwrap(root["request"]))
        )
    }

    private func hostedResponseData(
        request: ModelCoachingNeutralRequest,
        turn: [String: Any]
    ) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: hostedResponseObject(request: request, turn: turn)
        )
    }

    private func hostedResponseObject(
        request: ModelCoachingNeutralRequest,
        requestID: String? = nil,
        revision: Int? = nil,
        turn: [String: Any]
    ) throws -> [String: Any] {
        [
            "schemaVersion": "hosted-coaching-turn.v1",
            "requestID": requestID ?? request.requestID,
            "positionRevision": revision ?? request.positionRevision,
            "promptVersion": "tutor-v6",
            "turn": turn,
            "metrics": [
                "inputTokens": 100,
                "outputTokens": 30,
                "reasoningTokens": 10,
                "totalTokens": 130,
                "latencyMilliseconds": 123.0,
            ],
        ]
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private final class RecordingHostedLoader: HostedCoachingHTTPDataLoading, @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    private(set) var maximumByteCounts: [Int] = []
    let data: Data
    let response: URLResponse
    let error: Error?

    init(data: Data = Data(), response: URLResponse = URLResponse(), error: Error? = nil) {
        self.data = data
        self.response = response
        self.error = error
    }

    func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, URLResponse) {
        requests.append(request)
        maximumByteCounts.append(maximumBytes)
        if let error { throw error }
        return (data, response)
    }
}

private extension JSONEncoder {
    static var canonical: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

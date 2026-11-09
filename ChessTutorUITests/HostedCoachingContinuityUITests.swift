import XCTest
import Network

final class HostedCoachingContinuityUITests: XCTestCase {
    @MainActor
    func testRealHostedConfigurationSurvivesEnvironmentFreeRelaunch() async throws {
        let requestReceived = expectation(description: "Relaunched app contacts saved endpoint with saved credential")
        let server = try ConfigurationProbeServer(received: requestReceived)
        defer { server.stop() }
        let port = try await server.start()
        let app = XCUIApplication()
        let namespace = "-ui-test-hosted-config-\(UUID().uuidString)"
        app.launchArguments = [namespace]
        defer {
            app.terminate()
            app.launchEnvironment = [:]
            app.launchArguments = [namespace, "-cleanup-hosted-config-test"]
            app.launch()
            XCTAssertTrue(app.staticTexts["Configuration test cleanup complete"].waitForExistence(timeout: 5))
            app.terminate()
        }
        app.launchEnvironment = [
            "CHESS_TUTOR_COACHING_BASE_URL": "http://127.0.0.1:\(port)",
            "CHESS_TUTOR_COACHING_ACCESS_TOKEN": "configuration-test-only-token",
        ]
        app.launch()
        app.terminate()
        app.launchEnvironment = [:]
        XCTAssertNil(app.launchEnvironment["CHESS_TUTOR_COACHING_BASE_URL"])
        XCTAssertNil(app.launchEnvironment["CHESS_TUTOR_COACHING_ACCESS_TOKEN"])
        app.launch()
        XCTAssertTrue(app.buttons["empty-games-start-local"].waitForExistence(timeout: 5))
        app.buttons["empty-games-start-local"].tap()
        XCTAssertTrue(app.buttons["Help"].waitForExistence(timeout: 5))
        app.buttons["Help"].tap()
        await fulfillment(of: [requestReceived], timeout: 10)
        app.terminate()
    }

    @MainActor
    func testHostedQuestionAcceptsPieceTapAndEverythingLooksSafe() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-hosted-coaching-continuity"]
        app.launch()

        app.buttons["Start hosted coaching continuity test"].tap()
        XCTAssertTrue(
            app.staticTexts["Can you find the pawn in danger?"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["No piece needs help"].exists)

        app.buttons["Tap hosted pawn answer"].tap()
        XCTAssertTrue(
            app.staticTexts["Yes, that is the pawn to notice."]
                .waitForExistence(timeout: 5)
        )

        app.terminate()
        app.launch()
        app.buttons["Start hosted coaching continuity test"].tap()
        XCTAssertTrue(
            app.buttons["No piece needs help"].waitForExistence(timeout: 5)
        )
        app.buttons["No piece needs help"].tap()
        XCTAssertTrue(
            app.staticTexts["Good check. Nothing needs help right now."]
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testSupersedingMoveKeepsThinkingShellThenReplacesItAtomically() {
        XCUIDevice.shared.orientation = .landscapeRight
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-test-hosted-coaching-continuity",
            "-ui-test-hosted-coaching-snapshots",
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Choose a piece"].waitForExistence(timeout: 5))
        app.buttons["Start hosted coaching continuity test"].tap()

        let shell = app.buttons["Close coaching help"]
        XCTAssertTrue(shell.waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Choose a piece"].exists)
        let thinking = app.descendants(matching: .any)["coaching-thinking-indicator"]
        XCTAssertTrue(thinking.exists)
        XCTAssertEqual(thinking.label, "Thinking")
        XCTAssertFalse(app.staticTexts["Thinking…"].exists)
        let replyArea = app.descendants(matching: .any)["coaching-panel-conversation"].frame
        XCTAssertEqual(thinking.frame.midX, replyArea.midX, accuracy: 1)
        XCTAssertEqual(thinking.frame.midY, replyArea.midY, accuracy: 1)

        let thinkingSnapshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        thinkingSnapshot.name = "Coach thinking"
        thinkingSnapshot.lifetime = .keepAlways
        add(thinkingSnapshot)

        app.buttons["Stage hosted knight move for continuity test"].tap()
        assertThinkingShellRemainsVisible(shell: shell, app: app, duration: 0.65)
        XCTAssertFalse(app.staticTexts["This opening answer is stale."].exists)

        XCTAssertTrue(
            app.staticTexts["How does your knight help from f3?"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["Play this move"].exists)
        XCTAssertTrue(app.buttons["Try another move"].exists)
        XCTAssertFalse(app.staticTexts["Thinking…"].exists)
        XCTAssertFalse(thinking.exists)
        let identity = app.descendants(matching: .any)["coaching-panel-identity"]
        XCTAssertEqual(identity.label, "Coach")
        XCTAssertEqual(identity.value as? String, "")
        XCTAssertTrue(shell.exists)

        let readySnapshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        readySnapshot.name = "Coach ready"
        readySnapshot.lifetime = .keepAlways
        add(readySnapshot)
    }

    @MainActor
    private func assertThinkingShellRemainsVisible(
        shell: XCUIElement,
        app: XCUIApplication,
        duration: TimeInterval
    ) {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            XCTAssertTrue(shell.exists)
            XCTAssertTrue(app.descendants(matching: .any)["coaching-thinking-indicator"].exists)
            let identity = app.descendants(matching: .any)["coaching-panel-identity"]
            XCTAssertTrue(identity.exists)
            XCTAssertEqual(identity.label, "Coach")
            XCTAssertEqual(identity.value as? String, "Thinking")
            XCTAssertFalse(app.staticTexts["Choose a piece"].exists)
            XCTAssertFalse(app.staticTexts["This opening answer is stale."].exists)
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }
}

// Real loopback transport, no paid model and no test endpoint in application code.
private final class ConfigurationProbeServer: @unchecked Sendable {
    private let listener: NWListener
    private let received: XCTestExpectation
    private let queue = DispatchQueue(label: "configuration-probe")

    init(received: XCTestExpectation) throws {
        listener = try NWListener(using: .tcp, on: .any)
        self.received = received
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [self] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: listener.port!.rawValue)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [self] connection in
                connection.start(queue: queue)
                readHeaders(connection, buffer: Data())
            }
            listener.start(queue: queue)
        }
    }

    private func readHeaders(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 131072) { [self] data, _, complete, error in
            let accumulated = buffer + (data ?? Data())
            let text = String(decoding: accumulated, as: UTF8.self)
            if text.contains("\r\n\r\n") {
                if text.hasPrefix("POST /v1/coaching-turn HTTP/1.1"),
                   text.lowercased().contains("authorization: bearer configuration-test-only-token\r\n") {
                    received.fulfill()
                }
                let body = "{\"error\":{\"code\":\"providerUnavailable\"}}"
                let response = "HTTP/1.1 503 Service Unavailable\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            } else if !complete && error == nil && accumulated.count < 131072 {
                readHeaders(connection, buffer: accumulated)
            } else {
                connection.cancel()
            }
        }
    }

    func stop() { listener.cancel() }
}

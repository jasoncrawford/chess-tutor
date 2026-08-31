import XCTest

final class HostedCoachingContinuityUITests: XCTestCase {
    @MainActor
    func testSupersedingMoveKeepsThinkingShellThenReplacesItAtomically() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-hosted-coaching-continuity"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Choose a piece"].waitForExistence(timeout: 5))
        app.buttons["Start hosted coaching continuity test"].tap()

        let shell = app.buttons["Close coaching help"]
        XCTAssertTrue(shell.waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Choose a piece"].exists)

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
        XCTAssertTrue(shell.exists)
    }

    @MainActor
    private func assertThinkingShellRemainsVisible(
        shell: XCUIElement,
        app: XCUIApplication,
        duration: TimeInterval
    ) {
        let deadline = Date().addingTimeInterval(duration)
        var samples = 0
        while Date() < deadline {
            XCTAssertTrue(shell.exists)
            XCTAssertTrue(app.staticTexts["Thinking…"].exists)
            XCTAssertFalse(app.staticTexts["Choose a piece"].exists)
            XCTAssertFalse(app.staticTexts["This opening answer is stale."].exists)
            samples += 1
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertGreaterThanOrEqual(samples, 8)
    }
}

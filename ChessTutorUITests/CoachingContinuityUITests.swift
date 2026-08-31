import XCTest

final class CoachingContinuityUITests: XCTestCase {
    @MainActor
    func testDelayedLocalTurnKeepsCoachingShellVisibleUntilAtomicReplacement() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-coaching-continuity"]
        app.launch()

        let shell = app.buttons["Close coaching help"]
        XCTAssertTrue(app.staticTexts["Choose a piece"].waitForExistence(timeout: 5))
        app.buttons["Start coaching for continuity test"].tap()

        assertCoachingShellRemainsVisible(
            shell: shell,
            app: app,
            duration: 0.65
        )
        XCTAssertTrue(
            app.staticTexts["A center pawn or knight is a simple way to start."]
                .waitForExistence(timeout: 5)
        )

        app.buttons["Stage knight move for continuity test"].tap()

        assertCoachingShellRemainsVisible(
            shell: shell,
            app: app,
            duration: 0.65
        )
        XCTAssertTrue(
            app.staticTexts["You developed your knight toward the center."]
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    private func assertCoachingShellRemainsVisible(
        shell: XCUIElement,
        app: XCUIApplication,
        duration: TimeInterval
    ) {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            XCTAssertTrue(shell.exists)
            XCTAssertFalse(app.staticTexts["I'm checking the board."].exists)
            XCTAssertFalse(app.staticTexts["Choose a piece"].exists)
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }
}

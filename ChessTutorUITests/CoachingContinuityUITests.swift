import XCTest

final class CoachingContinuityUITests: XCTestCase {
    @MainActor
    func testDelayedLocalTurnKeepsCoachingShellVisibleUntilAtomicReplacement() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-coaching-continuity"]
        app.launch()

        let conversation = app.descendants(matching: .any)["coaching-panel-conversation"]
        XCTAssertTrue(conversation.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What move would you like to try?"].exists)

        app.buttons["Stage knight move for continuity test"].tap()

        let deadline = Date().addingTimeInterval(0.65)
        var samples = 0
        while Date() < deadline {
            XCTAssertTrue(conversation.exists)
            XCTAssertFalse(app.staticTexts["I'm checking the board."].exists)
            XCTAssertFalse(app.staticTexts["Choose a piece"].exists)
            samples += 1
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertGreaterThanOrEqual(samples, 8)
        XCTAssertTrue(
            app.staticTexts["You developed your knight."]
                .waitForExistence(timeout: 5)
        )
    }

}

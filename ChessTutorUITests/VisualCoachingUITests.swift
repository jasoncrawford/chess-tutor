import XCTest

@MainActor final class VisualCoachingUITests: XCTestCase {
    func testLinksReplayAndEscapeAreLocalAndAccessible() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-visual-coaching", "explanation"]
        app.launch()
        let link = app.buttons["coach-reference-0"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertEqual("Requests: 1", app.staticTexts["visual-request-count"].label)
        XCTAssertGreaterThanOrEqual(link.frame.height, 44)
        link.tap()
        XCTAssertEqual("Requests: 1", app.staticTexts["visual-request-count"].label)
        let replay = app.buttons["Replay board hint"]
        XCTAssertTrue(replay.exists)
        replay.tap()
        XCTAssertEqual("Requests: 1", app.staticTexts["visual-request-count"].label)
        attach(app, "linked-explanation")

        app.terminate()
        app.launchArguments = ["-ui-test-visual-coaching", "question"]
        app.launch()
        let escape = app.buttons["Play instead"]
        XCTAssertTrue(escape.waitForExistence(timeout: 5))
        attach(app, "answer-question")
        escape.tap()
        XCTAssertTrue(app.staticTexts["Try a move on the board."].exists)
        XCTAssertEqual("Requests: 1", app.staticTexts["visual-request-count"].label)
        XCTAssertFalse(escape.exists)
    }

    func testDraftLinksAndAllActionsFitWideLayoutAtLargeText() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-visual-coaching", "draft", "-visual-wide", "-visual-large"]
        app.launch()
        let piece = app.buttons["coach-reference-1"]
        XCTAssertTrue(piece.waitForExistence(timeout: 5))
        XCTAssertEqual("Requests: 1", app.staticTexts["visual-request-count"].label)
        XCTAssertGreaterThanOrEqual(piece.frame.height, 44)
        piece.tap()
        XCTAssertEqual("Requests: 1", app.staticTexts["visual-request-count"].label)
        let close = app.buttons["Close coaching help"]
        XCTAssertTrue(close.isHittable)
        XCTAssertLessThan(close.frame.maxY, app.frame.maxY - 12)
        attach(app, "draft-revision-wide-large")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPendingAnswerRemainsAQuestionAndDraggingSupersedesIt() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-visual-coaching", "question", "-visual-slow-answer"]
        app.launch()
        XCTAssertTrue(app.buttons["Play instead"].waitForExistence(timeout: 5))
        let knight = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "White knight on b1")).firstMatch
        knight.tap()
        XCTAssertTrue(app.buttons["Play instead"].exists)
        XCTAssertTrue(app.staticTexts["A rook attacks one of your knights. Tap the knight that needs help."].exists)
        attach(app, "pending-answer")
        let destination = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "c3")).firstMatch
        knight.press(forDuration: 0.1, thenDragTo: destination)
        XCTAssertFalse(app.buttons["Play instead"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "White knight on c3")).firstMatch.exists)
    }
}

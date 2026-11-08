import XCTest

final class ManagedGamesCoachingUITests: XCTestCase {
    @MainActor
    func testCoachingWorksAcrossNewReopenedAndRelaunchedGames() {
        XCUIDevice.shared.orientation = .landscapeRight
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-managed-games", "managed-games-run-\(UUID().uuidString)"]
        app.launch()
        app.buttons["empty-games-start-local"].tap()
        XCTAssertTrue(app.buttons["Help"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Play Remotely"].exists)
        app.buttons["Help"].tap()
        let feedback = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Game '")).firstMatch
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        let firstMessage = feedback.label
        XCTAssertTrue(firstMessage.hasSuffix("Moves: 0."))
        app.buttons["Games"].tap()
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'game-card-'"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))
        let firstID = cards.firstMatch.identifier
        app.buttons["games-start-card"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'On this iPad'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Help"].waitForExistence(timeout: 5))
        app.buttons["Help"].tap()
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        XCTAssertNotEqual(feedback.label, firstMessage)
        app.buttons["Games"].tap()
        XCTAssertTrue(app.buttons[firstID].waitForExistence(timeout: 5))
        XCTAssertEqual(cards.count, 2)
        app.buttons[firstID].tap()
        XCTAssertTrue(app.buttons["Help"].waitForExistence(timeout: 5))
        app.buttons["Help"].tap()
        XCTAssertTrue(app.staticTexts[firstMessage].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Help"].waitForExistence(timeout: 5))
        app.buttons["Help"].tap()
        XCTAssertTrue(app.staticTexts[firstMessage].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Integrated games and coaching"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testLeavingThinkingBoardDoesNotBlockHelpInAnotherGame() {
        XCUIDevice.shared.orientation = .landscapeRight
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-managed-games", "managed-games-run-\(UUID().uuidString)", "-delay-first-help"]
        app.launch()
        app.buttons["empty-games-start-local"].tap()
        XCTAssertTrue(app.buttons["Help"].waitForExistence(timeout: 5))
        app.buttons["Help"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["coaching-thinking-indicator"].waitForExistence(timeout: 3))
        app.buttons["Games"].tap()
        app.buttons["games-start-card"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'On this iPad'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Help"].waitForExistence(timeout: 5))
        app.buttons["Help"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Game '")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["coaching-thinking-indicator"].exists)
    }
}

import XCTest

final class ManagedGamesCoachingUITests: XCTestCase {
    @MainActor
    func testRealBoardUsesLastPieceTapWhileAdviceIsPending() {
        XCUIDevice.shared.orientation = .landscapeRight
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-managed-games", "managed-games-run-\(UUID().uuidString)", "-test-piece-answer-burst"]
        app.launch()
        app.buttons["empty-games-start-local"].tap()
        XCTAssertTrue(app.buttons["Help"].waitForExistence(timeout: 5))
        app.buttons["Help"].tap()
        XCTAssertTrue(app.staticTexts["Choose a knight."].waitForExistence(timeout: 5))
        let first = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'White knight on b1'")).firstMatch
        let second = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'White knight on g1'")).firstMatch
        XCTAssertTrue(first.exists)
        XCTAssertTrue(second.exists)
        // Physical contacts exercise the board's zero-distance drag/tap routing,
        // not the fixture buttons or the session handler directly.
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05)
        second.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05)
        app.buttons["Release test advice"].tap()
        XCTAssertTrue(app.staticTexts["Selected piece:white:knight:g1."].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Selected piece:white:knight:b1."].exists)
    }

    @MainActor
    func testCoachingWorksAcrossNewReopenedAndRelaunchedGames() {
        XCUIDevice.shared.orientation = .landscapeRight
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-managed-games", "managed-games-run-\(UUID().uuidString)", "-trace-game-navigation"]
        app.launch()
        addTeardownBlock { @MainActor in _ = self.attachNavigationTrace(app) }
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
    func testShortSavedCardTapsOpenTheSelectedGameAcrossRackTransitions() {
        XCUIDevice.shared.orientation = .landscapeRight
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-managed-games", "managed-games-run-\(UUID().uuidString)", "-trace-game-navigation"]
        app.launch()
        addTeardownBlock { @MainActor in _ = self.attachNavigationTrace(app) }
        app.buttons["empty-games-start-local"].tap()
        XCTAssertTrue(app.buttons["Help"].waitForExistence(timeout: 5))
        app.buttons["Games"].tap()
        app.buttons["games-start-card"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'On this iPad'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Help"].waitForExistence(timeout: 5))
        app.buttons["Games"].tap()
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'game-card-'"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))
        let identifiers = cards.allElementsBoundByIndex.map(\.identifier)
        guard identifiers.count == 2 else {
            XCTFail("Expected two saved games, found \(identifiers.count)")
            return
        }

        // Each contact must open the selected saved board on its first attempt.
        // Returning immediately through the real transition also exercises the
        // scroll view's touch handling; no retry or extended press masks a miss.
        for index in 0..<12 {
            let identifier = identifiers[index % identifiers.count]
            let card = app.buttons[identifier]
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05)
            guard app.buttons["Help"].waitForExistence(timeout: 5) else {
                XCTFail("Short saved-card tap \(index) did not open \(identifier)")
                return
            }
            app.buttons["Help"].tap()
            let gameID = identifier.replacingOccurrences(of: "game-card-", with: "").lowercased()
            XCTAssertTrue(app.staticTexts["Game \(gameID). Moves: 0."].waitForExistence(timeout: 5))
            app.buttons["Games"].tap()
        }
    }

    @MainActor
    func testNavigationTraceCapturesSavedCardTouchAndRoute() throws {
        XCUIDevice.shared.orientation = .landscapeRight
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-managed-games", "managed-games-run-\(UUID().uuidString)", "-trace-game-navigation"]
        app.launch()
        app.buttons["empty-games-start-local"].tap()
        XCTAssertTrue(app.buttons["Help"].waitForExistence(timeout: 5))
        app.buttons["Games"].tap()
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'game-card-'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let identifier = card.identifier
        let frame = card.frame
        // This instrumentation smoke holds long enough to observe isPressed.
        // Both failure reproductions retain their original 50 ms contacts.
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.3)
        XCTAssertTrue(app.buttons["Help"].waitForExistence(timeout: 5))
        let text = try XCTUnwrap(attachNavigationTrace(app))
        let events = text.split(separator: "\n").compactMap { line in
            try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        }
        let request = try XCTUnwrap(events.first {
            $0["event"] as? String == "gameNavigation.open.request"
                && ($0["fields"] as? [String: String])?["card"] == identifier
        })
        let completed = try XCTUnwrap(events.first {
            $0["event"] as? String == "gameNavigation.open.complete"
                && ($0["fields"] as? [String: String])?["card"] == identifier
        })
        let route = "board:" + identifier.replacingOccurrences(of: "game-card-", with: "")
        XCTAssertEqual((request["fields"] as? [String: String])?["route"], "games")
        XCTAssertEqual((completed["fields"] as? [String: String])?["route"], route)
        let changed = try XCTUnwrap(events.first {
            $0["event"] as? String == "gameNavigation.route.changed"
                && ($0["fields"] as? [String: String])?["from"] == "games"
                && ($0["fields"] as? [String: String])?["to"] == route
                && ($0["sequence"] as? Int ?? 0) > (request["sequence"] as? Int ?? 0)
        })
        XCTAssertTrue(events.contains {
            $0["event"] as? String == "gameNavigation.card.pressed"
                && ($0["fields"] as? [String: String])?["card"] == identifier
                && ($0["fields"] as? [String: String])?["pressed"] == "true"
        }, "The trace must observe the selected card's pressed state")
        let requestSequence = try XCTUnwrap(request["sequence"] as? Int)
        let completeSequence = try XCTUnwrap(completed["sequence"] as? Int)
        XCTAssertLessThan(requestSequence, completeSequence)
        XCTAssertLessThan(completeSequence, try XCTUnwrap(changed["sequence"] as? Int))
        XCTAssertTrue(events.contains {
            guard $0["event"] as? String == "gameNavigation.hitTest",
                  let fields = $0["fields"] as? [String: String],
                  let x = Double(fields["x"] ?? ""), let y = Double(fields["y"] ?? ""),
                  let sequence = $0["sequence"] as? Int else { return false }
            return abs(x - frame.midX) < 1 && abs(y - frame.midY) < 1 && sequence < requestSequence
        }, "The trace must include UIKit hit testing at the saved card's tap coordinates")
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

    @MainActor
    private func attachNavigationTrace(_ app: XCUIApplication) -> String? {
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Games hierarchy before trace export"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        if (testRun?.failureCount ?? 0) > 0 {
            let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screen.name = "Saved-game navigation failure"
            screen.lifetime = .keepAlways
            add(screen)
        }
        app.terminate()
        app.launchArguments.append("-dump-game-navigation")
        app.launch()
        let trace = app.staticTexts["game-navigation-trace"]
        guard trace.waitForExistence(timeout: 5) else {
            XCTFail("Could not export navigation trace from the same test run")
            return nil
        }
        let text = trace.label
        let attachment = XCTAttachment(string: text)
        attachment.name = "Saved-game navigation events"
        attachment.lifetime = .keepAlways
        add(attachment)
        return text
    }
}

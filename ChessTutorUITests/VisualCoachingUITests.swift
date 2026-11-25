import XCTest

@MainActor final class VisualCoachingUITests: XCTestCase {
    func testDraggingOutOfAnswerModeKeepsTheOriginalEdgeDestination() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-visual-coaching", "edge-drag", "-visual-large"]
        app.launch()
        XCTAssertTrue(app.buttons["Play instead"].waitForExistence(timeout: 5))
        let rook = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "White rook on a7")).firstMatch
        let destination = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "a8")).firstMatch
        let target = destination.frame
        // Freeze the finger destination before the banner is dismissed, as a
        // real child does; do not re-query a moving square halfway through.
        let point = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: target.midX - app.frame.minX, dy: target.midY - app.frame.minY))
        rook.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: point)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "White rook on a8")).firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["coaching-board-answer-banner"].exists)
        attach(app, "answer-escape-edge-drag")
    }

    func testLongLinkedPhrasesWrapAndRemainTappable() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-visual-coaching", "paragraph", "-visual-large"]
        app.launch()
        let knight = reference("your other knight", in: app)
        XCTAssertTrue(knight.waitForExistence(timeout: 5))
        knight.tap()
        assertFocus("g1", in: app)
        reference("Black's middle pawn", in: app).tap()
        assertFocus("e7", in: app)
        XCTAssertEqual("Requests: 1", app.staticTexts["visual-request-count"].label)
        attach(app, "wrapped-paragraph-large")
    }

    func testAnswerBannerFloatsWithoutMovingSquaresInAnyRotation() {
        XCUIDevice.shared.orientation = .landscapeLeft
        for rotation in ["0", "90", "180", "-90"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-test-visual-coaching", "question", "-visual-rotation", rotation, "-visual-large"]
            app.launch()
            let banner = app.descendants(matching: .any)["coaching-board-answer-banner"].firstMatch
            XCTAssertTrue(banner.waitForExistence(timeout: 5))
            XCTAssertTrue(app.frame.contains(banner.frame))
            let names = ["White knight on b1", "White knight on g1", "Black rook on b8", "Black king on e8"]
            var frames: [String: CGRect] = [:]
            for name in names {
                let square = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
                XCTAssertTrue(square.isHittable)
                frames[name] = square.frame
            }
            attach(app, "answer-banner-\(rotation)")
            app.buttons["Play instead"].tap()
            XCTAssertFalse(banner.exists)
            for name in names {
                let square = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
                XCTAssertEqual(square.frame, frames[name], "Showing or dismissing the banner must not move or resize the board")
            }
            XCTAssertEqual("Requests: 1", app.staticTexts["visual-request-count"].label)
            app.terminate()
        }
    }

    func testAnswerBannerPassesTapsThroughToThePieceUnderneath() {
        XCUIDevice.shared.orientation = .landscapeLeft
        for (rotation, name) in [("0", "Black king on e8"), ("180", "White king on e1")] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-test-visual-coaching", "question", "-visual-rotation", rotation,
                                   "-visual-large", "-visual-slow-answer"]
            app.launch()
            let banner = app.descendants(matching: .any)["coaching-board-answer-banner"].firstMatch
            XCTAssertTrue(banner.waitForExistence(timeout: 5))
            let square = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
            let center = CGPoint(x: square.frame.midX, y: square.frame.midY)
            XCTAssertTrue(banner.frame.contains(center), "Exercise a tap actually underneath the translucent overlay")
            square.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(app.staticTexts["Checking your answer…"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "Requests: 2")).firstMatch.waitForExistence(timeout: 3))
            if rotation == "180" {
                // The white king is both covered and movable. Starting a drag
                // through the overlay must leave answer mode and still land on
                // the square the child aimed at before the banner disappeared.
                let destination = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "d2")).firstMatch
                let target = destination.frame
                let point = app.coordinate(withNormalizedOffset: .zero).withOffset(
                    CGVector(dx: target.midX - app.frame.minX, dy: target.midY - app.frame.minY))
                square.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    .press(forDuration: 0.1, thenDragTo: point)
                XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "White king on d2")).firstMatch.waitForExistence(timeout: 3))
                XCTAssertFalse(banner.exists)
            }
            app.terminate()
        }
    }

    func testLinksAndEscapeAreLocalWithoutRedundantArrowControl() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-visual-coaching", "explanation"]
        app.launch()
        let link = reference("This rook", in: app)
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertEqual("Requests: 1", app.staticTexts["visual-request-count"].label)
        XCTAssertTrue(reference("your knight", in: app).exists)
        // The artwork itself must activate the same link as its words.
        link.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: 5, dy: 0)).tap()
        assertFocus("b8", in: app)
        XCTAssertEqual("Requests: 1", app.staticTexts["visual-request-count"].label)
        XCTAssertFalse(app.buttons["Show arrow"].exists)
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
        let piece = reference("your knight", in: app)
        XCTAssertTrue(piece.waitForExistence(timeout: 5))
        XCTAssertEqual("Requests: 1", app.staticTexts["visual-request-count"].label)
        XCTAssertTrue(app.links["here"].exists)
        XCTAssertFalse(app.buttons["Show arrow"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Play this move")).firstMatch.exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Play my move")).firstMatch.exists)
        piece.tap()
        assertFocus("h3", in: app)
        XCTAssertEqual("Requests: 1", app.staticTexts["visual-request-count"].label)
        let close = app.buttons["Close coaching help"]
        XCTAssertTrue(close.isHittable)
        XCTAssertLessThan(close.frame.maxY, app.frame.maxY - 12)
        attach(app, "draft-revision-wide-large")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testRotatedPanelsKeepReferenceOrderTargetsAndLocalActivation() {
        XCUIDevice.shared.orientation = .landscapeLeft
        for rotation in ["90", "-90"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-test-visual-coaching", "draft", "-visual-rotation", rotation]
            app.launch()
            let first = reference("your knight", in: app)
            let second = app.links["here"]
            XCTAssertTrue(first.waitForExistence(timeout: 5))
            XCTAssertEqual(["your knight", "here"], app.links.allElementsBoundByIndex.map {
                $0.label.trimmingCharacters(in: .whitespacesAndNewlines)
            })
            for (link, target) in [(first, "h3"), (second, "f3")] {
                XCTAssertTrue(link.isHittable)
                XCTAssertTrue(app.frame.contains(link.frame))
                link.tap()
                assertFocus(target, in: app)
                XCTAssertEqual("Requests: 1", app.staticTexts["visual-request-count"].label)
            }
            attach(app, "rotated-draft-\(rotation)")
            app.terminate()
        }
    }

    func testPendingAnswerRemainsAQuestionAndDraggingSupersedesIt() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-visual-coaching", "question", "-visual-slow-answer"]
        app.launch()
        XCTAssertTrue(app.buttons["Play instead"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Tap the piece that needs help"].exists)
        let knight = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "White knight on b1")).firstMatch
        knight.tap()
        XCTAssertTrue(app.buttons["Play instead"].exists)
        XCTAssertTrue(app.staticTexts["Checking your answer…"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["coaching-thinking-indicator"].exists)
        attach(app, "pending-answer")
        let destination = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "c3")).firstMatch
        knight.press(forDuration: 0.1, thenDragTo: destination)
        XCTAssertFalse(app.buttons["Play instead"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "White knight on c3")).firstMatch.exists)
    }

    private func assertFocus(_ square: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let expected = NSPredicate(format: "label == %@", "Focus: \(square)")
        XCTAssertTrue(app.staticTexts.matching(identifier: "visual-focus").matching(expected).firstMatch.waitForExistence(timeout: 1.5),
                      "Expected local highlight on \(square)", file: file, line: line)
    }

    private func reference(_ words: String, in app: XCUIApplication) -> XCUIElement {
        // TextKit omits the decorative attachment from its spoken name, leaving
        // only the nonbreaking space between that icon and the first word.
        app.links.matching(NSPredicate(format: "label == %@ OR label == %@", words, "\u{00a0}" + words)).firstMatch
    }
}

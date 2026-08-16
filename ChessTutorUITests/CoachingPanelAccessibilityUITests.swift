import XCTest

@MainActor
final class CoachingPanelAccessibilityUITests: XCTestCase {
    func testTallCompositionKeepsConversationBeforeRoutineAndActions() {
        assertSemanticOrder(for: "tall")
    }

    func testWideCompositionKeepsConversationBeforeRoutineAndActions() {
        assertSemanticOrder(for: "wide")
    }

    private func assertSemanticOrder(
        for composition: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-coaching-panel", composition]
        app.launch()

        let expectedSectionIdentifiers = [
            "coaching-panel-conversation",
            "coaching-panel-routine",
            "coaching-panel-actions",
        ]
        XCTAssertTrue(
            app.descendants(matching: .any)[expectedSectionIdentifiers[0]].waitForExistence(timeout: 3),
            "The coaching panel fixture did not appear.",
            file: file,
            line: line
        )

        let semanticElements = app.descendants(matching: .any).allElementsBoundByIndex
        XCTAssertEqual(
            semanticElements.map(\.identifier).filter(expectedSectionIdentifiers.contains),
            expectedSectionIdentifiers,
            "Unexpected semantic group order for the \(composition) composition.",
            file: file,
            line: line
        )

        let expectedLabels = [
            "What do you notice?",
            "Find a safe square.",
            "Safe, current step",
            "I need help",
        ]
        XCTAssertEqual(
            semanticElements.map(\.label).filter(expectedLabels.contains),
            expectedLabels,
            "Unexpected VoiceOver reading order for the \(composition) composition.",
            file: file,
            line: line
        )
    }
}

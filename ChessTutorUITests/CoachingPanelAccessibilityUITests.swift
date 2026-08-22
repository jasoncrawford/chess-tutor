import XCTest

@MainActor
final class CoachingPanelAccessibilityUITests: XCTestCase {
    func testTallCompositionKeepsConversationBeforeRoutineAndActions() {
        assertPanelLayout(
            for: "tall",
            expectedResponse: "Right—there isn’t one."
        )
    }

    func testClockwiseQuarterTurnKeepsReadableRegionsDisjointAndInsidePanel() {
        assertPanelLayout(
            for: "clockwise-quarter-turn",
            expectedResponse: "Right—there isn’t one."
        )
    }

    func testCounterclockwiseQuarterTurnKeepsReadableRegionsDisjointAndInsidePanel() {
        assertPanelLayout(
            for: "counterclockwise-quarter-turn",
            expectedResponse: "Right—there isn’t one."
        )
    }

    func testConversationOmitsResponseCleanlyWhenNil() {
        assertPanelLayout(for: "tall-no-response", expectedResponse: nil)
    }

    private func assertPanelLayout(
        for configuration: String,
        expectedResponse: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-coaching-panel", configuration]
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
            "Unexpected semantic group order for \(configuration).",
            file: file,
            line: line
        )

        let expectedHeadline = expectedResponse == nil
            ? "Yes—that pawn is attacking your queen. How could you help your queen?"
            : "Can one of your pieces make a useful capture?"
        let expectedInstruction = expectedResponse == nil
            ? "Try moving your queen, protecting it, or taking the attacker."
            : "Make the capture, or choose I don’t see one."
        let expectedLabels = ([
            expectedResponse,
            expectedHeadline,
            expectedInstruction,
            "Safe, current step",
            "Done with this move",
            "Keep looking for another move",
            "Stop coaching",
        ] as [String?]).compactMap { $0 }
        XCTAssertEqual(
            semanticElements.map(\.label).filter(expectedLabels.contains),
            expectedLabels,
            "Unexpected VoiceOver reading order for \(configuration).",
            file: file,
            line: line
        )

        let panel = app.descendants(matching: .any)["coaching-panel-frame"]
        XCTAssertTrue(panel.exists, "The fixture panel frame is missing.", file: file, line: line)

        let sections = expectedSectionIdentifiers.map {
            app.descendants(matching: .any)[$0]
        }
        for section in sections {
            XCTAssertTrue(
                panel.frame.contains(section.frame),
                "\(section.identifier) leaves the panel in \(configuration): "
                    + "panel=\(panel.frame), section=\(section.frame)",
                file: file,
                line: line
            )
        }
        for firstIndex in sections.indices {
            for secondIndex in sections.indices where secondIndex > firstIndex {
                XCTAssertFalse(
                    sections[firstIndex].frame.intersects(sections[secondIndex].frame),
                    "\(sections[firstIndex].identifier) overlaps "
                        + "\(sections[secondIndex].identifier) in \(configuration): "
                        + "\(sections[firstIndex].frame) vs \(sections[secondIndex].frame)",
                    file: file,
                    line: line
                )
            }
        }
    }
}

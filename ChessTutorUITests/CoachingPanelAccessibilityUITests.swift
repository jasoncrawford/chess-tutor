import XCTest

@MainActor
final class CoachingPanelAccessibilityUITests: XCTestCase {
    func testTallCompositionKeepsConversationBeforeRoutineAndActions() {
        assertPanelLayout(
            for: "tall",
            expectedObservation: "That knight does not cause trouble here."
        )
    }

    func testClockwiseQuarterTurnKeepsReadableRegionsDisjointAndInsidePanel() {
        assertPanelLayout(
            for: "clockwise-quarter-turn",
            expectedObservation: "That knight does not cause trouble here."
        )
    }

    func testCounterclockwiseQuarterTurnKeepsReadableRegionsDisjointAndInsidePanel() {
        assertPanelLayout(
            for: "counterclockwise-quarter-turn",
            expectedObservation: "That knight does not cause trouble here."
        )
    }

    func testConversationOmitsObservationCleanlyWhenNil() {
        assertPanelLayout(for: "tall-no-observation", expectedObservation: nil)
    }

    func testWideConversationOmitsObservationCleanlyWhenNil() {
        assertPanelLayout(for: "clockwise-quarter-turn-no-observation", expectedObservation: nil)
    }

    func testAccessibilityExtraLargeTallCompositionKeepsEveryRegionReachable() {
        assertPanelLayout(
            for: "tall",
            expectedObservation: "That knight does not cause trouble here.",
            accessibilityExtraLarge: true
        )
    }

    func testAccessibilityExtraLargeWideCompositionKeepsEveryRegionReachable() {
        assertPanelLayout(
            for: "clockwise-quarter-turn",
            expectedObservation: "That knight does not cause trouble here.",
            accessibilityExtraLarge: true
        )
    }

    private func assertPanelLayout(
        for configuration: String,
        expectedObservation: String?,
        accessibilityExtraLarge: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-coaching-panel", configuration]
        if accessibilityExtraLarge {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraLarge",
            ]
        }
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

        let expectedPrimary = "What could Black do next?"
        let expectedInstruction = "Tap a black piece that could check your king or win one of your pieces."
        let expectedLabels = ([
            expectedPrimary,
            expectedInstruction,
            expectedObservation,
            "Safe, current step",
            "Play this move",
            "Try another move",
            "Close coaching help",
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

import XCTest

@MainActor
final class CoachingPanelAccessibilityUITests: XCTestCase {
    func testCompactTurnsStayOrderedDisjointAndContainedAtStandardText() {
        assertPermanentMatrix(accessibilityExtraLarge: false)
    }

    func testCompactTurnsStayOrderedDisjointAndContainedAtAccessibilityExtraLarge() {
        assertPermanentMatrix(accessibilityExtraLarge: true)
    }

    private func assertPermanentMatrix(
        accessibilityExtraLarge: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let rotations = [
            "tall",
            "clockwise-quarter-turn",
            "counterclockwise-quarter-turn",
        ]
        let turns: [(
            configuration: String,
            primary: String,
            instruction: String,
            observation: String?,
            actions: [String]
        )] = [
            (
                "compact-no-observation",
                "That move seems safe.",
                "Play it, or try another move.",
                nil,
                ["Play this move", "Try another move", "Close coaching help"]
            ),
            (
                "compact-with-observation",
                "What could White do next?",
                "Tap a white piece that could check your king or win one of your pieces.",
                "That bishop attacks your pawn, but the pawn is protected.",
                ["Looks safe", "Show a hint", "Close coaching help"]
            ),
        ]

        for rotation in rotations {
            for turn in turns {
                assertPanelLayout(
                    for: rotation,
                    turn: turn.configuration,
                    expectedPrimary: turn.primary,
                    expectedInstruction: turn.instruction,
                    expectedObservation: turn.observation,
                    expectedActions: turn.actions,
                    accessibilityExtraLarge: accessibilityExtraLarge,
                    file: file,
                    line: line
                )
            }
        }
    }

    private func assertPanelLayout(
        for configuration: String,
        turn: String,
        expectedPrimary: String,
        expectedInstruction: String,
        expectedObservation: String?,
        expectedActions: [String],
        accessibilityExtraLarge: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-coaching-panel", configuration, turn]
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

        let expectedConversationLabels = ([
            expectedPrimary,
            expectedInstruction,
            expectedObservation,
        ] as [String?]).compactMap { $0 }
        let conversation = app.descendants(matching: .any)[expectedSectionIdentifiers[0]]
        XCTAssertEqual(
            conversation.staticTexts.allElementsBoundByIndex.map(\.label),
            expectedConversationLabels,
            "Unexpected conversation reading order for \(configuration), \(turn).",
            file: file,
            line: line
        )
        let expectedLabels = ([
            expectedPrimary,
            expectedInstruction,
            expectedObservation,
            "Safe, current step",
        ] as [String?]).compactMap { $0 } + expectedActions
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

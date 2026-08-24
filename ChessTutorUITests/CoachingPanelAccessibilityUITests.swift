import XCTest

@MainActor
final class CoachingPanelAccessibilityUITests: XCTestCase {
    func testCoachingTypographyAndActionGrowAtAccessibilityExtraLargeInTallLayout() {
        assertTypographyGrows(configuration: "tall")
    }

    func testCoachingTypographyAndActionGrowAtAccessibilityExtraLargeInWideLayout() {
        assertTypographyGrows(configuration: "clockwise-quarter-turn")
    }

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
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            accessibilityExtraLarge
                ? "UICTContentSizeCategoryAccessibilityExtraLarge"
                : "UICTContentSizeCategoryLarge",
            "-ui-test-dynamic-type-size",
            accessibilityExtraLarge ? "accessibility-extra-large" : "large",
        ]
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
            conversation.descendants(matching: .any).allElementsBoundByIndex
                .filter {
                    expectedConversationLabels.contains($0.label)
                        && ($0.label != expectedObservation
                            || $0.identifier == "coaching-response-note")
                }
                .map(\.label),
            expectedConversationLabels,
            "Unexpected conversation reading order for \(configuration), \(turn).",
            file: file,
            line: line
        )
        if let expectedObservation {
            let instruction = app.staticTexts[expectedInstruction]
            let response = app.otherElements["coaching-response-note"]
            XCTAssertTrue(
                response.waitForExistence(timeout: 3),
                "The response note is missing in \(configuration), \(turn).",
                file: file,
                line: line
            )
            XCTAssertEqual(response.label, expectedObservation, file: file, line: line)
            assertResponseFollowsInstruction(
                instruction.frame,
                response.frame,
                configuration: configuration,
                turn: turn,
                file: file,
                line: line
            )
            XCTAssertTrue(
                conversation.frame.contains(response.frame),
                "The response leaves the conversation in \(configuration), \(turn).",
                file: file,
                line: line
            )
        } else {
            XCTAssertFalse(
                app.otherElements["coaching-response-note"].exists,
                "A response note appeared without an observation in \(configuration), \(turn).",
                file: file,
                line: line
            )
        }
        let expectedLabels = ([
            expectedPrimary,
            expectedInstruction,
            expectedObservation,
            "Safe, current step",
        ] as [String?]).compactMap { $0 } + expectedActions
        XCTAssertEqual(
            semanticElements
                .filter {
                    expectedLabels.contains($0.label)
                        && ($0.label != expectedObservation
                            || $0.identifier == "coaching-response-note")
                }
                .map(\.label),
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
        let actionSection = sections[2]
        for label in expectedActions {
            let button = app.buttons[label]
            XCTAssertTrue(
                button.exists && button.isHittable,
                "\(label) is not reachable in \(configuration), \(turn).",
                file: file,
                line: line
            )
            XCTAssertTrue(
                panel.frame.contains(button.frame) && actionSection.frame.contains(button.frame),
                "\(label) leaves its action region in \(configuration), \(turn): "
                    + "panel=\(panel.frame), actions=\(actionSection.frame), button=\(button.frame)",
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

    private func assertResponseFollowsInstruction(
        _ instruction: CGRect,
        _ response: CGRect,
        configuration: String,
        turn: String,
        file: StaticString,
        line: UInt
    ) {
        switch configuration {
        case "clockwise-quarter-turn":
            XCTAssertLessThan(
                response.maxX,
                instruction.minX,
                "The response does not follow the instruction in \(configuration), \(turn).",
                file: file,
                line: line
            )
        case "counterclockwise-quarter-turn":
            XCTAssertLessThan(
                instruction.maxX,
                response.minX,
                "The response does not follow the instruction in \(configuration), \(turn).",
                file: file,
                line: line
            )
        default:
            XCTAssertLessThan(
                instruction.maxY,
                response.minY,
                "The response does not follow the instruction in \(configuration), \(turn).",
                file: file,
                line: line
            )
        }
    }

    private func typographyMetrics(
        configuration: String,
        contentSizeCategory: String,
        terminateAfterMeasurement: Bool
    ) -> (
        primaryThickness: CGFloat,
        instructionThickness: CGFloat,
        observationThickness: CGFloat,
        actionThickness: CGFloat
    ) {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-test-coaching-panel",
            configuration,
            "compact-with-observation",
            "-UIPreferredContentSizeCategoryName",
            contentSizeCategory,
            "-ui-test-dynamic-type-size",
            contentSizeCategory == "UICTContentSizeCategoryAccessibilityExtraLarge"
                ? "accessibility-extra-large"
                : "large",
        ]
        app.launch()

        let primary = app.staticTexts["What could White do next?"]
        XCTAssertTrue(primary.waitForExistence(timeout: 3))
        let instruction = app.staticTexts[
            "Tap a white piece that could check your king or win one of your pieces."
        ]
        let observation = app.staticTexts[
            "That bishop attacks your pawn, but the pawn is protected."
        ]
        let action = app.buttons["Looks safe"]
        XCTAssertTrue(instruction.exists)
        XCTAssertTrue(observation.exists)
        XCTAssertTrue(action.exists)
        let result = (
            min(primary.frame.width, primary.frame.height),
            min(instruction.frame.width, instruction.frame.height),
            min(observation.frame.width, observation.frame.height),
            min(action.frame.width, action.frame.height)
        )
        if terminateAfterMeasurement {
            app.terminate()
        }
        return result
    }

    private func assertTypographyGrows(
        configuration: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let large = typographyMetrics(
            configuration: configuration,
            contentSizeCategory: "UICTContentSizeCategoryLarge",
            terminateAfterMeasurement: true
        )
        let accessibilityExtraLarge = typographyMetrics(
            configuration: configuration,
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityExtraLarge",
            terminateAfterMeasurement: false
        )

        XCTAssertGreaterThan(
            accessibilityExtraLarge.primaryThickness,
            large.primaryThickness,
            "Primary coaching copy did not scale in \(configuration).",
            file: file,
            line: line
        )
        XCTAssertGreaterThan(
            accessibilityExtraLarge.instructionThickness,
            large.instructionThickness,
            "Instruction copy did not scale in \(configuration).",
            file: file,
            line: line
        )
        XCTAssertGreaterThan(
            accessibilityExtraLarge.observationThickness,
            large.observationThickness,
            "Observation copy did not scale in \(configuration).",
            file: file,
            line: line
        )
        XCTAssertGreaterThan(
            accessibilityExtraLarge.actionThickness,
            large.actionThickness,
            "Coaching actions did not scale in \(configuration).",
            file: file,
            line: line
        )
    }
}

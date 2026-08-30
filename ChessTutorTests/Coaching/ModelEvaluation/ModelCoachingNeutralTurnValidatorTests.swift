import XCTest
@testable import ChessTutor

final class ModelCoachingNeutralTurnValidatorTests: XCTestCase {
    func testValidTurnUsesOnlyRequestLocalAliases() {
        let compilation = compilation(
            bindings: [
                binding("action-1", category: .action),
                binding("piece-1", category: .piece),
                binding("move-1", category: .move),
            ]
        )
        let turn = ModelCoachingNeutralTurn(
            message: "What could your knight try next?",
            actions: ["action-1"],
            focus: ["piece-1", "move-1"]
        )

        XCTAssertEqual(
            ModelCoachingNeutralTurnValidator.issues(for: turn, compilation: compilation),
            []
        )
    }

    func testRejectsEmptyMessage() {
        let emptyTurn = ModelCoachingNeutralTurn(message: "  \n ", actions: [], focus: [])

        XCTAssertEqual(
            ModelCoachingNeutralTurnValidator.issues(for: emptyTurn, compilation: compilation()),
            ["Message must not be empty."]
        )
    }

    func testAllowsEighteenWordsAndRejectsNineteen() {
        let compilation = compilation()
        let eighteenWordTurn = ModelCoachingNeutralTurn(
            message: "One two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen.",
            actions: [],
            focus: []
        )
        let nineteenWordTurn = ModelCoachingNeutralTurn(
            message: "One two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen.",
            actions: [],
            focus: []
        )

        XCTAssertEqual(
            ModelCoachingNeutralTurnValidator.issues(for: eighteenWordTurn, compilation: compilation),
            []
        )
        XCTAssertEqual(
            ModelCoachingNeutralTurnValidator.issues(for: nineteenWordTurn, compilation: compilation),
            ["Message must be 18 words or fewer."]
        )
    }

    func testRejectsUnknownActionAlias() {
        let turn = ModelCoachingNeutralTurn(
            message: "What do you notice?",
            actions: ["action-99"],
            focus: []
        )

        XCTAssertEqual(
            ModelCoachingNeutralTurnValidator.issues(for: turn, compilation: compilation()),
            ["Unknown action alias: action-99."]
        )
    }

    func testRejectsUnknownFocusAlias() {
        let turn = ModelCoachingNeutralTurn(
            message: "What do you notice?",
            actions: [],
            focus: ["piece-99"]
        )

        XCTAssertEqual(
            ModelCoachingNeutralTurnValidator.issues(for: turn, compilation: compilation()),
            ["Unknown focus alias: piece-99."]
        )
    }

    func testRejectsDuplicateAliases() {
        let compilation = compilation(
            bindings: [
                binding("action-1", category: .action),
                binding("piece-1", category: .piece),
            ]
        )
        let turn = ModelCoachingNeutralTurn(
            message: "What do you notice?",
            actions: ["action-1", "action-1"],
            focus: ["piece-1", "piece-1"]
        )

        XCTAssertEqual(
            ModelCoachingNeutralTurnValidator.issues(for: turn, compilation: compilation),
            [
                "Duplicate action alias: action-1.",
                "Duplicate focus alias: piece-1.",
            ]
        )
    }

    func testRejectsMoreThanThreeActions() {
        let aliases = (1...4).map { "action-\($0)" }
        let compilation = compilation(
            bindings: aliases.map { binding($0, category: .action) }
        )
        let turn = ModelCoachingNeutralTurn(
            message: "What do you notice?",
            actions: aliases,
            focus: []
        )

        XCTAssertEqual(
            ModelCoachingNeutralTurnValidator.issues(for: turn, compilation: compilation),
            ["Actions must contain at most 3 aliases."]
        )
    }

    func testRejectsMoreThanFourFocusReferences() {
        let aliases = (1...5).map { "piece-\($0)" }
        let compilation = compilation(
            bindings: aliases.map { binding($0, category: .piece) }
        )
        let turn = ModelCoachingNeutralTurn(
            message: "What do you notice?",
            actions: [],
            focus: aliases
        )

        XCTAssertEqual(
            ModelCoachingNeutralTurnValidator.issues(for: turn, compilation: compilation),
            ["Focus must contain at most 4 aliases."]
        )
    }

    func testRejectsActionAliasPlacedInFocus() {
        let compilation = compilation(
            bindings: [binding("action-1", category: .action)]
        )
        let turn = ModelCoachingNeutralTurn(
            message: "What do you notice?",
            actions: [],
            focus: ["action-1"]
        )

        XCTAssertEqual(
            ModelCoachingNeutralTurnValidator.issues(for: turn, compilation: compilation),
            ["Unknown focus alias: action-1."]
        )
    }

    private func compilation(
        bindings: [ModelCoachingReferenceBinding] = []
    ) -> ModelCoachingNeutralContextCompilation {
        ModelCoachingNeutralContextCompilation(
            schemaVersion: "model-coaching-neutral-context.v1",
            promptVersion: "tutor-v5",
            requestID: "validator-test",
            positionRevision: 1,
            markdown: "# Chess coaching situation",
            referenceBindings: bindings
        )
    }

    private func binding(
        _ alias: String,
        category: ModelCoachingSourceReferenceCategory
    ) -> ModelCoachingReferenceBinding {
        ModelCoachingReferenceBinding(
            alias: alias,
            stableID: "stable:\(alias)",
            category: category,
            label: alias
        )
    }
}

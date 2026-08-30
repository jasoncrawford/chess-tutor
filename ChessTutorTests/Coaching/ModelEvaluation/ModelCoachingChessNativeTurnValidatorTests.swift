import Foundation
import XCTest
@testable import ChessTutor

final class ModelCoachingChessNativeTurnValidatorTests: XCTestCase {
    func testDecoderAcceptsValidSemanticSquareAndMoveFocus() throws {
        let data = Data(
            #"{"message":"Look at the queen. What could it take?","actions":["playMove"],"focus":[{"type":"square","square":"h4"},{"type":"move","from":"h4","to":"f2"}]}"#.utf8
        )

        XCTAssertEqual(
            try ModelCoachingChessNativeTurnDecoder.decodeAndValidate(
                data,
                compilation: compilation()
            ),
            ModelCoachingChessNativeTurn(
                message: "Look at the queen. What could it take?",
                actions: ["playMove"],
                focus: [
                    .square("h4"),
                    .move(from: "h4", to: "f2"),
                ]
            )
        )
    }

    func testDecoderRejectsMalformedAndNonObjectJSON() {
        assertRejected(Data(#"{"message":"Look at the queen.""#.utf8))
        assertRejected(Data(#"["Look at the queen."]"#.utf8))
    }

    func testDecoderRejectsUnknownOuterFields() {
        assertRejected(
            json: #"{"message":"Look at the queen.","actions":[],"focus":[],"analysis":"private"}"#
        )
    }

    func testDecoderRejectsUnknownSquareFocusFields() {
        assertRejected(
            json: #"{"message":"Look at the queen.","actions":[],"focus":[{"type":"square","square":"h4","label":"queen"}]}"#
        )
    }

    func testDecoderRejectsUnknownMoveFocusFields() {
        assertRejected(
            json: #"{"message":"Look at the queen.","actions":[],"focus":[{"type":"move","from":"h4","to":"f2","san":"Qxf2"}]}"#
        )
    }

    func testDecoderRejectsMalformedFocusObjects() {
        let malformedFocusValues = [
            #""h4""#,
            #"{"type":"piece","square":"h4"}"#,
            #"{"type":"square","from":"h4","to":"f2"}"#,
            #"{"type":"move","square":"h4"}"#,
        ]

        for focus in malformedFocusValues {
            assertRejected(
                json: #"{"message":"Look at the queen.","actions":[],"focus":[\#(focus)]}"#,
                file: #filePath,
                line: #line
            )
        }
    }

    func testDecoderRejectsUnavailableActions() {
        assertRejected(
            json: #"{"message":"Look at the queen.","actions":["tryAnotherMove"],"focus":[]}"#
        )
    }

    func testDecoderRejectsOffBoardSquareFocus() {
        for square in ["a0", "i4", "A4", "h9", "h44"] {
            assertRejected(
                json: #"{"message":"Look at the queen.","actions":[],"focus":[{"type":"square","square":"\#(square)"}]}"#,
                file: #filePath,
                line: #line
            )
        }
    }

    func testDecoderRejectsUnavailableMoveFocus() {
        assertRejected(
            json: #"{"message":"Look at the queen.","actions":[],"focus":[{"type":"move","from":"h4","to":"e4"}]}"#
        )
    }

    func testDecoderRejectsDuplicateActionsAndFocusObjects() {
        assertRejected(
            json: #"{"message":"Look at the queen.","actions":["playMove","playMove"],"focus":[{"type":"square","square":"h4"}]}"#
        )
        assertRejected(
            json: #"{"message":"Look at the queen.","actions":[],"focus":[{"type":"square","square":"h4"},{"type":"square","square":"h4"}]}"#
        )
        assertRejected(
            json: #"{"message":"Look at the queen.","actions":[],"focus":[{"type":"move","from":"h4","to":"f2"},{"type":"move","from":"h4","to":"f2"}]}"#
        )
    }

    func testDecoderEnforcesMessageActionAndFocusBounds() throws {
        let eighteenWords = (1...18).map { "word\($0)" }.joined(separator: " ")
        let nineteenWords = (1...19).map { "word\($0)" }.joined(separator: " ")
        let boundedCompilation = compilation(
            availableActions: ["hint", "playMove", "tryAnotherMove", "extraAction"],
            availableMoveFocus: []
        )

        XCTAssertNoThrow(
            try ModelCoachingChessNativeTurnDecoder.decodeAndValidate(
                turnData(message: eighteenWords),
                compilation: boundedCompilation
            )
        )
        assertRejected(turnData(message: "  \n "), compilation: boundedCompilation)
        assertRejected(turnData(message: nineteenWords), compilation: boundedCompilation)
        assertRejected(
            turnData(actions: ["hint", "playMove", "tryAnotherMove", "extraAction"]),
            compilation: boundedCompilation
        )
        assertRejected(
            turnData(focus: (1...5).map { ["type": "square", "square": "a\($0)"] }),
            compilation: boundedCompilation
        )
    }

    func testDecoderRejectsChessNotationInChildFacingMessage() {
        let forbiddenMessages = [
            "Try Nc3 next.",
            "What happens after Qxf2+?",
            "Could you play e2e4?",
            "Try O-O now.",
            "Can the queen x that pawn?",
            "That move gives +.",
            "That move gives #.",
        ]

        for message in forbiddenMessages {
            assertRejected(
                turnData(message: message),
                file: #filePath,
                line: #line
            )
        }
    }

    func testDecoderAllowsStandaloneSquareInOrdinaryLanguage() throws {
        let turn = try ModelCoachingChessNativeTurnDecoder.decodeAndValidate(
            turnData(message: "Look at the knight on c3."),
            compilation: compilation()
        )

        XCTAssertEqual(turn.message, "Look at the knight on c3.")
    }

    private func compilation(
        availableActions: [String] = ["hint", "playMove"],
        availableMoveFocus: [ModelCoachingChessNativeMoveFocus] = [
            ModelCoachingChessNativeMoveFocus(from: "h4", to: "f2"),
        ]
    ) -> ModelCoachingChessNativeContextCompilation {
        ModelCoachingChessNativeContextCompilation(
            schemaVersion: "model-coaching-chess-native-context.v1",
            promptVersion: "tutor-v6",
            requestID: "validator-test",
            positionRevision: 1,
            markdown: "# Chess coaching situation",
            availableActions: availableActions,
            availableMoveFocus: availableMoveFocus
        )
    }

    private func turnData(
        message: String = "Look at the queen.",
        actions: [String] = [],
        focus: [[String: String]] = []
    ) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "message": message,
            "actions": actions,
            "focus": focus,
        ])
    }

    private func assertRejected(
        json: String,
        compilation: ModelCoachingChessNativeContextCompilation? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertRejected(
            Data(json.utf8),
            compilation: compilation ?? self.compilation(),
            file: file,
            line: line
        )
    }

    private func assertRejected(
        _ data: Data,
        compilation: ModelCoachingChessNativeContextCompilation? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try ModelCoachingChessNativeTurnDecoder.decodeAndValidate(
                data,
                compilation: compilation ?? self.compilation()
            ),
            file: file,
            line: line
        )
    }
}

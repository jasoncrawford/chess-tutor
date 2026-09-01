import json
import sys
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

import chess_native_response


class ChessNativeResponseContractTests(unittest.TestCase):
    @staticmethod
    def contract():
        return chess_native_response.ChessNativeResponseContract.from_markdown(
            "# Chess coaching situation\n\n"
            "## Available UI response\n\n"
            "Actions: hint, playMove, tryAnotherMove\n"
            "Square focus: any board square\n"
            "Allowable move focus: g1-f3, h4-f2"
        )

    def test_parses_available_ui_response_from_exact_model_facing_markdown(self):
        markdown = (
            "# Chess coaching situation\n\n"
            "## Position\n\n"
            "Side to move: White\n\n"
            "## Available UI response\n\n"
            "Actions: hint, playMove, tryAnotherMove\n"
            "Square focus: any board square\n"
            "Allowable move focus: b1-c3, h4-e4, h4-f2, h4-h2"
        )

        contract = chess_native_response.ChessNativeResponseContract.from_markdown(
            markdown
        )

        self.assertEqual(("hint", "playMove", "tryAnotherMove"), contract.actions)
        self.assertEqual(
            (("b1", "c3"), ("h4", "e4"), ("h4", "f2"), ("h4", "h2")),
            contract.allowable_moves,
        )

    def test_v10_contract_requires_one_declared_interaction_channel(self):
        contract = chess_native_response.ChessNativeResponseContract.from_markdown(
            "# Chess coaching situation\n\n"
            "## Available UI response\n\n"
            "Actions: hint, noPieceNeedsHelp\n"
            "Expected response: none, selectPiece, stageMove\n"
            "Square focus: any board square\n"
            "Allowable move focus: none"
        )
        candidate = (
            '{"message":"Can you find the piece in danger?",'
            '"actions":["noPieceNeedsHelp"],"focus":[],'
            '"expects":"selectPiece"}'
        )

        self.assertEqual(
            ("none", "selectPiece", "stageMove"),
            contract.expected_responses,
        )
        self.assertEqual("selectPiece", contract.parse_and_validate(candidate)["expects"])
        self.assertEqual(
            ["none", "selectPiece", "stageMove"],
            contract.json_schema()["properties"]["expects"]["enum"],
        )
        with self.assertRaises(ValueError):
            contract.parse_and_validate(
                '{"message":"Look.","actions":[],"focus":[],"expects":"tapSquare"}'
            )

    def test_rejects_malformed_available_ui_response_contracts(self):
        invalid_sections = (
            "Actions: hint, hint\nSquare focus: any board square\nAllowable move focus: none",
            "Actions: bad-action\nSquare focus: any board square\nAllowable move focus: none",
            "Actions: hint\nSquare focus: h4\nAllowable move focus: none",
            "Actions: hint\nSquare focus: any board square\nAllowable move focus: i4-a1",
            (
                "Actions: hint\nSquare focus: any board square\n"
                "Allowable move focus: b1-c3, b1-c3"
            ),
            (
                "Actions: hint\nSquare focus: any board square\n"
                "Allowable move focus: none\nUnexpected: value"
            ),
        )

        for section in invalid_sections:
            with self.subTest(section=section), self.assertRaises(ValueError):
                chess_native_response.ChessNativeResponseContract.from_markdown(
                    "# Chess coaching situation\n\n"
                    "## Available UI response\n\n"
                    + section
                )

    def test_builds_exact_request_specific_grammar(self):
        grammar = self.contract().grammar(enable_thinking=False)

        self.assertIn("root ::= turn", grammar)
        self.assertNotIn("thinking-block", grammar)
        self.assertIn(
            'turn ::= "{" space message-kv "," space actions-kv "," space focus-kv space "}"',
            grammar,
        )
        self.assertIn("message-tail{0,17}", grammar)
        self.assertIn('actions ::= "[" space "]" | "[" space action', grammar)
        self.assertIn('action ::= ("\\\"hint\\\""', grammar)
        self.assertIn('"\\\"playMove\\\""', grammar)
        self.assertIn('"\\\"tryAnotherMove\\\""', grammar)
        self.assertIn('focus-tail{0,3}', grammar)
        self.assertIn('"\\\"g1\\\""', grammar)
        self.assertIn('"\\\"f3\\\""', grammar)
        self.assertIn('"\\\"h4\\\""', grammar)
        self.assertIn('"\\\"f2\\\""', grammar)
        self.assertNotIn('"\\\"a1\\\""', grammar)
        self.assertIn('board-square ::= "\\\"" [a-h] [1-8] "\\\""', grammar)
        self.assertIn(
            r'message-char ::= [^"\\ \x7F\x00-\x1F]',
            grammar,
        )

    def test_builds_strict_request_specific_json_schema(self):
        schema = self.contract().json_schema()

        self.assertFalse(schema["additionalProperties"])
        self.assertEqual(["message", "actions", "focus"], schema["required"])
        self.assertEqual(
            ["hint", "playMove", "tryAnotherMove"],
            schema["properties"]["actions"]["items"]["enum"],
        )

    def test_bounded_grammar_requires_one_short_closed_thinking_envelope(self):
        grammar = self.contract().grammar(enable_thinking=True)

        self.assertIn("root ::= thinking-block turn", grammar)
        self.assertIn('thinking-block ::= "<think>"', grammar)
        self.assertIn('"</think>"', grammar)
        self.assertIn("line-break{0,2}", grammar)
        self.assertIn("reasoning ::= [^<]{0,128}", grammar)

    def test_strips_bounded_thinking_without_returning_private_text(self):
        candidate = '{"message":"Look at the knight.","actions":[],"focus":[]}'
        raw_response = "<think>\nprivate reasoning\n</think>\n" + candidate

        stripped = self.contract().strip_thinking(
            raw_response, enable_thinking=True
        )

        self.assertEqual(candidate, stripped)
        self.assertNotIn("private reasoning", stripped)

    def test_enforces_trace_envelope_boundary(self):
        candidate = '{"message":"Look.","actions":[],"focus":[]}'
        contract = self.contract()

        self.assertEqual(
            candidate,
            contract.strip_thinking(
                "<think>" + ("x" * 128) + "</think>" + candidate,
                enable_thinking=True,
            ),
        )
        self.assertEqual(
            candidate,
            contract.strip_thinking(candidate, enable_thinking=False),
        )

        invalid_responses = (
            ("<think>private</think>" + candidate, False),
            ("<think>" + ("x" * 129) + "</think>" + candidate, True),
            ("<think>private<detail</think>" + candidate, True),
            ("<think>private" + candidate, True),
            (
                "<think>one</think><think>two</think>" + candidate,
                True,
            ),
            (
                "<think>private</think>"
                '{"message":"<think>leak</think>","actions":[],"focus":[]}',
                True,
            ),
        )
        for response, enable_thinking in invalid_responses:
            with self.subTest(response=response), self.assertRaises(ValueError):
                contract.strip_thinking(
                    response, enable_thinking=enable_thinking
                )

    def test_parses_one_valid_strict_response(self):
        candidate = (
            '{"message":"Look at the knight on g1.",'
            '"actions":["playMove"],'
            '"focus":[{"type":"square","square":"g1"},'
            '{"type":"move","from":"g1","to":"f3"}]}'
        )

        turn = self.contract().parse_and_validate(candidate)

        self.assertEqual(
            {
                "message": "Look at the knight on g1.",
                "actions": ["playMove"],
                "focus": [
                    {"type": "square", "square": "g1"},
                    {"type": "move", "from": "g1", "to": "f3"},
                ],
            },
            turn,
        )

    def test_rejects_duplicate_json_keys_at_every_object_depth(self):
        duplicate_candidates = (
            (
                '{"message":"Look.","mess\\u0061ge":"Again.",'
                '"actions":[],"focus":[]}'
            ),
            (
                '{"message":"Look.","actions":[],"focus":['
                '{"type":"square","square":"g1","square":"g1"}]}'
            ),
            (
                '{"message":"Look.","actions":[],"focus":['
                '{"type":"move","from":"g1","from":"g1","to":"f3"}]}'
            ),
        )

        for candidate in duplicate_candidates:
            with self.subTest(candidate=candidate), self.assertRaisesRegex(
                ValueError, "Duplicate JSON key"
            ):
                self.contract().parse_and_validate(candidate)

    def test_rejects_lone_unicode_surrogates_recursively(self):
        invalid_candidates = (
            '{"message":"Look \\ud800","actions":[],"focus":[]}',
            '{"message":"Look.","actions":["\\udfff"],"focus":[]}',
            (
                '{"message":"Look.","actions":[],"focus":['
                '{"type":"square","square":"\\ud800"}]}'
            ),
            '{"message":"Look.","actions":[],"focus":[],"\\udfff":0}',
        )

        for candidate in invalid_candidates:
            with self.subTest(candidate=candidate), self.assertRaisesRegex(
                ValueError, "lone Unicode surrogate"
            ):
                self.contract().parse_and_validate(candidate)

        valid_pair = (
            '{"message":"Look \\ud83d\\ude00","actions":[],"focus":[]}'
        )
        self.assertEqual(
            "Look \U0001F600",
            self.contract().parse_and_validate(valid_pair)["message"],
        )

    def test_rejects_wrong_outer_and_focus_shapes(self):
        invalid_candidates = (
            '[]',
            '{"message":"Look.","actions":[]}',
            '{"message":"Look.","actions":[],"focus":[],"analysis":"private"}',
            '{"message":7,"actions":[],"focus":[]}',
            '{"message":"Look.","actions":"hint","focus":[]}',
            '{"message":"Look.","actions":[7],"focus":[]}',
            '{"message":"Look.","actions":[],"focus":"g1"}',
            '{"message":"Look.","actions":[],"focus":["g1"]}',
            (
                '{"message":"Look.","actions":[],"focus":['
                '{"type":"square","square":"g1","label":"knight"}]}'
            ),
            (
                '{"message":"Look.","actions":[],"focus":['
                '{"type":"move","from":"g1","to":"f3","san":"Nf3"}]}'
            ),
            (
                '{"message":"Look.","actions":[],"focus":['
                '{"type":"piece","square":"g1"}]}'
            ),
            (
                '{"message":"Look.","actions":[],"focus":['
                '{"type":"move","square":"g1"}]}'
            ),
        )

        for candidate in invalid_candidates:
            with self.subTest(candidate=candidate), self.assertRaises(ValueError):
                self.contract().parse_and_validate(candidate)

    def test_enforces_swift_message_limits_and_notation_rules(self):
        invalid_messages = (
            "  \n ",
            " ".join(f"word{index}" for index in range(1, 20)),
            "Try Nc3 next.",
            "Try nc3 next.",
            "What happens after Qxf2+?",
            "Could you play e2e4?",
            "Could you play e7e8Q?",
            "Try O-O now.",
            "Can the queen x that pawn?",
            "That move gives #.",
            "Try ♘c3 next.",
        )

        for message in invalid_messages:
            candidate = json.dumps(
                {"message": message, "actions": [], "focus": []},
                separators=(",", ":"),
            )
            with self.subTest(message=message), self.assertRaises(ValueError):
                self.contract().parse_and_validate(candidate)

        eighteen_words = " ".join(f"word{index}" for index in range(1, 19))
        self.assertEqual(
            eighteen_words,
            self.contract().parse_and_validate(
                json.dumps(
                    {"message": eighteen_words, "actions": [], "focus": []},
                    separators=(",", ":"),
                )
            )["message"],
        )

    def test_enforces_action_allowlist_uniqueness_and_count(self):
        turn = {
            "message": "Look at the knight.",
            "actions": ["hint", "unavailable", "hint", "playMove"],
            "focus": [],
        }

        issues = self.contract().validation_issues(turn)

        self.assertIn("actions.unavailable:unavailable", issues)
        self.assertIn("actions.duplicate:hint", issues)
        self.assertIn("actions.limitExceeded", issues)
        with self.assertRaises(ValueError):
            self.contract().parse_and_validate(
                json.dumps(turn, separators=(",", ":"))
            )

    def test_enforces_focus_allowlists_board_bounds_uniqueness_and_count(self):
        turn = {
            "message": "Look at the knight.",
            "actions": [],
            "focus": [
                {"type": "square", "square": "a0"},
                {"type": "square", "square": "a0"},
                {"type": "move", "from": "g1", "to": "f3"},
                {"type": "move", "from": "g1", "to": "e2"},
                {"type": "move", "from": "g1", "to": "f3"},
            ],
        }

        issues = self.contract().validation_issues(turn)

        self.assertIn("focus.offBoardSquare:a0", issues)
        self.assertIn("focus.unavailableMove:g1-e2", issues)
        self.assertEqual(1, issues.count("focus.offBoardSquare:a0"))
        self.assertIn("focus.duplicate:square-a0", issues)
        self.assertIn("focus.duplicate:move-g1-f3", issues)
        self.assertIn("focus.limitExceeded", issues)
        with self.assertRaises(ValueError):
            self.contract().parse_and_validate(
                json.dumps(turn, separators=(",", ":"))
            )


if __name__ == "__main__":
    unittest.main()

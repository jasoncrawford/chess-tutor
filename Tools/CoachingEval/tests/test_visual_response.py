import copy
import json
import unittest
from pathlib import Path

from Tools.CoachingEval.visual_response import VisualResponseContract
from Tools.CoachingEval.chess_native_response import ChessNativeResponseValidationError


FIXTURE = Path(__file__).resolve().parents[1] / "fixtures/visual-coaching-validation-v1.json"


class VisualResponseTests(unittest.TestCase):
    def setUp(self):
        self.fixture = json.loads(FIXTURE.read_text())

    def test_shared_visual_contract_cases(self):
        for case in self.fixture["cases"]:
            with self.subTest(case=case["id"]):
                contract = VisualResponseContract.from_request(self.fixture["requests"][case["context"]])
                payload = json.dumps(case["turn"])
                if case["valid"]:
                    self.assertEqual(case["turn"], contract.parse_and_validate(payload))
                else:
                    with self.assertRaises(ChessNativeResponseValidationError):
                        contract.parse_and_validate(payload)

    def test_plain_text_is_joined_without_losing_spaces_or_punctuation(self):
        case = next(c for c in self.fixture["cases"] if c["id"] == "linked-threat")
        self.assertEqual("This rook attacks your knight. Where could it go?",
                         VisualResponseContract.plain_text(case["turn"]))

    def test_duplicate_keys_and_invalid_unicode_are_rejected(self):
        contract = VisualResponseContract.from_request(self.fixture["requests"]["normal"])
        for raw in ('{"message":[],"message":[]}',
                    '{"message":[{"type":"text","text":"a","text":"b"}],"actions":[],"visuals":[],"expects":"stageMove"}',
                    '{"message":[{"type":"text","text":"\\ud800"}],"actions":[],"visuals":[],"expects":"stageMove"}'):
            with self.subTest(raw=raw), self.assertRaises(ChessNativeResponseValidationError):
                contract.parse_and_validate(raw)

    def test_missing_displayed_facts_fail_closed_for_staged_piece_links(self):
        request = copy.deepcopy(self.fixture["requests"]["staged"])
        del request["tentativePosition"]
        contract = VisualResponseContract.from_request(request)
        turn = next(c["turn"] for c in self.fixture["cases"] if c["id"] == "staged-old-origin")
        with self.assertRaises(ChessNativeResponseValidationError):
            contract.parse_and_validate(json.dumps(turn))

    def test_schema_and_validation_accept_the_same_well_shaped_cases(self):
        # Strict schema must constrain shape without enumerating every chess fact.
        contract = VisualResponseContract.from_request(self.fixture["requests"]["normal"])
        schema = contract.json_schema()
        self.assertFalse(schema["additionalProperties"])
        self.assertEqual({"message", "actions", "visuals", "expects"}, set(schema["required"]))
        variants = schema["properties"]["message"]["items"]["anyOf"]
        self.assertEqual({"text", "piece", "square"}, {v["properties"]["type"]["enum"][0] for v in variants})
        self.assertTrue(all(not v["additionalProperties"] for v in variants))

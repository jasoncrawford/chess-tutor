import json
import re
import sys
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

import validate_turn


def valid_request():
    return {
        "schemaVersion": "model-coaching-request.v1",
        "promptVersion": "tutor-v1",
        "requestID": "request-1",
        "positionRevision": 7,
        "currentPosition": {"fen": "8/8/8/8/3K4/8/8/7k w - - 0 1", "sideToMove": "white", "status": "active"},
        "fullGameHistory": [],
        "currentInteraction": {
            "latestEvent": {"kind": "helpOpened", "referencedIDs": []},
            "availableOperationReferences": ["selectBoardPiece", "closeHelp"],
        },
        "currentTurnCoachingHistory": [],
        "chessEvidence": {
            "scope": {
                "legalMoves": "exhaustive",
                "relationships": "exhaustive",
                "immediateReplies": "bounded",
                "immediateRepliesDescription": "one legal opponent ply after each legal or staged learner move",
            },
            "pieces": [
                {"id": "piece:white:king:d4", "color": "white", "kind": "king", "square": "d4"}
            ],
            "legalMoves": [],
            "relationships": [],
            "immediateReplies": [],
            "tacticalFacts": [
                {"id": "fact:position", "kind": "stalemate", "subjectReferences": [], "integerValue": None}
            ],
        },
        "permittedReferences": {
            "actions": [{"id": "action:closeHelp", "kind": "closeHelp", "title": "Close help"}],
            "boardTasks": [{"id": "task:selectBoardPiece", "kind": "identifyPiece"}],
            "boardFocus": ["piece:white:king:d4"],
            "relationships": [],
            "evidence": ["fact:position"],
        },
    }


def valid_turn():
    return {
        "schemaVersion": "model-coaching-turn.v1",
        "requestID": "request-1",
        "teachingIntent": "chooseMove",
        "primaryMessage": "Choose a square for your king.",
        "instruction": "Tap your king, then move it.",
        "responseToLatestAction": None,
        "actionReferences": ["action:closeHelp"],
        "boardTaskReference": "task:selectBoardPiece",
        "boardFocusReferences": ["piece:white:king:d4"],
        "relationshipReferences": [],
        "supportingEvidenceReferences": ["fact:position"],
    }


class ValidateTurnTests(unittest.TestCase):
    def test_shared_python_swift_validation_fixture_contract(self):
        fixture = json.loads(
            (TOOLS_DIR / "fixtures" / "model-coaching-turn-validation-v1.json").read_text()
        )
        request = fixture["request"]

        outcomes = {
            case["id"]: not validate_turn.validate_turn(case["turn"], request)
            for case in fixture["cases"]
        }

        self.assertEqual(
            {case["id"]: case["expectedValid"] for case in fixture["cases"]},
            outcomes,
        )
        self.assertFalse(outcomes["additional-property"])

    def test_schema_has_strict_shape_enums_and_swift_optional_fields(self):
        schema = json.loads((TOOLS_DIR / "coaching-turn.schema.json").read_text())
        self.assertFalse(schema["additionalProperties"])
        self.assertEqual(
            [
                "actionReferences",
                "boardFocusReferences",
                "primaryMessage",
                "relationshipReferences",
                "requestID",
                "schemaVersion",
                "supportingEvidenceReferences",
                "teachingIntent",
            ],
            sorted(schema["required"]),
        )
        self.assertEqual(3, schema["properties"]["actionReferences"]["maxItems"])
        self.assertEqual(validate_turn.TEACHING_INTENTS, schema["properties"]["teachingIntent"]["enum"])
        for optional in ("instruction", "responseToLatestAction", "boardTaskReference"):
            self.assertEqual({"string", "null"}, set(schema["properties"][optional]["type"]))

    def test_schema_word_patterns_enforce_the_swift_word_limits_without_regex_shorthands(self):
        schema = json.loads((TOOLS_DIR / "coaching-turn.schema.json").read_text())
        limits = {
            "primaryMessage": 18,
            "instruction": 14,
            "responseToLatestAction": 16,
        }
        for field, limit in limits.items():
            pattern = schema["properties"][field]["pattern"]
            self.assertIsNotNone(re.fullmatch(pattern, "word " * (limit - 1) + "word"))
            self.assertIsNone(re.fullmatch(pattern, "word " * limit + "word"))
            self.assertIsNotNone(re.fullmatch(pattern, "\tword\nword\r"))

    def test_accepts_same_valid_turn_with_optional_fields_absent_or_null(self):
        request = valid_request()
        with_null = valid_turn()
        without_optional = valid_turn()
        del without_optional["instruction"]
        del without_optional["responseToLatestAction"]
        del without_optional["boardTaskReference"]
        self.assertEqual([], validate_turn.validate_turn(with_null, request))
        self.assertEqual([], validate_turn.validate_turn(without_optional, request))

    def test_rejects_unknown_shape_enum_identity_and_reference_membership(self):
        request = valid_request()
        turn = valid_turn()
        turn["unexpected"] = True
        turn["schemaVersion"] = "future"
        turn["requestID"] = "wrong"
        turn["teachingIntent"] = "lecture"
        turn["actionReferences"] = ["action:unknown"]
        turn["boardTaskReference"] = "task:unknown"
        turn["boardFocusReferences"] = ["piece:unknown"]
        turn["relationshipReferences"] = ["relationship:unknown"]
        turn["supportingEvidenceReferences"] = ["evidence:unknown"]

        self.assertEqual(
            [
                "shape.additionalProperty:unexpected",
                "shape.teachingIntent",
                "unsupportedTurnSchemaVersion",
                "requestIDMismatch",
                "unknownActionReference:action:unknown",
                "unknownBoardTaskReference:task:unknown",
                "unknownBoardFocusReference:piece:unknown",
                "unknownRelationshipReference:relationship:unknown",
                "unknownSupportingEvidenceReference:evidence:unknown",
            ],
            validate_turn.validate_turn(turn, request),
        )

    def test_matches_swift_duplicate_count_copy_and_required_evidence_limits(self):
        request = valid_request()
        request["permittedReferences"]["actions"].append(
            {"id": "action:wordy", "kind": "hint", "title": "one two three four five six"}
        )
        turn = valid_turn()
        turn["primaryMessage"] = " ".join(["word"] * 19)
        turn["instruction"] = " ".join(["word"] * 15)
        turn["responseToLatestAction"] = " ".join(["word"] * 17)
        turn["actionReferences"] = ["action:closeHelp"] * 4
        turn["boardFocusReferences"] = ["piece:white:king:d4"] * 2
        turn["supportingEvidenceReferences"] = []

        issues = validate_turn.validate_turn(turn, request)
        self.assertIn("duplicateActionReference:action:closeHelp", issues)
        self.assertIn("actionReferenceLimitExceeded", issues)
        self.assertIn("duplicateBoardFocusReference:piece:white:king:d4", issues)
        self.assertIn("primaryMessageWordLimitExceeded", issues)
        self.assertIn("instructionWordLimitExceeded", issues)
        self.assertIn("responseWordLimitExceeded", issues)
        self.assertIn("actionTitleWordLimitExceeded:action:wordy", issues)
        self.assertIn("missingSupportingEvidenceReference", issues)

    def test_schema_rejects_missing_nonoptional_and_wrong_json_types(self):
        request = valid_request()
        missing = valid_turn()
        del missing["primaryMessage"]
        wrong_type = valid_turn()
        wrong_type["boardFocusReferences"] = "piece:white:king:d4"
        self.assertEqual(
            ["shape.missing:primaryMessage"],
            validate_turn.validate_turn(missing, request),
        )
        self.assertEqual(
            ["shape.type:boardFocusReferences"],
            validate_turn.validate_turn(wrong_type, request),
        )


if __name__ == "__main__":
    unittest.main()

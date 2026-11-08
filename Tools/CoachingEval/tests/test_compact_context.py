import copy
import sys
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

import compact_context


def compact_case():
    request = {
        "requestID": "corpus:t11UnsafeBishopFound",
        "positionRevision": 5,
        "permittedReferences": {
            "actions": [
                {"id": "action:looksSafe"},
                {"id": "action:closeHelp"},
            ],
            "boardTasks": [{"id": "task:stageMove"}],
            "boardFocus": ["piece:white:bishop:a6"],
            "relationships": [
                "relationship:attack:piece:black:pawn:b7->piece:white:bishop:a6"
            ],
            "evidence": [
                "move:f1-a6",
                "reply:move:f1-a6->move:b7-b6",
                "fact:danger-loss:piece:white:bishop:a6",
            ],
        },
        "chessEvidence": {
            "pieces": [{"id": "piece:white:bishop:a6"}],
            "legalMoves": [{"id": "move:f1-a6"}],
            "relationships": [
                {
                    "id": "relationship:attack:piece:black:pawn:b7->piece:white:bishop:a6"
                }
            ],
            "immediateReplies": [
                {"id": "reply:move:f1-a6->move:b7-b6"}
            ],
            "tacticalFacts": [
                {"id": "fact:danger-loss:piece:white:bishop:a6"}
            ],
        },
    }
    bindings = [
        ("action-looks-safe", "action:looksSafe", "action"),
        ("action-close-help", "action:closeHelp", "action"),
        ("task-stage-move", "task:stageMove", "boardTask"),
        ("piece-white-bishop-a6", "piece:white:bishop:a6", "piece"),
        ("move-f1-a6", "move:f1-a6", "move"),
        (
            "relationship-attacks",
            "relationship:attack:piece:black:pawn:b7->piece:white:bishop:a6",
            "relationship",
        ),
        ("reply-b7-b6", "reply:move:f1-a6->move:b7-b6", "reply"),
        (
            "fact-danger-loss",
            "fact:danger-loss:piece:white:bishop:a6",
            "tacticalFact",
        ),
    ]
    markdown = "# Chess coaching context\n\n" + "\n".join(
        f"- {alias} — available" for alias, _stable, _category in bindings
    )
    return {
        "id": "t11UnsafeBishopFound",
        "request": request,
        "compactContext": {
            "schemaVersion": "model-coaching-context.v1",
            "promptVersion": "tutor-v3",
            "requestID": request["requestID"],
            "positionRevision": request["positionRevision"],
            "markdown": markdown,
            "referenceBindings": [
                {
                    "alias": alias,
                    "stableID": stable,
                    "category": category,
                    "label": "available",
                }
                for alias, stable, category in bindings
            ],
            "omissions": [],
        },
    }


def alias_turn():
    return {
        "schemaVersion": "model-coaching-turn.v1",
        "requestID": "corpus:t11UnsafeBishopFound",
        "teachingIntent": "reviseMove",
        "primaryMessage": "That bishop can be chased away.",
        "actionReferences": ["action-looks-safe"],
        "boardFocusReferences": ["piece-white-bishop-a6"],
        "relationshipReferences": ["relationship-attacks"],
        "supportingEvidenceReferences": ["reply-b7-b6", "move-f1-a6"],
        "instruction": "Try a different move.",
        "responseToLatestAction": None,
        "boardTaskReference": "task-stage-move",
    }


class CompactContextTests(unittest.TestCase):
    def test_validates_complete_compilation_and_restores_only_reference_fields(self):
        case = compact_case()

        self.assertEqual([], compact_context.validate_compilation(case))
        stable, issues = compact_context.restore_stable_turn(
            alias_turn(), case["compactContext"]
        )

        self.assertEqual([], issues)
        self.assertEqual("action:looksSafe", stable["actionReferences"][0])
        self.assertEqual("task:stageMove", stable["boardTaskReference"])
        self.assertEqual("piece:white:bishop:a6", stable["boardFocusReferences"][0])
        self.assertEqual(
            "relationship:attack:piece:black:pawn:b7->piece:white:bishop:a6",
            stable["relationshipReferences"][0],
        )
        self.assertEqual(
            ["reply:move:f1-a6->move:b7-b6", "move:f1-a6"],
            stable["supportingEvidenceReferences"],
        )
        for field in (
            "schemaVersion",
            "requestID",
            "teachingIntent",
            "primaryMessage",
            "instruction",
            "responseToLatestAction",
        ):
            self.assertEqual(alias_turn()[field], stable[field])

    def test_rejects_duplicate_unknown_mismatched_and_incompletely_accounted_references(self):
        case = compact_case()
        broken = copy.deepcopy(case)
        broken["compactContext"]["referenceBindings"][1]["alias"] = "action-looks-safe"
        broken["compactContext"]["referenceBindings"][2]["category"] = "piece"
        broken["compactContext"]["referenceBindings"].pop()
        broken["compactContext"]["markdown"] += "\n- fact-unknown — invented"
        broken["compactContext"]["requestID"] = "wrong"
        broken["compactContext"]["positionRevision"] = 99

        issues = compact_context.validate_compilation(broken)

        self.assertIn("compilation.requestIDMismatch", issues)
        self.assertIn("compilation.positionRevisionMismatch", issues)
        self.assertIn("bindings.duplicateAlias:action-looks-safe", issues)
        self.assertIn("bindings.categoryMismatch:task:stageMove", issues)
        self.assertIn(
            "accounting.missing:fact:danger-loss:piece:white:bishop:a6",
            issues,
        )
        self.assertIn("markdown.unknownAlias:fact-unknown", issues)

    def test_restoration_fails_closed_for_unknown_and_wrong_category_aliases(self):
        turn = alias_turn()
        turn["actionReferences"] = ["piece-white-bishop-a6", "action-unknown"]
        turn["boardTaskReference"] = "action-close-help"

        stable, issues = compact_context.restore_stable_turn(
            turn, compact_case()["compactContext"]
        )

        self.assertIn("alias.categoryMismatch:actionReferences:piece-white-bishop-a6", issues)
        self.assertIn("alias.unknown:actionReferences:action-unknown", issues)
        self.assertIn("alias.categoryMismatch:boardTaskReference:action-close-help", issues)
        self.assertEqual(turn["actionReferences"], stable["actionReferences"])
        self.assertEqual(turn["boardTaskReference"], stable["boardTaskReference"])


if __name__ == "__main__":
    unittest.main()

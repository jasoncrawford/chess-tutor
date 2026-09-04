import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from Tools.CoachingEval.benchmark.grader import RUBRIC_DIMENSIONS, RUBRIC_FLAGS
from Tools.CoachingEval.benchmark.reference_set import JudgeReferenceSet


ROOT = Path(__file__).resolve().parents[3]


class JudgeReferenceSetTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def test_requires_reviewed_provenance_for_real_qualification(self):
        path, sha = self.write_reference(review_status="pending")
        proposed = JudgeReferenceSet.load(path, sha, require_reviewed=False)
        self.assertEqual("pending", proposed.review_status)
        with self.assertRaisesRegex(ValueError, "human-reviewed"):
            JudgeReferenceSet.load(path, sha)

        path, sha = self.write_reference(
            review_status="humanReviewed",
            reviewed_by="Test Reviewer",
            reviewed_at="2026-09-03",
        )
        reviewed = JudgeReferenceSet.load(path, sha)
        self.assertEqual("Test Reviewer", reviewed.reviewed_by)
        self.assertEqual(20, len(reviewed.cases))

    def test_rejects_hash_drift_wrong_inventory_and_old_payload_shape(self):
        path, sha = self.write_reference(review_status="pending")
        with self.assertRaisesRegex(ValueError, "hash"):
            JudgeReferenceSet.load(path, "0" * 64, require_reviewed=False)

        value = self.reference_value(review_status="pending")
        value["cases"].pop()
        path, sha = self.write_value("short.json", value)
        with self.assertRaisesRegex(ValueError, "20"):
            JudgeReferenceSet.load(path, sha, require_reviewed=False)

        value = self.reference_value(review_status="pending")
        value["cases"][0]["graderBrief"] = {
            "context": "Old shorthand context.",
            "purpose": "Old shorthand purpose.",
        }
        path, sha = self.write_value("old-shape.json", value)
        with self.assertRaisesRegex(ValueError, "grader brief"):
            JudgeReferenceSet.load(path, sha, require_reviewed=False)

        value = self.reference_value(review_status="pending")
        value["cases"][0]["candidateTurn"]["message"] = "Try Nc3."
        path, sha = self.write_value("invalid-candidate.json", value)
        with self.assertRaisesRegex(ValueError, "app contract"):
            JudgeReferenceSet.load(path, sha, require_reviewed=False)

    def test_committed_review_sheet_is_deterministically_rendered(self):
        benchmark = ROOT / "Tools/CoachingEval/benchmark"
        path = benchmark / "judge-reference-v2.json"
        sha = hashlib.sha256(path.read_bytes()).hexdigest()
        reference = JudgeReferenceSet.load(path, sha, require_reviewed=False)
        rendered = reference.render_review()
        self.assertEqual(
            (benchmark / "judge-reference-v2-review.md").read_text(),
            rendered,
        )
        self.assertIn("Status: **pending human review**", rendered)
        self.assertIn("## ref-02", rendered)
        self.assertIn("Discovery and independence: 2", rendered)
        self.assertIn("**Acceptable alternatives:**", rendered)
        self.assertIn("allowableMoveFocus=", rendered)
        self.assertIn("answerRevealingGuidance: true", rendered)

    def write_reference(self, **provenance):
        return self.write_value("reference.json", self.reference_value(**provenance))

    def write_value(self, name, value):
        path = self.root / name
        data = (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()
        path.write_bytes(data)
        return path, hashlib.sha256(data).hexdigest()

    def reference_value(
        self,
        *,
        review_status,
        reviewed_by=None,
        reviewed_at=None,
    ):
        cases = []
        for index in range(1, 21):
            cases.append(
                {
                    "id": f"ref-{index:02}",
                    "graderBrief": {
                        "verifiedFacts": ["White to move.", "The position is ongoing."],
                        "coachingPurpose": "Coach one current step.",
                        "acceptableAlternatives": ["Any grounded question."],
                        "successCriteria": ["Uses the available interaction."],
                        "severeFailureCriteria": ["Invents checkmate."],
                    },
                    "availableUI": {
                        "actions": ["hint"],
                        "expectedResponses": ["stageMove"],
                        "allowableMoveFocus": [],
                    },
                    "candidateTurn": {
                        "message": "What could you notice?",
                        "actions": ["hint"],
                        "focus": [],
                        "expects": "stageMove",
                    },
                    "referenceScores": {
                        dimension: 5 for dimension in RUBRIC_DIMENSIONS
                    },
                    "referenceFlags": {
                        flag: False for flag in RUBRIC_FLAGS
                    },
                    "rationale": ["The response is grounded and answerable."],
                }
            )
        return {
            "schemaVersion": "coaching-quality-judge-reference-set.v2",
            "id": "test-reference-v2",
            "provenance": {
                "authoredBy": "Test fixture",
                "authoredAt": "2026-09-03",
                "reviewStatus": review_status,
                "reviewedBy": reviewed_by,
                "reviewedAt": reviewed_at,
            },
            "cases": cases,
        }


if __name__ == "__main__":
    unittest.main()

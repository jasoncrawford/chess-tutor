import copy
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from CoachingServer.chess_native_compiler import (
    compile_context,
    compile_follow_up_context,
)
from Tools.CoachingEval.benchmark.grader import RUBRIC_DIMENSIONS, RUBRIC_FLAGS
from Tools.CoachingEval.benchmark.reference_set import JudgeReferenceSet


ROOT = Path(__file__).resolve().parents[3]
FIXTURE = json.loads(
    (ROOT / "Tools/CoachingEval/fixtures/chess-native-context-v1.json").read_text()
)
EXPECTED_RESPONSES = {
    "findEndangeredPiece",
    "findSafeCapture",
    "stageMove",
    "judgeMoveSafety",
    "chooseWhetherToPlay",
}
EXPECTED_SOURCE_IDS = (
    "q01-starting-position",
    "d01-loose-bishop",
    "s01-danger-selection-response-02",
    "c01-safe-queen-capture",
    "s03-capture-none-02",
    "s04-safe-move-confirm-02",
    "s04-safe-move-confirm-03",
    "c02-poisoned-bishop-capture",
    "s05-unsafe-move-retry-03",
    "s06-replace-move-03",
    "h05-stale-selection-replaced",
    "s07-inspect-reply-03",
    "s08-hint-then-act-02",
    "m07-castling",
    "c06-en-passant",
    "m06-promotion",
    "c05-mating-capture",
    "h01-quiet-black-opening",
    "q02-quiet-midgame",
    "s10-close-and-reopen-03",
)


def canonical_sha(value):
    return hashlib.sha256(
        json.dumps(
            value,
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=False,
        ).encode("utf-8")
    ).hexdigest()


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
        self.assertEqual(20, len(reviewed.absolute_cases))
        self.assertEqual(reviewed.absolute_cases, reviewed.cases)

    def test_loads_exact_replayable_source_absolute_and_pairwise_inventories(self):
        reference = self.load_committed()

        self.assertEqual("chess-native-v13", reference.response_contract)
        self.assertEqual(EXPECTED_SOURCE_IDS, tuple(row["id"] for row in reference.sources))
        self.assertEqual(
            tuple(f"ref-{index:02}" for index in range(1, 21)),
            tuple(row["id"] for row in reference.absolute_cases),
        )
        self.assertEqual(
            tuple(f"pair-{index:02}" for index in range(1, 11)),
            tuple(row["id"] for row in reference.pairwise_cases),
        )
        self.assertEqual(20, len(reference.sources))
        self.assertEqual(20, len(reference.absolute_cases))
        self.assertEqual(10, len(reference.pairwise_cases))

    def test_sources_recompile_through_production_v13_and_derive_ui(self):
        reference = self.load_committed()
        stored = json.loads(
            (ROOT / "Tools/CoachingEval/benchmark/judge-reference-v2.json").read_text()
        )

        for source, case, stored_case in zip(
            reference.sources, reference.absolute_cases, stored["absoluteCases"]
        ):
            compiler = (
                compile_context
                if source["requestKind"] == "initial"
                else compile_follow_up_context
            )
            compilation = compiler(self.thaw(source["request"]), "tutor-v13")
            self.assertEqual(
                {
                    "actions": list(compilation.actions),
                    "expectedResponses": list(compilation.expected_responses),
                    "allowableMoveFocus": [list(move) for move in compilation.allowable_moves],
                },
                self.thaw(case["availableUI"]),
                source["id"],
            )
            self.assertNotIn("availableUI", source)
            self.assertNotIn("availableUI", stored_case)
            self.assertNotIn("graderBrief", stored_case)
            self.assertEqual(canonical_sha(self.thaw(source["request"])), source["requestSHA256"])

    def test_every_candidate_is_v13_valid_and_absolute_coverage_is_complete(self):
        reference = self.load_committed()
        responses = set()
        has_square_focus = False
        has_move_focus = False
        has_hint = False

        for case in reference.absolute_cases:
            turn = case["candidateTurn"]
            responses.add(turn["expects"])
            has_square_focus |= any(item["type"] == "square" for item in turn["focus"])
            has_move_focus |= any(item["type"] == "move" for item in turn["focus"])
            has_hint |= "hint" in turn["actions"]
            self.assertNotIn("request", case)
            self.assertEqual(["hint"], list(case["availableUI"]["actions"]))
            self.assertIn("expects", turn)

        for case in reference.pairwise_cases:
            self.assertNotIn("request", case)
            for key in ("responseOne", "responseTwo"):
                self.assertIn("expects", case[key])
            self.assertIn(case["referencePreference"], {"responseOne", "responseTwo", "tie"})

        self.assertEqual(EXPECTED_RESPONSES, responses)
        self.assertTrue(has_square_focus)
        self.assertTrue(has_move_focus)
        self.assertTrue(has_hint)
        self.assertEqual(
            {"responseOne", "responseTwo", "tie"},
            {case["referencePreference"] for case in reference.pairwise_cases},
        )

    def test_rejects_request_hash_source_resolution_and_candidate_contract_drift(self):
        value = self.reference_value(review_status="pending")
        value["sources"][0]["request"]["positionRevision"] = 1
        path, sha = self.write_value("request-drift.json", value)
        with self.assertRaisesRegex(ValueError, "request hash"):
            JudgeReferenceSet.load(path, sha, require_reviewed=False)

        value = self.reference_value(review_status="pending")
        value["absoluteCases"][0]["sourceID"] = "missing-source"
        path, sha = self.write_value("missing-source.json", value)
        with self.assertRaisesRegex(ValueError, "source"):
            JudgeReferenceSet.load(path, sha, require_reviewed=False)

        value = self.reference_value(review_status="pending")
        value["absoluteCases"][0]["candidateTurn"].pop("expects")
        path, sha = self.write_value("missing-expects.json", value)
        with self.assertRaisesRegex(ValueError, "candidate turn"):
            JudgeReferenceSet.load(path, sha, require_reviewed=False)

        value = self.reference_value(review_status="pending")
        value["absoluteCases"][0]["candidateTurn"]["focus"] = [
            {"type": "move", "from": "a1", "to": "a8"}
        ]
        path, sha = self.write_value("invalid-focus.json", value)
        with self.assertRaisesRegex(ValueError, "app contract"):
            JudgeReferenceSet.load(path, sha, require_reviewed=False)

    def test_rejects_unresolved_event_reference_and_help_closed_source(self):
        value = self.reference_value(review_status="pending")
        request = value["sources"][0]["request"]
        request["interaction"]["latestEvent"]["referencedIDs"] = ["piece:missing"]
        request["interaction"]["episodeEvents"][-1]["referencedIDs"] = ["piece:missing"]
        value["sources"][0]["requestSHA256"] = canonical_sha(request)
        path, sha = self.write_value("unresolved-reference.json", value)
        with self.assertRaisesRegex(ValueError, "event reference"):
            JudgeReferenceSet.load(path, sha, require_reviewed=False)

        value = self.reference_value(review_status="pending")
        request = value["sources"][0]["request"]
        closed = {"sequence": 1, "kind": "helpClosed", "referencedIDs": []}
        request["interaction"]["latestEvent"] = copy.deepcopy(closed)
        request["interaction"]["episodeEvents"] = [copy.deepcopy(closed)]
        value["sources"][0]["requestSHA256"] = canonical_sha(request)
        path, sha = self.write_value("help-closed.json", value)
        with self.assertRaisesRegex(ValueError, "help-closed"):
            JudgeReferenceSet.load(path, sha, require_reviewed=False)

    def test_rejects_hash_wrong_inventories_and_handwritten_ui(self):
        path, sha = self.write_reference(review_status="pending")
        with self.assertRaisesRegex(ValueError, "hash"):
            JudgeReferenceSet.load(path, "0" * 64, require_reviewed=False)

        value = self.reference_value(review_status="pending")
        value["provenance"]["sourceGitSHA"] = "not-a-git-sha"
        path, sha = self.write_value("invalid-source-git-sha.json", value)
        with self.assertRaisesRegex(ValueError, "Git SHA"):
            JudgeReferenceSet.load(path, sha, require_reviewed=False)

        for key, expected in (("absoluteCases", "20"), ("pairwiseCases", "10")):
            value = self.reference_value(review_status="pending")
            value[key].pop()
            path, sha = self.write_value(f"short-{key}.json", value)
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, expected):
                JudgeReferenceSet.load(path, sha, require_reviewed=False)

        value = self.reference_value(review_status="pending")
        value["absoluteCases"][0]["availableUI"] = {
            "actions": ["playMove"],
            "expectedResponses": ["none"],
            "allowableMoveFocus": [],
        }
        path, sha = self.write_value("handwritten-ui.json", value)
        with self.assertRaisesRegex(ValueError, "case fields"):
            JudgeReferenceSet.load(path, sha, require_reviewed=False)

    def test_committed_review_sheet_is_deterministically_rendered_and_rich(self):
        benchmark = ROOT / "Tools/CoachingEval/benchmark"
        reference = self.load_committed()
        rendered = reference.render_review()

        self.assertEqual((benchmark / "judge-reference-v2-review.md").read_text(), rendered)
        self.assertIn("Status: **pending human review**", rendered)
        self.assertIn("Response contract: `chess-native-v13`", rendered)
        self.assertIn("Source corpus cases SHA-256:", rendered)
        self.assertIn("## Absolute ref-02", rendered)
        self.assertIn("## Pairwise pair-10", rendered)
        self.assertIn("**Source:**", rendered)
        self.assertIn("**FEN:**", rendered)
        self.assertIn("**Move history:**", rendered)
        self.assertIn("**Latest interaction:**", rendered)
        self.assertIn("**Staged move:**", rendered)
        self.assertIn("**Request SHA-256:**", rendered)
        self.assertIn("allowableMoveFocus=", rendered)
        self.assertIn("**Reference preference:** responseTwo", rendered)
        self.assertIn("answerRevealingGuidance: true", rendered)

    def load_committed(self):
        path = ROOT / "Tools/CoachingEval/benchmark/judge-reference-v2.json"
        return JudgeReferenceSet.load(
            path,
            hashlib.sha256(path.read_bytes()).hexdigest(),
            require_reviewed=False,
        )

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
        sources = []
        absolute_cases = []
        for index in range(1, 21):
            source_id = f"case-{index:02}"
            request = copy.deepcopy(FIXTURE["request"])
            request["requestID"] = f"benchmark:{source_id}"
            sources.append(
                {
                    "schemaVersion": "coaching-quality-benchmark-case.v1",
                    "id": source_id,
                    "groupID": source_id,
                    "stepIndex": 1,
                    "split": "development",
                    "category": "interaction",
                    "requestKind": "initial",
                    "requestSHA256": canonical_sha(request),
                    "request": request,
                    "graderBrief": {
                        "verifiedFacts": ["White to move.", "The position is ongoing."],
                        "coachingPurpose": "Coach one current step.",
                        "acceptableAlternatives": ["Any grounded question."],
                        "successCriteria": ["Uses the available interaction."],
                        "severeFailureCriteria": ["Invents checkmate."],
                    },
                }
            )
            absolute_cases.append(
                {
                    "id": f"ref-{index:02}",
                    "sourceID": source_id,
                    "candidateTurn": {
                        "message": "What could you notice?",
                        "actions": ["hint"],
                        "focus": [],
                        "expects": "stageMove",
                    },
                    "referenceScores": {dimension: 5 for dimension in RUBRIC_DIMENSIONS},
                    "referenceFlags": {flag: False for flag in RUBRIC_FLAGS},
                    "rationale": ["The response is grounded and answerable."],
                }
            )
        pairwise_cases = []
        for index in range(1, 11):
            pairwise_cases.append(
                {
                    "id": f"pair-{index:02}",
                    "sourceID": f"case-{index:02}",
                    "responseOne": {
                        "message": "Which move could help?",
                        "actions": ["hint"],
                        "focus": [],
                        "expects": "stageMove",
                    },
                    "responseTwo": {
                        "message": "What could you try?",
                        "actions": [],
                        "focus": [],
                        "expects": "stageMove",
                    },
                    "referencePreference": "tie",
                    "rationale": ["Both responses are equally useful."],
                }
            )
        return {
            "schemaVersion": "coaching-quality-judge-reference-set.v2",
            "id": "test-reference-v2",
            "responseContract": "chess-native-v13",
            "provenance": {
                "authoredBy": "Test fixture",
                "authoredAt": "2026-09-03",
                "reviewStatus": review_status,
                "reviewedBy": reviewed_by,
                "reviewedAt": reviewed_at,
                "sourceGitSHA": "a" * 40,
                "sourceCasesSHA256": "1" * 64,
                "sourceManifestSHA256": "2" * 64,
            },
            "sources": sources,
            "absoluteCases": absolute_cases,
            "pairwiseCases": pairwise_cases,
        }

    @classmethod
    def thaw(cls, value):
        if hasattr(value, "items"):
            return {key: cls.thaw(child) for key, child in value.items()}
        if isinstance(value, (tuple, list)):
            return [cls.thaw(child) for child in value]
        return value


if __name__ == "__main__":
    unittest.main()

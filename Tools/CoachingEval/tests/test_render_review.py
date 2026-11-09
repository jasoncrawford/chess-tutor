import csv
import json
import sys
import tempfile
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

import render_review
from Tools.CoachingEval.tests.test_validate_turn import valid_request, valid_turn


def record(case_id, model_id):
    request = valid_request()
    request["requestID"] = "request-" + case_id
    turn = valid_turn()
    turn["requestID"] = request["requestID"]
    return {
        "caseID": case_id,
        "caseSplit": "visible",
        "modelID": model_id,
        "mode": "off",
        "seed": 1103,
        "parsedTurn": turn,
        "evaluationCase": {
            "id": case_id,
            "split": "visible",
            "request": request,
            "oracle": {
                "successCriteria": ["One useful current step.", "The instruction is answerable."],
                "severeFailureCriteria": ["The turn invents a board fact."],
            },
        },
    }


class RenderReviewTests(unittest.TestCase):
    def write_run(self, root, records):
        run = root / "run-one"
        run.mkdir(parents=True)
        with (run / "records.jsonl").open("w") as destination:
            for item in records:
                destination.write(json.dumps(item) + "\n")
        return run

    def test_refuses_recursive_model_root_with_multiple_record_sets(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            model_root = root / "runs"
            first = model_root / "run-one"
            second = model_root / "run-two"
            first.mkdir(parents=True)
            second.mkdir(parents=True)
            (first / "records.jsonl").write_text(json.dumps(record("case-a", "a")) + "\n")
            (second / "records.jsonl").write_text(json.dumps(record("case-b", "b")) + "\n")

            with self.assertRaisesRegex(ValueError, "exact run directory"):
                render_review.render_review([model_root], root / "review", review_seed=42)

            self.assertFalse((root / "review").exists())

    def test_writes_blinded_shuffled_packet_key_and_fixed_rubric(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            run = self.write_run(root / "runs", [record("case-a", "secret-a"), record("case-b", "secret-b")])
            output = root / "review"
            render_review.render_review([run], output, review_seed=42)

            packet = [json.loads(line) for line in (output / "review-packet.jsonl").read_text().splitlines()]
            key = json.loads((output / "review-key.json").read_text())
            with (output / "rubric.csv").open(newline="") as source:
                rubric = list(csv.DictReader(source))

            self.assertEqual(2, len(packet))
            self.assertEqual(42, key["reviewSeed"])
            self.assertEqual({entry["reviewID"] for entry in packet}, set(key["entries"]))
            self.assertEqual({"secret-a", "secret-b"}, {entry["modelID"] for entry in key["entries"].values()})
            serialized_packet = json.dumps(packet, sort_keys=True)
            self.assertNotIn("secret-a", serialized_packet)
            self.assertNotIn("secret-b", serialized_packet)
            for entry in packet:
                self.assertIn("position", entry)
                self.assertIn("fullGameHistory", entry)
                self.assertIn("latestAction", entry)
                self.assertIn("candidateTurn", entry)
                self.assertIn("successCriteria", entry)
                self.assertIn("severeFailureCriteria", entry)
            self.assertEqual(2, len(rubric))
            self.assertEqual(["reviewID"] + render_review.RUBRIC_COLUMNS, list(rubric[0]))
            self.assertTrue(all(not row["factualCorrectness"] for row in rubric))

    def test_same_review_seed_produces_byte_identical_artifacts(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            run = self.write_run(root / "runs", [record("case-a", "a"), record("case-b", "b")])
            first = root / "first"
            second = root / "second"
            render_review.render_review([run], first, review_seed=17)
            render_review.render_review([run], second, review_seed=17)
            for name in ("review-packet.jsonl", "review-key.json", "rubric.csv"):
                self.assertEqual((first / name).read_bytes(), (second / name).read_bytes())

    def test_review_uses_restored_stable_turn_not_request_local_alias_turn(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            item = record("case-a", "model-a")
            alias_turn = dict(item["parsedTurn"])
            alias_turn["supportingEvidenceReferences"] = ["fact-position"]
            stable_turn = dict(item["parsedTurn"])
            stable_turn["supportingEvidenceReferences"] = ["fact:position"]
            item["aliasTurn"] = alias_turn
            item["stableTurn"] = stable_turn
            item["parsedTurn"] = alias_turn
            run = self.write_run(root / "runs", [item])

            render_review.render_review([run], root / "review", review_seed=42)

            packet = json.loads((root / "review" / "review-packet.jsonl").read_text())
            self.assertEqual(stable_turn, packet["candidateTurn"])
            self.assertNotIn("fact-position", json.dumps(packet))


if __name__ == "__main__":
    unittest.main()

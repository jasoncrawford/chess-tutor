import csv
import json
import sys
import tempfile
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

import render_review
import summarize_eval
from Tools.CoachingEval.tests.test_render_review import record as review_record


def completed_row(review_id, base):
    return {
        "reviewID": review_id,
        "factualCorrectness": str(base),
        "oneCoherentStep": str(base),
        "responsiveToLatestAction": str(base),
        "answerability": str(base),
        "childClarity": str(base),
        "pedagogicalUsefulness": str(base),
        "unnecessaryInterrogation": "0",
        "mixedStages": "0",
        "severeError": "1" if base == 1 else "0",
        "notes": "reviewed",
    }


class SummarizeEvalTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name) / "run"
        child = self.root / "visible-one"
        self.run = child
        child.mkdir(parents=True)
        records = []
        for index, latency in enumerate((100.0, 200.0, 1000.0), 1):
            item = review_record(f"case-{index}", "model-a")
            item.update(
                {
                    "firstAttemptValidation": {"valid": index == 1, "errors": [] if index == 1 else ["invalid"]},
                    "repairAttempted": index in (2, 3),
                    "repairValidation": {"valid": True, "errors": []} if index == 2 else None,
                    "latencyMilliseconds": latency,
                    "promptTokens": index * 10,
                    "outputTokens": index * 2,
                    "rawFinalContent": json.dumps(item["parsedTurn"]),
                }
            )
            records.append(item)
        with (child / "records.jsonl").open("w") as destination:
            for item in records:
                destination.write(json.dumps(item) + "\n")
        render_review.render_review([self.run], self.root, review_seed=7)

    def tearDown(self):
        self.temporary.cleanup()

    def write_scores(self, rows):
        with (self.root / "rubric.csv").open("w", newline="") as destination:
            writer = csv.DictWriter(destination, fieldnames=["reviewID"] + render_review.RUBRIC_COLUMNS)
            writer.writeheader()
            writer.writerows(rows)

    def test_refuses_incomplete_or_out_of_range_human_scores(self):
        key = json.loads((self.root / "review-key.json").read_text())
        ids = sorted(key["entries"])
        rows = [completed_row(identifier, 4) for identifier in ids]
        rows[0]["childClarity"] = ""
        self.write_scores(rows)
        with self.assertRaisesRegex(ValueError, "incomplete.*childClarity"):
            summarize_eval.summarize(self.root)

        rows[0]["childClarity"] = "6"
        self.write_scores(rows)
        with self.assertRaisesRegex(ValueError, "childClarity.*1 through 5"):
            summarize_eval.summarize(self.root)

    def test_reports_each_dimension_validity_latency_tokens_severe_errors_and_examples(self):
        key = json.loads((self.root / "review-key.json").read_text())
        ids = sorted(key["entries"])
        self.write_scores(
            [completed_row(ids[0], 5), completed_row(ids[1], 3), completed_row(ids[2], 1)]
        )
        summary = summarize_eval.summarize(self.root)

        self.assertEqual(3, summary["recordCount"])
        self.assertEqual(1, summary["mechanical"]["firstAttemptValidCount"])
        self.assertEqual(2, summary["mechanical"]["repairAttemptCount"])
        self.assertEqual(1, summary["mechanical"]["repairedValidCount"])
        self.assertEqual(2, summary["mechanical"]["displayableValidCount"])
        self.assertEqual(200.0, summary["latencyMilliseconds"]["p50"])
        self.assertEqual(1000.0, summary["latencyMilliseconds"]["p90"])
        self.assertEqual(60, summary["tokens"]["inputTotal"])
        self.assertEqual(12, summary["tokens"]["outputTotal"])
        self.assertEqual(3.0, summary["rubric"]["dimensions"]["childClarity"]["mean"])
        self.assertEqual(1, summary["rubric"]["severeErrorCount"])
        self.assertEqual({"case-1", "case-2", "case-3"}, set(summary["examplesByCase"]))
        serialized = json.dumps(summary).lower()
        self.assertNotIn("composite", serialized)
        self.assertNotIn("winner", serialized)
        self.assertTrue((self.root / "aggregate.json").is_file())
        self.assertTrue((self.root / "summary.md").is_file())

    def test_combined_output_follows_review_key_pointers_to_every_source_run(self):
        second_root = Path(self.temporary.name) / "model-b"
        second_child = second_root / "visible-one"
        second_child.mkdir(parents=True)
        second = review_record("case-b", "model-b")
        second.update(
            {
                "firstAttemptValidation": {"valid": True, "errors": []},
                "repairAttempted": False,
                "repairValidation": None,
                "latencyMilliseconds": 75.0,
                "promptTokens": 8,
                "outputTokens": 2,
                "rawFinalContent": json.dumps(second["parsedTurn"]),
            }
        )
        (second_child / "records.jsonl").write_text(json.dumps(second) + "\n")

        combined = Path(self.temporary.name) / "combined-review"
        render_review.render_review([self.run, second_child], combined, review_seed=19)
        key = json.loads((combined / "review-key.json").read_text())
        with (combined / "rubric.csv").open("w", newline="") as destination:
            writer = csv.DictWriter(
                destination,
                fieldnames=["reviewID"] + render_review.RUBRIC_COLUMNS,
            )
            writer.writeheader()
            writer.writerows(completed_row(identifier, 4) for identifier in key["entries"])

        summary = summarize_eval.summarize(combined)

        self.assertEqual(4, summary["recordCount"])
        self.assertEqual(
            {"model-a|off|visible", "model-b|off|visible"},
            set(summary["byConfiguration"]),
        )


if __name__ == "__main__":
    unittest.main()

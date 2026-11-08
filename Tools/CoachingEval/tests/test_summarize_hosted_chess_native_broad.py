import csv
import importlib
import json
import sys
import tempfile
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

import run_hosted_chess_native_broad_comparison as broad_runner  # noqa: E402
from Tools.CoachingEval.tests.test_run_hosted_chess_native_broad_comparison import (  # noqa: E402
    CASE_IDS,
    RecordingHostedClient,
    write_broad_source,
)


def load_summarizer(test_case):
    try:
        return importlib.import_module("summarize_hosted_chess_native_broad")
    except ModuleNotFoundError:
        test_case.fail("summarize_hosted_chess_native_broad is not implemented")


class HostedChessNativeBroadSummaryTests(unittest.TestCase):
    def setUp(self):
        self.summarizer = load_summarizer(self)
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.fixture = write_broad_source(self.root)
        self.run = self.root / "run"
        broad_runner.run_broad_comparison(
            source_dir=self.fixture["source"],
            system_prompt_path=self.fixture["systemPath"],
            destination=self.run,
            client=RecordingHostedClient(),
            case_ids=CASE_IDS,
            expected_source_manifest_sha256=self.fixture[
                "sourceManifestSHA256"
            ],
            expected_examples_jsonl_sha256=self.fixture[
                "examplesJSONLSHA256"
            ],
            timeout=9,
            review_seed=b"summary-test-review-seed",
        )

    def tearDown(self):
        self.temporary.cleanup()

    def fill_rubric(self):
        key = json.loads((self.run / "review" / "review-key.json").read_text())
        identities = {
            entry["reviewID"]: entry["configurationID"]
            for entry in key["entries"]
        }
        rubric_path = self.run / "review" / "rubric.csv"
        with rubric_path.open(newline="") as source:
            rows = list(csv.DictReader(source))
        sol_ids = [
            row["reviewID"]
            for row in rows
            if identities[row["reviewID"]] == "sol-high"
        ]
        with rubric_path.open("w", encoding="utf-8", newline="") as destination:
            writer = csv.DictWriter(destination, fieldnames=self.summarizer.RUBRIC_FIELDS)
            writer.writeheader()
            for row in rows:
                is_sol = identities[row["reviewID"]] == "sol-high"
                severe = row["reviewID"] == sol_ids[0]
                writer.writerow(
                    {
                        "reviewID": row["reviewID"],
                        "factualCorrectness": "5" if is_sol else "3",
                        "currentStage": "5" if is_sol else "3",
                        "singlePurpose": "5" if is_sol else "3",
                        "discoveryCoaching": "5" if is_sol else "3",
                        "childLanguage": "5" if is_sol else "3",
                        "uiAlignment": "5" if is_sol else "3",
                        "severe": "true" if severe else "false",
                        "notes": "Invents a tactic." if severe else "Clear turn.",
                    }
                )
        return rubric_path

    def test_complete_rubric_joins_records_and_reports_each_dimension(self):
        rubric_path = self.fill_rubric()

        summary = self.summarizer.summarize(self.run, rubric_path=rubric_path)

        self.assertEqual(24, summary["recordCount"])
        self.assertEqual(24, summary["reviewCount"])
        by_id = {item["configurationID"]: item for item in summary["configurations"]}
        self.assertEqual(12, by_id["sol-high"]["total"])
        self.assertEqual(12, by_id["sol-high"]["strictValid"])
        self.assertEqual(1, by_id["sol-high"]["severe"])
        self.assertEqual(5.0, by_id["sol-high"]["dimensionMeans"]["childLanguage"])
        self.assertEqual(3.0, by_id["luna-high"]["dimensionMeans"]["childLanguage"])
        self.assertGreater(by_id["sol-high"]["estimatedCostUSD"], 0)
        self.assertGreater(by_id["sol-high"]["inputTokens"], 0)
        self.assertGreater(by_id["sol-high"]["outputTokens"], 0)
        self.assertLessEqual(len(by_id["sol-high"]["reviewExamples"]), 3)
        self.assertNotIn("score", summary)
        self.assertNotIn("winner", summary)

    def test_rejects_blank_reordered_out_of_range_and_invalid_severe_rows(self):
        rubric_path = self.run / "review" / "rubric.csv"
        with self.assertRaisesRegex(ValueError, "complete"):
            self.summarizer.summarize(self.run, rubric_path=rubric_path)

        self.fill_rubric()
        with rubric_path.open(newline="") as source:
            rows = list(csv.DictReader(source))
        mutations = (
            ("reordered", list(reversed(rows)), "order"),
            (
                "score",
                [dict(row, factualCorrectness="6") if index == 0 else row for index, row in enumerate(rows)],
                "1 through 5",
            ),
            (
                "severe",
                [dict(row, severe="yes") if index == 0 else row for index, row in enumerate(rows)],
                "true or false",
            ),
        )
        for name, values, expected in mutations:
            with self.subTest(name=name):
                path = self.root / f"{name}.csv"
                with path.open("w", encoding="utf-8", newline="") as destination:
                    writer = csv.DictWriter(
                        destination, fieldnames=self.summarizer.RUBRIC_FIELDS
                    )
                    writer.writeheader()
                    writer.writerows(values)
                with self.assertRaisesRegex(ValueError, expected):
                    self.summarizer.summarize(self.run, rubric_path=path)

    def test_rejects_record_hash_mismatch_and_key_path_escape(self):
        rubric_path = self.fill_rubric()
        key_path = self.run / "review" / "review-key.json"
        original = json.loads(key_path.read_text())
        for name, mutation, expected in (
            (
                "hash",
                lambda value: value["entries"][0].update(recordSHA256="0" * 64),
                "record hash",
            ),
            (
                "path",
                lambda value: value["entries"][0].update(recordPath="../private.json"),
                "inside run",
            ),
        ):
            with self.subTest(name=name):
                value = json.loads(json.dumps(original))
                mutation(value)
                key_path.write_text(json.dumps(value), encoding="utf-8")
                with self.assertRaisesRegex(ValueError, expected):
                    self.summarizer.summarize(self.run, rubric_path=rubric_path)
        key_path.write_text(json.dumps(original), encoding="utf-8")

    def test_write_summary_refuses_overwrite_and_persists_json_and_markdown(self):
        rubric_path = self.fill_rubric()
        destination = self.root / "summary"

        summary = self.summarizer.write_summary(
            self.run, rubric_path=rubric_path, destination=destination
        )

        self.assertEqual(
            summary,
            json.loads((destination / "comparison-summary.json").read_text()),
        )
        markdown = (destination / "comparison-summary.md").read_text()
        self.assertIn("sol-high", markdown)
        self.assertIn("luna-high", markdown)
        self.assertNotIn("winner", markdown.lower())
        with self.assertRaisesRegex(ValueError, "overwrite"):
            self.summarizer.write_summary(
                self.run, rubric_path=rubric_path, destination=destination
            )


if __name__ == "__main__":
    unittest.main()

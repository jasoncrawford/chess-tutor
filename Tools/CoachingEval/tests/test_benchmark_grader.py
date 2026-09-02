import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from Tools.CoachingEval.benchmark.configuration import load_judge
from Tools.CoachingEval.benchmark.corpus import (
    BenchmarkCorpus,
    BenchmarkGraderBrief,
    BenchmarkTurn,
)
from Tools.CoachingEval.benchmark.grader import (
    RUBRIC_DIMENSIONS,
    RUBRIC_FLAGS,
    calibrate_judge,
    grade_run,
)


ROOT = Path(__file__).resolve().parents[3]


class QueueJudge:
    def __init__(self, outputs):
        self.outputs = list(outputs)
        self.calls = []

    def complete(self, **arguments):
        self.calls.append(arguments)
        output = self.outputs.pop(0)
        return {
            "id": f"resp_{len(self.calls)}",
            "model": "gpt-5.6-sol",
            "status": "completed",
            "output_text": json.dumps(output, separators=(",", ":")),
            "usage": {
                "input_tokens": 50,
                "cached_input_tokens": 0,
                "output_tokens": 20,
                "reasoning_tokens": 5,
                "total_tokens": 70,
            },
        }


class RawQueueJudge(QueueJudge):
    def complete(self, **arguments):
        self.calls.append(arguments)
        output = self.outputs.pop(0)
        return {
            "id": f"resp_{len(self.calls)}",
            "model": "gpt-5.6-sol",
            "status": "completed",
            "output_text": output,
            "usage": {},
        }


class BenchmarkGraderTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        benchmark = ROOT / "Tools/CoachingEval/benchmark"
        self.configuration = load_judge(benchmark / "configs/judge-v1.json", ROOT)
        self.rows = [
            json.loads(line)
            for line in self.configuration.calibration_path.read_text().splitlines()
        ]

    def tearDown(self):
        self.temporary.cleanup()

    def absolute(self, row=None, score=5, severe=False):
        scores = (
            dict(row["humanScores"])
            if row is not None
            else {dimension: score for dimension in RUBRIC_DIMENSIONS}
        )
        flags = (
            dict(row["humanFlags"])
            if row is not None
            else {flag: False for flag in RUBRIC_FLAGS}
        )
        flags["severeError"] = severe if row is None else flags["severeError"]
        return {"scores": scores, "flags": flags, "evidence": ["Grounded in the supplied facts."]}

    def test_calibration_requires_exact_inventory_and_thresholds(self):
        client = QueueJudge([self.absolute(row) for row in self.rows])
        result = calibrate_judge(self.configuration, client)
        self.assertTrue(result.passed)
        self.assertEqual(1.0, result.severe_agreement)
        self.assertEqual(1.0, result.dimension_within_one)
        self.assertEqual(20, len(client.calls))

        severe_failures = [self.absolute(row) for row in self.rows]
        for index in (0, 1, 2):
            severe_failures[index]["flags"]["severeError"] = not self.rows[index]["humanFlags"]["severeError"]
        result = calibrate_judge(self.configuration, QueueJudge(severe_failures))
        self.assertFalse(result.passed)
        self.assertLess(result.severe_agreement, 0.90)

        score_failures = [self.absolute(row) for row in self.rows]
        changed = 0
        for output, row in zip(score_failures, self.rows):
            for dimension in RUBRIC_DIMENSIONS:
                if changed < 25:
                    output["scores"][dimension] = 1 if row["humanScores"][dimension] >= 3 else 5
                    changed += 1
        result = calibrate_judge(self.configuration, QueueJudge(score_failures))
        self.assertFalse(result.passed)
        self.assertLess(result.dimension_within_one, 0.80)

    def test_grade_run_mechanically_gates_and_blinds_absolute_and_pairwise_calls(self):
        corpus = self.make_corpus()
        run_root = self.make_run()
        outputs = [self.absolute(row) for row in self.rows]
        outputs.extend(self.absolute(score=4) for _ in range(3))
        outputs.append({"winner": "A", "evidence": ["A better supports discovery."]})
        client = QueueJudge(outputs)

        destination = self.root / "grades"
        grade_run(
            run_root=run_root,
            corpus=corpus,
            judge_configuration=self.configuration,
            client=client,
            destination=destination,
        )

        absolute = [json.loads(line) for line in (destination / "absolute-grades.jsonl").read_text().splitlines()]
        pairwise = [json.loads(line) for line in (destination / "pairwise-grades.jsonl").read_text().splitlines()]
        self.assertEqual(6, len(absolute))
        self.assertEqual(3, len(pairwise))
        self.assertEqual(24, len(client.calls))
        self.assertEqual(3, sum(grade["disposition"] == "unusable" for grade in absolute))
        self.assertEqual("candidateLoss", pairwise[0]["outcome"])
        self.assertEqual("unusableTie", pairwise[1]["outcome"])
        self.assertIn(pairwise[2]["outcome"], {"candidateWin", "candidateLoss"})

        for call in client.calls[20:]:
            payload = call["user_prompt"]
            for prohibited in ("baseline-id", "candidate-id", "gpt-5.6-sol", "latencyMilliseconds", "candidateCostUSD", "userPrompt"):
                self.assertNotIn(prohibited, payload)
            self.assertFalse(call["store"])

    def test_failed_calibration_prevents_candidate_grades(self):
        outputs = [self.absolute(row) for row in self.rows]
        for index in (0, 1, 2):
            outputs[index]["flags"]["severeError"] = not self.rows[index]["humanFlags"]["severeError"]
        client = QueueJudge(outputs)
        destination = self.root / "rejected"
        with self.assertRaisesRegex(ValueError, "calibration"):
            grade_run(
                run_root=self.make_run(),
                corpus=self.make_corpus(),
                judge_configuration=self.configuration,
                client=client,
                destination=destination,
            )
        self.assertEqual(20, len(client.calls))
        calibration = json.loads((destination / "calibration.json").read_text())
        manifest = json.loads((destination / "grade-manifest.json").read_text())
        self.assertFalse(calibration["passed"])
        self.assertEqual(20, len(calibration["rows"]))
        self.assertEqual("calibrationFailed", manifest["status"])
        self.assertEqual("", (destination / "absolute-grades.jsonl").read_text())
        self.assertEqual("", (destination / "pairwise-grades.jsonl").read_text())

    def test_candidate_judge_output_is_strict_bounded_and_identity_free(self):
        valid = self.absolute(score=4)
        cases = {
            "malformed": "not-json",
            "unknown fields": json.dumps({**valid, "extra": True}),
            "missing evidence": json.dumps({key: value for key, value in valid.items() if key != "evidence"}),
            "bounded evidence": json.dumps({**valid, "evidence": ["x" * 501]}),
            "identity": json.dumps({**valid, "evidence": ["candidate-id is better."]}),
        }
        for label, bad_output in cases.items():
            with self.subTest(label=label):
                calibration = [json.dumps(self.absolute(row)) for row in self.rows]
                client = RawQueueJudge(calibration + [bad_output])
                with self.assertRaises(ValueError):
                    grade_run(
                        run_root=self.make_run(),
                        corpus=self.make_corpus(),
                        judge_configuration=self.configuration,
                        client=client,
                        destination=self.root / f"rejected-{label.replace(' ', '-')}",
                    )
                self.assertEqual(21, len(client.calls))

    def test_grade_manifest_binds_both_judge_schemas(self):
        outputs = [self.absolute(row) for row in self.rows]
        outputs.extend(self.absolute(score=4) for _ in range(3))
        outputs.append({"winner": "A", "evidence": ["A better supports discovery."]})
        destination = self.root / "schema-bound-grades"
        grade_run(
            run_root=self.make_run(),
            corpus=self.make_corpus(),
            judge_configuration=self.configuration,
            client=QueueJudge(outputs),
            destination=destination,
        )
        manifest = json.loads((destination / "grade-manifest.json").read_text())
        self.assertRegex(manifest["absoluteSchemaSHA256"], r"^[0-9a-f]{64}$")
        self.assertRegex(manifest["pairwiseSchemaSHA256"], r"^[0-9a-f]{64}$")

    def make_corpus(self):
        brief = BenchmarkGraderBrief(
            verified_facts=("White to move.", "Position ongoing.", "Latest event helpOpened."),
            coaching_purpose="Coach one useful step.",
            acceptable_alternatives=("Any accurate response.",),
            success_criteria=("Accurate.",),
            severe_failure_criteria=("Invents danger.",),
        )
        turns = tuple(
            BenchmarkTurn(f"case-{index}", f"case-{index}", 1, "development", "quiet", {"requestID": f"case-{index}"}, brief, None)
            for index in range(1, 4)
        )
        return BenchmarkCorpus(self.root, "source", "c" * 64, turns, tuple())

    def make_run(self):
        root = self.root / f"run-{len(list(self.root.glob('run-*')))}"
        root.mkdir()
        records = []
        statuses = {
            "case-1": (True, False),
            "case-2": (False, False),
            "case-3": (True, True),
        }
        for case_id, validities in statuses.items():
            for configuration_id, valid in zip(("baseline-id", "candidate-id"), validities):
                records.append(
                    {
                        "cellID": f"{configuration_id}|{case_id}|r1",
                        "configurationID": configuration_id,
                        "caseID": case_id,
                        "groupID": case_id,
                        "stepIndex": 1,
                        "split": "development",
                        "category": "quiet",
                        "repetition": 1,
                        "userPrompt": "## Available UI response\n\nActions: hint\nExpected response: stageMove\nSquare focus: any board square\nAllowable move focus: none",
                        "parsedTurn": {"message": "What do you notice?", "actions": ["hint"], "focus": [], "expects": "stageMove"} if valid else None,
                        "mechanicalValidation": {"valid": valid, "categories": [] if valid else ["invalidJSON"]},
                        "generationStatus": "completed" if valid else "invalid",
                        "latencyMilliseconds": 1234,
                        "candidateCostUSD": "0.01",
                    }
                )
        records_bytes = b"".join(
            json.dumps(record, sort_keys=True, separators=(",", ":")).encode() + b"\n"
            for record in records
        )
        (root / "records.jsonl").write_bytes(records_bytes)
        manifest = {
            "schemaVersion": "coaching-quality-candidate-run.v1",
            "mode": "comparison",
            "corpusSHA256": "c" * 64,
            "configurations": [
                {"id": "baseline-id", "baseline": True},
                {"id": "candidate-id", "baseline": False},
            ],
            "recordsSHA256": hashlib.sha256(records_bytes).hexdigest(),
        }
        (root / "run-manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
        return root


if __name__ == "__main__":
    unittest.main()

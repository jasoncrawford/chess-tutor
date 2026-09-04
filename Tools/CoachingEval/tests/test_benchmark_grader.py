import hashlib
import json
import tempfile
import unittest
from dataclasses import replace
from datetime import datetime, timezone
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
from Tools.CoachingEval.benchmark.qualification import JudgeQualification
from Tools.CoachingEval.benchmark.reference_set import JudgeReferenceSet


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
        self.legacy_configuration = load_judge(
            benchmark / "configs/judge-v1.json", ROOT
        )
        self.rows = [
            json.loads(line)
            for line in self.legacy_configuration.calibration_path.read_text().splitlines()
        ]
        prompt = self.root / "judge.md"
        prompt.write_bytes((benchmark / "judge-v1.md").read_bytes())
        reference_value = json.loads(
            (benchmark / "judge-reference-v2.json").read_text()
        )
        reference_value["provenance"].update(
            {
                "reviewStatus": "humanReviewed",
                "reviewedBy": "Test Reviewer",
                "reviewedAt": "2026-09-03",
            }
        )
        reference = self.root / "reference.json"
        reference.write_text(json.dumps(reference_value), encoding="utf-8")
        judge_value = {
            "schemaVersion": "coaching-quality-judge.v2",
            "id": "judge-test-v2",
            "provider": "openai-responses-v1",
            "model": "gpt-5.6-sol",
            "reasoningEffort": "high",
            "conversationReuse": False,
            "maximumOutputTokens": 2048,
            "timeoutSeconds": 60,
            "systemPromptPath": "judge.md",
            "systemPromptSHA256": hashlib.sha256(prompt.read_bytes()).hexdigest(),
            "referenceSetPath": "reference.json",
            "referenceSetSHA256": hashlib.sha256(reference.read_bytes()).hexdigest(),
            "reviewSeed": 20260901,
            "qualificationRepetitions": 3,
            "minimumSevereAgreement": 0.95,
            "minimumDimensionAgreement": 0.90,
            "qualificationValidDays": 30,
        }
        judge_path = self.root / "judge.json"
        judge_path.write_text(json.dumps(judge_value), encoding="utf-8")
        self.configuration = load_judge(judge_path, self.root)
        self.reference = JudgeReferenceSet.load(
            reference, self.configuration.reference_set_sha256
        )
        self.now = datetime(2026, 9, 3, 12, 0, tzinfo=timezone.utc)
        self.qualification_path = JudgeQualification.ensure(
            self.configuration,
            QueueJudge(
                [
                    self.absolute(case)
                    for _repetition in range(3)
                    for case in self.reference.cases
                ]
            ),
            None,
            self.root / "qualifications",
            self.now,
        )

    def tearDown(self):
        self.temporary.cleanup()

    def absolute(self, row=None, score=5, severe=False):
        score_key = (
            "humanScores"
            if row is not None and "humanScores" in row
            else "referenceScores"
        )
        flag_key = (
            "humanFlags"
            if row is not None and "humanFlags" in row
            else "referenceFlags"
        )
        scores = (
            dict(row[score_key])
            if row is not None
            else {dimension: score for dimension in RUBRIC_DIMENSIONS}
        )
        flags = (
            dict(row[flag_key])
            if row is not None
            else {flag: False for flag in RUBRIC_FLAGS}
        )
        flags["severeError"] = severe if row is None else flags["severeError"]
        return {"scores": scores, "flags": flags, "evidence": ["Grounded in the supplied facts."]}

    def test_calibration_requires_exact_inventory_and_thresholds(self):
        client = QueueJudge([self.absolute(row) for row in self.rows])
        result = calibrate_judge(self.legacy_configuration, client)
        self.assertTrue(result.passed)
        self.assertEqual(1.0, result.severe_agreement)
        self.assertEqual(1.0, result.dimension_within_one)
        self.assertEqual(20, len(client.calls))

        severe_failures = [self.absolute(row) for row in self.rows]
        for index in (0, 1, 2):
            severe_failures[index]["flags"]["severeError"] = not self.rows[index]["humanFlags"]["severeError"]
        result = calibrate_judge(self.legacy_configuration, QueueJudge(severe_failures))
        self.assertFalse(result.passed)
        self.assertLess(result.severe_agreement, 0.90)

        score_failures = [self.absolute(row) for row in self.rows]
        changed = 0
        for output, row in zip(score_failures, self.rows):
            for dimension in RUBRIC_DIMENSIONS:
                if changed < 25:
                    output["scores"][dimension] = 1 if row["humanScores"][dimension] >= 3 else 5
                    changed += 1
        result = calibrate_judge(self.legacy_configuration, QueueJudge(score_failures))
        self.assertFalse(result.passed)
        self.assertLess(result.dimension_within_one, 0.80)

    def test_grade_run_mechanically_gates_and_blinds_absolute_and_pairwise_calls(self):
        corpus = self.make_corpus()
        run_root = self.make_run()
        outputs = [self.absolute(score=4) for _ in range(3)]
        outputs.append({"winner": "A", "evidence": ["A better supports discovery."]})
        client = QueueJudge(outputs)

        destination = self.root / "grades"
        grade_run(
            run_root=run_root,
            corpus=corpus,
            judge_configuration=self.configuration,
            client=client,
            destination=destination,
            qualification_path=self.qualification_path,
            now=self.now,
        )

        absolute = [json.loads(line) for line in (destination / "absolute-grades.jsonl").read_text().splitlines()]
        pairwise = [json.loads(line) for line in (destination / "pairwise-grades.jsonl").read_text().splitlines()]
        self.assertEqual(6, len(absolute))
        self.assertEqual(3, len(pairwise))
        self.assertEqual(4, len(client.calls))
        self.assertEqual(3, sum(grade["disposition"] == "unusable" for grade in absolute))
        self.assertEqual("candidateLoss", pairwise[0]["outcome"])
        self.assertEqual("unusableTie", pairwise[1]["outcome"])
        self.assertIn(pairwise[2]["outcome"], {"candidateWin", "candidateLoss"})

        for call in client.calls:
            payload = call["user_prompt"]
            for prohibited in ("baseline-id", "candidate-id", "gpt-5.6-sol", "latencyMilliseconds", "candidateCostUSD", "userPrompt"):
                self.assertNotIn(prohibited, payload)
            self.assertFalse(call["store"])

    def test_invalid_qualification_prevents_all_judge_calls(self):
        original = json.loads(self.qualification_path.read_text())
        bad_paths = []
        for name, update in (
            ("rejected", {"status": "rejected"}),
            (
                "expired",
                {
                    "createdAt": "2026-08-01T12:00:00Z",
                    "expiresAt": "2026-08-31T12:00:00Z",
                },
            ),
        ):
            value = json.loads(json.dumps(original))
            value.update(update)
            path = self.root / f"{name}.json"
            path.write_text(json.dumps(value), encoding="utf-8")
            bad_paths.append((name, path, self.configuration))
        value = json.loads(json.dumps(original))
        value["bindings"]["judgePromptSHA256"] = "0" * 64
        path = self.root / "mismatch.json"
        path.write_text(json.dumps(value), encoding="utf-8")
        bad_paths.append(("compatible", path, self.configuration))
        bad_paths.append(("load", self.root / "missing.json", self.configuration))

        pending = json.loads(self.configuration.reference_set_path.read_text())
        pending["provenance"].update(
            {"reviewStatus": "pending", "reviewedBy": None, "reviewedAt": None}
        )
        pending_path = self.root / "pending-reference.json"
        pending_path.write_text(json.dumps(pending), encoding="utf-8")
        pending_configuration = replace(
            self.configuration,
            reference_set_path=pending_path,
            reference_set_sha256=hashlib.sha256(pending_path.read_bytes()).hexdigest(),
        )
        bad_paths.append(("human-reviewed", self.qualification_path, pending_configuration))

        for label, path, configuration in bad_paths:
            client = QueueJudge([])
            with self.subTest(label=label), self.assertRaisesRegex(ValueError, label):
                grade_run(
                    run_root=self.make_run(),
                    corpus=self.make_corpus(),
                    judge_configuration=configuration,
                    client=client,
                    destination=self.root / f"rejected-{label}",
                    qualification_path=path,
                    now=self.now,
                )
            self.assertEqual([], client.calls)

    def test_grade_preflights_judge_price_before_provider_call(self):
        class MissingPrice:
            def estimate(self, _model, _usage):
                raise ValueError("No price is pinned for judge")

        client = QueueJudge([])
        with self.assertRaisesRegex(ValueError, "price"):
            grade_run(
                run_root=self.make_run(),
                corpus=self.make_corpus(),
                judge_configuration=self.configuration,
                client=client,
                destination=self.root / "unpriced",
                qualification_path=self.qualification_path,
                price_table=MissingPrice(),
                now=self.now,
            )
        self.assertEqual([], client.calls)

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
                client = RawQueueJudge([bad_output])
                with self.assertRaises(ValueError):
                    grade_run(
                        run_root=self.make_run(),
                        corpus=self.make_corpus(),
                        judge_configuration=self.configuration,
                        client=client,
                        destination=self.root / f"rejected-{label.replace(' ', '-')}",
                        qualification_path=self.qualification_path,
                        now=self.now,
                    )
                self.assertEqual(1, len(client.calls))

    def test_grade_manifest_binds_both_judge_schemas(self):
        outputs = [self.absolute(score=4) for _ in range(3)]
        outputs.append({"winner": "A", "evidence": ["A better supports discovery."]})
        destination = self.root / "schema-bound-grades"
        grade_run(
            run_root=self.make_run(),
            corpus=self.make_corpus(),
            judge_configuration=self.configuration,
            client=QueueJudge(outputs),
            destination=destination,
            qualification_path=self.qualification_path,
            now=self.now,
        )
        manifest = json.loads((destination / "grade-manifest.json").read_text())
        qualification_bytes = (destination / "qualification.json").read_bytes()
        self.assertEqual(
            hashlib.sha256(qualification_bytes).hexdigest(),
            manifest["qualificationSHA256"],
        )
        self.assertNotIn("calibrationSHA256", manifest)
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

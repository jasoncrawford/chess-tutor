import hashlib
import json
import tempfile
import unittest
from dataclasses import replace
from datetime import datetime, timedelta, timezone
from pathlib import Path

from Tools.CoachingEval.benchmark.configuration import load_judge
from Tools.CoachingEval.benchmark.grader import RUBRIC_DIMENSIONS
from Tools.CoachingEval.benchmark.qualification import (
    JudgeQualification,
    QualificationFailed,
)
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
            "output_text": json.dumps(output, separators=(",", ":")),
            "usage": {
                "input_tokens": 50,
                "cached_input_tokens": 10,
                "output_tokens": 20,
                "reasoning_tokens": 5,
                "total_tokens": 70,
            },
        }


class FailingJudge(QueueJudge):
    def complete(self, **arguments):
        self.calls.append(arguments)
        if len(self.calls) == 2:
            raise RuntimeError("private provider failure body")
        output = self.outputs.pop(0)
        return {
            "output_text": json.dumps(output, separators=(",", ":")),
            "usage": {},
        }


class RawQueueJudge(QueueJudge):
    def complete(self, **arguments):
        self.calls.append(arguments)
        output = self.outputs.pop(0)
        return {
            "output_text": output,
            "usage": {
                "input_tokens": 50,
                "cached_input_tokens": 10,
                "output_tokens": 20,
                "reasoning_tokens": 5,
                "total_tokens": 70,
            },
        }


class JudgeQualificationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        prompt_source = ROOT / "Tools/CoachingEval/benchmark/judge-v1.md"
        prompt = self.root / "judge.md"
        prompt.write_bytes(prompt_source.read_bytes())

        reference_value = json.loads(
            (ROOT / "Tools/CoachingEval/benchmark/judge-reference-v2.json").read_text()
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
        configuration_value = {
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
        configuration_path = self.root / "judge.json"
        configuration_path.write_text(json.dumps(configuration_value), encoding="utf-8")
        self.configuration = load_judge(configuration_path, self.root)
        self.reference = JudgeReferenceSet.load(
            reference, self.configuration.reference_set_sha256
        )
        self.now = datetime(2026, 9, 3, 12, 0, tzinfo=timezone.utc)

    def tearDown(self):
        self.temporary.cleanup()

    def output(self, case):
        return {
            "scores": dict(case["referenceScores"]),
            "flags": dict(case["referenceFlags"]),
            "evidence": ["Grounded in the supplied facts."],
        }

    def passing_outputs(self):
        return [
            self.output(case)
            for _repetition in range(3)
            for case in self.reference.cases
        ]

    def test_three_complete_passing_repetitions_publish_accepted_artifact(self):
        client = QueueJudge(self.passing_outputs())
        path = JudgeQualification.ensure(
            self.configuration,
            client,
            None,
            self.root / "qualifications",
            self.now,
        )

        self.assertEqual(60, len(client.calls))
        artifact = json.loads(path.read_text())
        self.assertEqual("accepted", artifact["status"])
        self.assertEqual(3, len(artifact["passes"]))
        self.assertEqual(1.0, artifact["minimumSevereAgreement"])
        self.assertEqual(1.0, artifact["minimumDimensionAgreement"])
        self.assertEqual(60, artifact["qualificationMetrics"]["callCount"])
        loaded = JudgeQualification.load_compatible(
            path, self.configuration, self.now + timedelta(days=29)
        )
        self.assertEqual(path, loaded.path)

    def test_each_pass_must_clear_severe_and_dimension_thresholds(self):
        severe_outputs = self.passing_outputs()
        for index in (0, 1):
            expected = self.reference.cases[index]["referenceFlags"]["severeError"]
            severe_outputs[index]["flags"]["severeError"] = not expected
        with self.assertRaises(QualificationFailed) as failure:
            JudgeQualification.ensure(
                self.configuration,
                QueueJudge(severe_outputs),
                None,
                self.root / "severe-rejected",
                self.now,
            )
        severe_artifact = json.loads(failure.exception.artifact_path.read_text())
        self.assertEqual("rejected", severe_artifact["status"])
        self.assertEqual(0.90, severe_artifact["passes"][0]["severeAgreement"])
        self.assertEqual(20, len(severe_artifact["passes"][0]["rows"]))

        score_outputs = self.passing_outputs()
        changed = 0
        for output, case in zip(score_outputs[:20], self.reference.cases):
            for dimension in RUBRIC_DIMENSIONS:
                if changed < 13:
                    reference = case["referenceScores"][dimension]
                    output["scores"][dimension] = 1 if reference >= 3 else 5
                    changed += 1
        with self.assertRaises(QualificationFailed) as failure:
            JudgeQualification.ensure(
                self.configuration,
                QueueJudge(score_outputs),
                None,
                self.root / "dimension-rejected",
                self.now,
            )
        score_artifact = json.loads(failure.exception.artifact_path.read_text())
        self.assertLess(score_artifact["passes"][0]["dimensionWithinOne"], 0.90)

    def test_expiration_hash_binding_and_newest_compatible_reuse(self):
        artifact_root = self.root / "reusable"
        first = JudgeQualification.ensure(
            self.configuration,
            QueueJudge(self.passing_outputs()),
            None,
            artifact_root,
            self.now,
        )
        no_calls = QueueJudge([])
        reused = JudgeQualification.ensure(
            self.configuration,
            no_calls,
            None,
            artifact_root,
            self.now + timedelta(days=10),
        )
        self.assertEqual(first, reused)
        self.assertEqual([], no_calls.calls)

        with self.assertRaisesRegex(ValueError, "expired"):
            JudgeQualification.load_compatible(
                first, self.configuration, self.now + timedelta(days=30)
            )

        artifact = json.loads(first.read_text())
        artifact["bindings"]["judgePromptSHA256"] = "0" * 64
        drifted = self.root / "drifted.json"
        drifted.write_text(json.dumps(artifact), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "compatible"):
            JudgeQualification.load_compatible(
                drifted, self.configuration, self.now + timedelta(days=1)
            )

        newer_artifact = json.loads(first.read_text())
        newer_artifact["createdAt"] = "2026-09-04T12:00:00Z"
        newer_artifact["expiresAt"] = "2026-10-04T12:00:00Z"
        newer = self.write_artifact(
            artifact_root, "20260904T120000Z", newer_artifact
        )
        selected = JudgeQualification.ensure(
            self.configuration,
            QueueJudge([]),
            None,
            artifact_root,
            self.now + timedelta(days=2),
        )
        self.assertEqual(newer, selected)

    def test_reuse_strictly_validates_evidence_timestamps_metrics_and_snapshot(self):
        artifact_root = self.root / "strict"
        path = JudgeQualification.ensure(
            self.configuration,
            QueueJudge(self.passing_outputs()),
            None,
            artifact_root,
            self.now,
        )
        original_bytes = path.read_bytes()
        original = json.loads(original_bytes)
        mutations = []

        future = json.loads(json.dumps(original))
        future["createdAt"] = "2026-09-04T12:00:00Z"
        future["expiresAt"] = "2026-10-04T12:00:00Z"
        mutations.append(("future", future, "future"))

        long_lived = json.loads(json.dumps(original))
        long_lived["expiresAt"] = "2099-01-01T00:00:00Z"
        mutations.append(("long-lived", long_lived, "validity interval"))

        extra = json.loads(json.dumps(original))
        extra["passes"][0]["rows"][0]["providerErrorBody"] = "private"
        mutations.append(("extra-row", extra, "row"))

        wrong_row = json.loads(json.dumps(original))
        wrong_row["passes"][0]["rows"][0]["rowID"] = "ref-99"
        mutations.append(("wrong-row", wrong_row, "row"))

        wrong_metrics = json.loads(json.dumps(original))
        wrong_metrics["qualificationMetrics"]["callCount"] = 59
        mutations.append(("wrong-metrics", wrong_metrics, "metrics"))

        for name, value, message in mutations:
            candidate = self.write_artifact(
                self.root / f"strict-{name}", "20260903T120000Z", value
            )
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, message):
                JudgeQualification.load_compatible(
                    candidate, self.configuration, self.now
                )

        loaded = JudgeQualification.load_compatible(
            path, self.configuration, self.now
        )
        path.write_text("{}", encoding="utf-8")
        self.assertEqual(original_bytes, loaded.artifact_bytes)

    def test_call_failure_publishes_bounded_rejected_diagnostics(self):
        client = FailingJudge([self.output(self.reference.cases[0])])
        with self.assertRaises(QualificationFailed) as failure:
            JudgeQualification.ensure(
                self.configuration,
                client,
                None,
                self.root / "call-failure",
                self.now,
            )

        artifact_text = failure.exception.artifact_path.read_text()
        artifact = json.loads(artifact_text)
        self.assertEqual("rejected", artifact["status"])
        self.assertEqual("judgeCallFailed", artifact["passes"][0]["failureCategory"])
        self.assertEqual(1, len(artifact["passes"][0]["rows"]))
        self.assertEqual(2, artifact["qualificationMetrics"]["callCount"])
        self.assertNotIn("private provider failure body", artifact_text)

    def test_invalid_structured_response_preserves_paid_call_usage(self):
        first = self.output(self.reference.cases[0])
        client = RawQueueJudge(
            [json.dumps(first), "not-json private provider response"]
        )
        with self.assertRaises(QualificationFailed) as failure:
            JudgeQualification.ensure(
                self.configuration,
                client,
                None,
                self.root / "invalid-response",
                self.now,
            )

        artifact_text = failure.exception.artifact_path.read_text()
        artifact = json.loads(artifact_text)
        metrics = artifact["qualificationMetrics"]
        self.assertEqual(2, metrics["callCount"])
        self.assertEqual(100, metrics["usage"]["inputTokens"])
        self.assertEqual(40, metrics["usage"]["outputTokens"])
        self.assertNotIn("private provider response", artifact_text)

    def test_missing_judge_price_fails_before_provider_call(self):
        class MissingPrice:
            def estimate(self, _model, _usage):
                raise ValueError("No price is pinned for judge")

        client = QueueJudge([])
        with self.assertRaisesRegex(ValueError, "price"):
            JudgeQualification.ensure(
                self.configuration,
                client,
                MissingPrice(),
                self.root / "missing-price",
                self.now,
            )
        self.assertEqual([], client.calls)

    def test_pending_reference_is_rejected_before_provider_calls(self):
        reference = json.loads(self.configuration.reference_set_path.read_text())
        reference["provenance"].update(
            {"reviewStatus": "pending", "reviewedBy": None, "reviewedAt": None}
        )
        self.configuration.reference_set_path.write_text(json.dumps(reference))
        configuration = replace(
            self.configuration,
            reference_set_sha256=hashlib.sha256(
                self.configuration.reference_set_path.read_bytes()
            ).hexdigest(),
        )
        client = QueueJudge([])
        with self.assertRaisesRegex(ValueError, "human-reviewed"):
            JudgeQualification.ensure(
                configuration,
                client,
                None,
                self.root / "pending",
                self.now,
            )
        self.assertEqual([], client.calls)

    @staticmethod
    def write_artifact(root, timestamp, value):
        data = (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()
        directory = Path(root) / f"{timestamp}-{hashlib.sha256(data).hexdigest()}"
        directory.mkdir(parents=True)
        path = directory / "qualification.json"
        path.write_bytes(data)
        return path


if __name__ == "__main__":
    unittest.main()

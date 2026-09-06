import hashlib
import json
import tempfile
import unittest
from dataclasses import replace
from datetime import datetime, timedelta, timezone
from decimal import Decimal
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
            "usage": {
                "input_tokens": 50,
                "cached_input_tokens": 10,
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
            "output_text": output,
            "usage": {
                "input_tokens": 50,
                "cached_input_tokens": 10,
                "output_tokens": 20,
                "reasoning_tokens": 5,
                "total_tokens": 70,
            },
        }


class FixedPrice:
    def estimate(self, _model, _usage):
        return Decimal("0.001")


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
                "reviewStatus": "agentReviewed",
                "reviewedBy": "GPT-6 Astra",
                "reviewedAt": "2026-09-06",
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
            "minimumPairwiseAgreement": 0.90,
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
            output
            for _repetition in range(3)
            for output in self.passing_pass_outputs()
        ]

    def passing_pass_outputs(self):
        outputs = [self.output(case) for case in self.reference.cases]
        for case in self.reference.pairwise_cases:
            outputs.append(self.pairwise_output(case, "A"))
            outputs.append(self.pairwise_output(case, "B"))
        return outputs

    @staticmethod
    def pairwise_output(case, response_one_presented_as):
        preference = case["referencePreference"]
        if preference == "tie":
            winner = "tie"
        elif preference == "responseOne":
            winner = response_one_presented_as
        else:
            winner = "B" if response_one_presented_as == "A" else "A"
        return {"winner": winner, "evidence": ["One response better fits the current step."]}

    def test_three_complete_passing_repetitions_publish_accepted_artifact(self):
        client = QueueJudge(self.passing_outputs())
        path = JudgeQualification.ensure(
            self.configuration,
            client,
            None,
            self.root / "qualifications",
            self.now,
        )

        self.assertEqual(120, len(client.calls))
        artifact = json.loads(path.read_text())
        self.assertEqual("accepted", artifact["status"])
        self.assertEqual(3, len(artifact["passes"]))
        self.assertEqual(1.0, artifact["minimumSevereAgreement"])
        self.assertEqual(1.0, artifact["minimumDimensionAgreement"])
        self.assertEqual(1.0, artifact["minimumPairwiseAgreement"])
        self.assertEqual(
            {
                "status": "agentReviewed",
                "reviewedBy": "GPT-6 Astra",
                "reviewedAt": "2026-09-06",
            },
            artifact["referenceReview"],
        )
        self.assertEqual(120, artifact["qualificationMetrics"]["callCount"])
        self.assertTrue(artifact["qualificationMetrics"]["accountingComplete"])
        self.assertEqual(1.0, artifact["passes"][0]["pairwiseAgreement"])
        self.assertEqual(20, len(artifact["passes"][0]["pairwiseRows"]))
        loaded = JudgeQualification.load_compatible(
            path, self.configuration, self.now + timedelta(days=29)
        )
        self.assertEqual(path, loaded.path)

    def test_qualification_sends_bounded_replayed_context_to_judge(self):
        client = QueueJudge(self.passing_outputs())
        JudgeQualification.ensure(
            self.configuration,
            client,
            None,
            self.root / "context-qualification",
            self.now,
        )

        safe_capture = json.loads(client.calls[3]["user_prompt"])
        self.assertEqual(
            {
                "kind",
                "graderBrief",
                "judgeContext",
                "availableUI",
                "candidateTurn",
            },
            set(safe_capture),
        )
        self.assertEqual(
            "rnb1kbnr/pppp1ppp/8/4p3/4P2q/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3",
            safe_capture["judgeContext"]["position"]["fen"],
        )
        self.assertIn(
            "move:f3-h4",
            [
                move["id"]
                for move in safe_capture["judgeContext"]["legalCaptures"]
            ],
        )
        poisoned = json.loads(client.calls[7]["user_prompt"])
        self.assertEqual(
            ["move:e8-f7"],
            [
                move["id"]
                for move in poisoned["judgeContext"]["immediateReplies"]
            ],
        )
        hint = json.loads(client.calls[12]["user_prompt"])
        self.assertEqual(
            ["action:hint"],
            hint["judgeContext"]["interaction"]["latestEvent"][
                "referencedIDs"
            ],
        )
        pair_a = json.loads(client.calls[20]["user_prompt"])
        pair_b = json.loads(client.calls[21]["user_prompt"])
        case = self.reference.pairwise_cases[0]
        self.assertEqual(
            {
                "kind",
                "graderBrief",
                "judgeContext",
                "availableUI",
                "responseA",
                "responseB",
            },
            set(pair_a),
        )
        self.assertEqual(self.thaw(case["judgeContext"]), pair_a["judgeContext"])
        self.assertEqual(self.thaw(case["responseOne"]), pair_a["responseA"])
        self.assertEqual(self.thaw(case["responseTwo"]), pair_a["responseB"])
        self.assertEqual(self.thaw(case["responseTwo"]), pair_b["responseA"])
        self.assertEqual(self.thaw(case["responseOne"]), pair_b["responseB"])
        for call in client.calls:
            payload = json.loads(call["user_prompt"])
            self.assertLessEqual(
                len(json.dumps(payload["judgeContext"]).encode("utf-8")),
                16_384,
            )
            self.assertNotIn("request", payload)
            self.assertNotIn("rationale", payload["judgeContext"])
            self.assertNotIn("referenceScores", payload["judgeContext"])

    def test_pairwise_rows_normalize_both_orders_and_preserve_ties(self):
        path = JudgeQualification.ensure(
            self.configuration,
            QueueJudge(self.passing_outputs()),
            None,
            self.root / "pairwise-normalization",
            self.now,
        )

        rows = json.loads(path.read_text())["passes"][0]["pairwiseRows"]
        for case_index, case in enumerate(self.reference.pairwise_cases):
            first, second = rows[case_index * 2 : case_index * 2 + 2]
            self.assertEqual(case["id"], first["pairID"])
            self.assertEqual("A", first["responseOnePresentedAs"])
            self.assertEqual("B", second["responseOnePresentedAs"])
            self.assertEqual(case["referencePreference"], first["normalizedWinner"])
            self.assertEqual(case["referencePreference"], second["normalizedWinner"])
            self.assertEqual(case["referencePreference"], first["referencePreference"])
            self.assertTrue(first["orderConsistent"])
            self.assertTrue(second["orderConsistent"])
            self.assertTrue(first["winnerMatch"])
            self.assertTrue(second["winnerMatch"])
        tie_case = next(
            case
            for case in self.reference.pairwise_cases
            if case["referencePreference"] == "tie"
        )
        tie_rows = [row for row in rows if row["pairID"] == tie_case["id"]]
        self.assertEqual(["tie", "tie"], [row["judgeWinner"] for row in tie_rows])

    def test_order_inconsistency_marks_both_rows_wrong_and_one_bad_pass_rejects(self):
        first_pass = self.passing_pass_outputs()
        for offset in (1, 3):
            output = first_pass[20 + offset]
            output["winner"] = "A" if output["winner"] != "A" else "B"
        outputs = first_pass + self.passing_pass_outputs() + self.passing_pass_outputs()

        with self.assertRaises(QualificationFailed) as failure:
            JudgeQualification.ensure(
                self.configuration,
                QueueJudge(outputs),
                None,
                self.root / "order-biased",
                self.now,
            )

        artifact = json.loads(failure.exception.artifact_path.read_text())
        self.assertEqual(0.8, artifact["passes"][0]["pairwiseAgreement"])
        self.assertEqual(1.0, artifact["passes"][1]["pairwiseAgreement"])
        self.assertEqual(0.8, artifact["minimumPairwiseAgreement"])
        for pair_id in ("pair-01", "pair-02"):
            rows = [
                row
                for row in artifact["passes"][0]["pairwiseRows"]
                if row["pairID"] == pair_id
            ]
            self.assertEqual(2, len(rows))
            self.assertTrue(all(not row["orderConsistent"] for row in rows))
            self.assertTrue(all(not row["winnerMatch"] for row in rows))

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
        wrong_metrics["qualificationMetrics"]["callCount"] = 119
        mutations.append(("wrong-metrics", wrong_metrics, "metrics"))

        incomplete_metrics = json.loads(json.dumps(original))
        incomplete_metrics["passes"][0]["judgeMetrics"]["accountingComplete"] = False
        mutations.append(("incomplete-metrics", incomplete_metrics, "metrics"))

        wrong_pair = json.loads(json.dumps(original))
        wrong_pair["passes"][0]["pairwiseRows"][0]["normalizedWinner"] = "tie"
        mutations.append(("wrong-pair", wrong_pair, "pairwise"))

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
                FixedPrice(),
                self.root / "call-failure",
                self.now,
            )

        artifact_text = failure.exception.artifact_path.read_text()
        artifact = json.loads(artifact_text)
        self.assertEqual("rejected", artifact["status"])
        self.assertEqual("judgeCallFailed", artifact["passes"][0]["failureCategory"])
        self.assertEqual(1, len(artifact["passes"][0]["rows"]))
        self.assertEqual(2, artifact["qualificationMetrics"]["callCount"])
        self.assertEqual(50, artifact["qualificationMetrics"]["usage"]["inputTokens"])
        self.assertFalse(artifact["passes"][0]["judgeMetrics"]["accountingComplete"])
        self.assertFalse(artifact["qualificationMetrics"]["accountingComplete"])
        self.assertIsNone(artifact["qualificationMetrics"]["estimatedCostUSD"])
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

    def test_pairwise_failure_retains_bounded_rows_usage_latency_and_cost(self):
        outputs = self.passing_pass_outputs()[:21]
        client = RawQueueJudge(
            [json.dumps(output) for output in outputs]
            + ["not-json private pairwise reasoning trace"]
        )
        with self.assertRaises(QualificationFailed) as failure:
            JudgeQualification.ensure(
                self.configuration,
                client,
                FixedPrice(),
                self.root / "pairwise-call-failure",
                self.now,
            )

        artifact_text = failure.exception.artifact_path.read_text()
        artifact = json.loads(artifact_text)
        result = artifact["passes"][0]
        metrics = artifact["qualificationMetrics"]
        self.assertEqual("judgeCallFailed", result["failureCategory"])
        self.assertEqual(20, len(result["rows"]))
        self.assertEqual(1, len(result["pairwiseRows"]))
        self.assertEqual(22, metrics["callCount"])
        self.assertEqual(1100, metrics["usage"]["inputTokens"])
        self.assertGreater(metrics["latencyMilliseconds"], 0)
        self.assertTrue(metrics["accountingComplete"])
        self.assertEqual("0.022", metrics["estimatedCostUSD"])
        self.assertNotIn("private pairwise reasoning trace", artifact_text)

    @classmethod
    def thaw(cls, value):
        if hasattr(value, "items"):
            return {key: cls.thaw(child) for key, child in value.items()}
        if isinstance(value, (tuple, list)):
            return [cls.thaw(child) for child in value]
        return value

    def test_missing_judge_price_fails_before_provider_call(self):
        class MissingPrice:
            def estimate(self, _model, _usage):
                raise ValueError("No price is pinned for judge")

        artifact_root = self.root / "missing-price"
        JudgeQualification.ensure(
            self.configuration,
            QueueJudge(self.passing_outputs()),
            None,
            artifact_root,
            self.now,
        )
        client = QueueJudge([])
        with self.assertRaisesRegex(ValueError, "price"):
            JudgeQualification.ensure(
                self.configuration,
                client,
                MissingPrice(),
                artifact_root,
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
        with self.assertRaisesRegex(ValueError, "has not been reviewed"):
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

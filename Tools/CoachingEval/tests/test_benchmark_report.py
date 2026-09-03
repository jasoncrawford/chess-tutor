import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from Tools.CoachingEval.benchmark.configuration import load_prices
from Tools.CoachingEval.benchmark.grader import RUBRIC_DIMENSIONS, RUBRIC_FLAGS
from Tools.CoachingEval.benchmark.report import build_report, write_report


ROOT = Path(__file__).resolve().parents[3]


class BenchmarkReportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.prices = load_prices(ROOT / "Tools/CoachingEval/benchmark/pricing-v1.json")
        self.run_root, self.grade_root = self.make_artifacts()

    def tearDown(self):
        self.temporary.cleanup()

    def test_aggregates_quality_reliability_latency_usage_cost_and_judge_overhead(self):
        report = build_report(self.run_root, self.grade_root, self.prices)
        baseline = report["configurations"]["baseline"]
        candidate = report["configurations"]["candidate"]

        self.assertEqual(4, baseline["responseCount"])
        self.assertEqual(0.75, baseline["reliability"]["providerSuccessRate"])
        self.assertEqual(0.75, baseline["reliability"]["mechanicalValidityRate"])
        self.assertEqual(
            [{"category": "httpError", "httpStatus": 502, "count": 1}],
            baseline["reliability"]["providerFailureBreakdown"],
        )
        self.assertEqual([], candidate["reliability"]["providerFailureBreakdown"])
        self.assertEqual(0.25, baseline["quality"]["severeErrorRate"])
        self.assertEqual(0.5, baseline["quality"]["allDimensionsAtLeast4Rate"])
        self.assertEqual({"1": 1, "3": 1, "4": 1, "5": 1}, baseline["quality"]["dimensions"]["chessCorrectness"]["distribution"])
        self.assertEqual(2, baseline["operations"]["retryCount"])
        self.assertEqual(10, baseline["usage"]["outputTokens"])
        self.assertEqual(2000.0, baseline["latencyMilliseconds"]["p50"])
        self.assertEqual(4000.0, baseline["latencyMilliseconds"]["p90"])
        self.assertEqual(1, len(baseline["completeSequenceCostsUSD"]))
        self.assertEqual(3, candidate["pairwise"]["wins"])
        self.assertEqual(0, candidate["pairwise"]["losses"])
        self.assertEqual(1, candidate["pairwise"]["ties"])
        self.assertEqual(1.0, candidate["breakdowns"]["category"]["quiet"]["strongResponseRate"])
        self.assertEqual(1.0, candidate["breakdowns"]["turnKind"]["initial"]["strongResponseRate"])
        self.assertGreater(float(candidate["candidateCostUSD"]["total"]), 0)
        self.assertEqual(30, report["judgeOverhead"]["callCount"])
        self.assertEqual(3000, report["judgeOverhead"]["usage"]["inputTokens"])
        self.assertTrue(candidate["promotionEligible"])
        self.assertIn("candidate", report["paretoFrontier"])
        self.assertNotIn("baseline", report["paretoFrontier"])
        self.assertEqual(
            ["baseline|s1-3|r1"],
            [value["cellID"] for value in report["mechanicalFailures"]],
        )
        self.assertEqual(502, report["mechanicalFailures"][0]["providerHTTPStatus"])

    def test_confidence_intervals_are_deterministic_and_manifest_failures_are_diagnostic(self):
        first = build_report(self.run_root, self.grade_root, self.prices)
        second = build_report(self.run_root, self.grade_root, self.prices)
        self.assertEqual(first["confidenceIntervals"], second["confidenceIntervals"])
        self.assertEqual(10_000, first["confidenceIntervals"]["draws"])
        self.assertEqual(20260901, first["confidenceIntervals"]["seed"])

        manifest_path = self.run_root / "run-manifest.json"
        manifest = json.loads(manifest_path.read_text())
        manifest["diagnosticSubset"] = True
        manifest_path.write_text(json.dumps(manifest))
        diagnostic_subset = build_report(self.run_root, self.grade_root, self.prices)
        self.assertFalse(diagnostic_subset["promotionEligible"])
        self.assertIn("diagnostic subset is not promotion eligible", diagnostic_subset["integrityIssues"])
        manifest["diagnosticSubset"] = False
        manifest_path.write_text(json.dumps(manifest))

        records_path = self.run_root / "records.jsonl"
        lines = records_path.read_text().splitlines()
        records_path.write_text("\n".join(lines[:-1]) + "\n")
        diagnostic = build_report(self.run_root, self.grade_root, self.prices)
        self.assertFalse(diagnostic["promotionEligible"])
        self.assertIn("candidate records hash mismatch", diagnostic["integrityIssues"])

    def test_writes_reproducible_json_and_markdown_without_overwrite(self):
        destination = self.root / "report"
        aggregate_path, summary_path = write_report(
            self.run_root,
            self.grade_root,
            self.prices,
            destination,
        )
        aggregate = json.loads(aggregate_path.read_text())
        summary = summary_path.read_text()
        self.assertEqual("coaching-quality-report.v1", aggregate["schemaVersion"])
        self.assertIn("# Coaching quality benchmark", summary)
        self.assertIn("Experiment changes", summary)
        self.assertIn("Quality and reliability", summary)
        self.assertIn("Candidate cost", summary)
        self.assertIn("Judge overhead", summary)
        self.assertIn("Pareto frontier", summary)
        self.assertIn("Mechanical failures", summary)
        self.assertIn("baseline|s1-3|r1", summary)
        self.assertIn("httpError (HTTP 502): 1", summary)
        self.assertIn("HTTP 502", summary)
        self.assertIn("transcripts/candidate--s1-3--r1.md", summary)
        with self.assertRaisesRegex(ValueError, "overwrite"):
            write_report(self.run_root, self.grade_root, self.prices, destination)

    def make_artifacts(self):
        run_root = self.root / "run"
        grade_root = self.root / "grades"
        run_root.mkdir()
        grade_root.mkdir()
        configurations = [
            {
                "id": "baseline",
                "baseline": True,
                "model": "gpt-5.6-sol",
                "systemPromptSHA256": "a" * 64,
                "initialReasoningEffort": "high",
                "followUpReasoningEffort": "none",
                "conversationReuse": True,
                "maximumOutputTokens": 2048,
                "userPromptGenerator": "chess-native-v13",
            },
            {
                "id": "candidate",
                "baseline": False,
                "model": "gpt-5.6-sol",
                "systemPromptSHA256": "b" * 64,
                "initialReasoningEffort": "medium",
                "followUpReasoningEffort": "none",
                "conversationReuse": True,
                "maximumOutputTokens": 1024,
                "userPromptGenerator": "chess-native-v13",
            },
        ]
        records = []
        grades = []
        cases = (("q1", "q1", 1, "quiet"), ("s1-1", "s1", 1, "interaction"), ("s1-2", "s1", 2, "interaction"), ("s1-3", "s1", 3, "interaction"))
        baseline_scores = (4, 5, 3, 1)
        candidate_scores = (5, 5, 5, 2)
        baseline_valid = (True, True, True, False)
        candidate_valid = (True, True, True, True)
        baseline_latency = (1000, 2000, 3000, 4000)
        candidate_latency = (800, 1200, 1800, 2500)
        for configuration_id, score_values, valid_values, latencies, input_tokens in (
            ("baseline", baseline_scores, baseline_valid, baseline_latency, 100),
            ("candidate", candidate_scores, candidate_valid, candidate_latency, 25),
        ):
            for (case_id, group_id, step_index, category), score, valid, latency in zip(cases, score_values, valid_values, latencies):
                cell_id = f"{configuration_id}|{case_id}|r1"
                status = "completed" if valid else "httpError"
                usage = {
                    "inputTokens": input_tokens if valid else 0,
                    "cachedInputTokens": 10 if valid else 0,
                    "outputTokens": 10 if case_id == "q1" and valid else 0,
                    "reasoningTokens": 2 if valid else 0,
                    "totalTokens": input_tokens + 10 if valid else 0,
                }
                records.append(
                    {
                        "cellID": cell_id,
                        "configurationID": configuration_id,
                        "caseID": case_id,
                        "groupID": group_id,
                        "stepIndex": step_index,
                        "split": "development",
                        "category": category,
                        "repetition": 1,
                        "generationStatus": status,
                        "providerHTTPStatus": None if valid else 502,
                        "mechanicalValidation": {"valid": valid, "categories": [] if valid else ["httpError"]},
                        "usage": usage,
                        "latencyMilliseconds": latency,
                        "attemptCount": 3 if configuration_id == "baseline" and case_id == "q1" else 1,
                        "candidateCostUSD": None,
                    }
                )
                flags = {flag: False for flag in RUBRIC_FLAGS}
                flags["severeError"] = not valid or (configuration_id == "candidate" and case_id == "s1-3")
                grades.append(
                    {
                        "schemaVersion": "coaching-quality-absolute-grade.v1",
                        "cellID": cell_id,
                        "disposition": "judged" if valid else "unusable",
                        "scores": {dimension: score for dimension in RUBRIC_DIMENSIONS},
                        "flags": flags,
                        "evidence": ["Synthetic benchmark evidence."],
                        "judgeMetrics": self.metrics(1 if valid else 0),
                    }
                )
        records_bytes = self.jsonl(records)
        (run_root / "records.jsonl").write_bytes(records_bytes)
        run_manifest = {
            "schemaVersion": "coaching-quality-candidate-run.v1",
            "mode": "comparison",
            "diagnosticSubset": False,
            "includeHoldout": False,
            "corpusSHA256": "c" * 64,
            "sourceGitSHA": "source",
            "configurations": configurations,
            "recordIDs": [record["cellID"] for record in records],
            "recordsSHA256": self.sha(records_bytes),
            "summary": {"recordCount": 8, "validCount": 7, "failedCount": 1},
        }
        (run_root / "run-manifest.json").write_text(json.dumps(run_manifest))

        pairs = []
        outcomes = ("candidateWin", "tie", "candidateWin", "candidateWin")
        for (case_id, _group_id, _step, _category), outcome in zip(cases, outcomes):
            pairs.append(
                {
                    "schemaVersion": "coaching-quality-pairwise-grade.v1",
                    "pairID": f"candidate|{case_id}|r1|vs|baseline",
                    "outcome": outcome,
                    "candidatePresentedAs": "A",
                    "evidence": ["Synthetic pair evidence."],
                    "judgeMetrics": self.metrics(0 if case_id == "s1-3" else 1),
                }
            )
        calibration = {
            "schemaVersion": "coaching-quality-calibration-result.v1",
            "passed": True,
            "severeAgreement": 1.0,
            "dimensionWithinOne": 1.0,
            "rowCount": 20,
            "calibrationSHA256": "d" * 64,
            "judgeMetrics": self.metrics(20),
        }
        absolute_bytes = self.jsonl(grades)
        pairwise_bytes = self.jsonl(pairs)
        calibration_bytes = self.pretty(calibration)
        (grade_root / "absolute-grades.jsonl").write_bytes(absolute_bytes)
        (grade_root / "pairwise-grades.jsonl").write_bytes(pairwise_bytes)
        (grade_root / "calibration.json").write_bytes(calibration_bytes)
        grade_manifest = {
            "schemaVersion": "coaching-quality-grade-run.v1",
            "sourceRunRecordsSHA256": self.sha(records_bytes),
            "corpusSHA256": "c" * 64,
            "judgeConfigurationSHA256": "e" * 64,
            "judgePromptSHA256": "f" * 64,
            "absoluteSchemaSHA256": "1" * 64,
            "pairwiseSchemaSHA256": "2" * 64,
            "calibrationSHA256": self.sha(calibration_bytes),
            "absoluteGradesSHA256": self.sha(absolute_bytes),
            "pairwiseGradesSHA256": self.sha(pairwise_bytes),
            "absoluteGradeCount": len(grades),
            "pairwiseGradeCount": len(pairs),
        }
        (grade_root / "grade-manifest.json").write_text(json.dumps(grade_manifest))
        return run_root, grade_root

    def metrics(self, calls):
        return {
            "callCount": calls,
            "usage": {
                "inputTokens": 100 * calls,
                "cachedInputTokens": 10 * calls,
                "outputTokens": 20 * calls,
                "reasoningTokens": 5 * calls,
                "totalTokens": 120 * calls,
            },
            "latencyMilliseconds": 100 * calls,
            "estimatedCostUSD": str(0.01 * calls),
        }

    @staticmethod
    def jsonl(values):
        return b"".join(json.dumps(value, sort_keys=True, separators=(",", ":")).encode() + b"\n" for value in values)

    @staticmethod
    def pretty(value):
        return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()

    @staticmethod
    def sha(value):
        return hashlib.sha256(value).hexdigest()


if __name__ == "__main__":
    unittest.main()

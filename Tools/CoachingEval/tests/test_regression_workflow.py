import hashlib
import json
import unittest
from pathlib import Path
from unittest import mock

from Tools.CoachingEval.benchmark.regression import RegressionEvaluation
from Tools.CoachingEval.tests import test_benchmark_runner as fixtures


ROOT = Path(__file__).resolve().parents[3]


class RegressionWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.BenchmarkRunnerTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.tearDown)
        self.root = self.fixture.root
        self.regression = self.root / "regression-corpus"
        self.regression.mkdir()
        raw = list(self.fixture.corpus.raw_cases[:8])
        data = b"".join(json.dumps(r).encode() + b"\n" for r in raw)
        (self.regression / "cases.jsonl").write_bytes(data)
        manifest = dict(schemaVersion="coaching-quality-playthrough-regression-manifest.v1",
                        sourceGitSHA="source", independentGroupCount=8, sequenceGroupCount=0,
                        turnCount=8, developmentTurnCount=8, holdoutTurnCount=0,
                        turnIDs=[r["id"] for r in raw], casesSHA256=hashlib.sha256(data).hexdigest())
        (self.regression / "benchmark-manifest.json").write_text(json.dumps(manifest))

    def run_workflow(self, output):
        return RegressionEvaluation.run(repository_root=ROOT, corpus_path=self.fixture.corpus.root,
            regression_path=self.regression, output=output, client=mock.Mock(),
            qualification_root=self.root / "qualifications", max_cost="10")

    def test_failed_sensitivity_prevents_candidate_spending_and_retains_status(self):
        output = self.root / "output"
        with mock.patch("Tools.CoachingEval.benchmark.regression.JudgeQualification.ensure", return_value=self.root / "qualification.json"), \
             mock.patch("Tools.CoachingEval.benchmark.regression.JudgeSensitivity.run", return_value={"passed": False}), \
             mock.patch("Tools.CoachingEval.benchmark.regression.run_candidates") as candidates:
            result = self.run_workflow(output)
        self.assertEqual("judgeSensitivityFailed", result["status"])
        candidates.assert_not_called()
        self.assertEqual(result, json.loads((output / "evaluation.json").read_text()))
        with self.assertRaises(FileExistsError):
            self.run_workflow(output)

    def test_both_suites_use_current_config_three_repetitions_and_separate_reports(self):
        output = self.root / "output"
        reports = []
        def report(run, grades, prices, destination):
            destination.mkdir(parents=True)
            aggregate = destination / "aggregate.json"
            aggregate.write_text(json.dumps({"integrityIssues": [], "configurations": {}}))
            summary = destination / "summary.md"
            summary.write_text("report")
            reports.append(destination)
            return aggregate, summary
        with mock.patch("Tools.CoachingEval.benchmark.regression.JudgeQualification.ensure", return_value=self.root / "qualification.json"), \
             mock.patch("Tools.CoachingEval.benchmark.regression.JudgeSensitivity.run", return_value={"passed": True}), \
             mock.patch("Tools.CoachingEval.benchmark.regression.run_candidates") as candidates, \
             mock.patch("Tools.CoachingEval.benchmark.regression.grade_run") as grades, \
             mock.patch("Tools.CoachingEval.benchmark.regression.write_report", side_effect=report):
            result = self.run_workflow(output)
        self.assertEqual("completed", result["status"])
        self.assertEqual(2, candidates.call_count)
        self.assertEqual(2, grades.call_count)
        for call in candidates.call_args_list:
            self.assertEqual("regression", call.kwargs["mode"])
            self.assertEqual("astra-discovery-v2-low", call.kwargs["configurations"][0].identifier)
            self.assertFalse(call.kwargs["include_holdout"])
        self.assertEqual({"benchmark", "playthrough"}, {p.parent.name for p in reports})
        self.assertEqual(3, result["repetitions"])
        self.assertEqual(2, len(result["suites"]))

    def test_interruption_keeps_manifest_and_no_false_completed_claim(self):
        output = self.root / "interrupted"
        with mock.patch("Tools.CoachingEval.benchmark.regression.JudgeQualification.ensure", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                self.run_workflow(output)
        result = json.loads((output / "evaluation.json").read_text())
        self.assertEqual("interrupted", result["status"])
        self.assertEqual({}, result["suites"])

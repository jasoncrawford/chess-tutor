import hashlib
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from Tools.CoachingEval.benchmark.regression import RegressionEvaluation
from Tools.CoachingEval.benchmark.budget import BudgetExceeded
from Tools.CoachingEval.benchmark.grade_checkpoint import JudgeCheckpoint
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

    def run_workflow(self, output, **updates):
        return RegressionEvaluation.run(repository_root=ROOT, corpus_path=self.fixture.corpus.root,
            regression_path=self.regression, output=output, client=mock.Mock(),
            qualification_root=self.root / "qualifications", **dict({"max_cost": "10"}, **updates))

    def test_local_budget_refusal_is_not_a_failed_paid_qualification(self):
        output = self.root / "budget-stop"
        with self.assertRaises(BudgetExceeded):
            self.run_workflow(output, max_cost="0.000001")
        result = json.loads((output / "evaluation.json").read_text())
        self.assertEqual("budgetStopped", result["status"])
        self.assertEqual("0", result["conservativeCostOrReservationUSD"])
        self.assertEqual(0, result["unknownAccountingCalls"])
        self.assertFalse((self.root / "qualifications").exists())

    def test_saved_exports_record_separate_executing_source_provenance(self):
        with mock.patch("Tools.CoachingEval.benchmark.regression.JudgeQualification.ensure", return_value=self.root / "qualification.json"), \
             mock.patch("Tools.CoachingEval.benchmark.regression.JudgeSensitivity.run", return_value={"passed": False}):
            result = self.run_workflow(self.root / "provenance")
        self.assertEqual("source", result["sourceGitSHA"])
        execution = result["executionSource"]
        self.assertEqual(subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(), execution["gitSHA"])
        self.assertIsInstance(execution["dirty"], bool)
        sources = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                   for directory in ("CoachingServer", "Tools/CoachingEval")
                   for path in sorted((ROOT / directory).rglob("*.py"))}
        self.assertEqual(sources, execution["pythonFilesSHA256"])

    def test_tmp_override_reaches_real_checkpoint_without_symlink_failure(self):
        def grade(**arguments):
            with JudgeCheckpoint(arguments["checkpoint_path"], {"judgments": {}}, lambda *_: None):
                pass
            raise KeyboardInterrupt
        with tempfile.TemporaryDirectory(dir="/tmp") as temporary, \
             mock.patch("Tools.CoachingEval.benchmark.regression.JudgeQualification.ensure", return_value=self.root / "qualification.json"), \
             mock.patch("Tools.CoachingEval.benchmark.regression.JudgeSensitivity.run", return_value={"passed": True}), \
             mock.patch("Tools.CoachingEval.benchmark.regression.run_candidates"), \
             mock.patch("Tools.CoachingEval.benchmark.regression.grade_run", side_effect=grade):
            with self.assertRaises(KeyboardInterrupt):
                self.run_workflow(Path(temporary) / "output")

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
            (destination.parent / "candidates.progress.jsonl").write_text(json.dumps(dict(
                configurationID="astra-discovery-v2-low", stepIndex=2, latencyMilliseconds=2100,
                mechanicalValidation={"valid": True},
                parsedTurn={"expects": "chooseWhetherToPlay", "message": "Keep this move?"},
            )) + "\n")
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
        metrics = result["experienceMetrics"]["benchmark"]["astra-discovery-v2-low"]
        self.assertEqual(1, metrics["followUp"]["count"])
        self.assertEqual(1, metrics["confirmationQuestionCount"])

    def test_experience_gate_is_required_before_any_candidate_calls(self):
        with mock.patch("Tools.CoachingEval.benchmark.regression.JudgeQualification.ensure", return_value=self.root / "qualification.json"), \
             mock.patch("Tools.CoachingEval.benchmark.regression.JudgeSensitivity.run", side_effect=[{"passed": True}, {"passed": False}]) as gate, \
             mock.patch("Tools.CoachingEval.benchmark.regression.run_candidates") as candidates:
            result = self.run_workflow(self.root / "experience-gate", experience_path=self.regression)
        self.assertEqual("judgeSensitivityFailed", result["status"])
        self.assertFalse(result["experienceSensitivityPassed"])
        gated_controls = json.loads(gate.call_args_list[1].args[0].read_text())
        self.assertTrue(any(row["id"] == "omitted-stalemate-warning" for row in gated_controls["cases"]))
        self.assertIn("experience", result["corpora"])
        candidates.assert_not_called()

    def test_experience_suite_runs_first_after_both_gates(self):
        with mock.patch("Tools.CoachingEval.benchmark.regression.JudgeQualification.ensure", return_value=self.root / "qualification.json"), \
             mock.patch("Tools.CoachingEval.benchmark.regression.JudgeSensitivity.run", return_value={"passed": True}) as gate, \
             mock.patch("Tools.CoachingEval.benchmark.regression.run_candidates", side_effect=KeyboardInterrupt) as candidates:
            with self.assertRaises(KeyboardInterrupt):
                self.run_workflow(self.root / "experience-first", experience_path=self.regression)
        self.assertEqual(2, gate.call_count)
        self.assertEqual("experience", candidates.call_args.kwargs["destination"].parent.name)

    def test_interruption_keeps_manifest_and_no_false_completed_claim(self):
        output = self.root / "interrupted"
        with mock.patch("Tools.CoachingEval.benchmark.regression.JudgeQualification.ensure", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                self.run_workflow(output)
        result = json.loads((output / "evaluation.json").read_text())
        self.assertEqual("interrupted", result["status"])
        self.assertEqual({}, result["suites"])

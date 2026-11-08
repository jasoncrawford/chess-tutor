import json
import unittest
from pathlib import Path
from unittest import mock

from Tools.CoachingEval.benchmark.experience import ExperienceEvaluation
from Tools.CoachingEval.benchmark.experience_metrics import ExperienceMetrics
from Tools.CoachingEval.benchmark.budget import BudgetedClient, BudgetExceeded
from Tools.CoachingEval.benchmark.configuration import load_prices
from Tools.CoachingEval.tests import test_regression_workflow as fixtures
from Tools.CoachingEval.tests.test_benchmark_runner import FakeClient
from Tools.CoachingEval.openai_responses import OpenAIResponsesError


ROOT = Path(__file__).resolve().parents[3]


class ExperienceEvaluationTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.RegressionWorkflowTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.root = self.fixture.root
        self.controls = ROOT / "Tools/CoachingEval/benchmark/judge-experience-v1.json"

    def run_workflow(self, output, **kwargs):
        client = kwargs.pop("client", mock.Mock())
        return ExperienceEvaluation.run(repository_root=ROOT, corpus_path=self.fixture.regression,
            candidate_paths=[ROOT / "Tools/CoachingEval/benchmark/configs/astra-discovery-v2-low.json"],
            controls_path=self.controls, output=output, client=client,
            qualification_path=self.root / "qualification.json", journal=self.root / "budget.jsonl",
            **kwargs)

    def test_failed_sensitivity_prevents_generation_and_output_is_immutable(self):
        with mock.patch("Tools.CoachingEval.benchmark.experience.JudgeQualification.load_compatible"), \
             mock.patch("Tools.CoachingEval.benchmark.experience.JudgeSensitivity.run", return_value={"passed": False}):
            result = self.run_workflow(self.root / "failed")
        self.assertEqual("judgeSensitivityFailed", result["status"])
        self.assertFalse((self.root / "failed/candidates").exists())
        self.assertEqual("0", result["conservativeCostOrReservationUSD"])
        with self.assertRaises(FileExistsError):
            self.run_workflow(self.root / "failed")

    def test_changed_sensitivity_binding_is_rejected_before_spending(self):
        saved = self.root / "sensitivity.json"
        saved.write_text(json.dumps({"passed": True, "corpusSHA256": "wrong"}))
        with mock.patch("Tools.CoachingEval.benchmark.experience.JudgeQualification.load_compatible"):
            with self.assertRaises(ValueError):
                self.run_workflow(self.root / "changed", sensitivity_path=saved)
        self.assertFalse((self.root / "budget.jsonl").exists())

    def test_budget_stop_is_recorded_without_provider_transmission(self):
        def spend(_controls, _corpus, judge, client, _prices, _destination):
            client.complete(model=judge.model, system_prompt="test", user_prompt="test",
                            schema={}, maximum_output_tokens=2000)
        with mock.patch("Tools.CoachingEval.benchmark.experience.JudgeQualification.load_compatible"), \
             mock.patch("Tools.CoachingEval.benchmark.experience.JudgeSensitivity.run", side_effect=spend):
            with self.assertRaises(BudgetExceeded):
                self.run_workflow(self.root / "budget-stop", max_cost="0.000001")
        saved = json.loads((self.root / "budget-stop/evaluation.json").read_text())
        self.assertEqual("budgetStopped", saved["status"])
        self.assertEqual(0, saved["unknownAccountingCalls"])

    def test_prior_phase_spend_is_retained_in_the_shared_budget(self):
        prices = load_prices(ROOT / "Tools/CoachingEval/benchmark/pricing-v2.json")
        provider = mock.Mock()
        provider.complete.return_value = dict(output_text="{}", usage=dict(
            input_tokens=1000, cached_input_tokens=0, output_tokens=100,
            reasoning_tokens=0, total_tokens=1100))
        previous = BudgetedClient(provider, prices, self.root / "budget.jsonl", "10")
        previous.complete(model="gpt-6-astra", system_prompt="old", user_prompt="old", schema={}, maximum_output_tokens=100)
        with mock.patch("Tools.CoachingEval.benchmark.experience.JudgeQualification.load_compatible"), \
             mock.patch("Tools.CoachingEval.benchmark.experience.JudgeSensitivity.run", return_value={"passed": False}):
            result = self.run_workflow(self.root / "next")
        self.assertEqual(str(previous.spent), result["startingCostUSD"])
        self.assertEqual(str(previous.spent), result["conservativeCostOrReservationUSD"])

    def test_metrics_separate_followups_preserve_failures_and_count_repeated_closings(self):
        def record(latency, step, text, valid=True):
            return dict(configurationID="candidate", stepIndex=step, latencyMilliseconds=latency,
                        generationStatus="completed" if valid else "providerError",
                        mechanicalValidation={"valid": valid},
                        parsedTurn=dict(message=text, expects="chooseWhetherToPlay") if valid else None)
        rows = [record(6000, 1, "A useful fact. Keep this move?"),
                record(2000, 2, "Another fact. Keep this move?"),
                record(4000, 3, "You can play this or try another."),
                record(30000, 1, "", False)]
        stats = ExperienceMetrics.summarize(rows, {"candidate": True})["candidate"]
        self.assertEqual(2, stats["fresh"]["count"])
        self.assertEqual(1, stats["followUp"]["overTargetCount"])
        self.assertEqual(3000, stats["followUp"]["medianMilliseconds"])
        self.assertEqual(1, stats["failedOrInvalidCount"])
        self.assertEqual(2, stats["confirmationQuestionCount"])
        self.assertEqual(2, stats["mostRepeatedConfirmationEndingCount"])
        self.assertEqual(3, stats["confirmationTurnCount"])
        no_reuse = ExperienceMetrics.summarize(rows, {"candidate": False})["candidate"]
        self.assertEqual(4, no_reuse["fresh"]["count"])
        self.assertEqual(0, no_reuse["followUp"]["count"])

    def test_actual_provider_failure_retains_case_timing_and_partial_metrics(self):
        client = FakeClient(failures=[OpenAIResponsesError("secret", category="timeout")])
        with mock.patch("Tools.CoachingEval.benchmark.experience.JudgeQualification.load_compatible"), \
             mock.patch("Tools.CoachingEval.benchmark.experience.JudgeSensitivity.run", return_value={"passed": True}):
            with self.assertRaisesRegex(RuntimeError, "Provider failed"):
                self.run_workflow(self.root / "timeout", client=client)
        saved = json.loads((self.root / "timeout/evaluation.json").read_text())
        self.assertEqual("stopped", saved["status"])
        stats = saved["experienceMetrics"]["astra-discovery-v2-low"]
        self.assertEqual(1, stats["failedOrInvalidCount"])
        self.assertEqual(1, stats["fresh"]["count"])
        self.assertEqual(1, saved["unknownAccountingCalls"])
        self.assertEqual(1, len(client.calls))

    def test_tone_diagnostics_count_exclamations_only_in_valid_visible_messages(self):
        rows = [dict(configurationID="candidate", stepIndex=1,
                     generationStatus="completed", mechanicalValidation={"valid": valid},
                     parsedTurn={"message": text, "expects": "chooseWhetherToPlay"})
                for text, valid in [("Great! Your bishop can come out!", True),
                                    ("Your pawn opens a path for your bishop.", True),
                                    ("Invalid!", False)]]
        stats = ExperienceMetrics.summarize(rows, {"candidate": True})["candidate"]
        self.assertEqual(2, stats["validMessageCount"])
        self.assertEqual(1, stats["exclamatoryMessageCount"])
        self.assertEqual(2, stats["exclamationMarkCount"])

    def test_blocked_sequence_rows_are_not_zero_latency_requests(self):
        rows = [dict(configurationID="candidate", stepIndex=2, latencyMilliseconds=0,
                     generationStatus="blockedByPriorTurn", attemptCount=0,
                     mechanicalValidation={"valid": False}, parsedTurn=None)]
        stats = ExperienceMetrics.summarize(rows, {"candidate": True})["candidate"]
        self.assertEqual(0, stats["followUp"]["count"])
        self.assertEqual(1, stats["blockedCount"])


if __name__ == "__main__":
    unittest.main()

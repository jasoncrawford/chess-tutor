import json
from pathlib import Path
import unittest
import tempfile
from types import SimpleNamespace
from unittest.mock import Mock, patch

from Tools.CoachingEval.benchmark.visual_metrics import VisualMetrics
from Tools.CoachingEval.benchmark.experience_metrics import ExperienceMetrics
from Tools.CoachingEval.benchmark.grader import _available_ui, readable_turn
from CoachingServer.chess_native_compiler import compile_visual_context, compile_visual_follow_up_context
from Tools.CoachingEval.benchmark.visual_evaluation import run


class VisualBenchmarkTests(unittest.TestCase):
    def test_visual_export_is_free_paid_calls_require_cap_and_saved_run_is_not_replayed(self):
        root = Path(__file__).resolve().parents[3]
        request = json.loads((root / "Tools/CoachingEval/fixtures/visual-coaching-validation-v1.json").read_text())["requests"]["normal"]
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            manifest = directory / "manifest.json"
            manifest.write_text(json.dumps({"schemaVersion": "coaching-quality-visual-regression-manifest.v1"}))
            corpus = SimpleNamespace(manifest_path=manifest, turns=[SimpleNamespace(identifier="test", request=request)])
            client = Mock()
            with patch("Tools.CoachingEval.benchmark.visual_evaluation.load_corpus", return_value=corpus):
                for cap in (None, "0", "-1", "NaN"):
                    with self.assertRaises(ValueError):
                        run(directory, directory / "paid", client=client, max_cost=cap)
                    client.complete.assert_not_called()
                    self.assertFalse((directory / "paid").exists())
                result = run(directory, directory / "free")
                self.assertEqual(0, result["paidCalls"])
                self.assertTrue((directory / "free/prompts.json").is_file())
                with self.assertRaises(FileExistsError):
                    run(directory, directory / "free", client=client, max_cost="10")
                client.complete.assert_not_called()

    def test_native_optional_fields_may_be_omitted_in_both_compilers(self):
        root = Path(__file__).resolve().parents[3]
        request = json.loads((root / "Tools/CoachingEval/fixtures/visual-coaching-validation-v1.json").read_text())["requests"]["normal"]
        del request["interaction"]["tentativeMove"]
        for compiler in (compile_visual_context, compile_visual_follow_up_context):
            self.assertIn("Displayed board references", compiler(request, "tutor-v14").markdown)

    def test_judge_sees_readable_words_and_exact_visual_mapping_without_mutation(self):
        turn = {"message": [{"type": "piece", "text": "Your knight", "square": "h3"},
                            {"type": "text", "text": " can try here."}], "actions": [],
                "visuals": [{"type": "move", "from": "g1", "to": "f3"}], "expects": "chooseWhetherToPlay"}
        payload = readable_turn(turn)
        self.assertEqual("Your knight can try here.", payload["message"])
        self.assertEqual(turn["message"], payload["messageRuns"])
        self.assertEqual(turn["visuals"], payload["visuals"])
        self.assertIsInstance(turn["message"], list)
        row = dict(configurationID="visual", stepIndex=1, parsedTurn=turn,
                   mechanicalValidation={"valid": True}, latencyMilliseconds=30)
        stats = ExperienceMetrics.summarize([row], {"visual": True})
        self.assertEqual(1, stats["visual"]["validMessageCount"])
        metrics = VisualMetrics.summarize([row])["visual"]
        self.assertEqual(1, metrics["linkedReferenceCount"])
        self.assertEqual(1, metrics["arrowCount"])
        self.assertEqual(0, metrics["coordinateMentionCount"])
        self.assertEqual(["hint"], _available_ui(row)["actions"])

    def test_plain_baseline_is_not_counted_as_failed_visual_capability(self):
        turn = {"message": "Try the middle.", "focus": [], "actions": ["hint"], "expects": "stageMove"}
        row = dict(configurationID="legacy", parsedTurn=turn, mechanicalValidation={"valid": True})
        self.assertEqual(turn, readable_turn(turn))
        self.assertEqual(1, VisualMetrics.summarize([row])["legacy"]["visualCapabilityUnavailableCount"])


import json
import copy
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
from Tools.CoachingEval.benchmark.configuration import load_candidate, load_prices
from Tools.CoachingEval.benchmark.runner import preview_prompts


class VisualBenchmarkTests(unittest.TestCase):
    def test_dry_prompts_use_the_actual_followup_compiler(self):
        root = Path(__file__).resolve().parents[3]
        request = json.loads((root / "Tools/CoachingEval/fixtures/visual-coaching-validation-v1.json").read_text())["requests"]["normal"]
        corpus = SimpleNamespace(turns=[SimpleNamespace(identifier=f"s{i}", group_id="sequence", step_index=i, request=request)
                                        for i in (1, 2, 3)])
        candidate = load_candidate(root / "Tools/CoachingEval/benchmark/configs/astra-visual-v3-low.json", root)
        prices = load_prices(root / "Tools/CoachingEval/benchmark/pricing-v2.json")
        prompts = preview_prompts(corpus, candidate, prices)
        self.assertEqual("initial", prompts[0]["kind"])
        self.assertEqual("followUp", prompts[1]["kind"])
        self.assertEqual(compile_visual_follow_up_context(request, "tutor-v14").markdown, prompts[1]["user"])
    def test_visual_answer_uses_latest_tap_not_old_mover_selection(self):
        root = Path(__file__).resolve().parents[3]
        fixtures = json.loads((root / "Tools/CoachingEval/fixtures/visual-coaching-validation-v1.json").read_text())
        request = copy.deepcopy(fixtures["requests"]["normal"])
        request["interaction"]["selectedPieceReference"] = "piece:black:king:e8"
        for compiler in (compile_visual_context, compile_visual_follow_up_context):
            prompt = compiler(request, "tutor-v14").markdown
            self.assertIn("selected the knight on b1", prompt)
            self.assertNotIn("selected the king on e8", prompt)

    def test_visual_answer_resolves_staged_location_not_committed_origin(self):
        root = Path(__file__).resolve().parents[3]
        fixtures = json.loads((root / "Tools/CoachingEval/fixtures/visual-coaching-validation-v1.json").read_text())
        request = copy.deepcopy(fixtures["requests"]["staged"])
        request["interaction"]["latestEvent"] = dict(sequence=3, kind="pieceSelected", referencedIDs=["piece:white:knight:a3"])
        request["interaction"]["episodeEvents"].append(request["interaction"]["latestEvent"])
        for compiler in (compile_visual_context, compile_visual_follow_up_context):
            self.assertIn("selected the knight on a3", compiler(request, "tutor-v14").markdown)

    def test_move_hint_acceptance_requires_directional_arrow_not_just_linked_endpoints(self):
        row = dict(cellID="visual|v05-draft-revision|r1", caseID="v05-draft-revision",
                   parsedTurn=dict(message=[dict(type="piece", text="Your knight", square="h3"),
                                           dict(type="square", text="here", square="f3")], visuals=[]))
        self.assertEqual([row["cellID"]], VisualMetrics.missing_move_arrows([row], {"v05-draft-revision"}))
        row["parsedTurn"]["visuals"] = [dict(type="move", **{"from": "g1", "to": "f3"})]
        self.assertEqual([], VisualMetrics.missing_move_arrows([row], {"v05-draft-revision"}))

    def test_visual_export_is_free_paid_calls_require_cap_and_saved_run_is_not_replayed(self):
        root = Path(__file__).resolve().parents[3]
        request = json.loads((root / "Tools/CoachingEval/fixtures/visual-coaching-validation-v1.json").read_text())["requests"]["normal"]
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            manifest = directory / "manifest.json"
            manifest.write_text(json.dumps({"schemaVersion": "coaching-quality-visual-regression-manifest.v1"}))
            corpus = SimpleNamespace(manifest_path=manifest, turns=[SimpleNamespace(identifier="test", request=request, group_id="test", step_index=1)])
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


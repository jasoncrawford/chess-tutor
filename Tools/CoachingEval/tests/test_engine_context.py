import hashlib
import json
import unittest
from dataclasses import replace
from types import SimpleNamespace

from Tools.CoachingEval.benchmark.engine_context import EngineContext
from Tools.CoachingEval.benchmark.runner import _preflight, _base_record
from Tools.CoachingEval.tests import test_benchmark_runner as fixtures


class EngineContextTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.BenchmarkRunnerTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.tearDown)
        self.turn = self.fixture.corpus.turns[0]
        self.corpus = replace(self.fixture.corpus, turns=(self.turn,))
        request = self.turn.request
        self.analysis = dict(positionFEN=request["position"]["fen"], sideToMove="white", historyMode="fullGame",
            draft=(request["interaction"].get("tentativeMove") or {}).get("canonicalMove"),
            analysisMilliseconds=240.0, candidates=[dict(move="b1c3", score={"centipawns": 25},
            line=["b1c3"], notation=["Nc3"], depth=12, nodes=200000)], proposed=None)
        self.data = dict(schemaVersion="coaching-engine-evidence.v1", corpusSHA256=self.corpus.sha256,
            metadata=dict(engine="Stockfish 18", binarySHA256="a" * 64, libraryVersion="1.11.2",
                          threads=1, hashMB=64, nodesPerSearch=200000, multiPV=3, maximumLinePlies=5),
            entries=[dict(caseID=self.turn.identifier, requestSHA256=hashlib.sha256(json.dumps(request,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()).hexdigest(), analysis=self.analysis)])
        self.path = self.fixture.root / "engine.json"

    def save(self):
        self.path.write_text(json.dumps(self.data))

    def test_runner_logs_exact_augmented_prompt_and_binds_engine_identity(self):
        self.save()
        context = EngineContext(self.path, self.corpus)
        old = _preflight([self.fixture.configuration], (self.turn,), 1, self.fixture.prices)[0]
        cell = _preflight([self.fixture.configuration], (self.turn,), 1, self.fixture.prices, engine_context=context)[0]
        row = _base_record(cell)
        self.assertTrue(row["userPrompt"].startswith(old["compilation"].markdown))
        self.assertIn("Stockfish 18", row["userPrompt"])
        self.assertIn("+0.25", row["userPrompt"])
        self.assertIn("not forced", row["userPrompt"])
        self.assertEqual(context.sha256, row["engineEvidenceSHA256"])
        self.assertEqual(240.0, row["engineAnalysisMilliseconds"])
        self.assertNotEqual(_base_record(old)["userPromptSHA256"], row["userPromptSHA256"])
        self.assertNotIn(self.turn.grader_brief.coaching_purpose, row["userPrompt"])

    def test_evidence_for_different_request_is_rejected_before_generation(self):
        self.data["entries"][0]["requestSHA256"] = "b" * 64
        self.save()
        with self.assertRaises(ValueError):
            EngineContext(self.path, self.corpus)

    def test_mate_distance_is_distinct_from_pawn_score(self):
        self.analysis["candidates"][0]["score"] = {"mate": -3}
        self.save()
        context = EngineContext(self.path, self.corpus)
        cell = _preflight([self.fixture.configuration], (self.turn,), 1, self.fixture.prices, engine_context=context)[0]
        self.assertIn("opponent can mate in 3", cell["compilation"].markdown)
        self.assertNotIn("-0.03", cell["compilation"].markdown)

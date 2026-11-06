import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from Tools.CoachingEval.benchmark.judge_contract import RUBRIC_DIMENSIONS, RUBRIC_FLAGS
from Tools.CoachingEval.benchmark.sensitivity import JudgeSensitivity
from Tools.CoachingEval.tests import test_benchmark_runner as fixtures


class JudgeSensitivityTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.BenchmarkRunnerTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.tearDown)
        self.root = self.fixture.root
        self.turn = self.fixture.corpus.turns[0]
        self.judge = SimpleNamespace(system_prompt="Judge", model="gpt-5.6-sol",
                                    reasoning_effort="low", maximum_output_tokens=100, timeout_seconds=10,
                                    sha256="judge", system_prompt_sha256="prompt")
        self.row = dict(id="known-bad", caseID=self.turn.identifier, source={"file": "retained.jsonl"},
            position=dict(id=self.turn.identifier, fen=self.turn.request["position"]["fen"], move=None,
                          event=self.turn.request["interaction"]["latestEvent"]["kind"]),
            candidateTurn=dict(message="Invented fact", actions=[], focus=[], expects="stageMove"),
            scores={"chessCorrectness": {"max": 2}}, flags={"factualOrIllegalAdvice": True})
        self.path = self.root / "controls.json"
        self.path.write_text(json.dumps(dict(schemaVersion="coaching-judge-sensitivity.v1",
                                            provenance="Test expectations", cases=[self.row])))

    def client(self, score):
        calls = []
        class Client:
            def complete(inner, **kwargs):
                calls.append(kwargs)
                output = dict(scores={d: score for d in RUBRIC_DIMENSIONS},
                              flags={f: f == "factualOrIllegalAdvice" for f in RUBRIC_FLAGS},
                              evidence=["Checked the supplied facts."])
                return dict(output_text=json.dumps(output), usage=dict(input_tokens=10,
                            cached_input_tokens=0, output_tokens=10, reasoning_tokens=0, total_tokens=20))
        return Client(), calls

    def test_retained_bad_answer_must_be_rejected_every_time_and_expectations_stay_private(self):
        client, calls = self.client(5)
        result = JudgeSensitivity.run(self.path, self.fixture.corpus, self.judge, client,
                                      self.fixture.prices, self.root / "checks")
        self.assertFalse(result["passed"])
        self.assertEqual(3, len(result["rows"]))
        self.assertTrue(all(not row["passed"] for row in result["rows"]))
        payload = json.loads(calls[0]["user_prompt"])
        self.assertEqual("Invented fact", payload["candidateTurn"]["message"])
        self.assertNotIn("scores", payload)
        self.assertNotIn("known-bad", calls[0]["user_prompt"])
        self.assertIn("judgeContext", payload)
        self.assertTrue((self.root / "checks/result.json").is_file())

    def test_matching_grade_passes_and_changed_position_is_rejected_before_spending(self):
        client, calls = self.client(2)
        result = JudgeSensitivity.run(self.path, self.fixture.corpus, self.judge, client,
                                      self.fixture.prices, self.root / "checks")
        self.assertTrue(result["passed"])
        with self.assertRaises(FileExistsError):
            JudgeSensitivity.run(self.path, self.fixture.corpus, self.judge, client,
                                 self.fixture.prices, self.root / "checks")
        raw = json.loads(self.path.read_text())
        raw["cases"][0]["position"]["fen"] = "wrong position"
        self.path.write_text(json.dumps(raw))
        with self.assertRaises(ValueError):
            JudgeSensitivity.run(self.path, self.fixture.corpus, self.judge, client,
                                 self.fixture.prices, self.root / "changed")
        self.assertEqual(3, len(calls))

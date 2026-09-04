import json
import hashlib
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path

from CoachingServer.model_configuration import HostedModelConfiguration
from Tools.CoachingEval.benchmark.configuration import CandidateConfiguration
from Tools.CoachingEval.benchmark.corpus import (
    BenchmarkCorpus,
    BenchmarkGraderBrief,
    BenchmarkTurn,
)
from Tools.CoachingEval.benchmark.runner import run_candidates
from Tools.CoachingEval.openai_responses import OpenAIResponsesError


ROOT = Path(__file__).resolve().parents[3]


class FakeClient:
    def __init__(self, failures=None):
        self.calls = []
        self.failures = list(failures or [])

    def complete(self, **arguments):
        self.calls.append(arguments)
        if self.failures:
            failure = self.failures.pop(0)
            if failure is not None:
                raise failure
        schema = arguments["schema"]
        turn = {"message": "What do you notice?", "actions": [], "focus": []}
        if "expects" in schema["required"]:
            turn["expects"] = schema["properties"]["expects"]["enum"][0]
        index = len(self.calls)
        return {
            "id": f"resp_{index}",
            "model": "gpt-5.6-sol",
            "status": "completed",
            "output_text": json.dumps(turn, separators=(",", ":")),
            "usage": {
                "input_tokens": 100,
                "cached_input_tokens": 20,
                "output_tokens": 10,
                "reasoning_tokens": 4,
                "total_tokens": 110,
            },
        }


class BenchmarkRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.corpus = self.make_corpus()
        self.configuration = self.make_configuration()

    def tearDown(self):
        self.temporary.cleanup()

    def make_configuration(self, **changes):
        model_configuration = HostedModelConfiguration.load(
            ROOT / "CoachingServer/configs/production-v1.json",
            ROOT,
        )
        raw = {
            "schemaVersion": "coaching-quality-candidate.v2",
            "id": "production",
            "baseline": True,
            "modelConfigurationPath": "CoachingServer/configs/production-v1.json",
            "modelConfigurationSHA256": model_configuration.sha256,
            "pricingVersion": "test",
        }
        configuration = CandidateConfiguration(
            identifier="production",
            baseline=True,
            model_configuration_path=ROOT / "CoachingServer/configs/production-v1.json",
            model_configuration_sha256=model_configuration.sha256,
            model_configuration=model_configuration,
            pricing_version="test",
            sha256="b" * 64,
            raw=raw,
        )
        return replace(configuration, **changes)

    def make_corpus(self):
        request = json.loads(
            (ROOT / "Tools/CoachingEval/fixtures/chess-native-context-v1.json").read_text()
        )["request"]
        brief = BenchmarkGraderBrief(
            verified_facts=("Side to move: white.",),
            coaching_purpose="Coach one step.",
            acceptable_alternatives=("Any accurate answer.",),
            success_criteria=("Accurate.",),
            severe_failure_criteria=("Invents mate.",),
        )
        turns = []
        for index in range(1, 41):
            split = "development" if index <= 32 else "holdout"
            identifier = f"d-{index:02}"
            detached = json.loads(json.dumps(request))
            detached["requestID"] = f"benchmark:{identifier}"
            turns.append(BenchmarkTurn(identifier, identifier, 1, split, "quiet", detached, brief, None))
        for sequence_index in range(1, 11):
            split = "development" if sequence_index <= 8 else "holdout"
            group = f"s-{sequence_index:02}"
            for step in range(1, 4):
                identifier = f"{group}-{step:02}"
                detached = json.loads(json.dumps(request))
                detached["requestID"] = f"benchmark:{identifier}"
                if step == 2:
                    event = {
                        "sequence": 1,
                        "kind": "moveStaged",
                        "referencedIDs": ["move:b1-c3"],
                    }
                    detached["interaction"]["latestEvent"] = event
                    detached["interaction"]["episodeEvents"] = [event]
                elif step == 3:
                    event = {
                        "sequence": 1,
                        "kind": "moveRemoved",
                        "referencedIDs": ["move:b1-c3"],
                    }
                    detached["interaction"]["latestEvent"] = event
                    detached["interaction"]["episodeEvents"] = [event]
                turns.append(BenchmarkTurn(identifier, group, step, split, "interaction", detached, brief, None))
        return BenchmarkCorpus(self.root, "source", "c" * 64, tuple(turns), tuple())

    def test_quick_and_comparison_execute_exact_matrices(self):
        quick_client = FakeClient()
        quick = run_candidates(
            corpus=self.corpus,
            configurations=(self.configuration,),
            mode="quick",
            destination=self.root / "quick",
            provider_factory=lambda _configuration: quick_client,
        )
        self.assertEqual(56, len(quick_client.calls))
        self.assertEqual(56, quick["summary"]["recordCount"])

        comparison_client = FakeClient()
        alternative = replace(
            self.configuration,
            identifier="alternative",
            baseline=False,
            sha256="d" * 64,
        )
        comparison = run_candidates(
            corpus=self.corpus,
            configurations=(self.configuration, alternative),
            mode="comparison",
            destination=self.root / "comparison",
            provider_factory=lambda _configuration: comparison_client,
        )
        self.assertEqual(336, len(comparison_client.calls))
        self.assertEqual(336, comparison["summary"]["recordCount"])

    def test_sequences_use_follow_up_prompt_effort_and_previous_response(self):
        client = FakeClient()
        run_candidates(
            corpus=self.corpus,
            configurations=(self.configuration,),
            mode="quick",
            destination=self.root / "run",
            provider_factory=lambda _configuration: client,
        )

        sequence_calls = client.calls[32:35]
        self.assertIn("# Chess coaching situation", sequence_calls[0]["user_prompt"])
        self.assertEqual("high", sequence_calls[0]["reasoning_effort"])
        self.assertIsNone(sequence_calls[0]["previous_response_id"])
        self.assertIn("# Chess coaching update", sequence_calls[1]["user_prompt"])
        self.assertEqual("low", sequence_calls[1]["reasoning_effort"])
        self.assertEqual("resp_33", sequence_calls[1]["previous_response_id"])
        self.assertTrue(sequence_calls[1]["store"])
        self.assertEqual("none", sequence_calls[2]["reasoning_effort"])
        self.assertEqual("resp_34", sequence_calls[2]["previous_response_id"])
        self.assertTrue(sequence_calls[2]["store"])

        records = [
            json.loads(line)
            for line in (self.root / "run/records.jsonl").read_text().splitlines()
        ]
        for record in records:
            self.assertNotIn("providerResponseID", record)
            self.assertNotIn("previousResponseIDUsed", record)
        manifest = json.loads((self.root / "run/run-manifest.json").read_text())
        resolved = manifest["configurations"][0]
        self.assertEqual("high", resolved["initialReasoningEffort"])
        self.assertEqual("low", resolved["tacticalFollowUpReasoningEffort"])
        self.assertEqual("none", resolved["simpleFollowUpReasoningEffort"])
        self.assertTrue(resolved["store"])

        independent_runtime = replace(
            self.configuration.model_configuration,
            conversation_reuse=False,
            store=False,
        )
        independent = replace(
            self.configuration,
            model_configuration=independent_runtime,
            identifier="no-reuse",
            sha256="e" * 64,
        )
        independent_client = FakeClient()
        run_candidates(
            corpus=self.corpus,
            configurations=(independent,),
            mode="quick",
            destination=self.root / "independent",
            provider_factory=lambda _configuration: independent_client,
        )
        for call in independent_client.calls[32:35]:
            self.assertIn("# Chess coaching situation", call["user_prompt"])
            self.assertEqual("high", call["reasoning_effort"])
            self.assertIsNone(call["previous_response_id"])

    def test_invalid_sequence_step_blocks_later_steps(self):
        client = FakeClient()
        original_complete = client.complete

        def complete(**arguments):
            if len(client.calls) == 32:
                client.calls.append(arguments)
                return {
                    "id": "resp_bad",
                    "model": "gpt-5.6-sol",
                    "status": "completed",
                    "output_text": "{}",
                    "usage": {},
                }
            return original_complete(**arguments)

        client.complete = complete
        run_candidates(
            corpus=self.corpus,
            configurations=(self.configuration,),
            mode="quick",
            destination=self.root / "blocked",
            provider_factory=lambda _configuration: client,
        )
        records = [json.loads(line) for line in (self.root / "blocked/records.jsonl").read_text().splitlines()]
        sequence = [record for record in records if record["groupID"] == "s-01"]
        self.assertEqual(["invalid", "blockedByPriorTurn", "blockedByPriorTurn"], [record["generationStatus"] for record in sequence])
        self.assertEqual(54, len(client.calls))

    def test_preflights_every_cell_before_provider_and_refuses_unsafe_runs(self):
        broken = list(self.corpus.turns)
        broken[55] = replace(broken[55], request={"bad": True})
        broken_corpus = replace(self.corpus, turns=tuple(broken))
        factory_calls = []
        with self.assertRaises(ValueError):
            run_candidates(
                corpus=broken_corpus,
                configurations=(self.configuration,),
                mode="quick",
                destination=self.root / "broken",
                provider_factory=lambda configuration: factory_calls.append(configuration),
            )
        self.assertEqual([], factory_calls)

        with self.assertRaises(ValueError):
            run_candidates(
                corpus=self.corpus,
                configurations=(replace(self.configuration, baseline=False),),
                mode="comparison",
                destination=self.root / "missing-baseline",
                provider_factory=lambda _configuration: FakeClient(),
            )

        with self.assertRaises(ValueError):
            run_candidates(
                corpus=self.corpus,
                configurations=(self.configuration, self.configuration),
                mode="quick",
                destination=self.root / "duplicate-config",
                provider_factory=lambda _configuration: FakeClient(),
            )

    def test_rejects_reordered_loaded_corpus_and_changed_case_bytes(self):
        raw_cases = tuple({"id": turn.identifier} for turn in self.corpus.turns)
        reordered = list(self.corpus.turns)
        reordered[0], reordered[1] = reordered[1], reordered[0]
        with self.assertRaises(ValueError):
            run_candidates(
                corpus=replace(self.corpus, turns=tuple(reordered), raw_cases=raw_cases),
                configurations=(self.configuration,),
                mode="quick",
                destination=self.root / "reordered",
                provider_factory=lambda _configuration: FakeClient(),
            )

        artifact_root = self.root / "bound-corpus"
        artifact_root.mkdir()
        cases_path = artifact_root / "cases.jsonl"
        cases_path.write_bytes(b"original\n")
        bound = replace(
            self.corpus,
            root=artifact_root,
            sha256=hashlib.sha256(cases_path.read_bytes()).hexdigest(),
        )
        cases_path.write_bytes(b"changed\n")
        with self.assertRaisesRegex(ValueError, "changed"):
            run_candidates(
                corpus=bound,
                configurations=(self.configuration,),
                mode="quick",
                destination=self.root / "hash-drift",
                provider_factory=lambda _configuration: FakeClient(),
            )
        (self.root / "exists").mkdir()
        with self.assertRaises(ValueError):
            run_candidates(
                corpus=self.corpus,
                configurations=(self.configuration,),
                mode="quick",
                destination=self.root / "exists",
                provider_factory=lambda _configuration: FakeClient(),
            )

    def test_retries_only_when_configured_and_redacts_exception_text(self):
        client = FakeClient(
            failures=[OpenAIResponsesError("secret-provider-body", category="timeout")]
        )
        retrying = replace(
            self.configuration,
            model_configuration=replace(
                self.configuration.model_configuration,
                maximum_attempts=2,
            ),
        )
        run_candidates(
            corpus=self.corpus,
            configurations=(retrying,),
            mode="quick",
            destination=self.root / "retry",
            provider_factory=lambda _configuration: client,
        )
        first = json.loads((self.root / "retry/records.jsonl").read_text().splitlines()[0])
        self.assertEqual(2, first["attemptCount"])
        self.assertNotIn("secret-provider-body", json.dumps(first))

        production_client = FakeClient(
            failures=[OpenAIResponsesError("another-secret", category="timeout")]
        )
        run_candidates(
            corpus=self.corpus,
            configurations=(self.configuration,),
            mode="quick",
            destination=self.root / "one-attempt",
            provider_factory=lambda _configuration: production_client,
        )
        first = json.loads((self.root / "one-attempt/records.jsonl").read_text().splitlines()[0])
        self.assertEqual(1, first["attemptCount"])
        self.assertEqual("timeout", first["generationStatus"])
        self.assertNotIn("another-secret", (self.root / "one-attempt/records.jsonl").read_text())

    def test_preserves_bounded_http_status_without_provider_error_content(self):
        client = FakeClient(
            failures=[
                OpenAIResponsesError(
                    "secret-provider-body",
                    category="httpError",
                    http_status=502,
                )
            ]
        )
        run_candidates(
            corpus=self.corpus,
            configurations=(self.configuration,),
            mode="quick",
            destination=self.root / "http-failure",
            provider_factory=lambda _configuration: client,
        )

        records_text = (self.root / "http-failure/records.jsonl").read_text()
        first = json.loads(records_text.splitlines()[0])
        second = json.loads(records_text.splitlines()[1])
        self.assertEqual("httpError", first["generationStatus"])
        self.assertEqual(502, first["providerHTTPStatus"])
        self.assertIsNone(second["providerHTTPStatus"])
        self.assertNotIn("secret-provider-body", records_text)


if __name__ == "__main__":
    unittest.main()

import json
import hashlib
import io
import os
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from dataclasses import replace
from pathlib import Path
from types import MappingProxyType
from unittest import mock

from CoachingServer.service import HostedCoachingService
from Tools.CoachingEval.benchmark import cli
from Tools.CoachingEval.benchmark.configuration import (
    load_candidate,
    load_prices,
)
from Tools.CoachingEval.benchmark.corpus import (
    BenchmarkGraderBrief,
    BenchmarkTurn,
    load_corpus,
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
        self.configuration_counter = 0
        self.corpus_counter = 0
        self.corpus = self.make_corpus()
        self.configuration = self.make_configuration()
        self.prices = replace(
            load_prices(ROOT / "Tools/CoachingEval/benchmark/pricing-v1.json"),
            version="test",
        )

    def tearDown(self):
        self.temporary.cleanup()

    def make_configuration(
        self,
        *,
        identifier="production",
        baseline=True,
        pricing_version="test",
        model_changes=None,
    ):
        self.configuration_counter += 1
        repository_root = self.root / "configuration-repository"
        prompt_path = repository_root / "prompts/tutor-v13.md"
        prompt_path.parent.mkdir(parents=True, exist_ok=True)
        prompt_bytes = (
            ROOT / "Tools/CoachingEval/prompts/tutor-v13.md"
        ).read_bytes()
        prompt_path.write_bytes(prompt_bytes)
        model_raw = json.loads(
            (ROOT / "CoachingServer/configs/production-v1.json").read_text()
        )
        model_raw["systemPromptPath"] = "prompts/tutor-v13.md"
        model_raw.update(model_changes or {})
        model_relative = (
            f"model-configs/{identifier}-{self.configuration_counter}.json"
        )
        model_path = repository_root / model_relative
        model_path.parent.mkdir(parents=True, exist_ok=True)
        model_bytes = self.pretty(model_raw)
        model_path.write_bytes(model_bytes)
        raw = {
            "schemaVersion": "coaching-quality-candidate.v2",
            "id": identifier,
            "baseline": baseline,
            "modelConfigurationPath": model_relative,
            "modelConfigurationSHA256": hashlib.sha256(model_bytes).hexdigest(),
            "pricingVersion": pricing_version,
        }
        candidate_path = (
            repository_root
            / f"candidates/{identifier}-{self.configuration_counter}.json"
        )
        candidate_path.parent.mkdir(parents=True, exist_ok=True)
        candidate_path.write_bytes(self.pretty(raw))
        return load_candidate(candidate_path, repository_root)

    def make_corpus(self, *, invalid_request_index=None):
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
        raw_cases = tuple(self.raw_turn(turn) for turn in turns)
        if invalid_request_index is not None:
            raw_cases = list(raw_cases)
            raw_cases[invalid_request_index] = {
                **raw_cases[invalid_request_index],
                "request": {"bad": True},
            }
            raw_cases = tuple(raw_cases)
        self.corpus_counter += 1
        root = self.root / f"pinned-corpus-{self.corpus_counter}"
        root.mkdir()
        cases_bytes = b"".join(
            json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
            + b"\n"
            for value in raw_cases
        )
        (root / "cases.jsonl").write_bytes(cases_bytes)
        manifest = {
            "schemaVersion": "coaching-quality-benchmark-manifest.v1",
            "sourceGitSHA": "source",
            "independentGroupCount": 40,
            "sequenceGroupCount": 10,
            "turnCount": 70,
            "developmentTurnCount": 56,
            "holdoutTurnCount": 14,
            "turnIDs": [value["id"] for value in raw_cases],
            "casesSHA256": hashlib.sha256(cases_bytes).hexdigest(),
        }
        (root / "benchmark-manifest.json").write_bytes(self.pretty(manifest))
        return load_corpus(root)

    @staticmethod
    def raw_turn(turn):
        brief = turn.grader_brief
        return {
            "schemaVersion": "coaching-quality-benchmark-case.v1",
            "id": turn.identifier,
            "groupID": turn.group_id,
            "stepIndex": turn.step_index,
            "split": turn.split,
            "category": turn.category,
            "request": turn.request,
            "graderBrief": {
                "verifiedFacts": list(brief.verified_facts),
                "coachingPurpose": brief.coaching_purpose,
                "acceptableAlternatives": list(brief.acceptable_alternatives),
                "successCriteria": list(brief.success_criteria),
                "severeFailureCriteria": list(brief.severe_failure_criteria),
            },
            "sourceTraceID": turn.source_trace_id,
        }

    @staticmethod
    def pretty(value):
        return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()

    def test_real_cli_runs_five_turn_diagnostic_with_pinned_corpus(self):
        client = FakeClient()
        selected_ids = ["d-01", "d-02", "s-01-01", "s-01-02", "s-01-03"]
        destination = self.root / "smoke"
        output, errors = io.StringIO(), io.StringIO()
        with (
            mock.patch.dict(os.environ, {"BENCHMARK_TEST_KEY": "test-only"}),
            mock.patch.object(cli, "OpenAIResponsesClient", return_value=client),
            redirect_stdout(output),
            redirect_stderr(errors),
        ):
            status = cli.main([
                "run", "--corpus", str(self.corpus.root), "--mode", "quick",
                "--candidate", str(ROOT / "Tools/CoachingEval/benchmark/configs/production-v1.json"),
                "--pricing", str(ROOT / "Tools/CoachingEval/benchmark/pricing-v1.json"),
                "--output", str(destination), "--api-key-env", "BENCHMARK_TEST_KEY",
                *[argument for identifier in selected_ids for argument in ("--case", identifier)],
            ])
        self.assertEqual(0, status, errors.getvalue())
        records = [json.loads(line) for line in (destination / "records.jsonl").read_text().splitlines()]
        self.assertEqual(selected_ids, [record["caseID"] for record in records])
        self.assertTrue(all(record["mechanicalValidation"]["valid"] for record in records))
        self.assertEqual(5, len(client.calls))
        self.assertEqual("resp_3", client.calls[3]["previous_response_id"])
        self.assertEqual("resp_4", client.calls[4]["previous_response_id"])
        summary = json.loads(output.getvalue())
        self.assertEqual("diagnosticSubset", summary["evidenceClassification"])
        self.assertFalse(summary["trialEligible"])

    def test_diagnostic_projection_rejects_altered_selected_request(self):
        selected = cli._select_cases(self.corpus, ["d-01"], False)
        selected.turns[0].request["requestID"] = "benchmark:altered"
        calls = []
        with self.assertRaisesRegex(ValueError, "changed after loading"):
            run_candidates(
                corpus=selected, configurations=(self.configuration,), mode="quick",
                destination=self.root / "altered-selection",
                provider_factory=lambda configuration: calls.append(configuration),
                price_table=self.prices, diagnostic_subset=True,
            )
        self.assertEqual([], calls)

    def test_quick_and_comparison_execute_exact_matrices(self):
        quick_client = FakeClient()
        quick = run_candidates(
            corpus=self.corpus,
            configurations=(self.configuration,),
            mode="quick",
            destination=self.root / "quick",
            provider_factory=lambda _configuration: quick_client,
            price_table=self.prices,
        )
        self.assertEqual(56, len(quick_client.calls))
        self.assertEqual(56, quick["summary"]["recordCount"])

        comparison_client = FakeClient()
        alternative = self.make_configuration(
            identifier="alternative",
            baseline=False,
        )
        comparison = run_candidates(
            corpus=self.corpus,
            configurations=(self.configuration, alternative),
            mode="comparison",
            destination=self.root / "comparison",
            provider_factory=lambda _configuration: comparison_client,
            price_table=self.prices,
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
            price_table=self.prices,
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

        independent = self.make_configuration(
            identifier="no-reuse",
            model_changes={"conversationReuse": False, "store": False},
        )
        independent_client = FakeClient()
        run_candidates(
            corpus=self.corpus,
            configurations=(independent,),
            mode="quick",
            destination=self.root / "independent",
            provider_factory=lambda _configuration: independent_client,
            price_table=self.prices,
        )
        live_client = FakeClient()
        service = HostedCoachingService(
            provider=live_client, configuration=independent.model_configuration,
        )
        previous_response_id = None
        sequence_turns = [turn for turn in self.corpus.turns if turn.group_id == "s-01"]
        for turn, call, effort in zip(sequence_turns, independent_client.calls[32:35], ("high", "low", "none")):
            result = service.complete({
                "schemaVersion": "hosted-coaching-request.v3",
                "gameID": "00000000-0000-0000-0000-000000000001",
                "episodeID": "00000000-0000-0000-0000-000000000002",
                "request": turn.request,
                "previousResponseID": previous_response_id,
            })
            previous_response_id = result.response["continuationID"]
            self.assertEqual(effort, live_client.calls[-1]["reasoning_effort"])
            self.assertEqual(live_client.calls[-1], call)
            self.assertIsNone(call["previous_response_id"])

    def test_invalid_provider_envelopes_become_invalid_records_without_crashing(self):
        def without_id(response):
            return {key: value for key, value in response.items() if key != "id"}

        cases = (
            ("non-mapping", lambda _response: ["not", "a", "mapping"]),
            (
                "non-completed",
                lambda response: {**response, "status": "in_progress"},
            ),
            ("missing-id", without_id),
            (
                "malformed-id",
                lambda response: {**response, "id": "request_not-a-continuation"},
            ),
        )
        for name, mutate in cases:
            with self.subTest(name=name):
                client = FakeClient()
                valid_complete = client.complete

                def complete(**arguments):
                    return mutate(valid_complete(**arguments))

                client.complete = complete
                try:
                    run_candidates(
                        corpus=self.corpus,
                        configurations=(self.configuration,),
                        mode="quick",
                        destination=self.root / f"invalid-envelope-{name}",
                        provider_factory=lambda _configuration: client,
                        price_table=self.prices,
                    )
                except Exception as error:
                    self.fail(f"invalid provider envelope crashed the runner: {error!r}")

                first = json.loads(
                    (
                        self.root
                        / f"invalid-envelope-{name}/records.jsonl"
                    ).read_text().splitlines()[0]
                )
                self.assertEqual("invalid", first["generationStatus"])
                self.assertEqual(
                    {"valid": False, "categories": ["invalidResponse"]},
                    first["mechanicalValidation"],
                )
                if name != "non-mapping":
                    self.assertEqual(100, first["usage"]["inputTokens"])
                    self.assertEqual("gpt-5.6-sol", first["providerModel"])

    def test_missing_or_malformed_usage_marks_candidate_accounting_incomplete(self):
        cases = (
            ("missing", lambda response: {key: value for key, value in response.items() if key != "usage"}),
            (
                "malformed",
                lambda response: {
                    **response,
                    "usage": {
                        "input_tokens": 100,
                        "cached_input_tokens": "private-invalid-usage",
                        "output_tokens": 10,
                        "reasoning_tokens": 4,
                        "total_tokens": 110,
                    },
                },
            ),
            (
                "inconsistent-total",
                lambda response: {
                    **response,
                    "usage": {
                        **response["usage"],
                        "total_tokens": 999,
                    },
                },
            ),
        )
        for name, mutate in cases:
            with self.subTest(name=name):
                client = FakeClient()
                valid_complete = client.complete

                def complete(**arguments):
                    return mutate(valid_complete(**arguments))

                client.complete = complete
                destination = self.root / f"accounting-{name}"
                run_candidates(
                    corpus=self.corpus,
                    configurations=(self.configuration,),
                    mode="quick",
                    destination=destination,
                    provider_factory=lambda _configuration: client,
                    price_table=self.prices,
                )

                first = json.loads(
                    (destination / "records.jsonl").read_text().splitlines()[0]
                )
                self.assertFalse(first["candidateAccountingComplete"])
                self.assertIsNone(first["candidateCostUSD"])
                if name == "malformed":
                    self.assertEqual(100, first["usage"]["inputTokens"])
                    self.assertEqual(10, first["usage"]["outputTokens"])
                self.assertNotIn("private-invalid-usage", json.dumps(first))

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
            price_table=self.prices,
        )
        records = [json.loads(line) for line in (self.root / "blocked/records.jsonl").read_text().splitlines()]
        sequence = [record for record in records if record["groupID"] == "s-01"]
        self.assertEqual(["invalid", "blockedByPriorTurn", "blockedByPriorTurn"], [record["generationStatus"] for record in sequence])
        for blocked in sequence[1:]:
            self.assertTrue(blocked["candidateAccountingComplete"])
            self.assertEqual("0", blocked["candidateCostUSD"])
            self.assertEqual(
                {
                    "inputTokens": 0,
                    "cachedInputTokens": 0,
                    "outputTokens": 0,
                    "reasoningTokens": 0,
                    "totalTokens": 0,
                },
                blocked["usage"],
            )
        self.assertEqual(54, len(client.calls))

    def test_preflights_every_cell_before_provider_and_refuses_unsafe_runs(self):
        broken_corpus = self.make_corpus(invalid_request_index=55)
        factory_calls = []
        with self.assertRaises(ValueError):
            run_candidates(
                corpus=broken_corpus,
                configurations=(self.configuration,),
                mode="quick",
                destination=self.root / "broken",
                provider_factory=lambda configuration: factory_calls.append(configuration),
                price_table=self.prices,
            )
        self.assertEqual([], factory_calls)

        with self.assertRaises(ValueError):
            run_candidates(
                corpus=self.corpus,
                configurations=(replace(self.configuration, baseline=False),),
                mode="comparison",
                destination=self.root / "missing-baseline",
                provider_factory=lambda _configuration: FakeClient(),
                price_table=self.prices,
            )

        with self.assertRaises(ValueError):
            run_candidates(
                corpus=self.corpus,
                configurations=(self.configuration, self.configuration),
                mode="quick",
                destination=self.root / "duplicate-config",
                provider_factory=lambda _configuration: FakeClient(),
                price_table=self.prices,
            )

    def test_complete_candidate_preflight_precedes_provider_construction(self):
        alternative = self.make_configuration(
            identifier="alternative",
            baseline=False,
        )
        missing_model_prices = replace(
            self.prices,
            models=MappingProxyType({}),
        )
        invalid_storage = replace(
            self.configuration,
            model_configuration=replace(
                self.configuration.model_configuration,
                conversation_reuse=True,
                store=False,
            ),
        )
        invalid_contract = replace(
            self.configuration,
            model_configuration=replace(
                self.configuration.model_configuration,
                response_contract="unknown-contract",
            ),
        )
        invalid_pin = replace(
            self.configuration,
            model_configuration=replace(
                self.configuration.model_configuration,
                system_prompt_sha256="0" * 64,
            ),
        )
        invalid_effort = replace(
            self.configuration,
            model_configuration=replace(
                self.configuration.model_configuration,
                initial_reasoning_effort="low",
            ),
        )
        invalid_runtime_limit = replace(
            self.configuration,
            model_configuration=replace(
                self.configuration.model_configuration,
                maximum_output_tokens=1,
            ),
        )
        invalid_wrapper_pin = replace(
            self.configuration,
            model_configuration_sha256="0" * 64,
        )
        invalid_wrapper_identity = replace(
            alternative,
            identifier="mutated-alternative",
        )
        broken_corpus = self.make_corpus(invalid_request_index=55)
        cases = (
            (
                "zero-baselines",
                (
                    self.make_configuration(
                        identifier="other-one",
                        baseline=False,
                    ),
                    alternative,
                ),
                self.prices,
                self.corpus,
            ),
            (
                "two-baselines",
                (
                    self.configuration,
                    self.make_configuration(
                        identifier="other-baseline",
                        baseline=True,
                    ),
                ),
                self.prices,
                self.corpus,
            ),
            (
                "missing-model-price",
                (self.configuration, alternative),
                missing_model_prices,
                self.corpus,
            ),
            (
                "pricing-version-mismatch",
                (
                    self.configuration,
                    self.make_configuration(
                        identifier="other-pricing",
                        baseline=False,
                        pricing_version="other",
                    ),
                ),
                self.prices,
                self.corpus,
            ),
            (
                "selected-pricing-version-mismatch",
                (
                    self.make_configuration(
                        identifier="baseline-other-pricing",
                        pricing_version="other",
                    ),
                    self.make_configuration(
                        identifier="candidate-other-pricing",
                        baseline=False,
                        pricing_version="other",
                    ),
                ),
                self.prices,
                self.corpus,
            ),
            (
                "invalid-conversation-storage",
                (invalid_storage, alternative),
                self.prices,
                self.corpus,
            ),
            (
                "unsupported-response-contract",
                (invalid_contract, alternative),
                self.prices,
                self.corpus,
            ),
            (
                "prompt-pin-drift",
                (invalid_pin, alternative),
                self.prices,
                self.corpus,
            ),
            (
                "in-memory-effort-drift",
                (invalid_effort, alternative),
                self.prices,
                self.corpus,
            ),
            (
                "in-memory-runtime-limit-drift",
                (invalid_runtime_limit, alternative),
                self.prices,
                self.corpus,
            ),
            (
                "wrapper-pin-drift",
                (invalid_wrapper_pin, alternative),
                self.prices,
                self.corpus,
            ),
            (
                "wrapper-identity-drift",
                (self.configuration, invalid_wrapper_identity),
                self.prices,
                self.corpus,
            ),
            (
                "compilation-failure",
                (self.configuration, alternative),
                self.prices,
                broken_corpus,
            ),
        )
        for name, configurations, prices, corpus in cases:
            with self.subTest(name=name):
                factory_calls = []
                with self.assertRaises(ValueError):
                    run_candidates(
                        corpus=corpus,
                        configurations=configurations,
                        mode="comparison",
                        destination=self.root / name,
                        provider_factory=lambda configuration: factory_calls.append(
                            configuration
                        ),
                        price_table=prices,
                    )
                self.assertEqual([], factory_calls)

    def test_exactly_one_comparison_baseline_publishes_execution_evidence(self):
        alternative = self.make_configuration(
            identifier="alternative",
            baseline=False,
        )
        factory_calls = []

        def provider_factory(configuration):
            factory_calls.append(configuration.identifier)
            return FakeClient()

        manifest = run_candidates(
            corpus=self.corpus,
            configurations=(self.configuration, alternative),
            mode="comparison",
            destination=self.root / "one-baseline",
            provider_factory=provider_factory,
            price_table=self.prices,
        )

        self.assertEqual(["production", "alternative"], factory_calls)
        self.assertEqual(
            {
                "classification": "developmentComparison",
                "trialEligible": True,
                "promotionEvidenceEligible": False,
            },
            manifest["evidence"],
        )
        for configuration in manifest["configurations"]:
            self.assertEqual("high", configuration["initialReasoningEffort"])
            self.assertEqual("low", configuration["tacticalFollowUpReasoningEffort"])
            self.assertEqual("none", configuration["simpleFollowUpReasoningEffort"])
            self.assertTrue(configuration["conversationReuse"])
            self.assertTrue(configuration["store"])

    def test_single_challenger_diagnostic_is_labeled_and_still_requires_pricing(self):
        challenger = self.make_configuration(
            identifier="challenger",
            baseline=False,
        )
        calls = []
        manifest = run_candidates(
            corpus=self.corpus,
            configurations=(challenger,),
            mode="quick",
            destination=self.root / "challenger-diagnostic",
            provider_factory=lambda _configuration: calls.append(True) or FakeClient(),
            price_table=self.prices,
            diagnostic_subset=True,
        )
        self.assertEqual([True], calls)
        self.assertEqual(
            {
                "classification": "diagnosticSubset",
                "trialEligible": False,
                "promotionEvidenceEligible": False,
            },
            manifest["evidence"],
        )

        factory_calls = []
        with self.assertRaisesRegex(ValueError, "price"):
            run_candidates(
                corpus=self.corpus,
                configurations=(challenger,),
                mode="quick",
                destination=self.root / "unpriced-challenger-diagnostic",
                provider_factory=lambda configuration: factory_calls.append(configuration),
                price_table=replace(self.prices, models=MappingProxyType({})),
                diagnostic_subset=True,
            )
        self.assertEqual([], factory_calls)

    def test_in_memory_corpus_mutation_stops_before_provider_construction(self):
        mutated = self.make_corpus()
        mutated.turns[0].request["requestID"] = "benchmark:valid-but-mutated"
        factory_calls = []

        with self.assertRaisesRegex(ValueError, "changed after loading"):
            run_candidates(
                corpus=mutated,
                configurations=(self.configuration,),
                mode="quick",
                destination=self.root / "mutated-corpus",
                provider_factory=lambda configuration: factory_calls.append(
                    configuration
                ),
                price_table=self.prices,
            )

        self.assertEqual([], factory_calls)

    def test_rejects_reordered_loaded_corpus_and_changed_case_bytes(self):
        reordered = list(self.corpus.turns)
        reordered[0], reordered[1] = reordered[1], reordered[0]
        with self.assertRaises(ValueError):
            run_candidates(
                corpus=replace(self.corpus, turns=tuple(reordered)),
                configurations=(self.configuration,),
                mode="quick",
                destination=self.root / "reordered",
                provider_factory=lambda _configuration: FakeClient(),
                price_table=self.prices,
            )

        changed = self.make_corpus()
        changed_cases_path = Path(changed.root) / "cases.jsonl"
        changed_cases_path.write_bytes(changed_cases_path.read_bytes() + b" ")
        with self.assertRaises(ValueError):
            run_candidates(
                corpus=changed,
                configurations=(self.configuration,),
                mode="quick",
                destination=self.root / "hash-drift",
                provider_factory=lambda _configuration: FakeClient(),
                price_table=self.prices,
            )
        (self.root / "exists").mkdir()
        with self.assertRaises(ValueError):
            run_candidates(
                corpus=self.corpus,
                configurations=(self.configuration,),
                mode="quick",
                destination=self.root / "exists",
                provider_factory=lambda _configuration: FakeClient(),
                price_table=self.prices,
            )

    def test_missing_or_repointed_corpus_artifacts_stop_before_provider_construction(self):
        missing_manifest = self.make_corpus()
        (Path(missing_manifest.root) / "benchmark-manifest.json").unlink()
        missing_cases = self.make_corpus()
        (Path(missing_cases.root) / "cases.jsonl").unlink()
        source = self.make_corpus()
        repointed_root = self.root / "repointed-corpus"
        repointed_root.mkdir()
        for name in ("cases.jsonl", "benchmark-manifest.json"):
            (repointed_root / name).write_bytes((Path(source.root) / name).read_bytes())
        repointed = replace(source, root=repointed_root)

        for name, corpus in (
            ("missing-manifest", missing_manifest),
            ("missing-cases", missing_cases),
            ("repointed-root", repointed),
        ):
            with self.subTest(name=name):
                factory_calls = []
                with self.assertRaisesRegex(ValueError, "missing or repointed"):
                    run_candidates(
                        corpus=corpus,
                        configurations=(self.configuration,),
                        mode="quick",
                        destination=self.root / name,
                        provider_factory=lambda configuration: factory_calls.append(
                            configuration
                        ),
                        price_table=self.prices,
                    )
                self.assertEqual([], factory_calls)

    def test_retries_only_when_configured_and_redacts_exception_text(self):
        client = FakeClient(
            failures=[OpenAIResponsesError("secret-provider-body", category="timeout")]
        )
        retrying = self.make_configuration(
            identifier="retrying",
            model_changes={"maximumAttempts": 2},
        )
        run_candidates(
            corpus=self.corpus,
            configurations=(retrying,),
            mode="quick",
            destination=self.root / "retry",
            provider_factory=lambda _configuration: client,
            price_table=self.prices,
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
            price_table=self.prices,
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
            price_table=self.prices,
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

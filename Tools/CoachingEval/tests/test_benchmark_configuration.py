import hashlib
import json
import tempfile
import unittest
from decimal import Decimal
from pathlib import Path

from Tools.CoachingEval.benchmark.cli import _select_cases
from Tools.CoachingEval.benchmark.configuration import (
    load_candidate,
    load_judge,
    load_prices,
)
from Tools.CoachingEval.benchmark.runner import run_candidates
from Tools.CoachingEval.tests import test_benchmark_runner as runner_fixtures


ROOT = Path(__file__).resolve().parents[3]


class BenchmarkConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        prompt_path = self.root / "Tools/CoachingEval/prompts/tutor-v13.md"
        prompt_path.parent.mkdir(parents=True)
        prompt_path.write_text("Coach one turn.\n", encoding="utf-8")
        self.prompt_path = prompt_path
        self.prompt_sha = hashlib.sha256(prompt_path.read_bytes()).hexdigest()
        model_configuration = {
            "schemaVersion": "hosted-coaching-model.v1",
            "provider": "openai-responses-v1",
            "model": "gpt-5.6-sol",
            "initialReasoningEffort": "high",
            "tacticalFollowUpReasoningEffort": "low",
            "simpleFollowUpReasoningEffort": "none",
            "conversationReuse": True,
            "store": True,
            "maximumOutputTokens": 2048,
            "timeoutSeconds": 30,
            "maximumAttempts": 1,
            "systemPromptPath": "Tools/CoachingEval/prompts/tutor-v13.md",
            "systemPromptSHA256": self.prompt_sha,
            "userPromptGenerator": "chess-native-v13",
            "responseContract": "chess-native-v13",
        }
        self.model_configuration_path = self.root / "configs/model.json"
        self.model_configuration_path.parent.mkdir(parents=True)
        self.model_configuration_path.write_text(
            json.dumps(model_configuration), encoding="utf-8"
        )
        self.model_configuration_sha = hashlib.sha256(
            self.model_configuration_path.read_bytes()
        ).hexdigest()
        self.candidate = {
            "schemaVersion": "coaching-quality-candidate.v2",
            "id": "production-sol-v1",
            "baseline": True,
            "modelConfigurationPath": "configs/model.json",
            "modelConfigurationSHA256": self.model_configuration_sha,
            "pricingVersion": "openai-2026-09-01",
        }
        self.judge = {
            "schemaVersion": "coaching-quality-judge.v1",
            "id": "judge-sol-v1",
            "provider": "openai-responses-v1",
            "model": "gpt-5.6-sol",
            "reasoningEffort": "high",
            "conversationReuse": False,
            "maximumOutputTokens": 2048,
            "timeoutSeconds": 60,
            "systemPromptPath": "Tools/CoachingEval/prompts/tutor-v13.md",
            "systemPromptSHA256": self.prompt_sha,
            "calibrationPath": "Tools/CoachingEval/prompts/tutor-v13.md",
            "calibrationSHA256": self.prompt_sha,
            "reviewSeed": 20260901,
        }
        reference = json.loads(
            (ROOT / "Tools/CoachingEval/benchmark/judge-reference-v2.json").read_text()
        )
        reference["provenance"].update(
            {
                "reviewStatus": "humanReviewed",
                "reviewedBy": "Test Reviewer",
                "reviewedAt": "2026-09-03",
            }
        )
        reference_path = self.root / "Tools/CoachingEval/benchmark/reference.json"
        reference_path.parent.mkdir(parents=True)
        reference_path.write_text(json.dumps(reference), encoding="utf-8")
        reference_sha = hashlib.sha256(reference_path.read_bytes()).hexdigest()
        self.judge_v2 = {
            "schemaVersion": "coaching-quality-judge.v2",
            "id": "judge-sol-v2",
            "provider": "openai-responses-v1",
            "model": "gpt-5.6-sol",
            "reasoningEffort": "high",
            "conversationReuse": False,
            "maximumOutputTokens": 2048,
            "timeoutSeconds": 60,
            "systemPromptPath": "Tools/CoachingEval/prompts/tutor-v13.md",
            "systemPromptSHA256": self.prompt_sha,
            "referenceSetPath": "Tools/CoachingEval/benchmark/reference.json",
            "referenceSetSHA256": reference_sha,
            "reviewSeed": 20260901,
            "qualificationRepetitions": 3,
            "minimumSevereAgreement": 0.95,
            "minimumDimensionAgreement": 0.90,
            "minimumPairwiseAgreement": 0.90,
            "qualificationValidDays": 30,
        }
        self.prices = {
            "schemaVersion": "coaching-quality-pricing.v1",
            "version": "openai-2026-09-01",
            "effectiveDate": "2026-09-01",
            "sourceURL": "https://openai.com/api/pricing/",
            "models": {
                "gpt-5.6-sol": {
                    "uncachedInputPerMillion": "2.00",
                    "cachedInputPerMillion": "0.20",
                    "outputPerMillion": "10.00",
                }
            },
        }

    def tearDown(self):
        self.temporary.cleanup()

    def dump(self, name, value):
        path = self.root / name
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def test_loads_frozen_candidate_judge_and_decimal_prices(self):
        candidate = load_candidate(self.dump("candidate.json", self.candidate), self.root)
        judge = load_judge(self.dump("judge.json", self.judge), self.root)
        prices = load_prices(self.dump("prices.json", self.prices))

        self.assertEqual(
            "Coach one turn.\n", candidate.model_configuration.system_prompt
        )
        self.assertEqual(
            self.model_configuration_sha,
            candidate.model_configuration_sha256,
        )
        self.assertTrue(candidate.baseline)
        self.assertEqual(64, len(candidate.sha256))
        self.assertEqual(20260901, judge.review_seed)
        self.assertEqual(1, judge.qualification_repetitions)
        self.assertEqual(0.0, judge.minimum_pairwise_agreement)
        self.assertEqual(
            Decimal("0.000011"),
            prices.estimate(
                "gpt-5.6-sol",
                {"inputTokens": 10, "cachedInputTokens": 5, "outputTokens": 0, "reasoningTokens": 0},
            ),
        )

        self.prompt_path.write_text("changed", encoding="utf-8")
        self.assertEqual(
            "Coach one turn.\n", candidate.model_configuration.system_prompt
        )
        with self.assertRaises(TypeError):
            candidate.raw["modelConfigurationPath"] = "changed"
        with self.assertRaises(TypeError):
            prices.models["other"] = prices.models["gpt-5.6-sol"]

    def test_loads_v2_judge_qualification_contract(self):
        judge = load_judge(self.dump("judge-v2.json", self.judge_v2), self.root)

        self.assertEqual("judge-sol-v2", judge.identifier)
        self.assertEqual(3, judge.qualification_repetitions)
        self.assertEqual(0.95, judge.minimum_severe_agreement)
        self.assertEqual(0.90, judge.minimum_dimension_agreement)
        self.assertEqual(0.90, judge.minimum_pairwise_agreement)
        self.assertEqual(30, judge.qualification_valid_days)
        self.assertEqual(
            self.judge_v2["referenceSetSHA256"], judge.reference_set_sha256
        )
        self.assertIsNone(judge.calibration_path)

    def test_v2_judge_rejects_bad_qualification_settings_and_reference_drift(self):
        for field, value in (
            ("qualificationRepetitions", 0),
            ("qualificationRepetitions", 2),
            ("qualificationRepetitions", 4),
            ("minimumSevereAgreement", 1.01),
            ("minimumSevereAgreement", 0.94),
            ("minimumDimensionAgreement", 0),
            ("minimumDimensionAgreement", 0.89),
            ("minimumPairwiseAgreement", 0),
            ("minimumPairwiseAgreement", 0.89),
            ("qualificationValidDays", -1),
            ("qualificationValidDays", 31),
        ):
            judge = dict(self.judge_v2, **{field: value})
            with self.subTest(field=field), self.assertRaises(ValueError):
                load_judge(self.dump(f"bad-{field}.json", judge), self.root)

        judge = dict(self.judge_v2, referenceSetSHA256="0" * 64)
        with self.assertRaisesRegex(ValueError, "hash"):
            load_judge(self.dump("reference-drift.json", judge), self.root)

    def test_candidate_rejects_unknown_fields_hash_drift_and_escape(self):
        candidate = dict(self.candidate, unexpected=True)
        with self.assertRaises(ValueError):
            load_candidate(self.dump("unknown.json", candidate), self.root)

        candidate = dict(self.candidate, modelConfigurationSHA256="0" * 64)
        with self.assertRaisesRegex(ValueError, "hash"):
            load_candidate(self.dump("drift.json", candidate), self.root)

        outside = self.root.parent / "outside-model.json"
        outside.write_text("{}", encoding="utf-8")
        candidate = dict(
            self.candidate,
            modelConfigurationPath="../outside-model.json",
            modelConfigurationSHA256=hashlib.sha256(outside.read_bytes()).hexdigest(),
        )
        with self.assertRaises(ValueError):
            load_candidate(self.dump("escape.json", candidate), self.root)

    def test_prices_reject_missing_model_negative_values_and_unknown_fields(self):
        path = self.dump("prices.json", self.prices)
        table = load_prices(path)
        with self.assertRaises(ValueError):
            table.estimate("missing", {"inputTokens": 1})

        prices = json.loads(json.dumps(self.prices))
        prices["models"]["gpt-5.6-sol"]["outputPerMillion"] = "-1"
        with self.assertRaises(ValueError):
            load_prices(self.dump("negative.json", prices))

        prices = dict(self.prices, extra=True)
        with self.assertRaises(ValueError):
            load_prices(self.dump("extra.json", prices))

    def test_portable_discovery_challengers_execute_the_pinned_shared_policies(self):
        benchmark = ROOT / "Tools/CoachingEval/benchmark"
        prices = load_prices(benchmark / "pricing-v2.json")
        baseline = load_candidate(benchmark / "configs/production-v2.json", ROOT)
        fixture = runner_fixtures.BenchmarkRunnerTests()
        fixture.setUp()
        self.addCleanup(fixture.tearDown)
        corpus = _select_cases(fixture.corpus, ["s-01-01", "s-01-02", "s-01-03"], False)
        for identifier, model, efforts in (
            ("astra-discovery-low", "gpt-6-astra", ("low", "low", "low")),
            ("sol-discovery-medium", "gpt-5.6-sol", ("medium", "low", "none")),
        ):
            with self.subTest(identifier=identifier):
                candidate = load_candidate(benchmark / f"configs/{identifier}.json", ROOT)
                configuration = candidate.model_configuration
                self.assertEqual(identifier, candidate.identifier)
                self.assertFalse(candidate.baseline)
                self.assertEqual(baseline.pricing_version, candidate.pricing_version)
                self.assertEqual(prices.version, candidate.pricing_version)
                self.assertEqual(benchmark / f"configs/models/{identifier}-model.json", configuration.path)
                self.assertEqual(ROOT / "Tools/CoachingEval/prompts/tutor-v13-discovery.md", configuration.system_prompt_path)
                self.assertEqual("88b95067d763ec020d2aa6f4e0ce37430cdf818591f8a76b6eaa3d9bf2d9fcc6", configuration.system_prompt_sha256)
                self.assertEqual("chess-native-v13", configuration.user_prompt_generator)
                self.assertEqual("chess-native-v13", configuration.response_contract)
                self.assertEqual(1, configuration.maximum_attempts)
                self.assertTrue(configuration.conversation_reuse)
                client = runner_fixtures.FakeClient()
                manifest = run_candidates(
                    corpus=corpus, configurations=(candidate,), mode="quick",
                    destination=self.root / identifier,
                    provider_factory=lambda _configuration: client,
                    price_table=prices, diagnostic_subset=True,
                )
                self.assertEqual(3, manifest["summary"]["validCount"])
                self.assertEqual(list(efforts), [call["reasoning_effort"] for call in client.calls])
                self.assertEqual([None, "resp_1", "resp_2"], [call["previous_response_id"] for call in client.calls])
                for call in client.calls:
                    self.assertEqual(model, call["model"])
                    self.assertEqual(configuration.system_prompt, call["system_prompt"])
                    self.assertTrue(call["store"])
                    self.assertEqual(2048, call["maximum_output_tokens"])
                    self.assertEqual(30, call["timeout"])

    def test_repository_astra_judge_and_current_baseline_pricing_load_together(self):
        benchmark = ROOT / "Tools/CoachingEval/benchmark"
        judge = load_judge(benchmark / "configs/judge-v3.json", ROOT)
        candidate = load_candidate(benchmark / "configs/production-v2.json", ROOT)
        previous_candidate = load_candidate(benchmark / "configs/production-v1.json", ROOT)
        previous_judge = load_judge(benchmark / "configs/judge-v2.json", ROOT)
        prices = load_prices(benchmark / "pricing-v2.json")

        self.assertEqual("judge-astra-v3", judge.identifier)
        self.assertEqual("gpt-6-astra", judge.model)
        self.assertEqual("low", judge.reasoning_effort)
        self.assertEqual(4096, judge.maximum_output_tokens)
        self.assertEqual(benchmark / "judge-v2.md", judge.system_prompt_path)
        self.assertEqual(
            "35b6efb23fcdd7d1e6b501ad34946b9a0c5f79d5beaae17e607fb9b2571d0807",
            judge.system_prompt_sha256,
        )
        self.assertEqual(previous_judge.reference_set_sha256, judge.reference_set_sha256)
        self.assertEqual(3, judge.qualification_repetitions)
        self.assertEqual(0.95, judge.minimum_severe_agreement)
        self.assertEqual(0.90, judge.minimum_dimension_agreement)
        self.assertEqual(0.90, judge.minimum_pairwise_agreement)
        self.assertEqual(30, judge.qualification_valid_days)
        self.assertEqual("production-sol-v2", candidate.identifier)
        self.assertTrue(candidate.baseline)
        self.assertEqual(previous_candidate.model_configuration, candidate.model_configuration)
        self.assertEqual("openai-2026-09-06", candidate.pricing_version)
        self.assertEqual(candidate.pricing_version, prices.version)
        usage = {"inputTokens": 100, "cachedInputTokens": 20, "outputTokens": 10, "reasoningTokens": 4}
        self.assertEqual(Decimal("0.000528"), prices.estimate(candidate.model_configuration.model, usage))
        self.assertEqual(Decimal("0.00132"), prices.estimate(judge.model, usage))

    def test_repository_production_judge_and_pricing_pins_load(self):
        repository_root = ROOT
        benchmark = repository_root / "Tools/CoachingEval/benchmark"

        candidate = load_candidate(
            benchmark / "configs/production-v1.json", repository_root
        )
        judge = load_judge(benchmark / "configs/judge-v1.json", repository_root)
        judge_v2 = load_judge(benchmark / "configs/judge-v2.json", repository_root)
        prices = load_prices(benchmark / "pricing-v1.json")

        self.assertEqual("production-sol-v1", candidate.identifier)
        self.assertEqual("gpt-5.6-sol", candidate.model_configuration.model)
        self.assertEqual(
            "35a881fa378cb52dfe1f070742ea2908626d280c9f77f0562b5d68a39ca79106",
            candidate.model_configuration_sha256,
        )
        self.assertEqual("judge-sol-v1", judge.identifier)
        self.assertEqual("judge-sol-v2", judge_v2.identifier)
        reference_path = benchmark / "judge-reference-v2.json"
        self.assertEqual(
            hashlib.sha256(reference_path.read_bytes()).hexdigest(),
            judge_v2.reference_set_sha256,
        )
        self.assertEqual(
            "chess-native-v13",
            json.loads(reference_path.read_text())["responseContract"],
        )
        self.assertEqual("openai-2026-09-01", prices.version)


if __name__ == "__main__":
    unittest.main()

import hashlib
import json
import tempfile
import unittest
from decimal import Decimal
from pathlib import Path

from Tools.CoachingEval.benchmark.configuration import (
    load_candidate,
    load_judge,
    load_prices,
)


class BenchmarkConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        prompt_path = self.root / "Tools/CoachingEval/prompts/tutor-v13.md"
        prompt_path.parent.mkdir(parents=True)
        prompt_path.write_text("Coach one turn.\n", encoding="utf-8")
        self.prompt_path = prompt_path
        self.prompt_sha = hashlib.sha256(prompt_path.read_bytes()).hexdigest()
        self.candidate = {
            "schemaVersion": "coaching-quality-candidate.v1",
            "id": "production-sol-v1",
            "baseline": True,
            "provider": "openai-responses-v1",
            "model": "gpt-5.6-sol",
            "initialReasoningEffort": "high",
            "followUpReasoningEffort": "none",
            "conversationReuse": True,
            "maximumOutputTokens": 2048,
            "timeoutSeconds": 30,
            "maximumAttempts": 1,
            "systemPromptPath": "Tools/CoachingEval/prompts/tutor-v13.md",
            "systemPromptSHA256": self.prompt_sha,
            "userPromptGenerator": "chess-native-v13",
            "responseContract": "chess-native-v13",
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

        self.assertEqual("Coach one turn.\n", candidate.system_prompt)
        self.assertTrue(candidate.baseline)
        self.assertEqual(64, len(candidate.sha256))
        self.assertEqual(20260901, judge.review_seed)
        self.assertEqual(
            Decimal("0.000011"),
            prices.estimate(
                "gpt-5.6-sol",
                {"inputTokens": 10, "cachedInputTokens": 5, "outputTokens": 0, "reasoningTokens": 0},
            ),
        )

        self.prompt_path.write_text("changed", encoding="utf-8")
        self.assertEqual("Coach one turn.\n", candidate.system_prompt)
        with self.assertRaises(TypeError):
            candidate.raw["model"] = "changed"
        with self.assertRaises(TypeError):
            prices.models["other"] = prices.models["gpt-5.6-sol"]

    def test_candidate_rejects_unknown_fields_hash_drift_unsupported_ids_and_escape(self):
        for field, value in (
            ("provider", "shell-command"),
            ("userPromptGenerator", "arbitrary-python"),
            ("responseContract", "permissive"),
        ):
            candidate = dict(self.candidate)
            candidate[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                load_candidate(self.dump(f"{field}.json", candidate), self.root)

        candidate = dict(self.candidate, unexpected=True)
        with self.assertRaises(ValueError):
            load_candidate(self.dump("unknown.json", candidate), self.root)

        candidate = dict(self.candidate, systemPromptSHA256="0" * 64)
        with self.assertRaisesRegex(ValueError, "hash"):
            load_candidate(self.dump("drift.json", candidate), self.root)

        outside = self.root.parent / "outside-prompt.md"
        outside.write_text("outside", encoding="utf-8")
        candidate = dict(
            self.candidate,
            systemPromptPath="../outside-prompt.md",
            systemPromptSHA256=hashlib.sha256(outside.read_bytes()).hexdigest(),
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

    def test_repository_production_judge_and_pricing_pins_load(self):
        repository_root = Path(__file__).resolve().parents[3]
        benchmark = repository_root / "Tools/CoachingEval/benchmark"

        candidate = load_candidate(
            benchmark / "configs/production-v1.json", repository_root
        )
        judge = load_judge(benchmark / "configs/judge-v1.json", repository_root)
        prices = load_prices(benchmark / "pricing-v1.json")

        self.assertEqual("production-sol-v1", candidate.identifier)
        self.assertEqual("judge-sol-v1", judge.identifier)
        self.assertEqual("openai-2026-09-01", prices.version)


if __name__ == "__main__":
    unittest.main()

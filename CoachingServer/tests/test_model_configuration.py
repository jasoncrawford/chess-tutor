import copy
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from CoachingServer.chess_native_compiler import parse_neutral_request
from CoachingServer.model_configuration import HostedModelConfiguration


ROOT = Path(__file__).resolve().parents[2]
FIXTURE = json.loads(
    (ROOT / "Tools/CoachingEval/fixtures/chess-native-context-v1.json").read_text(
        encoding="utf-8"
    )
)


class HostedModelConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.prompt_path = self.root / "prompts/tutor-v13.md"
        self.prompt_path.parent.mkdir(parents=True)
        self.prompt_path.write_text("Coach one turn.\n", encoding="utf-8")
        self.configuration = {
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
            "systemPromptPath": "prompts/tutor-v13.md",
            "systemPromptSHA256": hashlib.sha256(
                self.prompt_path.read_bytes()
            ).hexdigest(),
            "userPromptGenerator": "chess-native-v13",
            "responseContract": "chess-native-v13",
        }

    def tearDown(self):
        self.temporary.cleanup()

    def dump(self, value, name="model.json"):
        path = self.root / name
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def test_loads_strict_pinned_configuration_and_owns_reasoning_routes(self):
        path = self.dump(self.configuration)

        configuration = HostedModelConfiguration.load(path, self.root)

        self.assertEqual("gpt-5.6-sol", configuration.model)
        self.assertEqual("Coach one turn.\n", configuration.system_prompt)
        self.assertEqual("tutor-v13", configuration.prompt_version)
        self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), configuration.sha256)
        request = parse_neutral_request(FIXTURE["request"])
        self.assertEqual("high", configuration.reasoning_effort(request, False))

        cases = (
            ("moveStaged", ["move:b1-c3"], "low"),
            ("moveReplaced", ["move:b1-c3"], "low"),
            ("squareInspected", ["piece:white:knight:b1"], "low"),
            ("actionChosen", ["action:hint"], "low"),
            ("actionChosen", ["action:noPieceNeedsHelp"], "none"),
            ("moveRemoved", ["move:b1-c3"], "none"),
        )
        for kind, references, expected in cases:
            with self.subTest(kind=kind, references=references):
                follow_up = copy.deepcopy(FIXTURE["request"])
                event = {
                    "sequence": 1,
                    "kind": kind,
                    "referencedIDs": references,
                }
                follow_up["interaction"]["latestEvent"] = event
                follow_up["interaction"]["episodeEvents"] = [event]
                self.assertEqual(
                    expected,
                    configuration.reasoning_effort(
                        parse_neutral_request(follow_up), True
                    ),
                )

        with self.assertRaises(TypeError):
            configuration.raw["model"] = "changed"

    def test_rejects_prompt_drift_unknown_fields_and_unstored_conversation_reuse(self):
        drifted = dict(self.configuration, systemPromptSHA256="0" * 64)
        with self.assertRaisesRegex(ValueError, "hash"):
            HostedModelConfiguration.load(self.dump(drifted, "drifted.json"), self.root)

        unknown = dict(self.configuration, unexpected=True)
        with self.assertRaisesRegex(ValueError, "fields"):
            HostedModelConfiguration.load(self.dump(unknown, "unknown.json"), self.root)

        unstored = dict(self.configuration, store=False)
        with self.assertRaisesRegex(ValueError, "storage"):
            HostedModelConfiguration.load(self.dump(unstored, "unstored.json"), self.root)

    def test_repository_production_configuration_preserves_live_policy(self):
        configuration = HostedModelConfiguration.load(
            ROOT / "CoachingServer/configs/production-v1.json",
            ROOT,
        )

        self.assertEqual("gpt-5.6-sol", configuration.model)
        self.assertEqual("high", configuration.initial_reasoning_effort)
        self.assertEqual("low", configuration.tactical_follow_up_reasoning_effort)
        self.assertEqual("none", configuration.simple_follow_up_reasoning_effort)
        self.assertTrue(configuration.conversation_reuse)
        self.assertTrue(configuration.store)
        self.assertEqual(2048, configuration.maximum_output_tokens)
        self.assertEqual(30.0, configuration.timeout_seconds)
        self.assertEqual(1, configuration.maximum_attempts)
        self.assertEqual("tutor-v13", configuration.prompt_version)


if __name__ == "__main__":
    unittest.main()

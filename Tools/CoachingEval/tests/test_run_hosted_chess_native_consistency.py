import contextlib
import importlib
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

from Tools.CoachingEval.tests.test_run_chess_native_pilot import (  # noqa: E402
    synthetic_source_pins,
    write_synthetic_source,
)
from Tools.CoachingEval.tests.test_run_hosted_chess_native_pilot import (  # noqa: E402
    RecordingHostedClient,
)


HARD_CASE_IDS = (
    "02-attacked-piece",
    "05-tactical-reply",
    "06-inspected-reply",
    "07-answering-check",
)


def load_runner(test_case):
    try:
        return importlib.import_module("run_hosted_chess_native_consistency")
    except ModuleNotFoundError:
        test_case.fail("run_hosted_chess_native_consistency is not implemented")


class HostedChessNativeConsistencyTests(unittest.TestCase):
    def setUp(self):
        self.runner = load_runner(self)
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.fixture = write_synthetic_source(self.root)

    def tearDown(self):
        self.temporary.cleanup()

    def run_consistency(self, client, destination=None, **overrides):
        destination = destination or self.root / "consistency-run"
        arguments = {
            "source_dir": self.fixture["source"],
            "system_prompt_path": self.fixture["systemPath"],
            "destination": destination,
            "client": client,
            "timeout": 9,
        }
        arguments.update(overrides)
        with synthetic_source_pins(self.runner.hosted_pilot, self.fixture):
            return self.runner.run_hosted_consistency(**arguments)

    def test_runs_two_new_samples_of_each_hard_case_without_changing_requests(self):
        client = RecordingHostedClient()

        manifest = self.run_consistency(client)

        expected_ids = list(HARD_CASE_IDS) * 2
        self.assertEqual(
            [self.fixture["userPrompts"][identifier] for identifier in expected_ids],
            [call["user_prompt"] for call in client.calls],
        )
        self.assertEqual(8, len(client.calls))
        for call in client.calls:
            self.assertEqual(self.fixture["system"], call["system_prompt"])
            self.assertEqual("gpt-5.6-sol", call["model"])
            self.assertEqual("high", call["reasoning_effort"])
            self.assertEqual(2048, call["maximum_output_tokens"])
            self.assertEqual(9, call["timeout"])
            self.assertEqual(
                ["message", "actions", "focus"], call["schema"]["required"]
            )
            self.assertFalse(call["schema"]["additionalProperties"])

        self.assertEqual([2, 3], manifest["sampleIndices"])
        self.assertEqual(list(HARD_CASE_IDS), manifest["caseIDs"])
        self.assertEqual(
            {
                "recordCount": 8,
                "completionAttempts": 8,
                "validCount": 8,
                "invalidCount": 0,
                "providerErrorCount": 0,
            },
            manifest["summary"],
        )
        self.assertEqual(
            [
                f"records/{identifier}-sample-{sample_index}.json"
                for sample_index in (2, 3)
                for identifier in HARD_CASE_IDS
            ],
            [record["path"] for record in manifest["records"]],
        )
        for sample_index in (2, 3):
            for identifier in HARD_CASE_IDS:
                record = json.loads(
                    (
                        self.root
                        / "consistency-run"
                        / "records"
                        / f"{identifier}-sample-{sample_index}.json"
                    ).read_text(encoding="utf-8")
                )
                self.assertEqual(identifier, record["caseID"])
                self.assertEqual(sample_index, record["sampleIndex"])
                self.assertEqual(
                    "model-coaching-chess-native-hosted-consistency-record.v1",
                    record["schemaVersion"],
                )

    def test_redacts_one_provider_failure_and_continues_all_samples(self):
        private_marker = "PRIVATE_HOSTED_CONSISTENCY_BODY"

        def response(index):
            if index == 2:
                return OSError(private_marker)
            return RecordingHostedClient._valid_response(index)

        client = RecordingHostedClient(response)

        manifest = self.run_consistency(client)

        self.assertEqual(8, len(client.calls))
        self.assertEqual(7, manifest["summary"]["validCount"])
        self.assertEqual(1, manifest["summary"]["providerErrorCount"])
        failed = json.loads(
            (
                self.root
                / "consistency-run"
                / "records"
                / "06-inspected-reply-sample-2.json"
            ).read_text(encoding="utf-8")
        )
        self.assertEqual("generationError", failed["generationStatus"])
        self.assertEqual(2, failed["sampleIndex"])
        for path in (self.root / "consistency-run").rglob("*"):
            if path.is_file():
                self.assertNotIn(private_marker, path.read_text(encoding="utf-8"))

    def test_selected_configuration_drives_every_call_and_manifest(self):
        client = RecordingHostedClient()
        configuration = self.runner.HOSTED_CONFIGURATIONS["terra-high"]

        manifest = self.run_consistency(client, configuration=configuration)

        self.assertEqual(8, len(client.calls))
        self.assertTrue(all(call["model"] == "gpt-5.6-terra" for call in client.calls))
        self.assertTrue(all(call["reasoning_effort"] == "high" for call in client.calls))
        self.assertEqual(
            {
                "api": "openai-responses-v1",
                "model": "gpt-5.6-terra",
                "reasoningEffort": "high",
                "maximumOutputTokens": 2048,
            },
            manifest["provider"],
        )

    def test_luna_medium_is_an_available_frozen_consistency_configuration(self):
        client = RecordingHostedClient()
        configuration = self.runner.HOSTED_CONFIGURATIONS["luna-medium"]

        manifest = self.run_consistency(client, configuration=configuration)

        self.assertEqual(8, len(client.calls))
        self.assertTrue(all(call["model"] == "gpt-5.6-luna" for call in client.calls))
        self.assertTrue(
            all(call["reasoning_effort"] == "medium" for call in client.calls)
        )
        self.assertEqual("gpt-5.6-luna", manifest["provider"]["model"])
        self.assertEqual("medium", manifest["provider"]["reasoningEffort"])

    def test_refuses_overwrite_before_any_provider_call(self):
        destination = self.root / "existing"
        destination.mkdir()
        client = RecordingHostedClient()

        with self.assertRaisesRegex(ValueError, "overwrite"):
            self.run_consistency(client, destination)

        self.assertEqual([], client.calls)

    def test_main_uses_environment_key_and_prints_only_the_summary(self):
        import openai_responses

        destination = self.root / "cli-run"
        client = RecordingHostedClient()
        key = "sk-test-consistency-private"
        argv = [
            "--source",
            str(self.fixture["source"]),
            "--system-prompt",
            str(self.fixture["systemPath"]),
            "--destination",
            str(destination),
            "--timeout",
            "9",
        ]
        output = io.StringIO()
        with (
            synthetic_source_pins(self.runner.hosted_pilot, self.fixture),
            mock.patch.dict(os.environ, {"OPENAI_API_KEY": key}, clear=True),
            mock.patch.object(
                openai_responses,
                "OpenAIResponsesClient",
                return_value=client,
            ) as constructor,
            contextlib.redirect_stdout(output),
        ):
            result = self.runner.main(argv)

        self.assertEqual(0, result)
        constructor.assert_called_once_with("https://api.openai.com", api_key=key)
        self.assertEqual(8, len(client.calls))
        self.assertEqual(8, json.loads(output.getvalue())["recordCount"])
        for path in destination.rglob("*"):
            if path.is_file():
                self.assertNotIn(key, path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()

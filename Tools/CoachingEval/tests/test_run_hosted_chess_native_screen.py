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
CONFIGURATIONS = (
    ("sol-medium", "gpt-5.6-sol", "medium"),
    ("terra-high", "gpt-5.6-terra", "high"),
    ("luna-high", "gpt-5.6-luna", "high"),
)
LOWER_EFFORT_CONFIGURATIONS = (
    ("sol-low", "gpt-5.6-sol", "low"),
    ("terra-medium", "gpt-5.6-terra", "medium"),
    ("luna-medium", "gpt-5.6-luna", "medium"),
)


def load_runner(test_case):
    try:
        return importlib.import_module("run_hosted_chess_native_screen")
    except ModuleNotFoundError:
        test_case.fail("run_hosted_chess_native_screen is not implemented")


class HostedChessNativeScreenTests(unittest.TestCase):
    def setUp(self):
        self.runner = load_runner(self)
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.fixture = write_synthetic_source(self.root)

    def tearDown(self):
        self.temporary.cleanup()

    def run_screen(self, client, destination=None, **overrides):
        destination = destination or self.root / "screen-run"
        arguments = {
            "source_dir": self.fixture["source"],
            "system_prompt_path": self.fixture["systemPath"],
            "destination": destination,
            "client": client,
            "timeout": 9,
        }
        arguments.update(overrides)
        with synthetic_source_pins(self.runner.hosted_pilot, self.fixture):
            return self.runner.run_hosted_screen(**arguments)

    def test_runs_exact_three_configuration_four_case_screen(self):
        client = RecordingHostedClient()

        manifest = self.run_screen(client)

        expected_calls = [
            (configuration_id, model, effort, case_id)
            for configuration_id, model, effort in CONFIGURATIONS
            for case_id in HARD_CASE_IDS
        ]
        self.assertEqual(12, len(client.calls))
        for call, (_configuration_id, model, effort, case_id) in zip(
            client.calls, expected_calls
        ):
            self.assertEqual(self.fixture["system"], call["system_prompt"])
            self.assertEqual(self.fixture["userPrompts"][case_id], call["user_prompt"])
            self.assertEqual(model, call["model"])
            self.assertEqual(effort, call["reasoning_effort"])
            self.assertEqual(2048, call["maximum_output_tokens"])
            self.assertEqual(9, call["timeout"])
            self.assertEqual(
                ["message", "actions", "focus"], call["schema"]["required"]
            )
            self.assertFalse(call["schema"]["additionalProperties"])

        self.assertEqual(
            [
                {"id": identifier, "model": model, "reasoningEffort": effort}
                for identifier, model, effort in CONFIGURATIONS
            ],
            manifest["configurations"],
        )
        self.assertEqual(list(HARD_CASE_IDS), manifest["caseIDs"])
        self.assertEqual(
            {
                "recordCount": 12,
                "completionAttempts": 12,
                "validCount": 12,
                "invalidCount": 0,
                "providerErrorCount": 0,
            },
            manifest["summary"],
        )
        self.assertEqual(
            [
                f"records/{configuration_id}--{case_id}.json"
                for configuration_id, _model, _effort in CONFIGURATIONS
                for case_id in HARD_CASE_IDS
            ],
            [record["path"] for record in manifest["records"]],
        )
        for configuration_id, model, effort, case_id in expected_calls:
            record = json.loads(
                (
                    self.root
                    / "screen-run"
                    / "records"
                    / f"{configuration_id}--{case_id}.json"
                ).read_text(encoding="utf-8")
            )
            self.assertEqual(configuration_id, record["configurationID"])
            self.assertEqual(case_id, record["caseID"])
            self.assertEqual(model, record["requestedModel"])
            self.assertEqual(effort, record["reasoningEffort"])
            self.assertEqual(
                "model-coaching-chess-native-hosted-screen-record.v1",
                record["schemaVersion"],
            )

    def test_redacts_provider_failure_and_continues_all_configurations(self):
        private_marker = "PRIVATE_HOSTED_SCREEN_BODY"

        def response(index):
            if index == 4:
                return OSError(private_marker)
            return RecordingHostedClient._valid_response(index)

        client = RecordingHostedClient(response)

        manifest = self.run_screen(client)

        self.assertEqual(12, len(client.calls))
        self.assertEqual(11, manifest["summary"]["validCount"])
        self.assertEqual(1, manifest["summary"]["providerErrorCount"])
        failed = json.loads(
            (
                self.root
                / "screen-run"
                / "records"
                / "terra-high--02-attacked-piece.json"
            ).read_text(encoding="utf-8")
        )
        self.assertEqual("generationError", failed["generationStatus"])
        for path in (self.root / "screen-run").rglob("*"):
            if path.is_file():
                self.assertNotIn(private_marker, path.read_text(encoding="utf-8"))

    def test_runs_the_frozen_next_lower_effort_matrix(self):
        client = RecordingHostedClient()
        configurations = self.runner.LOWER_EFFORT_CONFIGURATIONS

        manifest = self.run_screen(client, configurations=configurations)

        expected = [
            (identifier, model, effort, case_id)
            for identifier, model, effort in LOWER_EFFORT_CONFIGURATIONS
            for case_id in HARD_CASE_IDS
        ]
        self.assertEqual(12, len(client.calls))
        for call, (_identifier, model, effort, case_id) in zip(client.calls, expected):
            self.assertEqual(model, call["model"])
            self.assertEqual(effort, call["reasoning_effort"])
            self.assertEqual(self.fixture["userPrompts"][case_id], call["user_prompt"])
        self.assertEqual(
            [
                {"id": identifier, "model": model, "reasoningEffort": effort}
                for identifier, model, effort in LOWER_EFFORT_CONFIGURATIONS
            ],
            manifest["configurations"],
        )

    def test_refuses_overwrite_before_any_provider_call(self):
        destination = self.root / "existing"
        destination.mkdir()
        client = RecordingHostedClient()

        with self.assertRaisesRegex(ValueError, "overwrite"):
            self.run_screen(client, destination)

        self.assertEqual([], client.calls)

    def test_main_reads_environment_key_and_prints_only_summary(self):
        import openai_responses

        destination = self.root / "cli-run"
        client = RecordingHostedClient()
        key = "sk-test-screen-private"
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
        self.assertEqual(12, len(client.calls))
        self.assertEqual(12, json.loads(output.getvalue())["recordCount"])
        for path in destination.rglob("*"):
            if path.is_file():
                self.assertNotIn(key, path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()

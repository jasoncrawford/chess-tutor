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
    EXAMPLE_IDS,
    synthetic_source_pins,
    write_synthetic_source,
)


def load_runner(test_case):
    try:
        return importlib.import_module("run_hosted_chess_native_pilot")
    except ModuleNotFoundError:
        test_case.fail("run_hosted_chess_native_pilot is not implemented")


class RecordingHostedClient:
    def __init__(self, response_for_index=None):
        self.calls = []
        self.response_for_index = response_for_index or self._valid_response

    @staticmethod
    def _valid_response(index):
        turn = {
            "message": f"Look for one calm choice number {index + 1}.",
            "actions": [],
            "focus": [],
        }
        return {
            "id": f"resp_{index + 1}",
            "model": "gpt-5.6-sol-2026-08-01",
            "status": "completed",
            "output_text": json.dumps(turn, separators=(",", ":")),
            "usage": {
                "input_tokens": 700 + index,
                "output_tokens": 20 + index,
                "reasoning_tokens": 5 + index,
                "total_tokens": 725 + 3 * index,
            },
        }

    def complete(self, **arguments):
        index = len(self.calls)
        self.calls.append(arguments)
        response = self.response_for_index(index)
        if isinstance(response, Exception):
            raise response
        return response


class HostedChessNativePilotTests(unittest.TestCase):
    def setUp(self):
        self.runner = load_runner(self)
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.fixture = write_synthetic_source(self.root)

    def tearDown(self):
        self.temporary.cleanup()

    def run_pilot(self, client, destination=None):
        destination = destination or self.root / "hosted-run"
        with synthetic_source_pins(self.runner, self.fixture):
            return self.runner.run_hosted_pilot(
                source_dir=self.fixture["source"],
                system_prompt_path=self.fixture["systemPath"],
                destination=destination,
                client=client,
                timeout=7,
            )

    def test_runs_exact_eight_frozen_messages_once_with_request_specific_schema(self):
        client = RecordingHostedClient()
        manifest = self.run_pilot(client)

        self.assertEqual([call["user_prompt"] for call in client.calls], [
            self.fixture["userPrompts"][identifier] for identifier in EXAMPLE_IDS
        ])
        self.assertEqual(len(client.calls), 8)
        for call in client.calls:
            self.assertEqual(call["system_prompt"], self.fixture["system"])
            self.assertEqual(call["model"], "gpt-5.6-sol")
            self.assertEqual(call["reasoning_effort"], "high")
            self.assertEqual(call["maximum_output_tokens"], 2048)
            self.assertEqual(call["timeout"], 7)
            schema = call["schema"]
            self.assertEqual(schema["required"], ["message", "actions", "focus"])
            self.assertFalse(schema["additionalProperties"])
            encoded_schema = json.dumps(schema, sort_keys=True)
            self.assertNotIn('"const"', encoded_schema)
            self.assertNotIn('"uniqueItems"', encoded_schema)
            self.assertEqual(
                schema["properties"]["actions"]["items"]["enum"],
                ["hint"] if call["user_prompt"].find("Actions: hint\n") >= 0 else [
                    "hint", "playMove", "tryAnotherMove"
                ],
            )

        self.assertEqual(manifest["summary"], {
            "recordCount": 8,
            "completionAttempts": 8,
            "validCount": 8,
            "invalidCount": 0,
            "providerErrorCount": 0,
        })
        self.assertEqual(manifest["provider"]["model"], "gpt-5.6-sol")
        self.assertEqual(manifest["provider"]["reasoningEffort"], "high")

        destination = self.root / "hosted-run"
        record = json.loads((destination / "records" / "01-quiet-help.json").read_text())
        self.assertEqual(record["providerResponseID"], "resp_1")
        self.assertEqual(record["providerModel"], "gpt-5.6-sol-2026-08-01")
        self.assertEqual(record["parsedTurn"]["actions"], [])
        self.assertEqual(record["metrics"]["inputTokens"], 700)
        self.assertEqual(record["metrics"]["reasoningTokens"], 5)
        self.assertNotIn("reasoning", record)

    def test_invalid_and_provider_failure_are_redacted_and_do_not_stop_later_cases(self):
        private_marker = "PRIVATE_PROVIDER_BODY"

        def response(index):
            if index == 1:
                return RecordingHostedClient._valid_response(index) | {
                    "output_text": json.dumps({
                        "message": "Try Nf3.", "actions": [], "focus": []
                    })
                }
            if index == 3:
                return OSError(private_marker)
            return RecordingHostedClient._valid_response(index)

        client = RecordingHostedClient(response)
        manifest = self.run_pilot(client)
        self.assertEqual(len(client.calls), 8)
        self.assertEqual(manifest["summary"]["validCount"], 6)
        self.assertEqual(manifest["summary"]["providerErrorCount"], 1)

        destination = self.root / "hosted-run"
        invalid = json.loads(
            (destination / "records" / "02-attacked-piece.json").read_text()
        )
        failed = json.loads(
            (destination / "records" / "04-replaced-tentative-move.json").read_text()
        )
        self.assertEqual(invalid["generationStatus"], "invalid")
        self.assertEqual(failed["generationStatus"], "generationError")
        self.assertEqual(failed["errors"], [{
            "kind": "generationError",
            "message": "Hosted provider generation failed.",
        }])
        for path in destination.rglob("*"):
            if path.is_file():
                self.assertNotIn(private_marker, path.read_text())

    def test_refuses_missing_key_and_never_returns_or_persists_it(self):
        self.assertRaisesRegex(
            ValueError,
            "OPENAI_API_KEY",
            self.runner._api_key_from_environment,
            {},
        )
        key = "sk-test-private-value"
        self.assertEqual(
            self.runner._api_key_from_environment({"OPENAI_API_KEY": key}), key
        )

        client = RecordingHostedClient()
        self.run_pilot(client)
        for path in (self.root / "hosted-run").rglob("*"):
            if path.is_file():
                self.assertNotIn(key, path.read_text())

    def test_refuses_overwrite_before_any_provider_call(self):
        destination = self.root / "existing"
        destination.mkdir()
        client = RecordingHostedClient()
        with self.assertRaisesRegex(ValueError, "Refusing to overwrite"):
            self.run_pilot(client, destination)
        self.assertEqual(client.calls, [])

    def test_atomic_publish_failure_leaves_no_destination_or_temporary_directory(self):
        destination = self.root / "publish"
        client = RecordingHostedClient()
        with (
            synthetic_source_pins(self.runner, self.fixture),
            mock.patch.object(self.runner.os, "rename", side_effect=OSError("private")),
            self.assertRaises(OSError),
        ):
            self.runner.run_hosted_pilot(
                source_dir=self.fixture["source"],
                system_prompt_path=self.fixture["systemPath"],
                destination=destination,
                client=client,
                timeout=7,
            )

        self.assertFalse(destination.exists())
        self.assertEqual(list(self.root.glob(".publish.tmp-*")), [])

    def test_main_uses_environment_key_without_persisting_it(self):
        import openai_responses

        destination = self.root / "cli-run"
        client = RecordingHostedClient()
        key = "sk-test-main-private"
        argv = [
            "--source", str(self.fixture["source"]),
            "--system-prompt", str(self.fixture["systemPath"]),
            "--destination", str(destination),
            "--timeout", "7",
        ]
        output = io.StringIO()
        with (
            synthetic_source_pins(self.runner, self.fixture),
            mock.patch.dict(os.environ, {"OPENAI_API_KEY": key}, clear=True),
            mock.patch.object(
                openai_responses,
                "OpenAIResponsesClient",
                return_value=client,
            ) as constructor,
            contextlib.redirect_stdout(output),
        ):
            result = self.runner.main(argv)

        self.assertEqual(result, 0)
        constructor.assert_called_once_with(
            "https://api.openai.com", api_key=key
        )
        self.assertEqual(len(client.calls), 8)
        self.assertEqual(json.loads(output.getvalue())["recordCount"], 8)
        for path in destination.rglob("*"):
            if path.is_file():
                self.assertNotIn(key, path.read_text())


if __name__ == "__main__":
    unittest.main()

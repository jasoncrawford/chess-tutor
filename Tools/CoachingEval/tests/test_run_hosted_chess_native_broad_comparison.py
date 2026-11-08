import contextlib
import csv
import hashlib
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

from Tools.CoachingEval.tests.test_run_hosted_chess_native_pilot import (  # noqa: E402
    RecordingHostedClient,
)


CASE_IDS = tuple(f"b{index:02}-case" for index in range(1, 13))
CONFIGURATIONS = (
    ("sol-high", "gpt-5.6-sol", "high"),
    ("luna-high", "gpt-5.6-luna", "high"),
)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def canonical_json(value):
    return (
        json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    ).encode("utf-8")


def write_broad_source(root):
    source = root / "swift-export"
    users = source / "user-prompts"
    users.mkdir(parents=True)
    system = "# Chess Tutor v6\n\nCoach one short turn from the supplied facts.\n"
    system_bytes = system.encode("utf-8")
    system_path = root / "tutor-v6.md"
    system_path.write_bytes(system_bytes)
    (source / "system-prompt.md").write_bytes(system_bytes)
    audit_bytes = b"audit-only\n"
    (source / "examples.jsonl").write_bytes(audit_bytes)
    declared = [
        {"path": "examples.jsonl", "role": "auditOnly"},
        {"path": "preview-manifest.json", "role": "auditOnly"},
        {"path": "system-prompt.md", "role": "modelFacingSystemMessage"},
    ]
    examples = []
    prompts = {}
    for index, identifier in enumerate(CASE_IDS, start=1):
        actions = "hint" if index <= 4 else "hint, playMove, tryAnotherMove"
        moves = "none" if index <= 4 else "b1-c3"
        prompt = (
            "# Chess coaching situation\n\n"
            "## Position\n\n"
            "Side to move: White\n"
            "Status: ongoing\n"
            f"Moves: e4 e5 Nf3 Nc6 {index}\n"
            "Tentative move: none\n\n"
            "## Latest interaction\n\n"
            "Help opened.\n\n"
            "## Relevant legal facts\n\n"
            "White is not in check.\n\n"
            "## Available UI response\n\n"
            f"Actions: {actions}\n"
            "Square focus: any board square\n"
            f"Allowable move focus: {moves}"
        )
        user_bytes = prompt.encode("utf-8")
        file_name = f"{identifier}.md"
        relative = f"user-prompts/{file_name}"
        (source / relative).write_bytes(user_bytes)
        declared.append({"path": relative, "role": "modelFacingUserMessage"})
        examples.append(
            {
                "fileName": file_name,
                "id": identifier,
                "requestSHA256": sha256(f"request-{identifier}".encode()),
                "systemPromptSHA256": sha256(system_bytes),
                "userPromptSHA256": sha256(user_bytes),
            }
        )
        prompts[identifier] = prompt
    manifest = {
        "contextSchemaVersion": "model-coaching-chess-native-context.v1",
        "declaredFiles": declared,
        "exampleIDs": list(CASE_IDS),
        "examples": examples,
        "examplesJSONLSHA256": sha256(audit_bytes),
        "promptVersion": "tutor-v6",
        "requestSchemaVersion": "model-coaching-neutral-request.v1",
        "schemaVersion": "model-coaching-chess-native-preview-manifest.v2",
        "systemPromptSHA256": sha256(system_bytes),
    }
    manifest_bytes = canonical_json(manifest)
    (source / "preview-manifest.json").write_bytes(manifest_bytes)
    return {
        "source": source,
        "systemPath": system_path,
        "system": system,
        "prompts": prompts,
        "sourceManifestSHA256": sha256(manifest_bytes),
        "examplesJSONLSHA256": sha256(audit_bytes),
    }


def load_runner(test_case):
    try:
        return importlib.import_module("run_hosted_chess_native_broad_comparison")
    except ModuleNotFoundError:
        test_case.fail("run_hosted_chess_native_broad_comparison is not implemented")


class HostedChessNativeBroadComparisonTests(unittest.TestCase):
    def setUp(self):
        self.runner = load_runner(self)
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.fixture = write_broad_source(self.root)

    def tearDown(self):
        self.temporary.cleanup()

    def run_comparison(self, client, destination=None, **overrides):
        arguments = {
            "source_dir": self.fixture["source"],
            "system_prompt_path": self.fixture["systemPath"],
            "destination": destination or self.root / "run",
            "client": client,
            "case_ids": CASE_IDS,
            "expected_source_manifest_sha256": self.fixture[
                "sourceManifestSHA256"
            ],
            "expected_examples_jsonl_sha256": self.fixture[
                "examplesJSONLSHA256"
            ],
            "timeout": 9,
            "review_seed": b"fixed-review-seed",
        }
        arguments.update(overrides)
        return self.runner.run_broad_comparison(**arguments)

    def test_runs_exact_two_by_twelve_matrix_and_writes_blinded_review(self):
        client = RecordingHostedClient()

        manifest = self.run_comparison(client)

        expected = [
            (configuration, model, effort, case_id)
            for configuration, model, effort in CONFIGURATIONS
            for case_id in CASE_IDS
        ]
        self.assertEqual(24, len(client.calls))
        for call, (_configuration, model, effort, case_id) in zip(
            client.calls, expected
        ):
            self.assertEqual(self.fixture["system"], call["system_prompt"])
            self.assertEqual(self.fixture["prompts"][case_id], call["user_prompt"])
            self.assertEqual(model, call["model"])
            self.assertEqual(effort, call["reasoning_effort"])
            self.assertEqual(2048, call["maximum_output_tokens"])
            self.assertEqual(9, call["timeout"])
            self.assertEqual(
                ["message", "actions", "focus"], call["schema"]["required"]
            )
            self.assertFalse(call["schema"]["additionalProperties"])

        self.assertEqual(24, manifest["summary"]["recordCount"])
        self.assertEqual(24, manifest["summary"]["validCount"])
        run = self.root / "run"
        packet = [
            json.loads(line)
            for line in (run / "review" / "review-packet.jsonl")
            .read_text(encoding="utf-8")
            .splitlines()
        ]
        key = json.loads((run / "review" / "review-key.json").read_text())
        with (run / "review" / "rubric.csv").open(newline="") as handle:
            rubric = list(csv.DictReader(handle))
        self.assertEqual(24, len(packet))
        self.assertEqual(24, len({row["reviewID"] for row in packet}))
        self.assertEqual([row["reviewID"] for row in packet], [
            row["reviewID"] for row in rubric
        ])
        self.assertTrue(all(not any(row[field] for field in row if field != "reviewID") for row in rubric))
        self.assertEqual(
            {row["reviewID"] for row in packet},
            {row["reviewID"] for row in key["entries"]},
        )
        public_text = (run / "review" / "review-packet.jsonl").read_text()
        for forbidden in (
            "sol-high",
            "luna-high",
            "gpt-5.6",
            "providerResponseID",
            "providerModel",
            "reasoning",
            "trace",
        ):
            self.assertNotIn(forbidden, public_text)

    def test_preflights_every_schema_before_first_call_and_refuses_hash_drift(self):
        client = RecordingHostedClient()
        bad_prompt = self.fixture["source"] / "user-prompts" / f"{CASE_IDS[-1]}.md"
        bad_prompt.write_text("not a valid prompt", encoding="utf-8")

        with self.assertRaises(ValueError):
            self.run_comparison(client)
        self.assertEqual([], client.calls)
        self.assertFalse((self.root / "run").exists())

        client = RecordingHostedClient()
        with self.assertRaisesRegex(ValueError, "source manifest"):
            self.run_comparison(
                client,
                destination=self.root / "hash-drift",
                expected_source_manifest_sha256="0" * 64,
            )
        self.assertEqual([], client.calls)

    def test_invalid_and_provider_failure_are_redacted_and_do_not_stop(self):
        private_marker = "PRIVATE_BROAD_PROVIDER_BODY"

        def response(index):
            if index == 2:
                return OSError(private_marker)
            if index == 4:
                value = RecordingHostedClient._valid_response(index)
                value["output_text"] = json.dumps(
                    {"message": "Try Nf3.", "actions": [], "focus": []}
                )
                return value
            return RecordingHostedClient._valid_response(index)

        client = RecordingHostedClient(response)
        manifest = self.run_comparison(client)

        self.assertEqual(24, len(client.calls))
        self.assertEqual(22, manifest["summary"]["validCount"])
        self.assertEqual(1, manifest["summary"]["providerErrorCount"])
        for path in (self.root / "run").rglob("*"):
            if path.is_file():
                self.assertNotIn(private_marker, path.read_text(encoding="utf-8"))

    def test_refuses_overwrite_before_any_provider_call(self):
        destination = self.root / "existing"
        destination.mkdir()
        client = RecordingHostedClient()

        with self.assertRaisesRegex(ValueError, "overwrite"):
            self.run_comparison(client, destination=destination)
        self.assertEqual([], client.calls)

    def test_main_reads_environment_key_and_prints_only_summary(self):
        import openai_responses

        client = RecordingHostedClient()
        key = "sk-test-broad-private"
        destination = self.root / "cli"
        argv = [
            "--source",
            str(self.fixture["source"]),
            "--system-prompt",
            str(self.fixture["systemPath"]),
            "--destination",
            str(destination),
            "--source-manifest-sha256",
            self.fixture["sourceManifestSHA256"],
            "--examples-jsonl-sha256",
            self.fixture["examplesJSONLSHA256"],
        ]
        for case_id in CASE_IDS:
            argv.extend(("--case-id", case_id))
        argv.extend(("--timeout", "9"))
        output = io.StringIO()
        with (
            mock.patch.dict(os.environ, {"OPENAI_API_KEY": key}, clear=True),
            mock.patch.object(
                openai_responses, "OpenAIResponsesClient", return_value=client
            ) as constructor,
            mock.patch.object(self.runner.os, "urandom", return_value=b"x" * 32),
            contextlib.redirect_stdout(output),
        ):
            result = self.runner.main(argv)

        self.assertEqual(0, result)
        constructor.assert_called_once_with("https://api.openai.com", api_key=key)
        self.assertEqual(24, len(client.calls))
        self.assertEqual(24, json.loads(output.getvalue())["recordCount"])
        for path in destination.rglob("*"):
            if path.is_file():
                self.assertNotIn(key, path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()

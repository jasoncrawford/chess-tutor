import contextlib
import hashlib
import importlib
import io
import json
import math
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


TOOLS_DIR = Path(__file__).resolve().parents[1]
EXAMPLE_IDS = (
    "01-quiet-help",
    "02-attacked-piece",
    "03-selected-piece",
    "04-replaced-tentative-move",
    "05-tactical-reply",
    "06-inspected-reply",
    "07-answering-check",
    "08-long-history",
)

sys.path.insert(0, str(TOOLS_DIR))


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def canonical_json(value):
    return json.dumps(
        value, indent=2, sort_keys=True, ensure_ascii=False
    ).encode("utf-8") + b"\n"


def write_synthetic_source(root):
    source = root / "swift-export"
    users = source / "user-prompts"
    users.mkdir(parents=True)
    system = (
        "# Chess Tutor v6\n\n"
        "Coach one short turn from chess-native facts in ordinary language.\n"
    )
    system_bytes = system.encode("utf-8")
    system_path = root / "tutor-v6.md"
    system_path.write_bytes(system_bytes)
    (source / "system-prompt.md").write_bytes(system_bytes)

    audit_bytes = (
        b'{"response":{"message":"AUDIT RESPONSE MUST NOT BE SENT"},'
        b'"hidden":"AUDIT HIDDEN MUST NOT BE SENT",'
        b'"trace":"AUDIT TRACE MUST NOT BE SENT"}\n'
    )
    (source / "examples.jsonl").write_bytes(audit_bytes)
    declared_files = [
        {"path": "examples.jsonl", "role": "auditOnly"},
        {"path": "preview-manifest.json", "role": "auditOnly"},
        {"path": "system-prompt.md", "role": "modelFacingSystemMessage"},
    ]
    examples = []
    user_prompts = {}
    for index, identifier in enumerate(EXAMPLE_IDS, start=1):
        actions = (
            "hint, playMove, tryAnotherMove"
            if index in {4, 5, 6, 7}
            else "hint"
        )
        allowable_moves = "g1-f3" if index in {3, 4, 5, 6, 7} else "none"
        markdown = (
            "# Chess coaching situation\n\n"
            "## Position\n\n"
            f"Side to move: {'White' if index % 2 else 'Black'}\n"
            "Status: ongoing\n"
            "Moves: none\n"
            "Tentative move: none\n\n"
            "## Latest interaction\n\n"
            "Help opened.\n\n"
            "## Relevant legal facts\n\n"
            "White is not in check.\n\n"
            "## Available UI response\n\n"
            f"Actions: {actions}\n"
            "Square focus: any board square\n"
            f"Allowable move focus: {allowable_moves}"
        )
        user_bytes = markdown.encode("utf-8")
        file_name = f"{identifier}.md"
        relative_path = f"user-prompts/{file_name}"
        (source / relative_path).write_bytes(user_bytes)
        declared_files.append(
            {"path": relative_path, "role": "modelFacingUserMessage"}
        )
        examples.append(
            {
                "fileName": file_name,
                "id": identifier,
                "requestSHA256": sha256(f"request-{identifier}".encode("utf-8")),
                "systemPromptSHA256": sha256(system_bytes),
                "userPromptSHA256": sha256(user_bytes),
            }
        )
        user_prompts[identifier] = markdown

    manifest = {
        "contextSchemaVersion": "model-coaching-chess-native-context.v1",
        "declaredFiles": declared_files,
        "exampleIDs": list(EXAMPLE_IDS),
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
        "userPrompts": user_prompts,
        "sourceManifestSHA256": sha256(manifest_bytes),
        "examplesJSONLSHA256": sha256(audit_bytes),
        "systemPromptSHA256": sha256(system_bytes),
    }


def write_synthetic_provenance_files(
    root,
    *,
    model_id="smollm3-3b-q4_k_m",
    filename="SmolLM3-Q4_K_M.gguf",
):
    model_bytes = b"synthetic-smollm3-artifact"
    model_path = root / "models" / filename
    model_path.parent.mkdir(parents=True)
    model_path.write_bytes(model_bytes)
    revision = "1" * 40
    model_manifest = {
        "bytes": len(model_bytes),
        "filename": model_path.name,
        "license": "Apache-2.0",
        "modelID": model_id,
        "repository": "synthetic/test-only",
        "requestedRevision": "main",
        "resolvedRevision": revision,
        "selector": "Q4_K_M",
        "sha256": sha256(model_bytes),
    }
    model_manifest_path = model_path.parent / "artifact-manifest.json"
    model_manifest_bytes = canonical_json(model_manifest)
    model_manifest_path.write_bytes(model_manifest_bytes)

    server_path = root / "runtime" / "llama-server"
    server_path.parent.mkdir(parents=True)
    server_path.write_bytes(b"synthetic-server-not-executed")
    runtime_manifest_path = server_path.parent / "runtime-manifest.json"
    runtime_manifest_bytes = canonical_json(
        {
            "binaryPath": str(server_path.resolve()),
            "binarySHA256": sha256(server_path.read_bytes()),
            "sourceCommit": "2" * 40,
            "sourceTag": "b10516",
            "versionOutput": "synthetic version",
        }
    )
    runtime_manifest_path.write_bytes(runtime_manifest_bytes)
    return {
        "modelPath": model_path,
        "modelBytes": model_bytes,
        "modelManifestPath": model_manifest_path,
        "modelManifestSHA256": sha256(model_manifest_bytes),
        "revision": revision,
        "serverPath": server_path,
        "runtimeManifestPath": runtime_manifest_path,
        "runtimeManifestSHA256": sha256(runtime_manifest_bytes),
        "runtimeBinarySHA256": sha256(server_path.read_bytes()),
        "runtimeCommit": "2" * 40,
    }


@contextlib.contextmanager
def synthetic_source_pins(runner, fixture):
    with mock.patch.multiple(
        runner,
        SOURCE_MANIFEST_SHA256=fixture["sourceManifestSHA256"],
        EXAMPLES_JSONL_SHA256=fixture["examplesJSONLSHA256"],
        SYSTEM_PROMPT_SHA256=fixture["systemPromptSHA256"],
    ):
        yield


def load_runner(test_case):
    try:
        return importlib.import_module("run_chess_native_pilot")
    except ModuleNotFoundError:
        test_case.fail("run_chess_native_pilot is not implemented")


def exact_provenance():
    return {
        **exact_verified_provenance(),
        "serverCommand": ["fake-llama-server", "--test-only"],
        "pilotCommand": ["python3", "run_chess_native_pilot.py", "--test-only"],
    }


def exact_verified_provenance():
    return {
        "modelID": "smollm3-3b-q4_k_m",
        "modelArtifactSHA256": (
            "8334b850b7bd46238c16b0c550df2138f0889bf433809008cc17a8b05761863e"
        ),
        "modelArtifactBytes": 1915305312,
        "modelArtifactManifestSHA256": (
            "3037744008c5c6c656294b7998c78727dde2adfcf89bd186dee85116ef4c8bcf"
        ),
        "modelResolvedRevision": "4965cb60b150737b68a0408c36aeefb65078f894",
        "runtimeSourceTag": "b10516",
        "runtimeSourceCommit": "b95502ba9aa0eb73a2f4fc8878d7fbe6a847a0b9",
        "runtimeBinarySHA256": (
            "fa65f946a434fcb34de87520ab76a3f2d576f97ad9f5a81b3a6e4201daff137e"
        ),
        "runtimeManifestSHA256": (
            "27a5ebb2a0e3beee2c407e58173f1397ec183970cb721f0a5bf8be871340205b"
        ),
        "runtimeVersion": "version: 0.1.2-dev (build 10516, commit b95502ba9a)",
    }


class RecordingPilotClient:
    def __init__(self, *, token_counts=None, response_for_index=None):
        self.events = []
        self.token_counts = list(token_counts or [640] * len(EXAMPLE_IDS))
        self.response_for_index = response_for_index or self._valid_response
        self.completion_count = 0

    @staticmethod
    def _valid_response(index):
        candidate = json.dumps(
            {
                "message": f"Look for one calm move number {index + 1}.",
                "actions": [],
                "focus": [],
            },
            separators=(",", ":"),
        )
        return {
            "content": "<think>PRIVATE REASONING</think>\n" + candidate,
            "choices": [
                {
                    "message": {
                        "role": "assistant",
                        "content": "<think>PRIVATE REASONING</think>\n" + candidate,
                        "reasoning_content": "PRIVATE PROVIDER TRACE",
                    },
                    "finish_reason": "eos",
                }
            ],
            "usage": {"prompt_tokens": 700 + index, "completion_tokens": 20 + index},
            "timings": {
                "prompt_ms": 10.5 + index,
                "predicted_ms": 20.5 + index,
            },
            "provider_response_body": "PRIVATE PROVIDER BODY",
        }

    def render_prompt(self, **arguments):
        self.events.append(("render", arguments))
        return "<system>\n{}\n</system>\n<user>\n{}\n</user>".format(
            arguments["system_prompt"], arguments["user_content"]
        )

    def token_count(self, prompt, **arguments):
        self.events.append(("token", {"prompt": prompt, **arguments}))
        return self.token_counts.pop(0)

    def complete_rendered(self, **arguments):
        self.events.append(("complete", arguments))
        index = self.completion_count
        self.completion_count += 1
        return self.response_for_index(index)


class ThrowingPilotClient(RecordingPilotClient):
    def __init__(self, errors):
        super().__init__()
        self.errors = dict(errors)

    def complete_rendered(self, **arguments):
        self.events.append(("complete", arguments))
        index = self.completion_count
        self.completion_count += 1
        if index in self.errors:
            raise self.errors[index]
        return self._valid_response(index)


class FakeLlamaServer:
    instances = []

    def __init__(self, executable, model_path, *, context_tokens):
        self.executable = Path(executable)
        self.model_path = Path(model_path)
        self.context_tokens = context_tokens
        self.command = []
        self.started_with = None
        self.stopped = False
        self.client = RecordingPilotClient()
        self.__class__.instances.append(self)

    def start(self, timeout):
        self.started_with = timeout
        self.command = [
            str(self.executable),
            "-m",
            str(self.model_path),
            "-c",
            str(self.context_tokens),
        ]

    def stop(self):
        self.stopped = True

    def render_prompt(self, **arguments):
        return self.client.render_prompt(**arguments)

    def token_count(self, prompt, **arguments):
        return self.client.token_count(prompt, **arguments)

    def complete_rendered(self, **arguments):
        return self.client.complete_rendered(**arguments)


class ChessNativePilotRunnerTests(unittest.TestCase):
    def run_pilot(self, root, destination, client, **overrides):
        runner = load_runner(self)
        fixture = write_synthetic_source(root)
        arguments = {
            "source_dir": fixture["source"],
            "system_prompt_path": fixture["systemPath"],
            "destination": destination,
            "client": client,
            "provenance": exact_provenance(),
            "timeout": 37,
        }
        arguments.update(overrides)
        with synthetic_source_pins(runner, fixture):
            return runner.run_pilot(**arguments), fixture

    def test_runs_exact_frozen_eight_cases_once_after_complete_preflight(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            destination = root / "pilot"
            client = RecordingPilotClient()

            manifest, fixture = self.run_pilot(root, destination, client)

            self.assertEqual(
                ["render", "token"] * 8 + ["complete"] * 8,
                [kind for kind, _arguments in client.events],
            )
            render_calls = [arguments for kind, arguments in client.events if kind == "render"]
            token_calls = [arguments for kind, arguments in client.events if kind == "token"]
            completion_calls = [
                arguments for kind, arguments in client.events if kind == "complete"
            ]
            system_text = fixture["system"]
            for identifier, render_call, token_call, completion_call in zip(
                EXAMPLE_IDS, render_calls, token_calls, completion_calls
            ):
                user_text = fixture["userPrompts"][identifier]
                expected_rendered = (
                    f"<system>\n{system_text}\n</system>\n<user>\n{user_text}\n</user>"
                )
                self.assertEqual(
                    {
                        "system_prompt": system_text,
                        "user_content": user_text,
                        "enable_thinking": True,
                        "timeout": 37,
                    },
                    render_call,
                )
                self.assertEqual({"prompt": expected_rendered, "timeout": 37}, token_call)
                self.assertEqual(expected_rendered, completion_call["prompt"])
                self.assertIn('thinking-block ::= "<think>"', completion_call["grammar"])
                self.assertEqual(1103, completion_call["seed"])
                self.assertEqual(512, completion_call["maximum_output_tokens"])
                self.assertEqual(0.2, completion_call["temperature"])
                self.assertEqual(0.95, completion_call["top_p"])
                self.assertEqual(37, completion_call["timeout"])
                self.assertEqual(
                    {
                        "prompt",
                        "grammar",
                        "seed",
                        "maximum_output_tokens",
                        "temperature",
                        "top_p",
                        "timeout",
                    },
                    set(completion_call),
                )

            all_model_arguments = json.dumps(
                [arguments for _kind, arguments in client.events], sort_keys=True
            )
            self.assertNotIn('"request":', all_model_arguments)
            self.assertNotIn('"legalMoves":', all_model_arguments)
            self.assertNotIn('"occupiedSquareRelationships":', all_model_arguments)
            self.assertNotIn('"visibility":', all_model_arguments)
            self.assertNotIn("AUDIT RESPONSE MUST NOT BE SENT", all_model_arguments)
            self.assertNotIn("AUDIT HIDDEN MUST NOT BE SENT", all_model_arguments)
            self.assertNotIn("AUDIT TRACE MUST NOT BE SENT", all_model_arguments)
            self.assertNotIn("PRIVATE PROVIDER TRACE", all_model_arguments)

            self.assertEqual("model-coaching-chess-native-pilot.v1", manifest["schemaVersion"])
            self.assertEqual(list(EXAMPLE_IDS), manifest["exampleIDs"])
            self.assertEqual(
                fixture["sourceManifestSHA256"],
                manifest["sourceManifestSHA256"],
            )
            self.assertEqual(exact_provenance(), manifest["provenance"])
            self.assertEqual(
                {
                    "mode": "bounded",
                    "seed": 1103,
                    "maximumOutputTokens": 512,
                    "temperature": 0.2,
                    "topP": 0.95,
                    "promptBudgetTokens": 2500,
                },
                manifest["settings"],
            )
            self.assertEqual(8, manifest["summary"]["validCount"])
            self.assertEqual(0, manifest["summary"]["invalidCount"])
            self.assertEqual(8, manifest["summary"]["completionAttempts"])

            record_files = sorted((destination / "records").glob("*.json"))
            self.assertEqual(
                [f"{identifier}.json" for identifier in EXAMPLE_IDS],
                [path.name for path in record_files],
            )
            for index, (identifier, path) in enumerate(zip(EXAMPLE_IDS, record_files)):
                record_bytes = path.read_bytes()
                record = json.loads(record_bytes)
                candidate = json.dumps(
                    {
                        "message": f"Look for one calm move number {index + 1}.",
                        "actions": [],
                        "focus": [],
                    },
                    separators=(",", ":"),
                )
                user_bytes = (
                    fixture["source"] / "user-prompts" / f"{identifier}.md"
                ).read_bytes()
                self.assertEqual(identifier, record["caseID"])
                self.assertEqual("valid", record["generationStatus"])
                self.assertEqual(candidate, record["finalContent"])
                self.assertEqual(json.loads(candidate), record["parsedTurn"])
                self.assertEqual({"valid": True, "errors": []}, record["validation"])
                self.assertEqual([], record["errors"])
                self.assertEqual(sha256(user_bytes), record["userPromptSHA256"])
                self.assertEqual(sha256(candidate.encode()), record["finalContentSHA256"])
                self.assertEqual(640, record["renderedPromptTokens"])
                self.assertEqual(700 + index, record["metrics"]["promptTokens"])
                self.assertEqual(20 + index, record["metrics"]["outputTokens"])
                self.assertEqual(10.5 + index, record["metrics"]["promptMilliseconds"])
                self.assertEqual(20.5 + index, record["metrics"]["generationMilliseconds"])
                self.assertTrue(
                    math.isfinite(record["metrics"]["latencyMilliseconds"])
                    and record["metrics"]["latencyMilliseconds"] >= 0
                )
                self.assertEqual(exact_provenance(), record["provenance"])
                manifest_record = manifest["records"][index]
                self.assertEqual(f"records/{identifier}.json", manifest_record["path"])
                self.assertEqual(sha256(record_bytes), manifest_record["sha256"])

            artifact_text = "\n".join(
                path.read_text(encoding="utf-8")
                for path in sorted(destination.rglob("*"))
                if path.is_file()
            )
            self.assertNotIn("PRIVATE REASONING", artifact_text)
            self.assertNotIn("PRIVATE PROVIDER TRACE", artifact_text)
            self.assertNotIn("PRIVATE PROVIDER BODY", artifact_text)
            self.assertNotIn("<think", artifact_text.lower())
            review = (destination / "review.md").read_text(encoding="utf-8")
            for identifier in EXAMPLE_IDS:
                self.assertIn(
                    f"[{identifier}.md]({(fixture['source'] / 'user-prompts' / f'{identifier}.md').resolve().as_posix()})",
                    review,
                )
            self.assertIn(
                f"[system-prompt.md]({(fixture['source'] / 'system-prompt.md').resolve().as_posix()})",
                review,
            )

    def test_aborts_all_generation_when_any_of_eight_prompts_exceeds_budget(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            destination = root / "pilot"
            client = RecordingPilotClient(token_counts=[2500] * 7 + [2501])

            with self.assertRaisesRegex(ValueError, "2,500"):
                self.run_pilot(root, destination, client)

            self.assertEqual(
                ["render", "token"] * 8,
                [kind for kind, _arguments in client.events],
            )
            self.assertEqual(0, client.completion_count)
            self.assertFalse(destination.exists())

    def test_classifies_invalid_output_without_repair_or_retry(self):
        invalid = (
            '{"message":"Look.","actions":[],"focus":[],"extra":"not allowed"}'
        )

        def response(index):
            result = RecordingPilotClient._valid_response(index)
            if index == 2:
                result["content"] = "<think>PRIVATE INVALID TRACE</think>\n" + invalid
                result["choices"][0]["message"]["content"] = result["content"]
            return result

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            destination = root / "pilot"
            client = RecordingPilotClient(response_for_index=response)

            manifest, _fixture = self.run_pilot(root, destination, client)

            self.assertEqual(8, client.completion_count)
            self.assertEqual(8, len([event for event in client.events if event[0] == "render"]))
            invalid_record = json.loads(
                (destination / "records" / "03-selected-piece.json").read_text(
                    encoding="utf-8"
                )
            )
            self.assertEqual("invalid", invalid_record["generationStatus"])
            self.assertEqual(invalid, invalid_record["finalContent"])
            self.assertIsNone(invalid_record["parsedTurn"])
            self.assertFalse(invalid_record["validation"]["valid"])
            self.assertEqual(1, len(invalid_record["validation"]["errors"]))
            self.assertEqual(1, manifest["summary"]["invalidCount"])
            self.assertEqual(7, manifest["summary"]["validCount"])
            self.assertNotIn(
                "PRIVATE INVALID TRACE",
                (destination / "records" / "03-selected-piece.json").read_text(
                    encoding="utf-8"
                ),
            )

    def test_redacts_provider_failures_and_continues_through_later_cases(self):
        runner = load_runner(self)
        errors = {
            1: runner.llama_server.LlamaServerError(
                "SECRET CONTEXT RESPONSE BODY",
                category="contextOverflow",
                http_status=413,
            ),
            3: runner.llama_server.LlamaServerTimeout("SECRET TIMEOUT RESPONSE BODY"),
            5: OSError("SECRET GENERIC RESPONSE BODY"),
        }
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            destination = root / "pilot"
            client = ThrowingPilotClient(errors)

            manifest, _fixture = self.run_pilot(root, destination, client)

            self.assertEqual(8, client.completion_count)
            self.assertEqual(8, manifest["summary"]["completionAttempts"])
            self.assertEqual(3, manifest["summary"]["providerErrorCount"])
            records = {
                identifier: json.loads(
                    (destination / "records" / f"{identifier}.json").read_text(
                        encoding="utf-8"
                    )
                )
                for identifier in EXAMPLE_IDS
            }
            self.assertEqual(
                "contextOverflow", records["02-attacked-piece"]["generationStatus"]
            )
            self.assertEqual(
                [{
                    "kind": "contextOverflow",
                    "message": "Provider request exceeded the context window.",
                }],
                records["02-attacked-piece"]["errors"],
            )
            self.assertEqual(
                [{
                    "kind": "generationError",
                    "message": "Provider response timed out.",
                }],
                records["04-replaced-tentative-move"]["errors"],
            )
            self.assertEqual(
                [{
                    "kind": "generationError",
                    "message": "Provider generation failed.",
                }],
                records["06-inspected-reply"]["errors"],
            )
            self.assertEqual("valid", records["03-selected-piece"]["generationStatus"])
            self.assertEqual("valid", records["05-tactical-reply"]["generationStatus"])
            self.assertEqual("valid", records["07-answering-check"]["generationStatus"])
            artifact_text = "\n".join(
                path.read_text(encoding="utf-8")
                for path in destination.rglob("*")
                if path.is_file()
            )
            self.assertNotIn("SECRET CONTEXT RESPONSE BODY", artifact_text)
            self.assertNotIn("SECRET TIMEOUT RESPONSE BODY", artifact_text)
            self.assertNotIn("SECRET GENERIC RESPONSE BODY", artifact_text)
            self.assertNotIn("PRIVATE REASONING", artifact_text)

    def test_pinned_provenance_hashes_synthetic_artifacts_without_running_them(self):
        runner = load_runner(self)
        with tempfile.TemporaryDirectory() as temporary:
            fixture = write_synthetic_provenance_files(Path(temporary))
            runtime_record = {
                "sourceTag": "b10516",
                "sourceCommit": fixture["runtimeCommit"],
                "binarySHA256": fixture["runtimeBinarySHA256"],
                "versionOutput": "synthetic version output",
            }
            with mock.patch.multiple(
                runner,
                MODEL_ARTIFACT_SHA256=sha256(fixture["modelBytes"]),
                MODEL_ARTIFACT_BYTES=len(fixture["modelBytes"]),
                MODEL_MANIFEST_SHA256=fixture["modelManifestSHA256"],
                MODEL_RESOLVED_REVISION=fixture["revision"],
                RUNTIME_SOURCE_TAG="b10516",
                RUNTIME_SOURCE_COMMIT=fixture["runtimeCommit"],
                RUNTIME_BINARY_SHA256=fixture["runtimeBinarySHA256"],
                RUNTIME_MANIFEST_SHA256=fixture["runtimeManifestSHA256"],
            ), mock.patch.object(
                runner.runtime_provenance,
                "verify_runtime",
                return_value=runtime_record,
            ):
                provenance = runner._pinned_provenance(
                    model_path=fixture["modelPath"],
                    model_manifest_path=fixture["modelManifestPath"],
                    server_path=fixture["serverPath"],
                    runtime_manifest_path=fixture["runtimeManifestPath"],
                )

            self.assertEqual(
                {
                    "modelID": "smollm3-3b-q4_k_m",
                    "modelArtifactSHA256": sha256(fixture["modelBytes"]),
                    "modelArtifactBytes": len(fixture["modelBytes"]),
                    "modelArtifactManifestSHA256": fixture["modelManifestSHA256"],
                    "modelResolvedRevision": fixture["revision"],
                    "runtimeSourceTag": "b10516",
                    "runtimeSourceCommit": fixture["runtimeCommit"],
                    "runtimeBinarySHA256": fixture["runtimeBinarySHA256"],
                    "runtimeManifestSHA256": fixture["runtimeManifestSHA256"],
                    "runtimeVersion": "synthetic version output",
                },
                provenance,
            )

    def test_qwen_candidate_validates_its_artifact_and_persists_its_identity(self):
        runner = load_runner(self)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fixture = write_synthetic_provenance_files(
                root,
                model_id="qwen3-1.7b-q4_k_m",
                filename="Qwen3-1.7B-Q4_K_M.gguf",
            )
            candidate = runner.ModelCandidate(
                identifier="qwen3-1.7b-q4_k_m",
                display_name="Qwen3 1.7B",
                filename="Qwen3-1.7B-Q4_K_M.gguf",
                artifact_sha256=sha256(fixture["modelBytes"]),
                artifact_bytes=len(fixture["modelBytes"]),
                manifest_sha256=fixture["modelManifestSHA256"],
                resolved_revision=fixture["revision"],
            )
            runtime_record = {
                "sourceTag": "b10516",
                "sourceCommit": fixture["runtimeCommit"],
                "binarySHA256": fixture["runtimeBinarySHA256"],
                "versionOutput": "synthetic version output",
            }
            with mock.patch.multiple(
                runner,
                RUNTIME_SOURCE_TAG="b10516",
                RUNTIME_SOURCE_COMMIT=fixture["runtimeCommit"],
                RUNTIME_BINARY_SHA256=fixture["runtimeBinarySHA256"],
                RUNTIME_MANIFEST_SHA256=fixture["runtimeManifestSHA256"],
            ), mock.patch.object(
                runner.runtime_provenance,
                "verify_runtime",
                return_value=runtime_record,
            ):
                verified = runner._pinned_provenance(
                    candidate=candidate,
                    model_path=fixture["modelPath"],
                    model_manifest_path=fixture["modelManifestPath"],
                    server_path=fixture["serverPath"],
                    runtime_manifest_path=fixture["runtimeManifestPath"],
                )

            provenance = {
                **verified,
                "runtimeSourceTag": "b10516",
                "runtimeSourceCommit": (
                    "b95502ba9aa0eb73a2f4fc8878d7fbe6a847a0b9"
                ),
                "runtimeBinarySHA256": (
                    "fa65f946a434fcb34de87520ab76a3f2d576f97ad9f5a81b3a6e4201daff137e"
                ),
                "runtimeManifestSHA256": (
                    "27a5ebb2a0e3beee2c407e58173f1397ec183970cb721f0a5bf8be871340205b"
                ),
                "runtimeVersion": (
                    "version: 0.1.2-dev (build 10516, commit b95502ba9a)"
                ),
                "serverCommand": ["fake-llama-server", "--test-only"],
                "pilotCommand": ["python3", "run_chess_native_pilot.py", "--test-only"],
            }
            destination = root / "qwen-pilot"
            manifest, _fixture = self.run_pilot(
                root / "source",
                destination,
                RecordingPilotClient(),
                candidate=candidate,
                provenance=provenance,
            )

            self.assertEqual("qwen3-1.7b-q4_k_m", verified["modelID"])
            self.assertEqual(
                "qwen3-1.7b-q4_k_m", manifest["provenance"]["modelID"]
            )
            record = json.loads(
                (destination / "records" / "01-quiet-help.json").read_text(
                    encoding="utf-8"
                )
            )
            self.assertEqual(
                "qwen3-1.7b-q4_k_m", record["provenance"]["modelID"]
            )

    def test_qwen_candidate_rejects_an_artifact_manifest_for_smollm3(self):
        runner = load_runner(self)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fixture = write_synthetic_provenance_files(root)
            candidate = runner.ModelCandidate(
                identifier="qwen3-1.7b-q4_k_m",
                display_name="Qwen3 1.7B",
                filename="Qwen3-1.7B-Q4_K_M.gguf",
                artifact_sha256=sha256(fixture["modelBytes"]),
                artifact_bytes=len(fixture["modelBytes"]),
                manifest_sha256=fixture["modelManifestSHA256"],
                resolved_revision=fixture["revision"],
            )

            with self.assertRaisesRegex(ValueError, "Qwen3 1.7B artifact manifest"):
                runner._pinned_provenance(
                    candidate=candidate,
                    model_path=fixture["modelPath"],
                    model_manifest_path=fixture["modelManifestPath"],
                    server_path=fixture["serverPath"],
                    runtime_manifest_path=fixture["runtimeManifestPath"],
                )

    def test_main_uses_one_server_and_persists_exact_cli_commands(self):
        runner = load_runner(self)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fixture = write_synthetic_source(root)
            destination = root / "pilot"
            server_path = root / "runtime" / "llama-server"
            runtime_manifest = root / "runtime" / "runtime-manifest.json"
            model_path = root / "models" / "SmolLM3-Q4_K_M.gguf"
            model_manifest = root / "models" / "artifact-manifest.json"
            argv = [
                "--source",
                str(fixture["source"]),
                "--system-prompt",
                str(fixture["systemPath"]),
                "--server",
                str(server_path),
                "--runtime-manifest",
                str(runtime_manifest),
                "--model",
                str(model_path),
                "--model-manifest",
                str(model_manifest),
                "--destination",
                str(destination),
                "--timeout",
                "41",
            ]
            FakeLlamaServer.instances = []
            with synthetic_source_pins(runner, fixture), mock.patch.object(
                runner,
                "_pinned_provenance",
                return_value=exact_verified_provenance(),
            ), mock.patch.object(
                runner.llama_server, "LlamaServer", FakeLlamaServer
            ), mock.patch("sys.stdout", new_callable=io.StringIO) as stdout:
                exit_code = runner.main(argv)

            self.assertEqual(0, exit_code, stdout.getvalue())
            self.assertEqual(1, len(FakeLlamaServer.instances))
            server = FakeLlamaServer.instances[0]
            self.assertEqual(server_path, server.executable)
            self.assertEqual(model_path, server.model_path)
            self.assertEqual(8192, server.context_tokens)
            self.assertEqual(41, server.started_with)
            self.assertTrue(server.stopped)
            self.assertEqual(8, server.client.completion_count)
            manifest = json.loads(
                (destination / "run-manifest.json").read_text(encoding="utf-8")
            )
            self.assertEqual(server.command, manifest["provenance"]["serverCommand"])
            self.assertEqual(
                [sys.executable, str(Path(runner.__file__).resolve()), *argv],
                manifest["provenance"]["pilotCommand"],
            )
            self.assertEqual(
                {"completionAttempts": 8, "invalidCount": 0, "providerErrorCount": 0,
                 "recordCount": 8, "validCount": 8},
                json.loads(stdout.getvalue()),
            )

    def test_main_selects_qwen_and_resolves_its_pinned_default_artifact_paths(self):
        runner = load_runner(self)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fixture = write_synthetic_source(root)
            destination = root / "pilot"
            artifact_root = root / "artifacts"
            candidate = runner.QWEN3_1_7B_CANDIDATE
            qwen_provenance = {
                **exact_verified_provenance(),
                "modelID": candidate.identifier,
                "modelArtifactSHA256": candidate.artifact_sha256,
                "modelArtifactBytes": candidate.artifact_bytes,
                "modelArtifactManifestSHA256": candidate.manifest_sha256,
                "modelResolvedRevision": candidate.resolved_revision,
            }
            argv = [
                "--candidate",
                candidate.identifier,
                "--source",
                str(fixture["source"]),
                "--system-prompt",
                str(fixture["systemPath"]),
                "--destination",
                str(destination),
                "--timeout",
                "41",
            ]
            FakeLlamaServer.instances = []
            with synthetic_source_pins(runner, fixture), mock.patch.object(
                runner, "ARTIFACT_ROOT", artifact_root
            ), mock.patch.object(
                runner,
                "_pinned_provenance",
                return_value=qwen_provenance,
            ) as provenance_call, mock.patch.object(
                runner.llama_server, "LlamaServer", FakeLlamaServer
            ), mock.patch("sys.stdout", new_callable=io.StringIO) as stdout:
                exit_code = runner.main(argv)

            self.assertEqual(0, exit_code, stdout.getvalue())
            expected_model = (
                artifact_root
                / "models"
                / candidate.identifier
                / candidate.filename
            )
            expected_manifest = (
                artifact_root
                / "models"
                / candidate.identifier
                / "artifact-manifest.json"
            )
            server = FakeLlamaServer.instances[0]
            self.assertEqual(expected_model, server.model_path)
            provenance_call.assert_called_once_with(
                candidate=candidate,
                model_path=expected_model,
                model_manifest_path=expected_manifest,
                server_path=artifact_root / "runtime" / "b10516" / "bin" / "llama-server",
                runtime_manifest_path=(
                    artifact_root
                    / "runtime"
                    / "b10516"
                    / "runtime-manifest.json"
                ),
            )
            manifest = json.loads(
                (destination / "run-manifest.json").read_text(encoding="utf-8")
            )
            self.assertEqual(candidate.identifier, manifest["provenance"]["modelID"])

    def test_refuses_overwrite_before_calling_client(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            destination = root / "pilot"
            destination.mkdir()
            client = RecordingPilotClient()

            with self.assertRaisesRegex(ValueError, "overwrite"):
                self.run_pilot(root, destination, client)

            self.assertEqual([], client.events)

    def test_refuses_source_hash_drift_before_calling_client(self):
        runner = load_runner(self)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            original = write_synthetic_source(root / "original")
            source = root / "mutated-swift-export"
            shutil.copytree(original["source"], source)
            (source / "user-prompts" / "01-quiet-help.md").write_text(
                "changed", encoding="utf-8"
            )
            client = RecordingPilotClient()

            with synthetic_source_pins(runner, original):
                with self.assertRaisesRegex(ValueError, "frozen source|hash"):
                    runner.run_pilot(
                        source_dir=source,
                        system_prompt_path=original["systemPath"],
                        destination=root / "pilot",
                        client=client,
                        provenance=exact_provenance(),
                        timeout=37,
                    )

            self.assertEqual([], client.events)


if __name__ == "__main__":
    unittest.main()

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

import preview_neutral_prompts


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


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def canonical_json(value):
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode("utf-8")


class TokenizerOnlyFake:
    def __init__(self, token_counts=None):
        self.render_calls = []
        self.token_calls = []
        self.generation_calls = 0
        self.token_counts = list(token_counts or [321] * len(EXAMPLE_IDS))

    def render_prompt(self, **arguments):
        self.render_calls.append(arguments)
        return "<system>\n{}\n</system>\n<user>\n{}\n</user>".format(
            arguments["system_prompt"], arguments["user_content"]
        )

    def token_count(self, prompt, **arguments):
        self.token_calls.append((prompt, arguments))
        return self.token_counts.pop(0)

    def complete_rendered(self, **arguments):
        self.generation_calls += 1
        raise AssertionError("Prompt preview must never request generation")


class NeutralPromptPreviewTests(unittest.TestCase):
    def _write_source(self, root):
        source = root / "swift"
        users = source / "user-prompts"
        users.mkdir(parents=True, exist_ok=True)
        system = (
            "# Chess Tutor v5\n\n"
            "Coach one short turn from neutral chess-rule facts.\n"
        )
        system_bytes = system.encode("utf-8")
        (source / "system-prompt.md").write_bytes(system_bytes)

        records = []
        manifest_examples = []
        for index, identifier in enumerate(EXAMPLE_IDS, start=1):
            file_name = f"{identifier}.md"
            markdown = (
                "# Chess coaching situation\n\n"
                "## Game\n\n"
                f"Side to move: {'White' if index % 2 else 'Black'}\n\n"
                "## Current help episode\n\n"
                f"{index}. helpOpened\n\n"
                "## Rule facts\n\n"
                "White is not in check.\n\n"
                "## Available interactions\n\n"
                "Actions: action-1 (hint)\n"
            )
            user_bytes = markdown.encode("utf-8")
            request = {
                "requestID": identifier,
                "schemaVersion": "model-coaching-neutral-request.v1",
            }
            request_sha = sha256(canonical_json(request))
            user_sha = sha256(user_bytes)
            record = {
                "compilation": {
                    "markdown": markdown,
                    "positionRevision": index,
                    "promptVersion": "tutor-v5",
                    "referenceBindings": [],
                    "requestID": identifier,
                    "schemaVersion": "model-coaching-neutral-context.v1",
                },
                "fileName": file_name,
                "id": identifier,
                "request": request,
                "requestSHA256": request_sha,
                "userPromptSHA256": user_sha,
                "visibility": "visible",
            }
            records.append(record)
            manifest_examples.append(
                {
                    "fileName": file_name,
                    "id": identifier,
                    "requestSHA256": request_sha,
                    "userPromptSHA256": user_sha,
                }
            )
            (users / file_name).write_bytes(user_bytes)

        jsonl_bytes = b"".join(canonical_json(record) + b"\n" for record in records)
        (source / "examples.jsonl").write_bytes(jsonl_bytes)
        manifest = {
            "contextSchemaVersion": "model-coaching-neutral-context.v1",
            "exampleIDs": list(EXAMPLE_IDS),
            "examples": manifest_examples,
            "examplesJSONLSHA256": sha256(jsonl_bytes),
            "promptVersion": "tutor-v5",
            "requestSchemaVersion": "model-coaching-neutral-request.v1",
            "schemaVersion": "model-coaching-neutral-preview-manifest.v1",
            "systemPromptSHA256": sha256(system_bytes),
        }
        (source / "preview-manifest.json").write_bytes(canonical_json(manifest) + b"\n")
        system_path = root / "tutor-v5.md"
        system_path.write_bytes(system_bytes)
        return source, system_path

    def _build(self, root, *, destination_name="final", client=None):
        source, system = self._write_source(root)
        client = client or TokenizerOnlyFake()
        destination = root / destination_name
        manifest = preview_neutral_prompts.build_preview(
            source_dir=source,
            system_prompt_path=system,
            destination=destination,
            client=client,
            tokenizer_provenance={
                "modelID": "qwen3-1.7b-q4_k_m",
                "modelArtifactSHA256": "a" * 64,
                "runtimeSourceTag": "b10516",
                "runtimeSourceCommit": "b" * 40,
                "runtimeBinarySHA256": "c" * 64,
            },
        )
        return manifest, destination, source, system, client

    def test_builds_exact_ordered_hash_bound_tokenizer_only_packet(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest, destination, source, system, client = self._build(root)

            persisted = json.loads(
                (destination / "preview-manifest.json").read_text(encoding="utf-8")
            )
            self.assertEqual(manifest, persisted)
            self.assertEqual(
                "model-coaching-neutral-human-preview.v1", manifest["schemaVersion"]
            )
            self.assertEqual("tutor-v5", manifest["promptVersion"])
            self.assertEqual(2500, manifest["budgetTokens"])
            self.assertEqual(list(EXAMPLE_IDS), manifest["exampleIDs"])
            self.assertEqual(8, len(manifest["prompts"]))
            self.assertEqual(
                sha256(system.read_bytes()), manifest["systemPromptSHA256"]
            )
            self.assertEqual(
                sha256((source / "examples.jsonl").read_bytes()),
                manifest["examplesJSONLSHA256"],
            )
            self.assertEqual(
                sha256((source / "preview-manifest.json").read_bytes()),
                manifest["sourceManifestSHA256"],
            )
            self.assertEqual(321, manifest["summary"]["minimumTokens"])
            self.assertEqual(321, manifest["summary"]["maximumTokens"])

            self.assertEqual(8, len(client.render_calls))
            self.assertEqual(8, len(client.token_calls))
            self.assertEqual(0, client.generation_calls)
            self.assertTrue(
                all(call["enable_thinking"] is False for call in client.render_calls)
            )
            self.assertTrue(all(call["timeout"] == 30 for call in client.render_calls))
            self.assertTrue(all(call[1]["timeout"] == 30 for call in client.token_calls))

            transcript_files = sorted((destination / "prompts").glob("*.md"))
            self.assertEqual(
                [f"{identifier}.md" for identifier in EXAMPLE_IDS],
                [path.name for path in transcript_files],
            )
            records = [
                json.loads(line)
                for line in (source / "examples.jsonl")
                .read_text(encoding="utf-8")
                .splitlines()
            ]
            for cell, record, transcript_path in zip(
                manifest["prompts"], records, transcript_files
            ):
                user = record["compilation"]["markdown"]
                rendered = "<system>\n{}\n</system>\n<user>\n{}\n</user>".format(
                    system.read_text(encoding="utf-8"), user
                )
                transcript = transcript_path.read_bytes()
                self.assertEqual(record["id"], cell["id"])
                self.assertEqual(record["requestSHA256"], cell["requestSHA256"])
                self.assertEqual(manifest["systemPromptSHA256"], cell["systemPromptSHA256"])
                self.assertEqual(record["userPromptSHA256"], cell["userPromptSHA256"])
                self.assertEqual(len(user.encode("utf-8")), cell["userPromptUTF8Bytes"])
                self.assertEqual(len(user.split()), cell["userPromptWords"])
                self.assertEqual(len(rendered.encode("utf-8")), cell["renderedPromptUTF8Bytes"])
                self.assertEqual(sha256(rendered.encode("utf-8")), cell["renderedPromptSHA256"])
                self.assertEqual(321, cell["renderedPromptTokens"])
                self.assertEqual(sha256(transcript), cell["transcriptSHA256"])
                self.assertEqual(len(transcript), cell["transcriptUTF8Bytes"])
                transcript_text = transcript.decode("utf-8")
                self.assertIn("## System message\n\n" + system.read_text(), transcript_text)
                self.assertIn("## User message\n\n" + user, transcript_text)
                self.assertNotIn("## Assistant", transcript_text)
                self.assertNotIn("<think>", transcript_text)

            artifact_text = "\n".join(
                path.read_text(encoding="utf-8")
                for path in sorted(destination.rglob("*"))
                if path.is_file()
            )
            self.assertNotIn("hidden", artifact_text.lower())
            self.assertNotIn("t1OutsidePawnMove", artifact_text)
            self.assertNotIn("t3WrongAttacker", artifact_text)
            self.assertNotIn("t7UnsafeCapture", artifact_text)
            self.assertNotIn("t12WrongChecker", artifact_text)
            self._assert_no_forbidden_fields(manifest)

    def test_deterministic_clients_produce_byte_identical_packets(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self._build(root, destination_name="first")
            self._build(root, destination_name="second")

            first = {
                path.relative_to(root / "first"): path.read_bytes()
                for path in (root / "first").rglob("*")
                if path.is_file()
            }
            second = {
                path.relative_to(root / "second"): path.read_bytes()
                for path in (root / "second").rglob("*")
                if path.is_file()
            }
            self.assertEqual(first, second)

    def test_refuses_to_overwrite_even_an_empty_destination(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, system = self._write_source(root)
            destination = root / "final"
            destination.mkdir()
            client = TokenizerOnlyFake()

            with self.assertRaisesRegex(ValueError, "overwrite"):
                preview_neutral_prompts.build_preview(
                    source_dir=source,
                    system_prompt_path=system,
                    destination=destination,
                    client=client,
                    tokenizer_provenance={"modelID": "qwen3-1.7b-q4_k_m"},
                )

            self.assertEqual(0, len(client.render_calls))
            self.assertEqual(0, client.generation_calls)

    def test_rejects_any_prompt_over_budget_without_writing_packet(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, system = self._write_source(root)
            destination = root / "final"
            client = TokenizerOnlyFake([2500, 2501] + [100] * 6)

            with self.assertRaisesRegex(ValueError, "2,500"):
                preview_neutral_prompts.build_preview(
                    source_dir=source,
                    system_prompt_path=system,
                    destination=destination,
                    client=client,
                    tokenizer_provenance={"modelID": "qwen3-1.7b-q4_k_m"},
                )

            self.assertFalse(destination.exists())
            self.assertEqual(0, client.generation_calls)

    def test_rejects_source_hash_drift_and_hidden_or_response_data(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, system = self._write_source(root)
            manifest_path = source / "preview-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["systemPromptSHA256"] = "0" * 64
            manifest_path.write_bytes(canonical_json(manifest) + b"\n")
            client = TokenizerOnlyFake()

            with self.assertRaisesRegex(ValueError, "system prompt hash"):
                preview_neutral_prompts.build_preview(
                    source_dir=source,
                    system_prompt_path=system,
                    destination=root / "bad-hash",
                    client=client,
                    tokenizer_provenance={"modelID": "qwen3-1.7b-q4_k_m"},
                )

            self.assertEqual([], client.render_calls)

        for mutation, expected in (("hidden", "hidden"), ("response", "response/output")):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                source, system = self._write_source(root)
                lines = (source / "examples.jsonl").read_text(encoding="utf-8").splitlines()
                first = json.loads(lines[0])
                if mutation == "hidden":
                    first["id"] = "hidden-quiet-help"
                else:
                    first["response"] = {"message": "not allowed"}
                lines[0] = canonical_json(first).decode("utf-8")
                (source / "examples.jsonl").write_text(
                    "\n".join(lines) + "\n", encoding="utf-8"
                )

                with self.assertRaisesRegex(ValueError, expected):
                    preview_neutral_prompts.build_preview(
                        source_dir=source,
                        system_prompt_path=system,
                        destination=root / mutation,
                        client=TokenizerOnlyFake(),
                        tokenizer_provenance={"modelID": "qwen3-1.7b-q4_k_m"},
                    )

    def _assert_no_forbidden_fields(self, value):
        if isinstance(value, dict):
            for key, item in value.items():
                lowered = key.lower()
                self.assertNotIn("response", lowered)
                self.assertNotIn("output", lowered)
                self.assertNotIn("trace", lowered)
                self._assert_no_forbidden_fields(item)
        elif isinstance(value, list):
            for item in value:
                self._assert_no_forbidden_fields(item)


if __name__ == "__main__":
    unittest.main()

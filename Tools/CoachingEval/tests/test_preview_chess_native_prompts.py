import hashlib
import json
import re
import sys
import tempfile
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

import preview_chess_native_prompts


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
        value, indent=2, sort_keys=True, ensure_ascii=False
    ).encode("utf-8") + b"\n"


class TokenizerOnlyFake:
    def __init__(self, token_counts=None):
        self.render_calls = []
        self.token_calls = []
        self.generation_calls = 0
        self.token_counts = list(token_counts or [640] * len(EXAMPLE_IDS))

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
        raise AssertionError("Chess-native preview must never request generation")


class ChessNativePromptPreviewTests(unittest.TestCase):
    def _write_source(self, root):
        source = root / "swift"
        users = source / "user-prompts"
        users.mkdir(parents=True, exist_ok=True)
        system = (
            "# Chess Tutor v6\n\n"
            "Coach one short turn from chess-native facts in ordinary language.\n"
        )
        system_bytes = system.encode("utf-8")
        (source / "system-prompt.md").write_bytes(system_bytes)

        examples = []
        declared_files = [
            {"path": "examples.jsonl", "role": "auditOnly"},
            {"path": "preview-manifest.json", "role": "auditOnly"},
            {
                "path": "system-prompt.md",
                "role": "modelFacingSystemMessage",
            },
        ]
        for index, identifier in enumerate(EXAMPLE_IDS, start=1):
            file_name = f"{identifier}.md"
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
                "Actions: hint\n"
                "Square focus: any board square\n"
                "Allowable move focus: none"
            )
            user_bytes = markdown.encode("utf-8")
            request_sha = sha256(f"request-{identifier}".encode("utf-8"))
            user_sha = sha256(user_bytes)
            examples.append(
                {
                    "fileName": file_name,
                    "id": identifier,
                    "requestSHA256": request_sha,
                    "systemPromptSHA256": sha256(system_bytes),
                    "userPromptSHA256": user_sha,
                }
            )
            relative_path = f"user-prompts/{file_name}"
            declared_files.append(
                {"path": relative_path, "role": "modelFacingUserMessage"}
            )
            (source / relative_path).write_bytes(user_bytes)

        # This intentionally is not valid JSONL and contains prohibited material.
        # A role-driven tokenizer preview must never parse or render it.
        audit_bytes = (
            b'not-json {"response":{},"trace":"hidden",'
            b'"alias":"relationship-1","id":"t1OutsidePawnMove"}\n'
        )
        (source / "examples.jsonl").write_bytes(audit_bytes)
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
        (source / "preview-manifest.json").write_bytes(canonical_json(manifest))
        system_path = root / "tutor-v6.md"
        system_path.write_bytes(system_bytes)
        return source, system_path, manifest

    def _build(self, root, *, destination_name="final", client=None):
        source, system, source_manifest = self._write_source(root)
        client = client or TokenizerOnlyFake()
        destination = root / destination_name
        manifest = preview_chess_native_prompts.build_preview(
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
        return (
            manifest,
            destination,
            source,
            system,
            source_manifest,
            client,
        )

    def test_builds_exact_role_driven_hash_bound_tokenizer_only_packet(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (
                manifest,
                destination,
                source,
                system,
                source_manifest,
                client,
            ) = self._build(root)

            persisted = json.loads(
                (destination / "preview-manifest.json").read_text(encoding="utf-8")
            )
            self.assertEqual(manifest, persisted)
            self.assertEqual(
                "model-coaching-chess-native-human-preview.v1",
                manifest["schemaVersion"],
            )
            self.assertEqual("tutor-v6", manifest["promptVersion"])
            self.assertEqual(2500, manifest["budgetTokens"])
            self.assertEqual(list(EXAMPLE_IDS), manifest["exampleIDs"])
            self.assertEqual(
                ["modelFacingSystemMessage", "modelFacingUserMessage"],
                manifest["consumedSourceRoles"],
            )
            self.assertEqual(8, len(manifest["prompts"]))
            self.assertEqual(sha256(system.read_bytes()), manifest["systemPromptSHA256"])
            self.assertEqual(
                sha256((source / "preview-manifest.json").read_bytes()),
                manifest["sourceManifestSHA256"],
            )
            self.assertNotIn("examplesJSONLSHA256", manifest)
            self.assertEqual(640, manifest["summary"]["minimumTokens"])
            self.assertEqual(640, manifest["summary"]["maximumTokens"])
            self.assertEqual(8, manifest["summary"]["preferredRangePromptCount"])

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
            for cell, source_example, transcript_path, render_call in zip(
                manifest["prompts"],
                source_manifest["examples"],
                transcript_files,
                client.render_calls,
            ):
                user = (
                    source / "user-prompts" / source_example["fileName"]
                ).read_text(encoding="utf-8")
                rendered = "<system>\n{}\n</system>\n<user>\n{}\n</user>".format(
                    system.read_text(encoding="utf-8"), user
                )
                transcript = transcript_path.read_bytes()
                self.assertEqual(source_example["id"], cell["id"])
                self.assertEqual(source_example["requestSHA256"], cell["requestSHA256"])
                self.assertEqual(manifest["systemPromptSHA256"], cell["systemPromptSHA256"])
                self.assertEqual(source_example["userPromptSHA256"], cell["userPromptSHA256"])
                self.assertEqual(sha256(rendered.encode("utf-8")), cell["renderedPromptSHA256"])
                self.assertEqual(640, cell["renderedPromptTokens"])
                self.assertEqual(sha256(transcript), cell["transcriptSHA256"])
                transcript_text = transcript.decode("utf-8")
                self.assertEqual(system.read_text(), render_call["system_prompt"])
                self.assertEqual(user, render_call["user_content"])
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
            self.assertIsNone(
                re.search(r"\b(?:relationship|move|piece|action)-[0-9]+\b", artifact_text)
            )
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
            source, system, _ = self._write_source(root)
            destination = root / "final"
            destination.mkdir()
            client = TokenizerOnlyFake()

            with self.assertRaisesRegex(ValueError, "overwrite"):
                preview_chess_native_prompts.build_preview(
                    source_dir=source,
                    system_prompt_path=system,
                    destination=destination,
                    client=client,
                    tokenizer_provenance={"modelID": "qwen3-1.7b-q4_k_m"},
                )

            self.assertEqual([], client.render_calls)
            self.assertEqual(0, client.generation_calls)

    def test_rejects_any_prompt_over_budget_without_writing_packet(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, system, _ = self._write_source(root)
            destination = root / "final"
            client = TokenizerOnlyFake([2500, 2501] + [100] * 6)

            with self.assertRaisesRegex(ValueError, "2,500"):
                preview_chess_native_prompts.build_preview(
                    source_dir=source,
                    system_prompt_path=system,
                    destination=destination,
                    client=client,
                    tokenizer_provenance={"modelID": "qwen3-1.7b-q4_k_m"},
                )

            self.assertFalse(destination.exists())
            self.assertEqual(0, client.generation_calls)

    def test_rejects_hash_drift_or_a_model_facing_file_with_an_audit_role(self):
        for mutation, expected in (("hash", "hash"), ("role", "role")):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                source, system, manifest = self._write_source(root)
                if mutation == "hash":
                    (source / "user-prompts" / f"{EXAMPLE_IDS[0]}.md").write_text(
                        "changed", encoding="utf-8"
                    )
                else:
                    manifest["declaredFiles"][3]["role"] = "auditOnly"
                    (source / "preview-manifest.json").write_bytes(canonical_json(manifest))

                client = TokenizerOnlyFake()
                with self.assertRaisesRegex(ValueError, expected):
                    preview_chess_native_prompts.build_preview(
                        source_dir=source,
                        system_prompt_path=system,
                        destination=root / mutation,
                        client=client,
                        tokenizer_provenance={"modelID": "qwen3-1.7b-q4_k_m"},
                    )
                self.assertEqual([], client.render_calls)
                self.assertEqual(0, client.generation_calls)

    def _assert_no_forbidden_fields(self, value):
        if isinstance(value, dict):
            for key, item in value.items():
                lowered = key.lower()
                self.assertNotIn("response", lowered)
                self.assertNotIn("assistant", lowered)
                self.assertNotIn("trace", lowered)
                self.assertNotIn("hidden", lowered)
                self._assert_no_forbidden_fields(item)
        elif isinstance(value, list):
            for item in value:
                self._assert_no_forbidden_fields(item)


if __name__ == "__main__":
    unittest.main()

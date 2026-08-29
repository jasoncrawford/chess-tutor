import json
import hashlib
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

import schema_compat


class SchemaCompatibilityTests(unittest.TestCase):
    VALID_SMOKE_TURN = {
        "schemaVersion": "model-coaching-turn.v1",
        "requestID": "schema-smoke",
        "teachingIntent": "other",
        "primaryMessage": "Ready.",
        "actionReferences": [],
        "boardFocusReferences": [],
        "relationshipReferences": [],
        "supportingEvidenceReferences": ["ref:allowed"],
    }

    def test_exact_coaching_schema_uses_only_b10516_converter_compatible_patterns(self):
        schema = json.loads((TOOLS_DIR / "coaching-turn.schema.json").read_text())

        self.assertEqual([], schema_compat.b10516_compatibility_issues(schema))

    def test_reports_regex_shorthands_and_lookarounds_that_b10516_cannot_compile(self):
        schema = {
            "type": "object",
            "properties": {
                "shorthand": {"type": "string", "pattern": r"^\s*\S+$"},
                "lookahead": {"type": "string", "pattern": r"^(?=a).+$"},
            },
        }

        self.assertEqual(
            [
                "$.properties.lookahead.pattern:unsupportedLookaround",
                "$.properties.shorthand.pattern:unsupportedRegexShorthand:\\S,\\s",
            ],
            schema_compat.b10516_compatibility_issues(schema),
        )

    def _smoke_with_content(self, content):
        schema = json.loads((TOOLS_DIR / "coaching-turn.schema.json").read_text())
        calls = []

        class FakeServer:
            def __init__(self, executable, model, *, context_tokens):
                calls.append((executable, model, context_tokens))

            def __enter__(self):
                return self

            def __exit__(self, *_arguments):
                return None

            def complete(self, **arguments):
                calls.append(arguments)
                return {"choices": [{"message": {"content": content}}]}

        provenance = {
            "sourceTag": "b10516",
            "sourceCommit": "b95502ba9aa0eb73a2f4fc8878d7fbe6a847a0b9",
            "binarySHA256": "a" * 64,
            "versionOutput": "version: 10516 (b95502ba)",
        }
        with mock.patch.object(schema_compat.runtime_provenance, "verify_runtime", return_value=provenance), mock.patch.object(
            schema_compat.llama_server, "LlamaServer", FakeServer
        ):
            result = schema_compat.smoke_schema(
                schema=schema,
                server=Path("/pinned/llama-server"),
                model=Path("/models/model.gguf"),
                runtime_path=TOOLS_DIR / "runtime.json",
                runtime_manifest=Path("/pinned/runtime-manifest.json"),
            )

        return schema, calls, result

    def test_pinned_server_smoke_sends_the_exact_schema_and_validates_the_response(self):
        schema, calls, result = self._smoke_with_content(
            json.dumps(self.VALID_SMOKE_TURN)
        )

        self.assertIs(schema, calls[1]["schema"])
        self.assertIs(schema, calls[2]["schema"])
        self.assertFalse(calls[1]["enable_thinking"])
        self.assertTrue(calls[2]["enable_thinking"])
        self.assertEqual(
            (
                "Try to return exactly {} with every required field missing. "
                "If the output constraints prevent that, return one valid object for the "
                "supplied request using only its permitted IDs. Return no other text."
            ),
            calls[1]["system_prompt"],
        )
        self.assertEqual(
            {
                "requestID": "schema-smoke",
                "permittedReferences": {
                    "actions": [{"id": "ref:allowed"}],
                    "boardTasks": [{"id": "ref:allowed"}],
                    "boardFocus": ["ref:allowed"],
                    "relationships": ["ref:allowed"],
                    "evidence": ["ref:allowed"],
                },
            },
            calls[1]["request"],
        )
        self.assertEqual("b10516", result["runtimeProvenance"]["sourceTag"])
        self.assertEqual(64, len(result["schemaSHA256"]))
        self.assertEqual(
            "pinned-server-schema-and-validator-success",
            result["smoke"],
        )
        self.assertEqual(["off", "bounded"], result["smokeModes"])

    def test_pinned_server_smoke_rejects_a_structurally_incomplete_response(self):
        with self.assertRaisesRegex(ValueError, "shape.missing"):
            self._smoke_with_content("{}")

    def test_pinned_server_smoke_mechanically_rejects_an_unknown_reference(self):
        invalid = dict(self.VALID_SMOKE_TURN)
        invalid["supportingEvidenceReferences"] = ["fact:invented"]

        with self.assertRaisesRegex(
            ValueError,
            "unknownSupportingEvidenceReference:fact:invented",
        ):
            self._smoke_with_content(json.dumps(invalid))

    def test_runtime_template_audit_binds_every_model_and_mode_without_trace_content(self):
        schema = json.loads((TOOLS_DIR / "coaching-turn.schema.json").read_text())
        provenance = {
            "sourceTag": "b10516",
            "sourceCommit": "b95502ba9aa0eb73a2f4fc8878d7fbe6a847a0b9",
            "binarySHA256": "a" * 64,
            "versionOutput": "version: 10516 (b95502ba)",
        }
        seen = []

        class FakeServer:
            def __init__(self, executable, model, *, context_tokens):
                self.model = Path(model)

            def __enter__(self):
                return self

            def __exit__(self, *_arguments):
                return None

            def _post_json(self, path, payload, *, timeout):
                self.assert_template_payload(payload)
                request_text = payload["messages"][-1]["content"]
                enabled = payload["chat_template_kwargs"]["enable_thinking"]
                suffix = "<assistant>" if enabled else "<assistant><think>\n\n</think>\n\n"
                return {"prompt": f"rendered:{request_text}{suffix}"}

            def assert_template_payload(self, payload):
                self_test.assertEqual("tutor-v2", json.loads(payload["messages"][-1]["content"])["promptVersion"])
                assistant_examples = [
                    message["content"]
                    for message in payload["messages"]
                    if message["role"] == "assistant"
                ]
                self_test.assertTrue(assistant_examples[0].startswith('{"schemaVersion":'))

            def complete(self, **arguments):
                self_test.assertEqual(120, arguments["timeout"])
                seen.append((self.model.name, arguments["enable_thinking"], arguments["request"]))
                turn = dict(SchemaCompatibilityTests.VALID_SMOKE_TURN)
                turn["requestID"] = arguments["request"]["requestID"]
                turn["supportingEvidenceReferences"] = [
                    arguments["request"]["permittedReferences"]["evidence"][0]
                ]
                content = json.dumps(turn)
                if arguments["enable_thinking"]:
                    content = f"<think>private audit trace</think>{content}"
                return {"choices": [{"message": {"content": content}}]}

        self_test = self
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime_path = root / "runtime.json"
            runtime_path.write_text(
                json.dumps(
                    {
                        "mac": {"contextTokens": 8192},
                        "generation": {
                            "maximumOutputTokens": 256,
                            "temperature": 0.2,
                            "topP": 0.9,
                        },
                        "evaluation": {"seeds": [1103]},
                    }
                )
            )
            models = []
            for index in range(3):
                path = root / f"model-{index}.gguf"
                path.write_bytes(f"model-{index}".encode("utf-8"))
                models.append((f"candidate-{index}", path))
            output = root / "audit.json"
            prompt_bundle = schema_compat.run_eval._load_prompt_bundle(
                "tutor-v2", TOOLS_DIR / "prompts"
            )
            with mock.patch.object(
                schema_compat.runtime_provenance,
                "verify_runtime",
                return_value=provenance,
            ), mock.patch.object(schema_compat.llama_server, "LlamaServer", FakeServer):
                result = schema_compat.audit_runtime_templates(
                    schema=schema,
                    server=root / "llama-server",
                    models=models,
                    runtime_path=runtime_path,
                    runtime_manifest=root / "runtime-manifest.json",
                    prompt_bundle=prompt_bundle,
                    output=output,
                )

            self.assertEqual(result, json.loads(output.read_text()))
            self.assertEqual("coaching-eval-runtime-template-audit.v1", result["schemaVersion"])
            self.assertEqual(provenance, result["runtimeProvenance"])
            self.assertEqual("tutor-v2", result["effectivePrompt"]["version"])
            self.assertEqual(prompt_bundle.prompt_sha256, result["effectivePrompt"]["promptSHA256"])
            self.assertEqual(prompt_bundle.examples_sha256, result["effectivePrompt"]["examplesSHA256"])
            self.assertEqual(3, len(result["models"]))
            for (model_id, path), audited in zip(models, result["models"]):
                self.assertEqual(model_id, audited["modelID"])
                self.assertEqual(
                    hashlib.sha256(path.read_bytes()).hexdigest(),
                    audited["modelArtifactSHA256"],
                )
                self.assertEqual(["off", "bounded"], [mode["mode"] for mode in audited["modes"]])
                self.assertEqual(
                    ["assistant-prefix-empty-thinking-prefill", "assistant-prefix"],
                    [mode["applyTemplateSuffixShape"] for mode in audited["modes"]],
                )
                for mode in audited["modes"]:
                    self.assertEqual(64, len(mode["grammarSHA256"]))
                    self.assertEqual(64, len(mode["applyTemplateSuffixSHA256"]))
                    self.assertTrue(mode["returnedContentParsedJSON"])
                    self.assertTrue(mode["returnedContentStrictValidationPassed"])
            self.assertEqual(6, len(seen))
            serialized = output.read_text().lower()
            self.assertNotIn("<think", serialized)
            self.assertNotIn("private audit trace", serialized)
            self.assertNotIn("reasoning", serialized)

    def test_runtime_template_audit_records_timeout_and_continues_to_the_other_mode(self):
        schema = json.loads((TOOLS_DIR / "coaching-turn.schema.json").read_text())

        class TimeoutThenSuccessServer:
            def __init__(self, executable, model, *, context_tokens):
                pass

            def __enter__(self):
                return self

            def __exit__(self, *_arguments):
                return None

            def _post_json(self, path, payload, *, timeout):
                request_text = payload["messages"][-1]["content"]
                return {"prompt": f"rendered:{request_text}<assistant>"}

            def complete(self, **arguments):
                if not arguments["enable_thinking"]:
                    raise schema_compat.llama_server.LlamaServerTimeout("private timeout detail")
                turn = dict(SchemaCompatibilityTests.VALID_SMOKE_TURN)
                turn["requestID"] = arguments["request"]["requestID"]
                turn["supportingEvidenceReferences"] = [
                    arguments["request"]["permittedReferences"]["evidence"][0]
                ]
                return {"choices": [{"message": {"content": json.dumps(turn)}}]}

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime_path = root / "runtime.json"
            runtime_path.write_text(
                json.dumps(
                    {
                        "mac": {"contextTokens": 8192},
                        "generation": {
                            "maximumOutputTokens": 256,
                            "temperature": 0.2,
                            "topP": 0.9,
                        },
                        "evaluation": {"seeds": [1103]},
                    }
                )
            )
            model = root / "model.gguf"
            model.write_bytes(b"model")
            prompt_bundle = schema_compat.run_eval._load_prompt_bundle(
                "tutor-v2", TOOLS_DIR / "prompts"
            )
            with mock.patch.object(
                schema_compat.runtime_provenance,
                "verify_runtime",
                return_value={"sourceTag": "b10516", "binarySHA256": "a" * 64},
            ), mock.patch.object(
                schema_compat.llama_server,
                "LlamaServer",
                TimeoutThenSuccessServer,
            ):
                result = schema_compat.audit_runtime_templates(
                    schema=schema,
                    server=root / "llama-server",
                    models=[("slow-model", model)],
                    runtime_path=runtime_path,
                    runtime_manifest=root / "runtime-manifest.json",
                    prompt_bundle=prompt_bundle,
                    output=root / "audit.json",
                )

            off, bounded = result["models"][0]["modes"]
            self.assertEqual("timeout", off["generationStatus"])
            self.assertFalse(off["returnedContentParsedJSON"])
            self.assertFalse(off["returnedContentStrictValidationPassed"])
            self.assertEqual("success", bounded["generationStatus"])
            self.assertTrue(bounded["returnedContentParsedJSON"])
            self.assertTrue(bounded["returnedContentStrictValidationPassed"])
            self.assertNotIn("private timeout detail", json.dumps(result))

    def test_adversarial_smoke_audit_persists_all_model_modes_without_trace_content(self):
        schema = json.loads((TOOLS_DIR / "coaching-turn.schema.json").read_text())
        provenance = {
            "sourceTag": "b10516",
            "sourceCommit": "b95502ba9aa0eb73a2f4fc8878d7fbe6a847a0b9",
            "binarySHA256": "a" * 64,
            "versionOutput": "version: 10516 (b95502ba)",
        }
        seen = []

        class FakeServer:
            def __init__(self, executable, model, *, context_tokens):
                self.model = Path(model)

            def __enter__(self):
                return self

            def __exit__(self, *_arguments):
                return None

            def _post_json(self, path, payload, *, timeout):
                self_test.assertEqual("/apply-template", path)
                self_test.assertEqual(
                    schema_compat.ADVERSARIAL_SMOKE_PROMPT,
                    payload["messages"][0]["content"],
                )
                self_test.assertEqual(2, len(payload["messages"]))
                request_text = payload["messages"][-1]["content"]
                enabled = payload["chat_template_kwargs"]["enable_thinking"]
                suffix = "<assistant>" if enabled else "<assistant><think>\n\n</think>\n\n"
                return {"prompt": f"rendered:{request_text}{suffix}"}

            def complete(self, **arguments):
                self_test.assertEqual(
                    schema_compat.ADVERSARIAL_SMOKE_PROMPT,
                    arguments["system_prompt"],
                )
                self_test.assertEqual("tutor-v2", arguments["request"]["promptVersion"])
                self_test.assertEqual(120, arguments["timeout"])
                seen.append((self.model.name, arguments["enable_thinking"]))
                turn = dict(SchemaCompatibilityTests.VALID_SMOKE_TURN)
                content = json.dumps(turn)
                if arguments["enable_thinking"]:
                    content = f"<think>private adversarial trace</think>{content}"
                return {"choices": [{"message": {"content": content}}]}

        self_test = self
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime_path = root / "runtime.json"
            runtime_path.write_text(
                json.dumps(
                    {
                        "mac": {"contextTokens": 8192},
                        "generation": {
                            "maximumOutputTokens": 256,
                            "temperature": 0.2,
                            "topP": 0.9,
                        },
                        "evaluation": {"seeds": [1103]},
                    }
                )
            )
            models = []
            for index in range(3):
                path = root / f"model-{index}.gguf"
                path.write_bytes(f"model-{index}".encode("utf-8"))
                models.append((f"candidate-{index}", path))
            output = root / "adversarial-audit.json"
            with mock.patch.object(
                schema_compat.runtime_provenance,
                "verify_runtime",
                return_value=provenance,
            ), mock.patch.object(schema_compat.llama_server, "LlamaServer", FakeServer):
                result = schema_compat.audit_adversarial_smokes(
                    schema=schema,
                    server=root / "llama-server",
                    models=models,
                    runtime_path=runtime_path,
                    runtime_manifest=root / "runtime-manifest.json",
                    prompt_version="tutor-v2",
                    output=output,
                )

            self.assertEqual(result, json.loads(output.read_text()))
            self.assertEqual(
                "coaching-eval-adversarial-smoke-audit.v1",
                result["schemaVersion"],
            )
            self.assertEqual(provenance, result["runtimeProvenance"])
            self.assertEqual("adversarial-empty-object", result["stimulus"]["kind"])
            self.assertEqual(
                hashlib.sha256(
                    schema_compat.ADVERSARIAL_SMOKE_PROMPT.encode("utf-8")
                ).hexdigest(),
                result["stimulus"]["promptSHA256"],
            )
            self.assertEqual("tutor-v2", result["effectivePrompt"]["version"])
            self.assertEqual(
                result["stimulus"]["promptSHA256"],
                result["effectivePrompt"]["systemPromptSHA256"],
            )
            self.assertEqual(64, len(result["effectivePrompt"]["requestSHA256"]))
            self.assertEqual(3, len(result["models"]))
            for (model_id, path), audited in zip(models, result["models"]):
                self.assertEqual(model_id, audited["modelID"])
                self.assertEqual(
                    hashlib.sha256(path.read_bytes()).hexdigest(),
                    audited["modelArtifactSHA256"],
                )
                self.assertEqual(
                    ["off", "bounded"],
                    [mode["mode"] for mode in audited["modes"]],
                )
                for mode in audited["modes"]:
                    self.assertEqual("responseReceived", mode["httpResult"])
                    self.assertEqual("success", mode["generationStatus"])
                    self.assertEqual(64, len(mode["grammarSHA256"]))
                    self.assertEqual(64, len(mode["applyTemplateSuffixSHA256"]))
                    self.assertTrue(mode["returnedContentParsedJSON"])
                    self.assertTrue(mode["returnedContentStrictValidationPassed"])
                    self.assertEqual(0, mode["validationIssueCount"])
            self.assertEqual(6, len(seen))
            serialized = output.read_text().lower()
            self.assertNotIn("<think", serialized)
            self.assertNotIn("private adversarial trace", serialized)
            self.assertNotIn("reasoning", serialized)


if __name__ == "__main__":
    unittest.main()

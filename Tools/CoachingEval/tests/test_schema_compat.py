import json
import sys
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


if __name__ == "__main__":
    unittest.main()

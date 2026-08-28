import json
import sys
import unittest
from pathlib import Path
from unittest import mock


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

import schema_compat


class SchemaCompatibilityTests(unittest.TestCase):
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

    def test_pinned_server_smoke_sends_the_exact_schema_through_the_real_client_path(self):
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
                return {"choices": [{"message": {"content": "{}"}}]}

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

        self.assertIs(schema, calls[1]["schema"])
        self.assertEqual("b10516", result["runtimeProvenance"]["sourceTag"])
        self.assertEqual(64, len(result["schemaSHA256"]))


if __name__ == "__main__":
    unittest.main()

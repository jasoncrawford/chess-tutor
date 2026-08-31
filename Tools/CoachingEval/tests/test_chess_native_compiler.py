import json
import unittest
from pathlib import Path

from CoachingServer.chess_native_compiler import compile_context


FIXTURE_PATH = (
    Path(__file__).resolve().parents[1]
    / "fixtures"
    / "chess-native-context-v1.json"
)


class ChessNativeCompilerTests(unittest.TestCase):
    def setUp(self):
        self.fixture = json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))

    def test_compiles_shared_request_to_exact_swift_contract(self):
        compilation = compile_context(self.fixture["request"], "tutor-v6")

        self.assertEqual(self.fixture["expectedMarkdown"], compilation.markdown)
        self.assertEqual(
            tuple(self.fixture["expectedActions"]),
            compilation.actions,
        )
        self.assertEqual(
            tuple(tuple(move) for move in self.fixture["expectedMoveFocus"]),
            compilation.allowable_moves,
        )

    def test_rejects_unknown_request_fields_and_schema_versions(self):
        request = dict(self.fixture["request"])
        request["authoredAdvice"] = "Tell the child what to do."
        with self.assertRaises(ValueError):
            compile_context(request, "tutor-v6")

        request = dict(self.fixture["request"])
        request["schemaVersion"] = "model-coaching-neutral-request.v2"
        with self.assertRaises(ValueError):
            compile_context(request, "tutor-v6")


if __name__ == "__main__":
    unittest.main()

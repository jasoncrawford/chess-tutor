import json
import sys
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

import coaching_grammar


class CoachingGrammarTests(unittest.TestCase):
    def test_request_specific_grammar_pins_identity_and_exact_alias_membership(self):
        schema = json.loads((TOOLS_DIR / "coaching-turn.schema.json").read_text())
        permitted = {
            "actions": ["action-close", "action-try-another"],
            "boardTasks": ["task-stage-move"],
            "boardFocus": ["piece-white-bishop-a6"],
            "relationships": ["relationship-attack-1"],
            "evidence": ["reply-b7-b6", "fact-danger-1"],
        }

        grammar = coaching_grammar.strict_grammar(
            schema,
            enable_thinking=False,
            request_id="corpus:t11UnsafeBishopFound",
            permitted_aliases=permitted,
        )

        self.assertIn('requestID-kv ::= "\\\"requestID\\\"" space ":" space "\\\"corpus:t11UnsafeBishopFound\\\""', grammar)
        for aliases in permitted.values():
            for alias in aliases:
                self.assertIn(f'"\\\"{alias}\\\""', grammar)
        self.assertIn('actionReferences ::= "[" space "]"', grammar)
        self.assertIn('boardTaskReference ::= "null"', grammar)
        self.assertIn('boardFocusReferences ::= "[" space "]"', grammar)
        self.assertIn('relationshipReferences ::= "[" space "]"', grammar)
        self.assertIn('supportingEvidenceReferences ::= "[" space evidenceReference', grammar)
        self.assertNotIn("action:closeHelp", grammar)
        self.assertNotIn("piece:black:pawn:b7", grammar)

    def test_exact_schema_builds_strict_json_grammar_with_word_limits(self):
        schema = json.loads((TOOLS_DIR / "coaching-turn.schema.json").read_text())

        grammar = coaching_grammar.strict_grammar(schema, enable_thinking=False)

        self.assertIn('root ::= coaching-turn', grammar)
        self.assertNotIn('thinking-block', grammar)
        self.assertNotIn('<think>', grammar)
        self.assertIn('coaching-turn ::= "{" space schemaVersion-kv', grammar)
        self.assertIn('primaryMessage-tail{0,17}', grammar)
        self.assertIn('instruction-tail{0,13}', grammar)
        self.assertIn('responseToLatestAction-tail{0,15}', grammar)
        self.assertIn('[^"\\\\ \\t\\r\\n]', grammar)
        self.assertIn('"\\\"scanDanger\\\""', grammar)

    def test_bounded_mode_requires_a_closed_thinking_block_before_strict_json(self):
        schema = json.loads((TOOLS_DIR / "coaching-turn.schema.json").read_text())

        grammar = coaching_grammar.strict_grammar(schema, enable_thinking=True)

        self.assertIn('root ::= thinking-block coaching-turn', grammar)
        self.assertIn('thinking-block ::= "<think>"', grammar)
        self.assertIn('"</think>"', grammar)
        self.assertIn('line-break{0,2}', grammar)
        self.assertIn('reasoning ::= [^<]{0,128}', grammar)

    def test_changed_schema_is_rejected_instead_of_silently_weakening_constraints(self):
        schema = json.loads((TOOLS_DIR / "coaching-turn.schema.json").read_text())
        schema["properties"]["actionReferences"]["maxItems"] = 4

        with self.assertRaisesRegex(ValueError, "does not match the pinned coaching contract"):
            coaching_grammar.strict_grammar(schema, enable_thinking=False)


if __name__ == "__main__":
    unittest.main()

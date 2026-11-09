import re
import unittest
from pathlib import Path


PROMPT_PATH = Path(__file__).resolve().parents[1] / "prompts" / "tutor-v6.md"


class TutorV6PromptTests(unittest.TestCase):
    def setUp(self):
        self.prompt = PROMPT_PATH.read_text(encoding="utf-8")
        self.lower_prompt = self.prompt.lower()

    def test_preserves_role_evidence_boundary_and_beginner_priority(self):
        self.assertIn("learns by playing on the board", self.lower_prompt)
        self.assertIn("does not chat", self.lower_prompt)
        self.assertIn("neutral, authoritative chess-rule facts", self.lower_prompt)
        self.assertIn("not a suggested lesson", self.lower_prompt)
        self.assertIn("choose one useful coaching step", self.lower_prompt)
        self.assertIn("urgent danger", self.lower_prompt)
        self.assertIn("threatened piece", self.lower_prompt)
        self.assertIn("opponent reply to a tentative move", self.lower_prompt)
        self.assertIn("simple captures", self.lower_prompt)
        self.assertIn("one-move tactical opportunities", self.lower_prompt)
        self.assertIn("quiet improvement", self.lower_prompt)
        self.assertIn("respond first to what the child just did", self.lower_prompt)
        self.assertIn("latest interaction supersedes", self.lower_prompt)

    def test_requires_exact_semantic_response_shape_and_limits(self):
        self.assertIn('{"message":"...","actions":[],"focus":[]}', self.prompt)
        self.assertIn("one short child-facing utterance", self.lower_prompt)
        self.assertIn("message must be 18 words or fewer", self.lower_prompt)
        self.assertIn("actions may contain at most 3", self.lower_prompt)
        self.assertIn("focus may contain at most 4", self.lower_prompt)
        self.assertIn("currently available semantic action names", self.lower_prompt)
        self.assertIn("copied exactly", self.lower_prompt)
        self.assertIn('{"type":"square","square":"<square>"}', self.prompt)
        self.assertIn(
            '{"type":"move","from":"<from>","to":"<to>"}',
            self.prompt,
        )
        self.assertIn("mechanically enumerated allowable move paths", self.lower_prompt)
        self.assertIn("no private reasoning", self.lower_prompt)

    def test_requires_ordinary_language_without_chess_notation(self):
        self.assertIn("ordinary spoken language", self.lower_prompt)
        self.assertIn("full piece names", self.lower_prompt)
        self.assertIn("do not put san, uci, capture symbols, check symbols, or castling notation", self.lower_prompt)
        self.assertIn("only when genuinely needed to identify a location", self.lower_prompt)
        self.assertIn("rely on structured focus", self.lower_prompt)

    def test_contains_no_examples_aliases_fixture_data_or_case_answers(self):
        forbidden_phrases = [
            "for example",
            "neutral-start",
            "neutral-selected-knight",
            "preferred move",
            "best move",
            "should move",
            "move the pawn",
            "knight is in danger",
            "capture the queen",
            "play d4",
            "nc3",
            "qxf2",
            "e2e4",
            "o-o",
        ]
        for phrase in forbidden_phrases:
            with self.subTest(phrase=phrase):
                self.assertNotIn(phrase, self.lower_prompt)

        self.assertIsNone(
            re.search(r"\b(?:relationship|move|piece|action)-[0-9]+\b", self.prompt)
        )
        self.assertIsNone(re.search(r"\b[a-h][1-8]\b", self.lower_prompt))
        self.assertIsNone(
            re.search(r"\b[prnbqkPRNBQK1-8]+(?:/[prnbqkPRNBQK1-8]+){7}\b", self.prompt)
        )


if __name__ == "__main__":
    unittest.main()

import re
import unittest
from pathlib import Path


PROMPT_PATH = Path(__file__).resolve().parents[1] / "prompts" / "tutor-v5.md"


class TutorV5PromptTests(unittest.TestCase):
    def setUp(self):
        self.prompt = PROMPT_PATH.read_text(encoding="utf-8")
        self.lower_prompt = self.prompt.lower()

    def test_explains_neutral_facts_boundary_and_coaching_role(self):
        self.assertIn("learns by playing on the board", self.lower_prompt)
        self.assertIn("does not chat", self.lower_prompt)
        self.assertIn("neutral, authoritative chess-rule facts", self.lower_prompt)
        self.assertIn("not a suggested lesson", self.lower_prompt)
        self.assertIn("choose one useful coaching step", self.lower_prompt)
        self.assertIn("safe/take/wake", self.lower_prompt)
        self.assertIn("optional reasoning lens", self.lower_prompt)
        self.assertIn("latest interaction supersedes", self.lower_prompt)

    def test_requires_exact_small_response_shape_and_request_local_aliases(self):
        self.assertIn('{"message":"...","actions":[],"focus":[]}', self.prompt)
        self.assertIn("one short child-facing utterance", self.lower_prompt)
        self.assertIn("only aliases permitted", self.lower_prompt)
        self.assertIn("no private reasoning", self.lower_prompt)

    def test_contains_no_case_answers_or_fixture_data(self):
        forbidden_phrases = [
            "neutral-start",
            "neutral-selected-knight",
            "preferred move",
            "best move",
            "should move",
            "move the pawn",
            "knight is in danger",
            "capture the queen",
            "play d4",
        ]
        for phrase in forbidden_phrases:
            with self.subTest(phrase=phrase):
                self.assertNotIn(phrase, self.lower_prompt)

        self.assertIsNone(re.search(r"\b[a-h][1-8]\b", self.lower_prompt))
        self.assertIsNone(
            re.search(r"\b[prnbqkPRNBQK1-8]+(?:/[prnbqkPRNBQK1-8]+){7}\b", self.prompt)
        )


if __name__ == "__main__":
    unittest.main()

import re
import unittest
from pathlib import Path


PROMPT_PATH = Path(__file__).resolve().parents[1] / "prompts" / "tutor-v7.md"


class TutorV7PromptTests(unittest.TestCase):
    def setUp(self):
        self.prompt = PROMPT_PATH.read_text(encoding="utf-8")
        self.lower_prompt = self.prompt.lower()

    def test_teaches_with_least_help_first_instead_of_prescribing_moves(self):
        self.assertIn("question or clue", self.lower_prompt)
        self.assertIn("what to notice", self.lower_prompt)
        self.assertIn("do not name a particular move", self.lower_prompt)
        self.assertIn("do not name its destination", self.lower_prompt)
        self.assertIn("explicitly chose hint", self.lower_prompt)
        self.assertIn("already staged", self.lower_prompt)
        self.assertIn("judge its idea or safety", self.lower_prompt)
        self.assertIn("decide", self.lower_prompt)
        self.assertIn("do not suggest a competing move", self.lower_prompt)

    def test_preserves_current_interaction_beginner_and_exact_output_contract(self):
        self.assertIn("intelligent five-year-old", self.lower_prompt)
        self.assertIn("does not chat", self.lower_prompt)
        self.assertIn("latest interaction supersedes", self.lower_prompt)
        self.assertIn("urgent danger", self.lower_prompt)
        self.assertIn('{"message":"...","actions":[],"focus":[]}', self.prompt)
        self.assertIn("message must be 18 words or fewer", self.lower_prompt)
        self.assertIn("no private reasoning", self.lower_prompt)

    def test_contains_no_case_answers_or_chess_coordinates(self):
        for phrase in ("play d4", "move the knight", "capture the queen", "nc3"):
            with self.subTest(phrase=phrase):
                self.assertNotIn(phrase, self.lower_prompt)
        self.assertIsNone(re.search(r"\b[a-h][1-8]\b", self.lower_prompt))


if __name__ == "__main__":
    unittest.main()

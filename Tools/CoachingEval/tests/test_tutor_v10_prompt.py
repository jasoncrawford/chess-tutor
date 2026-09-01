import re
import unittest
from pathlib import Path


PROMPT_PATH = Path(__file__).resolve().parents[1] / "prompts" / "tutor-v10.md"


class TutorV10PromptTests(unittest.TestCase):
    def setUp(self):
        self.prompt = PROMPT_PATH.read_text(encoding="utf-8")
        self.lower_prompt = self.prompt.lower()

    def test_every_question_declares_a_real_child_interaction(self):
        self.assertIn("real way to answer every coaching turn", self.lower_prompt)
        self.assertIn("`selectpiece`", self.lower_prompt)
        self.assertIn("`stagemove`", self.lower_prompt)
        self.assertIn("`none`", self.lower_prompt)
        self.assertIn("`nopieceneedshelp`", self.lower_prompt)
        self.assertIn("everything looks safe", self.lower_prompt)

    def test_preserves_v9_chess_and_teaching_constraints(self):
        for phrase in (
            "help the child notice, think, and decide",
            "immediate recapture",
            "latest interaction supersedes",
            "message and focus must refer to the same",
            "message must be 18 words or fewer",
            "no private reasoning",
        ):
            with self.subTest(phrase=phrase):
                self.assertIn(phrase, self.lower_prompt)
        self.assertIsNone(re.search(r"\b[a-h][1-8]\b", self.lower_prompt))

    def test_output_contract_contains_only_the_four_hosted_turn_fields(self):
        self.assertIn(
            '{"message":"...","actions":[],"focus":[],"expects":"none"}',
            self.prompt,
        )


if __name__ == "__main__":
    unittest.main()

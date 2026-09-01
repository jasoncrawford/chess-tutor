import re
import unittest
from pathlib import Path


PROMPT_PATH = Path(__file__).resolve().parents[1] / "prompts" / "tutor-v9.md"


class TutorV9PromptTests(unittest.TestCase):
    def setUp(self):
        self.prompt = PROMPT_PATH.read_text(encoding="utf-8")
        self.lower_prompt = self.prompt.lower()

    def test_help_opening_starts_with_the_danger_scan_before_development(self):
        self.assertIn("latest interaction is help opened", self.lower_prompt)
        self.assertIn("start with the urgent-danger scan", self.lower_prompt)
        self.assertIn("do not jump directly", self.lower_prompt)
        self.assertIn("quiet improvement", self.lower_prompt)

    def test_actions_are_direct_answers_and_do_not_endorse_a_bad_move(self):
        self.assertIn("actions must be sensible direct replies", self.lower_prompt)
        self.assertIn("warning against a staged move", self.lower_prompt)
        self.assertIn("do not include `playmove`", self.lower_prompt)

    def test_distinguishes_real_threat_and_aligns_message_with_focus(self):
        self.assertIn("immediate recapture", self.lower_prompt)
        self.assertIn("resulting material", self.lower_prompt)
        self.assertIn("not automatically a real threat", self.lower_prompt)
        self.assertIn("message and focus must refer to the same", self.lower_prompt)
        self.assertIn("focus that piece", self.lower_prompt)
        self.assertIn("focus destination squares", self.lower_prompt)

    def test_preserves_hint_staged_current_step_and_output_contract(self):
        self.assertIn("explicitly chose hint", self.lower_prompt)
        self.assertIn("already staged", self.lower_prompt)
        self.assertIn("latest interaction supersedes", self.lower_prompt)
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

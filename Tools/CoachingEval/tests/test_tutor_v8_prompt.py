import re
import unittest
from pathlib import Path


PROMPT_PATH = Path(__file__).resolve().parents[1] / "prompts" / "tutor-v8.md"


class TutorV8PromptTests(unittest.TestCase):
    def setUp(self):
        self.prompt = PROMPT_PATH.read_text(encoding="utf-8")
        self.lower_prompt = self.prompt.lower()

    def test_initial_help_teaches_the_routine_without_choosing_a_plan(self):
        self.assertIn("ordinary help", self.lower_prompt)
        self.assertIn("urgent danger", self.lower_prompt)
        self.assertIn("simple capture", self.lower_prompt)
        self.assertIn("quiet improvement", self.lower_prompt)
        self.assertIn("do not choose a specific move", self.lower_prompt)
        self.assertIn("specific piece unless danger is urgent", self.lower_prompt)

    def test_distinguishes_a_real_threat_from_a_merely_legal_capture(self):
        self.assertIn("immediate recapture", self.lower_prompt)
        self.assertIn("resulting material", self.lower_prompt)
        self.assertIn("merely legal capture", self.lower_prompt)
        self.assertIn("not automatically a real threat", self.lower_prompt)

    def test_hint_and_staged_move_can_be_precise_without_prescribing_a_replacement(self):
        self.assertIn("explicitly chose hint", self.lower_prompt)
        self.assertIn("already staged", self.lower_prompt)
        self.assertIn("judge its idea or safety", self.lower_prompt)
        self.assertIn("do not suggest a competing move", self.lower_prompt)

    def test_message_and_focus_must_express_the_same_idea(self):
        self.assertIn("message and focus must refer to the same", self.lower_prompt)
        self.assertIn("asks about a piece", self.lower_prompt)
        self.assertIn("focus that piece", self.lower_prompt)
        self.assertIn("asks about destinations", self.lower_prompt)
        self.assertIn("focus destination squares", self.lower_prompt)

    def test_preserves_current_interaction_beginner_and_exact_output_contract(self):
        self.assertIn("intelligent five-year-old", self.lower_prompt)
        self.assertIn("does not chat", self.lower_prompt)
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

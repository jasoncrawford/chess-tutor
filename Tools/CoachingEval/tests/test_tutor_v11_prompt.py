import unittest
from pathlib import Path


PROMPT_PATH = Path(__file__).resolve().parents[1] / "prompts" / "tutor-v11.md"


class TutorV11PromptTests(unittest.TestCase):
    def test_response_types_name_exact_visible_controls(self):
        prompt = PROMPT_PATH.read_text(encoding="utf-8")

        required_phrases = (
            "`findEndangeredPiece`",
            "No piece needs help",
            "`findSafeCapture`",
            "No safe capture",
            "`judgeMoveSafety`",
            "Looks safe",
            "`chooseWhetherToPlay`",
            "Play this move",
            "Try another move",
        )
        for phrase in required_phrases:
            with self.subTest(phrase=phrase):
                self.assertIn(phrase, prompt)

    def test_model_does_not_choose_primary_response_buttons(self):
        prompt = PROMPT_PATH.read_text(encoding="utf-8")

        self.assertIn("The app derives the primary response controls", prompt)
        self.assertIn("Actions may contain only `hint`", prompt)


if __name__ == "__main__":
    unittest.main()

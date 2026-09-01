import unittest
from pathlib import Path


PROMPT_PATH = Path(__file__).resolve().parents[1] / "prompts" / "tutor-v12.md"


class TutorV12PromptTests(unittest.TestCase):
    def test_visible_control_titles_use_plain_text_or_quotes(self):
        prompt = PROMPT_PATH.read_text(encoding="utf-8")

        self.assertIn('"No piece needs help"', prompt)
        self.assertIn('"No safe capture"', prompt)
        self.assertIn('"Looks safe"', prompt)
        self.assertIn('"Play this move"', prompt)
        self.assertIn('"Try another move"', prompt)
        self.assertIn("Do not use Markdown", prompt)
        self.assertNotIn("exact bold title", prompt)
        self.assertNotIn("**No piece needs help**", prompt)

    def test_discovery_questions_do_not_focus_the_answer(self):
        prompt = PROMPT_PATH.read_text(encoding="utf-8")

        self.assertIn(
            "For `findEndangeredPiece` and `findSafeCapture`, return an empty `focus` list",
            prompt,
        )
        self.assertIn("Do not circle or otherwise reveal the answer", prompt)

    def test_eighteen_words_is_guidance_not_a_validity_rule(self):
        prompt = PROMPT_PATH.read_text(encoding="utf-8")

        self.assertIn("Aim for 18 words or fewer", prompt)
        self.assertNotIn("message must be 18 words or fewer", prompt.casefold())


if __name__ == "__main__":
    unittest.main()

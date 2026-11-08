import unittest
from pathlib import Path


PROMPT_PATH = Path(__file__).resolve().parents[1] / "prompts" / "tutor-v13.md"


class TutorV13PromptTests(unittest.TestCase):
    def test_every_live_turn_requires_a_meaningful_response(self):
        self.assertTrue(PROMPT_PATH.exists(), "tutor-v13 prompt is missing")
        prompt = PROMPT_PATH.read_text(encoding="utf-8")

        self.assertIn("Every live coaching turn needs a real response", prompt)
        self.assertIn("feedback and the next question in the same message", prompt)
        self.assertNotIn("`none`", prompt)
        self.assertNotIn('"expects":"none"', prompt)


if __name__ == "__main__":
    unittest.main()

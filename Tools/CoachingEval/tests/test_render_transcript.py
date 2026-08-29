import json
import os
import sys
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

import render_transcript


class RenderTranscriptTests(unittest.TestCase):
    def test_renders_fixed_readable_sections_exact_text_and_evidence_accounting(self):
        markdown = "# Chess coaching context\n\n- Latest action: moved knight"
        rendered_prompt = "SYSTEM\n" + markdown + "\nASSISTANT"
        response = '{"schemaVersion":"model-coaching-turn.v1"}'
        record = {
            "caseID": "case-1",
            "caseSplit": "visible",
            "modelID": "test-model",
            "mode": "off",
            "seed": 1103,
            "requestID": "request-1",
            "positionRevision": 7,
            "modelArtifactSHA256": "f" * 64,
            "llamaCppVersion": "b10516",
            "evaluatorPromptVersion": "tutor-v3",
            "evaluationCase": {
                "compactContext": {
                    "markdown": markdown,
                    "referenceBindings": [
                        {
                            "alias": "piece-white-king-d4",
                            "stableID": "piece:white:king:d4",
                            "category": "piece",
                        }
                    ],
                    "omissions": [
                        {
                            "stableID": "move:d4-e4",
                            "category": "move",
                            "reason": "not currently relevant",
                        }
                    ],
                }
            },
            "rawFinalContent": response,
            "aliasTurn": {"boardFocusReferences": ["piece-white-king-d4"]},
            "stableTurn": {"boardFocusReferences": ["piece:white:king:d4"]},
            "firstAttemptValidation": {"valid": True, "errors": []},
            "aliasRestorationErrors": [],
            "renderedPromptTokens": 4000,
            "promptTokens": 4000,
            "outputTokens": 50,
            "latencyMilliseconds": 123.5,
        }
        environment = {"COACHING_EVAL_REFERENCE_API_KEY": "DO-NOT-LEAK"}

        transcript = render_transcript.render_transcript(
            record,
            rendered_prompt=rendered_prompt,
            environment=environment,
        )

        headings = [
            "# Coaching evaluation transcript",
            "## Identity and provenance",
            "## Model input Markdown",
            "## Exact rendered prompt",
            "## Model response",
            "## Alias turn",
            "## Stable-ID turn",
            "## Validation",
            "## Evidence accounting",
            "## Tokens and timing",
        ]
        positions = [transcript.index(heading) for heading in headings]
        self.assertEqual(sorted(positions), positions)
        self.assertIn(markdown, transcript)
        self.assertIn(rendered_prompt, transcript)
        self.assertIn(response, transcript)
        self.assertIn("piece-white-king-d4", transcript)
        self.assertIn("piece:white:king:d4", transcript)
        self.assertIn("move:d4-e4", transcript)
        self.assertIn("not currently relevant", transcript)
        self.assertIn("4,000", transcript)
        self.assertNotIn(environment["COACHING_EVAL_REFERENCE_API_KEY"], transcript)
        lowered = transcript.lower()
        self.assertNotIn("<think", lowered)
        self.assertNotIn("reasoning_content", lowered)
        self.assertNotIn("provider body", lowered)


if __name__ == "__main__":
    unittest.main()

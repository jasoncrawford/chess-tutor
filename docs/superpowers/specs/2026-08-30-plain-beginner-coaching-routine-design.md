# Plain Beginner Coaching Routine Prompt Design

Date: 2026-08-30

## Goal

Replace the unexplained Safe/Take/Wake mnemonic in `tutor-v5.md` with a short plain-language priority routine that a model can apply without product-specific vocabulary.

## Prompt behavior

The system prompt will tell the tutor to favor immediate, understandable ideas over deep tactics and apply this flexible priority order:

1. Notice urgent danger: check, a threatened piece, or a strong opponent reply to a tentative move.
2. Notice simple captures or one-move tactical opportunities.
3. When neither is pressing, notice a quiet improvement that brings a piece into play, protects something, controls useful squares, or improves king safety.

The routine is guidance rather than a deterministic sequence. The latest learner interaction still takes precedence, and the model must respond to what the child just did. The names Safe, Take, and Wake will not appear in the model-facing prompt.

## History behavior

The user message continues to include the complete committed move history on one compact `Moves:` line in SAN. A tentative move remains separate and is never folded into committed history.

## Verification and gate

The prompt boundary test will require the plain-language priorities and reject the mnemonic. The eight structured examples will be regenerated, rendered and tokenized without completion or inference, checked against the 2,500-token ceiling, and returned to the user for another review before any model call.

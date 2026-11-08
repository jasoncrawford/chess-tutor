# Hosted Coaching Development Traces Design

## Goal

Make a complete successful coaching exchange easy to copy from the local development terminal so advice quality can be reviewed across a real play session without reconstructing the interaction by hand.

## Behavior

- Content traces are off by default.
- `scripts/run_hosted_coaching_dev.sh` turns them on for its local server process.
- Each successful model exchange is logged as one compact JSON line containing:
  - FEN, compact move history, side/status, revision, and the current help-session events/selection/staged move;
  - request kind and reasoning effort;
  - validated message/actions/focus and latency.
- Large rule-evidence arrays—pieces, legal moves, relationships, tentative replies, and capabilities—are omitted because FEN plus move/interaction history is sufficient to reconstruct the chess situation for qualitative review.
- The block identifies the safe request trace and whether it is an initial request or follow-up.
- Existing operational lifecycle and latency logs remain unchanged.

## Privacy And Failure Boundaries

Content traces never contain the model-facing system/user prompts, OpenAI API key, app access token, provider response IDs, continuation IDs, reasoning traces, or raw provider error/response bodies. Invalid or failed provider responses produce only the existing stable operational logs; no content trace is emitted because there is no validated response.

## Configuration

`CHESS_TUTOR_COACHING_LOG_CONTENT=1` enables content traces. Any other value, including an unset variable, leaves them disabled. The checked-in deployment configuration does not set this variable.

## Verification

Tests will prove default silence, exact compact history/interaction/advice content, exclusion of verbose rule arrays, prompts, and provider identifiers, absence of raw invalid output, environment wiring, and automatic launcher opt-in.

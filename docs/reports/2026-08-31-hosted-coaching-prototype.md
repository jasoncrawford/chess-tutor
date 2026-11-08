# Hosted coaching prototype

## Result

The private hosted-coaching path is implemented end to end and ready for
hands-on prototype use. The iPad remains authoritative for chess state and
legal facts. It sends one strict structured request to a portable Python
service; the service owns prompt rendering, GPT-5.6 Sol/high, strict Structured
Outputs, and the private OpenAI key.

The app shows a persistent **Thinking…** coaching shell while a request is in
flight. Any selection, inspection, staged move, replacement, or removal creates
a fresh request from current first principles. Older responses cannot replace
newer state. Success appears atomically; failure offers Retry and Close Help,
with no deterministic-coach fallback.

## Architecture

1. `GameSession` records the latest learner interaction and current board state.
2. The existing neutral request builder derives chess facts mechanically.
3. The server compiles the same request into concise `tutor-v6` Markdown.
4. GPT-5.6 Sol/high returns one request-specific JSON turn.
5. Server and device independently validate exact fields, actions, focus, and
   request identity.
6. SwiftUI projects the validated turn into the existing coaching panel.

The device never holds the OpenAI key. The server never receives or stores a
child identity, conversation, provider response ID, or hidden reasoning.

## Verified behavior

- Help, Thinking, success, failure, Retry, Hint, Play This Move, Try Another
  Move, Close Help, and stale-response rejection are covered by permanent tests.
- Board input remains ordinary chess input while hosted help is active; coaching
  recalculates around what the child actually does.
- A delayed-provider UI test samples the full transition and confirms that the
  coaching shell never falls back to the ordinary sidebar or shows stale copy.
- Existing local coaching remains unchanged when hosted configuration is absent.
- Configuration is resolved once and carried into new or restored games.
- The server rejects noncanonical chess strings before prompt compilation, and
  the iPad streams responses through a hard 64 KiB limit instead of buffering
  an unbounded body.
- Provider timeouts, including upstream HTTP 504 responses, remain a distinct
  retryable timeout at the API boundary.

Final verification on iPad (A16), iOS 26.5 Simulator:

- Swift unit/UI suite: **948 passed, 0 failed, 0 skipped**
- Coaching evaluator Python suite: **177 passed**
- Hosted server Python suite: **11 passed**
- Standalone simulator build: **succeeded**
- `git diff --check`: clean

## Model evidence and latency concern

The prior frozen twelve-position evaluation remains the semantic model gate:
Sol/high produced **12/12 valid responses and 0 severe responses**, with 4.7 s
median and 7.3 s p90 latency. See
[the broader evaluation](./2026-08-30-broader-hosted-coaching-evaluation.md).

During final live-server verification on August 31, 2026, a minimal OpenAI
connectivity request completed successfully, but two Sol/high structured
coaching attempts did not return within bounded client waits; the second was
stopped at 90 seconds. No invalid response or private data was persisted. This
looks like current provider latency variance rather than a contract failure,
but it is the main prototype concern. The iPad transport now stops waiting at
35 seconds and presents Retry. Before production, collect real interactive
latency over ordinary play and decide whether to lower reasoning effort,
introduce a faster first-pass model, or keep Sol/high with a longer wait.

## Running it

Use [the server runbook](../hosted-coaching-server.md) for local development and
Vercel deployment. The same dependency-free WSGI application serves both.

The implementation follows OpenAI's
[Structured Outputs guidance](https://developers.openai.com/api/docs/guides/structured-outputs)
and Vercel's
[Python Functions runtime](https://vercel.com/docs/functions/runtimes/python).

# Chess-native hosted-model pilot implementation plan

**Goal:** Produce one immutable, trace-free, strictly validated eight-response `gpt-5.6-sol` pilot from the frozen tutor-v6 packet.

**Architecture:** Add a small OpenAI Responses API client and a hosted runner beside the existing local pilot. Reuse the frozen-source loader and `ChessNativeResponseContract`; do not alter prompt bytes, app behavior, the local runner, or hidden data.

## Task 1: Responses API transport

- Write failing tests for exact system/user roles, model/reasoning settings, request-specific strict JSON Schema, HTTPS credential enforcement, redirect credential stripping, response extraction, bounded error redaction, and absence of reasoning persistence.
- Implement the minimal transport that satisfies them.
- Run the focused transport tests.

## Task 2: Immutable hosted runner

- Write failing tests for exact eight-case order and hashes, one call per case, no retry/repair, continuation after failures, request-aware validation, trace-free atomic artifacts, environment credential handling, and overwrite refusal.
- Implement the hosted runner and review renderer.
- Run focused and full `Tools/CoachingEval` tests.

## Task 3: Eight-case hosted run

- Verify the frozen source and system hashes before any request.
- Require `OPENAI_API_KEY` without printing or persisting it.
- Run exactly eight serial calls once and verify output artifacts.
- Inspect and compare all eight responses with the prior SmolLM3 pilot.

## Task 4: Handoff

- Record exact model/settings, mechanical outcomes, representative strengths/failures, and the online-versus-local conclusion.
- Run final tests and diff/status checks.
- Commit only scoped tracked code, tests, and report; keep raw evaluation artifacts ignored.

# Hosted Coaching Follow-ups Implementation Plan

## 1. Responses transport and service policy

Write failing Python tests for optional `previous_response_id`, stored responses, cached-token extraction, initial high reasoning, follow-up low reasoning, strict continuation validation, and stateless HTTP envelopes. Extend the OpenAI client and service minimally. Add server configuration for `low` or `none`; never set a premium service tier.

## 2. iPad transport contract

Write failing Swift transport tests for the v2 request envelope and response continuation ID. Extend hosted contracts and strict decoding. Keep the opaque ID in memory only and reject malformed or mismatched responses.

## 3. Episode state and request cadence

Write failing hosted-session and GameSession tests proving that selection/inspection produces no request, meaningful move changes produce one request, a completed response supplies the next continuation, and stop/commit/new-position resets it. Implement this in the hosted session and pending-request path without changing chess-rule code or views.

## 4. Least-help-first prompt

Add `tutor-v7.md` and focused prompt-contract tests for discovery-first language, explicit Hint/staged-move exceptions, current-interaction precedence, and the unchanged strict output shape. Point the hosted server and Swift response guard to v7.

## 5. Verification

Run focused RED/GREEN suites after each slice, then all CoachingServer and CoachingEval Python tests, affected Swift tests, and the full iPad scheme. Launch the real local development server and perform one bounded Help → selection → staged-move flow, confirming request count, high→low reasoning, latency, visible continuity, and coaching quality. Repeat only the short follow-up with `none` if it gives useful comparison evidence.

## 6. Delivery

Self-review the diff and security boundaries, commit on `codex/hosted-coaching-followups`, push, open a PR against `codex/chess-coaching-comparison`, and wait for CI.

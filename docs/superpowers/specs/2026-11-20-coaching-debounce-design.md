# Coaching input batching and client diagnostics

Approved in chat: implement debounce and client logging together; no further design review requested.

## Intent

Let a child explore the board while Help is open without producing a request for every fleeting choice. Keep board feedback immediate and make the request savings and added waiting measurable. The 400 ms interval is a tunable starting hypothesis, not an empirically established optimum.

## Approach

Opening Help and explicit response controls remain immediate. Board answers and staged-move changes wait until 400 ms after the latest coaching-relevant interaction. Ordinary selections remain local. A burst retains only its newest pending request; one provider call may be in flight per GameSession. New board input does not cancel/restart that call. When it completes, discard outdated advice and send only the latest pending state once its quiet interval has elapsed. Do not chain unseen advice into the conversation continuation.

Keep the current selection question available internally while its answer is pending, so subsequent piece taps can replace the answer rather than silently being ignored. A staged move supersedes that question. Actual moves, captures, promotion and turn completion keep their existing rules. Close Help, new game, game switches and remote locking invalidate queued work; cancelled or stale replies never change current advice.

Alternatives considered: debounce only after a second tap still spends a request on the first fleeting choice; debounce alone does not prevent overlapping requests; disabling board interaction would frustrate exploration. Use trailing-edge debounce plus one in-flight call and one replaceable pending update. Limit is client/session scoped, not a cross-device server rate limit.

## Diagnostics

Reuse the bounded on-device DiagnosticsLog and its existing Share Diagnostics export. Record compact coaching events with wall-clock timestamp, monotonic timing, event sequence, schema version, game/episode/request IDs where applicable, and configured debounce. Record board input and its disposition, meaningful interactions, scheduling/coalescing, actual provider invocation, completion/failure/cancellation, and applied versus discarded responses. Capture the event time before asynchronous file writing. A sequence field disambiguates asynchronous log-write ordering.

At dispatch include the number of unsent requests combined, time since final interaction, burst age, debounce wait, and extra in-flight wait beyond the debounce interval. Server logs already provide provider duration and tokens; correlate using game + episode + request ID. Never infer server cancellation or refunded cost from a client cancellation.

No tokens, continuation IDs, prompts, raw errors, or full request/response payloads in client logs. No per-tap network telemetry, new database, prompt/model changes, production rollout, paid evaluation, or physical-device installation in this task. Logs remain bounded under existing retention. A human can export the trace to compare candidate debounce intervals; this change does not claim to automate that analysis.

## Acceptance

- Help starts immediately; a short burst sends only its final answer/state after 400 ms of quiet.
- A request already in progress is not replaced by parallel calls; only the newest follow-up runs next.
- Selecting, moving and revising pieces remain immediate; stale advice is never shown.
- Closing/reopening Help and cancelling a resolver cannot leak queued requests or cross conversation context.
- Exported client logs explain local-only taps, combined requests, waits, outcomes and application/discard decisions without sensitive content.
- Fake-clock integration tests prove timing and request counts without paid API calls; full native tests remain green.

# Hosted coaching follow-ups

## Outcome

Hosted coaching now keeps piece selection and inspection local. Opening Help starts
one stored Responses API chain; staged, replaced, or removed moves, Hint, and retry
continue that chain with a compact update. The initial request uses high reasoning,
while follow-ups use low reasoning by default. No Fast service tier is requested.

The server-owned `tutor-v7` prompt uses least-help-first coaching: ordinary Help
begins with a question or clue, while exact moves are reserved for Hint or feedback
about a move the child already staged.

## Live simulator evidence

The final app and server were exercised on the `ChessTutor Coaching Smoke` iPad
(A16) simulator with GPT-5.6 Sol:

| Interaction | Reasoning | Requests | Latency | Visible coaching |
| --- | --- | ---: | ---: | --- |
| Open Help | high | 1 | 6.767 s | “Can you find a center pawn that could move and open a path for a piece?” |
| Select a knight | local | 0 | — | Existing advice remained visible |
| Stage g1–f3 | low | 1 | 3.258 s | “Nice! This knight comes out and helps control the center. Would you like to keep it?” |
| Stage g1–f3 (comparison) | none | 1 | 1.941 s | “Nice! Your knight jumps toward the center, and Black has no immediate attack. Would you keep it?” |

The approved default remains `low`; `none` is available only as a server-owned
development comparison. Cached input tokens were zero in these short trials, so
the measured improvement came from the compact follow-up and reduced reasoning,
not prompt caching.

## Verification

- Full iPad scheme: 948 passed, 0 failed, 0 skipped.
- Coaching server: 28 passed.
- Coaching evaluator: 183 passed.
- Standalone iPad simulator build: succeeded.

# Family iPad coaching timeouts — November 18

## Finding

The reported failures were the server's 30-second provider timeout, not a
reported quota rejection. Three initial Help requests for White's move 24
returned HTTP 504 at approximately 30.04 seconds. Vercel reported warm
functions, no crash, and a 60-second platform limit. Prompt compilation took
only a few milliseconds. The failure was inside the outbound provider call.

This identifies the failing boundary, **not** whether the delay was provider
queueing/generation or the intervening network. The old logs did not record
whether response headers had arrived. No provider outage is established.

## Controlled replay

The retained game's 46-ply move history was replayed through the production
Swift rules and neutral request builder. The test asserts this exact FEN:

`r2q2k1/ppp5/6N1/2PP1r1p/3Q4/5p2/PPP2PP1/R4RK1 w - - 0 24`

The first failed interaction was `helpOpened`, with no selected piece or staged
move. The replay reconstructs that interaction; it is not the original raw
HTTP body, which was intentionally not logged. The subsequent two failures
were retries (`helpReopened`) in the same episode, with no continuation ID.

Four paid diagnostic calls were made: two pairs of hosted versus direct
requests for this position, using the unchanged accepted policy. Direct calls
allowed 90 seconds for diagnosis; hosted calls retained the production limit.
No model sweep, grading, prompt change, or automatic paid retry was performed.

| Replay | Path | Outcome | Wall time | Input / output / reasoning tokens |
| --- | --- | --- | --- | --- |
| 1 | Direct | Valid coaching | 20.17 s | 1,889 / 440 / 373 |
| 1 | Hosted | HTTP 504 | 30.46 s | Unknown |
| 2 | Direct | Valid coaching | 23.45 s | 1,889 / 524 / 450 |
| 2 | Hosted | Valid coaching | 16.52 s | 1,889 / 369 / 303 |

Successful direct requests received headers at 20.16 and 23.44 seconds;
remaining body parsing/validation was milliseconds. The second hosted request
reported 16.15 seconds inside the provider call. The first direct request had
no cached input; the two later successes each had 1,886 cached tokens. A large
prompt or accumulated follow-up chain does not explain these initial failures.

The replay confirms intermittent behavior, not a permanently failing position
or broken Vercel connection. It does **not** prove how long a failed call would
eventually take. Therefore the provider/client/platform limits remain
30/35/60 seconds; increasing them would currently be a speculative mitigation.

Local diagnostic artifacts (not source-controlled):

- `/tmp/chess-nov18-incident-request.json`
- `/tmp/chess_timeout_probe.py`
- `/tmp/chess-timeout-probe.jsonl`
- `/tmp/chess-timeout-probe-repeat.jsonl`

## Changes

- Preserve response-body timeouts as `timeout`, instead of converting them to
  generic transport errors. A failing unit test reproduced this separate bug;
  it is not claimed as the original incident's cause.
- Provider failures log bounded `transport` metadata: category, HTTP status,
  phase (`awaitingHeaders`, `readingBody`, or `httpResponse`), and time to headers
  when known. Completed failed-turn summaries retain the same metadata.
- No credentials, raw prompts/responses, exception text, continuation IDs or
  reasoning content are added to logs or the client wire response.
- The iPad distinguishes HTTP 504 and local URL timeouts from other errors and
  says: “The coach took too long to reply. Try again, or keep playing.”
- Retry remains user-controlled, preserving the current game, staged move and
  last successful continuation. Closing/reopening Help rejects late failures.

## Verification / rollout

The provider phase/body-timeout tests, server diagnostic test, and three native
timeout/retry tests were observed failing before their fixes. The incident
replay test passed and exported the real-rule request. Full post-change test
results and PR status are recorded at delivery; no new production deployment
or physical-iPad installation is implied by these local tests.

After merging/deploying the diagnostics, collect the next failure's
`coaching_turn` record. `awaitingHeaders` still includes connection establishment
and provider processing: it must not be labeled as proven model reasoning time.
A `readingBody` failure establishes that an HTTP response had already begun.
If the slow response problem recurs, use that evidence for a longer hosted
diagnostic or a separately budgeted latency-policy experiment.

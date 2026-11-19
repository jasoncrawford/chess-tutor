# Family iPad coaching timeouts — November 18

## November 19 mitigation

The user approved increasing timeout headroom. PR #26 now selects a dedicated
`CoachingServer/configs/production-v2.json`: the accepted Astra experience-v7
policy with **only** its provider timeout raised from 30 to 60 seconds. The iPad
request timeout is 70 seconds and Vercel's function ceiling is 90 seconds.
The development launcher selects the same configuration. Historical benchmark
inputs and the legacy v1 config remain untouched; this changes no model,
prompt, reasoning, output-token limit or automatic-retry policy.

This is an approved mitigation, not proof that it rescues the originally failed
requests. Successful requests still return immediately. No additional paid
replay or quality benchmark was run for this configuration change. The live
server and family iPad have not been updated: both a deployment and an app
rebuild/install are required, with the newer iPad installed before or alongside
the server so the old 35-second client cutoff does not mask the extra headroom.
The investigation and limits described below are the earlier checkpoints.

Verification for the headroom change: **1,013 native unit tests, 11 UI tests,
73 server tests and 381 evaluation-tooling tests passed, zero failures/skips**.
Native result: `/tmp/chess-headroom-full.xcresult`; Python logs:
`/tmp/chess-headroom-server-full.log` and `/tmp/chess-headroom-eval-full.log`.
The packaged-app/provider, development-policy and native outgoing-request tests
were observed failing with the old limits before the changes. Final review also
caught `.env.example` silently restoring the old timeout; a shell/launcher
regression reproduced 30 seconds and passed after making the example override
optional. One minor suggestion is deferred: an additional packaged-server test
that counts attempts on a provider timeout (the attempt policy remains one;
timeout mapping and exact policy parity already have coverage).

The user subsequently authorized merging once CI is green and rolling out both
parts. As of this source checkpoint that rollout is pending; do not infer that
the live endpoint or physical iPad is updated from the passing local tests.

## Finding

The reported failures were the server's 30-second provider timeout, not a
reported quota rejection. Three initial Help requests for White's move 24
returned HTTP 504 at approximately 30.04 seconds. Vercel reported warm
functions, no crash, and a 60-second platform limit. Prompt compilation took
only a few milliseconds. The failure was inside the outbound provider call.

The original logs identify the failing boundary, **not** whether the delay was
provider processing or the intervening network. The longer hosted replay below
strongly supports provider processing as the source of the slow responses, but
did not reproduce a provider call exceeding 30 seconds. No provider outage is
established, and the original timed-out calls have no phase measurements.

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

## Longer hosted replay (November 19 UTC / November 18 local)

Following the user's request to pursue the cause rather than just improve error
handling, four additional paid calls replayed the same rule-generated request
through a disposable Vercel project in `iad1`. It used the same app, prompt,
model and reasoning policy. Only the generated diagnostic bundle changed the
provider/platform deadlines to 90/120 seconds; its HTTP caller allowed 110
seconds. Each call was an initial Help request with no continuation. No paid
retry or model sweep ran.

The diagnostic measured DNS/TCP/verified TLS, request submission, response
headers, and body completion. OpenAI's `openai-processing-ms` response header
reports provider processing time; it does not distinguish internal queueing
from inference. See the [OpenAI API reference](https://developers.openai.com/api/reference/overview/).

| Call | HTTPS connected | Provider reported processing | Provider call total | Hosted HTTP wall time | Reasoning tokens |
| --- | --- | --- | --- | --- | --- |
| 1 | 9.8 ms | 12.559 s | 13.340 s | 13.672 s | 296 |
| 2 | 7.2 ms | 29.766 s | 29.897 s | 30.218 s | 755 |
| 3 | 7.7 ms | 28.181 s | 28.248 s | 28.460 s | 776 |
| 4 | 8.2 ms | Not retained | 28.264 s | 28.672 s | 661 |

All four returned HTTP 200. For the three fully retained traces, body
reading/parsing after response headers took less than 10 ms. The fourth
response's metrics were retained, but its final phase logs had not appeared
when the project was removed. They could not be retrieved afterward. The
repeatable tool now polls for terminal log events before cleanup and explicitly
reports any missing events; no extra paid call was made to fill that gap.

These results show that slow **successful** hosted calls spend almost all their
time in provider processing, not connection setup, request upload, prompt
compilation or response parsing. The input was constant at 1,889 tokens, with
1,886 cached input tokens on calls 2–4. Reported reasoning output varied from
296 to 776 tokens, but this correlation does not prove reasoning alone caused
the latency.

The most likely explanation is provider processing variability colliding with
our 30-second deadline. However, none of these provider calls exceeded 30
seconds (call 2 came within about 0.1 seconds). Therefore this experiment did
**not** demonstrate that a longer timeout rescues a formerly failing request.
It is a diagnostic finding, not a root-cause fix. At this diagnostic checkpoint,
production remained at 30/35/60 seconds; no prompt, model, reasoning, or deployment changes were made.
A coordinated deadline increase remains a possible mitigation, not a latency
improvement. Changing model/effort would require quality evaluation.

Diagnostic setup initially encountered Vercel preview login protection. Those
attempts were removed before any model call. The eventual disposable project
used a random bearer token, one-hour expiry, and checked rejection of
unauthenticated requests before making the four calls. Its deployment and
project were deleted afterward. The live production deployment ID and access
protection were verified unchanged.

Reproduction, **only with approval for up to four additional paid requests**:

```sh
.venv/bin/python -m scripts.probe_hosted_coaching \
  --request /tmp/chess-nov18-incident-request.json --calls 4
```

This requires `VERCEL_TOKEN`, the existing OpenAI Keychain credential, and the
neutral request exported by
`HostedCoachingIncidentReplayTests.testNovember18TimeoutPositionCanBeReplayedAndExported`
with `COACHING_INCIDENT_REQUEST_PATH` set in the test process. Credentials are
never passed as command arguments or printed. The command creates and deletes
only its newly named diagnostic project; it does not promote a deployment into
the production project. It logs timing/usage, not prompts, replies or reasoning
content. The diagnostic implementation is excluded from the production runtime
manifest.

Evidence: `/tmp/chess-hosted-rootcause-replay-6.jsonl`; diagnostic game
`3c416ddd-86ad-4791-92fc-27377a58e099`, now-deleted deployment
`dpl_G6LR6DvLtdyN2ZhZCLNdeMeYKmER`. Total additional usage reported by the four
successful calls: 7,556 input tokens (5,658 cached), 2,767 output tokens,
including 2,488 reasoning tokens.

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
- Independent review found and reproduced malformed HTTP status lines escaping
  the bounded Python error handler, and interrupted error bodies hiding an
  already-known HTTP status. The handler now bounds HTTP protocol exceptions
  and closes unused error bodies without reading them.
- The real iPad URLSession loader also handles non-200 status immediately after
  headers, cancelling the unused body stream. Successful responses retain the
  size limit. A cancelled resolver ignores both queued success and failure.

## Verification / rollout

The provider phase/body-timeout tests, server diagnostic test, and three native
timeout/retry tests were observed failing before their fixes. The incident
replay test passed and exported the real-rule request. Full post-change test
results:

- 1,024 native tests passed; zero failures or skips. Result bundle:
  `/tmp/chess-timeout-verified-native.xcresult`.
- 66 server tests passed (`/tmp/chess-timeout-server-final.log`).
- 380 evaluation-tooling tests passed (`/tmp/chess-timeout-eval-final.log`).
- `git diff --check` passed. One independent review; all four important findings
  fixed and covered by regression tests, with none deferred.

After the longer hosted diagnostic, fresh full Python runs passed 72 server
tests and 381 evaluation-tooling tests, with zero failures or skips
(`/tmp/chess-rootcause-server-final.log` and
`/tmp/chess-rootcause-eval-final.log`). Native source was unchanged from the
1,024-test run above. The incremental diagnostic review found one important
issue: caller-side exceptions could skip log collection before deletion. A
failing lifecycle regression reproduced it; attempted-call logs are now
collected in `finally`, with deletion in a nested `finally`. The regression
passed, as did the complete suites after the fix. No review finding was
deferred. Log-ingestion polling also has incomplete/complete regression cases;
cleanup and call-cap tests make no external requests.

These are local results. The PR is left for review; no new production deployment
or physical-iPad installation is implied. Model, prompt, reasoning and benchmark
configurations are unchanged, so no paid quality-evaluation run was performed.

After merging/deploying the diagnostics, collect the next failure's
`coaching_turn` record. `awaitingHeaders` still includes connection establishment
and provider processing: it must not be labeled as proven model reasoning time.
A `readingBody` failure establishes that an HTTP response had already begun.
If the slow response problem recurs, use that evidence for a longer hosted
diagnostic (the first four-call hosted run above did not exceed 30 seconds) or
a separately budgeted latency-policy experiment.

Execution decisions: native test waits overlapped Python implementation/tests;
the initial full native run was stopped after review found additional cases,
and a new complete run was started against all final fixes. No review finding
was deferred. No deadline change or model-quality change was made.

The first complete native run passed 1,023 tests and failed the new URLSession
fixture test. An isolated local probe demonstrated that omitting Content-Type
made URLSession buffer the simulated response before yielding its headers.
The fixture now declares JSON (matching the server), uses a private URL scheme
that cannot fall through to external networking, and still never supplies the
body. Its regression was rechecked against the old body-reading behavior before
the final full-suite run; no production behavior was weakened to satisfy it.

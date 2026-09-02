# Hosted coaching server

The private prototype accepts mechanically generated chess facts from the iPad,
renders the coaching prompts on the server, and returns one validated coaching
turn. The device never receives the OpenAI key.

The server owns the `tutor-v13` system prompt, converts the structured device
request into model-facing Markdown, and validates the model's strict JSON
before returning it. Opening Help uses GPT-5.6 Sol with high reasoning. A
meaningful follow-up continues that Responses API chain with a compact update.
Move evaluation, inspected tactical replies, and Hint use low reasoning; simple
episode updates use none. Selecting a piece remains local and does not call the
server. The iPad validates the JSON again before showing it.

The model chooses one authoritative expected response for each turn. The app
then supplies the matching interaction mechanically: finding an endangered
piece includes **No piece needs help**; finding a safe capture includes **No
safe capture**; judging an unplayed move includes **Looks safe** and **Try
another move**; and deciding whether to keep a confirmed-safe move includes
**Play this move** and **Try another move**. The model can additionally request
Hint, but it cannot invent or mix the primary controls.

## Local development

For Simulator development, store the OpenAI key once in the macOS Keychain
service `ChessTutor-CoachingEval-OpenAI`, then run:

```bash
./scripts/run_hosted_coaching_dev.sh
```

The script creates an ignored `.venv` when needed, installs the pinned server
dependency, chooses and boots `iPad (A16)`, starts the server, builds the app,
and installs and launches it with hosted coaching configured. Leave the
terminal open while testing; Ctrl-C stops the server. To use another available
Simulator, pass its name as the only argument:

```bash
./scripts/run_hosted_coaching_dev.sh "ChessTutor Coaching Smoke"
```

For lower-level server work, copy `.env.example` into your preferred local
secret manager or export both variables in the shell. Use a long random value
for `CHESS_TUTOR_COACHING_ACCESS_TOKEN`, then run:

```bash
.venv/bin/python -m CoachingServer.local --host 127.0.0.1 --port 8787
```

Simple follow-ups default to `none` reasoning. Set
`CHESS_TUTOR_COACHING_FOLLOWUP_REASONING_EFFORT=low` to compare their quality
and latency locally. Tactical follow-ups still use low. The server accepts only
`low` or `none`; the app cannot choose the policy. No Fast service tier is used.

Check readiness with `GET http://127.0.0.1:8787/health`. Coaching requests use
`POST /v1/coaching-turn`, `Content-Type: application/json`, and
`Authorization: Bearer <access token>`.

Enable hosted mode in the app by setting
`CHESS_TUTOR_COACHING_BASE_URL`. For the simulator, use
`http://127.0.0.1:8787`. Supply `CHESS_TUTOR_COACHING_ACCESS_TOKEN` on the first
launch; the app stores it in the device Keychain. If the base URL is absent,
the existing local coach remains active. If hosted mode is configured but the
server or model fails, the app shows Retry and never substitutes local advice.

The base URL may be plain HTTP only in Debug builds and only for loopback or a
private LAN address. Production configuration requires HTTPS. Device requests
time out after 35 seconds.

## Reviewing one game

Application logs are one-line `coaching-log.v1` JSON objects. Each completed
request has exactly one `coaching_turn` record containing a compact board and
move summary, the validated advice shown by the app, provider metrics, outcome,
HTTP status, and elapsed time. It deliberately excludes credentials, prompts,
full rule arrays, provider/continuation IDs, reasoning, raw provider bodies, and
exception text.

In a hosted build, open About and choose **Copy Coaching Game ID**. Use that
value to filter retained server logs by `game_id`; within the result,
`episode_id` groups one opening of Help and `trace_id` identifies one HTTP
request. To extract completed turns from a local JSONL capture:

```bash
jq 'select(.event == "coaching_turn" and .game_id == "<copied-game-id>")' server.jsonl
```

New Game creates a new game ID. Closing and reopening Help keeps the game ID
but creates a new episode ID.

## Vercel

The committed `api/index.py` exposes the same WSGI app and `vercel.json` routes
both endpoints to it. The committed `.python-version` selects Python 3.12.
Configure `OPENAI_API_KEY` and
`CHESS_TUTOR_COACHING_ACCESS_TOKEN` as encrypted Vercel environment variables,
then deploy from the repository root:

```bash
vercel
vercel --prod
```

Set the app base URL to the resulting HTTPS origin. Do not commit either
secret. Vercel recognizes `app` as a WSGI entry point for a Python Function;
see the [Vercel Python runtime documentation](https://vercel.com/docs/functions/runtimes/python).

The endpoint is intentionally private and stateless. It keeps no in-process
conversation map. The app holds one opaque Responses API ID in memory while
Help is open and returns it with meaningful follow-ups; OpenAI stores the
linked responses needed for that chain. Closing Help or changing the committed
turn discards the ID. No reasoning trace is returned or logged.

## API boundary

`POST /v1/coaching-turn` accepts one strict `hosted-coaching-request.v3`
envelope containing game and Help-episode UUIDs, a
`model-coaching-neutral-request.v1` object, and an optional previous response
ID. The successful response contains only:

- request identity and position revision;
- the opaque continuation ID for this Help episode;
- the validated child-facing message, actions, and board focus; and
- bounded input, cached-input, output, reasoning, total-token, and latency
  counts.

The server uses the OpenAI [Responses API](https://developers.openai.com/api/docs/guides/structured-outputs)
with Structured Outputs and stored response chaining. It exposes only the
opaque response ID needed to continue the active episode, never raw provider
output or reasoning.

If a provider turn fails validation, the server still returns the same small
`invalidProviderResponse` error. Its local log includes only fixed diagnostic
categories such as `invalidJSON`, `unavailableAction`, or
`unavailableExpectedResponse`; rejected model text and identifiers are not
logged.

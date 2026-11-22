# Hosted coaching server

The private prototype accepts mechanically generated chess facts from the iPad,
renders the coaching prompts on the server, and returns one validated coaching
turn. The device never receives the OpenAI key.

The server owns the system prompt, converts the structured device request
into model-facing Markdown, and validates the model's strict JSON before
returning it. The family deployment and development launcher select the accepted
`CoachingServer/configs/production-v2.json` policy: GPT-6 Astra, low reasoning for all
requests, the pinned `tutor-v13-experience-v6.md` prompt, and grounded-v4 compiler. A
meaningful follow-up continues that Responses API chain with a compact update.
Selecting a piece remains local and does not call the
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

This convenience launcher uses the same configuration as family deployment at
`CoachingServer/configs/production-v2.json`:
GPT-6 Astra with low reasoning for initial and follow-up requests, the
`tutor-v13-experience-v6.md` prompt, stored conversation reuse, a 2,048-token output
cap, a 60-second timeout, and one attempt. The v13 compiler and response
contract are unchanged. Hosting this policy does not change the prompt or assert
new benchmark results; it makes the play-tested policy available off the Mac.
Only the timeout differs from the accepted `astra-experience-v7-low-model.json`
benchmark configuration, which remains frozen at 30 seconds. Historical latency
and failure-rate measurements therefore retain their original deadline.

An explicitly set `CHESS_TUTOR_COACHING_MODEL_CONFIG` takes precedence. The
launcher prints whether it selected the family deployment policy or an explicit override,
and passes that selection only to its server child, not the iPad. Empty or
invalid overrides fail configuration loading; they do not silently fall back
to Astra. To use the unchanged Sol policy locally:

```bash
CHESS_TUTOR_COACHING_MODEL_CONFIG=CoachingServer/configs/production-v1.json \
  ./scripts/run_hosted_coaching_dev.sh
```

The script creates an ignored `.venv` when needed, installs the pinned server
dependency, chooses and boots `iPad (A16)`, and opens Simulator (or Device Hub
on current Xcode). It then starts the server, builds the app, and installs and
launches it with hosted coaching configured. If neither simulator frontend
opens, it stops before starting the server or build. Leave the
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

Direct server invocation (without the deployment configuration) still loads
`CoachingServer/configs/production-v1.json` when the model override is unset;
the local launcher's Astra default does not apply to it. To compare a
different pinned model policy locally, set `CHESS_TUTOR_COACHING_MODEL_CONFIG`
to another repository-relative configuration path. The app cannot choose the
model policy. No Fast service tier is used.

Check readiness with `GET http://127.0.0.1:8787/health`. Coaching requests use
`POST /v1/coaching-turn`, `Content-Type: application/json`, and
`Authorization: Bearer <access token>`.

Enable hosted mode in the app by setting
`CHESS_TUTOR_COACHING_BASE_URL`. For the simulator, use
`http://127.0.0.1:8787`. Supply `CHESS_TUTOR_COACHING_ACCESS_TOKEN` on the first
launch; the app stores the URL and token together in the device Keychain. On
later Home-screen launches it restores that configuration without launch variables.
A never-configured app retains its existing local behavior. If hosted mode is configured but the
server or model fails, the app shows Retry and never substitutes local advice.

The base URL may be plain HTTP only in Debug builds and only for loopback or a
private LAN address. Production configuration requires HTTPS. Device requests
use a 70-second request timeout, leaving 10 seconds beyond the provider budget
for server work and returning either advice or a useful timeout response.
These are timeout limits, not artificial delays; successful replies return
immediately. The player can still close Help while a request is pending.

## Reviewing one game

Application logs are one-line `coaching-log.v1` JSON objects. Each completed
request has exactly one `coaching_turn` record containing a compact board and
move summary, the validated advice returned to the app, provider metrics, outcome,
HTTP status, and elapsed time. It deliberately excludes credentials, prompts,
full rule arrays, provider/continuation IDs, reasoning, raw provider bodies, and
exception text.

Provider failures also include a bounded `provider.transport` object in the
`coaching_turn` record (and `transport` on `provider_request_failed`): category,
HTTP status, phase, and `headers_ms` when response headers arrived.
`awaitingHeaders` includes connection setup **and** provider processing; it does
not establish which was slow. `readingBody` means headers arrived before the
failure. The metadata never contains exception text or provider content.
HTTP 504 and device network timeouts show a specific timeout message with
**Try again** / **Close help**, preserving the staged move and game.
See [the November 18 incident replay](reports/2026-11-18-coaching-timeout-investigation.md).

In a hosted build, open About and choose **Copy Coaching Game ID**. Use that
value to filter retained server logs by `game_id`; within the result,
`episode_id` groups one opening of Help and `trace_id` identifies one HTTP
request. To extract completed turns from a local JSONL capture:

```bash
jq 'select(.event == "coaching_turn" and .game_id == "<copied-game-id>")' server.jsonl
```

New Game creates a new game ID. Closing and reopening Help keeps the game ID
but creates a new episode ID.

### Client interaction timing

For rapid tapping or unexplained waiting, use **About → Share Diagnostics** on
the iPad. Server logs only describe requests that reached the server; the client
export also describes local-only input and requests combined before dispatch.
The existing bounded log retains approximately the most recent 512 KB (it trims
to roughly half that size when full), so export soon after the incident.

Client coaching records use the existing compact diagnostics format, category
`coaching`, and `schema_version=coaching-client.v1`. They include UTC event time,
monotonic `uptime_ms`, `event_sequence`, `game_id`, `episode_id`, and (for request
events) `request_id`. Sort events within a session by `event_sequence`; asynchronous
file writes need not finish in event order. Join server records using game,
episode, and request ID; wall-clock subtraction across devices is not a reliable
latency measurement.

| Event | Meaning |
| --- | --- |
| `board_input`, `interaction` | Tap/drag or resulting state change; disposition distinguishes local exploration, an answer, or a move destination. |
| `request_scheduled`, `request_coalesced` | First pending update, or replacement of an unsent update. Replaced request ID is included. |
| `request_dispatched` | Passed to the transport; not proof of server receipt. Includes final selection/move and wait measurements. |
| `request_completed`, `request_failed`, `request_cancelled` | Client operation outcome; only safe error categories are recorded. Client cancellation does not prove provider cancellation or a cost refund. |
| `response_applied`, `failure_applied`, `response_discarded` | Used for current advice or rejected as outdated. Applied means updated presentation state, not proof that the child read it. |

At dispatch, `coalesced_count` counts **unsent** updates replaced (not completed
or cancelled provider calls). `wait_ms` is time since the final relevant input;
`burst_ms` is time since the first input represented by that pending batch.
`debounce_wait_ms` is the configured quiet interval applied to this request.
`in_flight_wait_ms` is additional waiting for a previous call **beyond** that
quiet interval, avoiding double counting their overlap. `duration_ms` measures
the client operation; `interaction_to_advice_ms` includes the final input's
wait plus the operation when advice is applied. These, input timings and
`debounce_ms` let us compare request reduction against extra waiting and estimate
alternative intervals without making more model calls.

The current starting interval is 400 ms in `HostedCoachingTiming`. Opening Help
and explicit controls have no debounce delay. Changed piece answers and move
revisions use trailing-edge debounce; identical repeated answers and ordinary
selections stay local. One call runs at a time per GameSession, with only the
latest update waiting. Neither the board nor turn completion waits for coaching.
This is not a cross-device server rate limit. Prompts, advice text, credentials,
continuation IDs, full payloads, and arbitrary errors are excluded from these
client events. No additional network telemetry is sent.

## Vercel

The deployment manifest is `CoachingServer/deployment.json`. It identifies the
`chess-tutor-coaching` project in team `jasoncrawford`, the stable HTTPS origin,
the selected model, the explicit upload allowlist, and Keychain **service names**
(never their contents). With Vercel CLI installed/logged in and the existing
OpenAI key in Keychain, run:

```bash
python3 scripts/deploy_coaching_server.py --deploy
```

The command creates the dedicated project if absent, generates a separate
random family token in Keychain service `ChessTutor-HostedCoaching-Family`,
and sets missing production secrets through stdin. It never overwrites existing
cloud secrets. Missing local credentials for an already-configured server fail
closed; do not generate a replacement token without deliberately rotating the
server and re-provisioning every device. The OpenAI key stays server-side.

Only the minimal runtime and pinned resources are staged in a temporary directory.
No iPad assets, eval logs, local secrets, or build artifacts are uploaded. To
inspect the package without deploying: `python3 scripts/deploy_coaching_server.py
--package /tmp/chess-runtime-inspection` (destination must not exist).

`api/index.py` exposes the same Flask application. `vercel.json` routes requests,
pins the family model policy and sets a 90-second ceiling; `.python-version`
selects Python 3.12. The provider timeout is 60 seconds, with one attempt.
Deploy the server and rebuild/install the iPad app to apply the coordinated
60/70/90-second provider/client/platform limits. A server-only update leaves an
old iPad build's 35-second client cutoff in place; update the iPad before or
alongside the server. These limits provide headroom, not faster generation or
a guarantee against all timeouts.
See [Vercel's Python runtime](https://vercel.com/docs/functions/runtimes/python).

This team's existing Pro plan retains runtime logs for **one day by default**.
After a playtest, copy the game's ID from About and export/filter the project's
runtime logs promptly. There is no database or long-term trace archive, and this
setup does not add a paid logging upgrade. See [runtime log retention](https://vercel.com/docs/logs/runtime).

Use the Vercel dashboard's request details when collecting a full trace. The
installed Vercel CLI 50.19.1 historical log command prints only the first
application message in each request, even with `--expand`; that summary is not
a complete coaching trace. Do not mistake it for the full JSONL output described
above.

## Install on the family iPad

Connect and unlock the iPad, trust this Mac, and enable Developer Mode if iPadOS
asks for it. With the Xcode signing account already configured:

```bash
python3 scripts/install_hosted_coaching_device.py --list-devices
python3 scripts/install_hosted_coaching_device.py --device "<listed identifier or exact iPad name>"
```

The second command builds a signed Release app, installs it on that exact
physical iPad, and performs the setup launch. It reads the family token from
macOS Keychain and passes it through the device-launch process environment—not
arguments or a configuration file. No OpenAI key is installed on the iPad.
The installed app saves its HTTPS endpoint and family token as one device-only
Keychain item. Launch it from the Home screen, start a game, and try Help. The
Mac and this terminal are no longer needed. Chess works offline; the coach
requires internet. This remains a development-signed family build, not TestFlight
or App Store distribution; signing/provisioning expiration still applies.

Re-running setup updates the existing app without deleting games. It never
chooses a simulator or an ambiguous device name. The URL and token must be
re-provisioned together when changing servers. A different-origin URL alone
cannot borrow a saved token. Keychain failures show unavailable hosted help
rather than silently reverting to the old local coach.

The endpoint is intentionally private and stateless. It keeps no in-process
conversation map. The app holds one opaque Responses API ID in memory while
Help is open and returns it with meaningful follow-ups; OpenAI stores the
linked responses needed for that chain. Closing Help or changing the committed
turn discards the ID. No reasoning trace is returned or logged.

## API boundary

### Visual-coaching preview (v4)

The server routes `hosted-coaching-request.v3` to the unchanged production-v2
configuration and `hosted-coaching-request.v4` to visual-v4. The latter returns
`hosted-coaching-turn.v4` / `tutor-v14`: typed text/piece/square message runs and
at most one validated attack or move arrow. The new native client opts into v4;
installed v3 clients keep their existing plain-text response. Both paths share
authentication, limits, timing, correlation IDs and failure handling.

Visual-v4 preserves visual-v3's chess policy, changing only the commit control
name to “Play my move” and explaining that it commits the child's draft, not a
suggested alternative. The visual benchmark uses the same pinned revision.

To preview, run `./scripts/run_hosted_coaching_dev.sh "ChessTutor Coaching Smoke"`
from the visual-coaching checkout. No production deployment or family-device
installation is needed. `CHESS_TUTOR_COACHING_VISUAL_MODEL_CONFIG` overrides the
visual path independently of the legacy model configuration.

Roll out **server first**, verify both versions, then install the v4 client.
Do not install the new client against an old v3-only server. Each Help episode
starts without a continuation; continuation IDs are in-memory only and do not
survive app replacement. Close Help before changing a development endpoint.
V4 continuation handles are protocol-tagged (`resp_v4_…`); the router unwraps
them for the provider and resets cross-version continuations in either direction.
The tag is version isolation, not an authentication or authorization mechanism.
Keep the v3 route until all installed clients have been updated. Deploying or
installing the preview is a separate, explicitly authorized operation.

Linked words and Replay are local presentation actions; Play instead locally
cancels pending answer work. They do not generate provider calls. The board
and legal move guards remain playable while help is open.

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

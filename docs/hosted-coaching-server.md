# Hosted coaching server

The private prototype accepts mechanically generated chess facts from the iPad,
renders the coaching prompts on the server, and returns one validated coaching
turn. The device never receives the OpenAI key.

The server owns the `tutor-v6` system prompt, converts the structured device
request into the model-facing Markdown situation, calls GPT-5.6 Sol with high
reasoning, and validates the model's strict JSON before returning it. The iPad
validates the JSON again before showing it.

## Local development

Copy `.env.example` into your preferred local secret manager or export both
variables in the shell. Use a long random value for
`CHESS_TUTOR_COACHING_ACCESS_TOKEN`.

```bash
python3 -m CoachingServer.local --host 127.0.0.1 --port 8787
```

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

## Vercel

The committed `api/index.py` exposes the same WSGI app and `vercel.json` routes
both endpoints to it. Configure `OPENAI_API_KEY` and
`CHESS_TUTOR_COACHING_ACCESS_TOKEN` as encrypted Vercel environment variables,
then deploy from the repository root:

```bash
vercel
vercel --prod
```

Set the app base URL to the resulting HTTPS origin. Do not commit either
secret. Vercel recognizes `app` as a WSGI entry point for a Python Function;
see the [Vercel Python runtime documentation](https://vercel.com/docs/functions/runtimes/python).

The endpoint is intentionally private and stateless. It stores no child data,
conversation, provider response IDs, prompts, or reasoning.

## API boundary

`POST /v1/coaching-turn` accepts one strict `model-coaching-neutral-request.v1`
object. The successful response contains only:

- request identity and position revision;
- the validated child-facing message, actions, and board focus; and
- bounded token and latency counts.

The server uses the OpenAI [Responses API](https://developers.openai.com/api/docs/guides/structured-outputs)
with Structured Outputs and `store: false`. It does not expose provider IDs,
raw provider output, or reasoning.

# Hosted coaching server

The private prototype accepts mechanically generated chess facts from the iPad,
renders the coaching prompts on the server, and returns one validated coaching
turn. The device never receives the OpenAI key.

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

## Vercel

The committed `api/index.py` exposes the same WSGI app and `vercel.json` routes
both endpoints to it. Configure `OPENAI_API_KEY` and
`CHESS_TUTOR_COACHING_ACCESS_TOKEN` as encrypted Vercel environment variables,
then deploy normally. Do not commit either value.

The endpoint is intentionally private and stateless. It stores no child data,
conversation, provider response IDs, prompts, or reasoning.

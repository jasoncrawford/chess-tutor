# Hosted Coaching Structured Logs Design

## Goal

Make a production coaching game reconstructable from ordinary retained server logs without adding a database. A developer should be able to identify one game, collect all of its coaching requests, responses, timings, and failures, and parse the result mechanically.

## Scope

This change replaces the hosted-coaching application's mixed `key=value` and embedded-JSON messages with versioned JSON Lines. It adds stable client-generated identifiers for a game and a Help episode, preserves the existing per-request trace identifier, and exposes the current game identifier quietly in the existing About sheet.

This change does not add a database, durable trace API, third-party logging provider, in-app trace viewer, or production-log download script. Ordinary Vercel retention remains the production store. A later exporter may filter these records by `game_id` and render Markdown without changing the log schema.

## Identifier Lifetimes

- `game_id` is a lowercase canonical UUID created with a new `GameSession`. It remains stable for the entire game and changes when New Game starts another game.
- `episode_id` is a lowercase canonical UUID created when Help opens. It remains stable through selections, staged moves, response controls, retries, and every follow-up in that Help episode. Closing Help ends the episode; opening Help again creates another identifier.
- `trace_id` remains a server-generated identifier for one HTTP request.
- The client sends `gameID` and `episodeID` only in the hosted transport envelope. They are operational correlation metadata and never become part of the model-facing chess prompt.

The hosted request envelope advances from `hosted-coaching-request.v2` to `hosted-coaching-request.v3` and has exactly these fields:

```json
{
  "schemaVersion": "hosted-coaching-request.v3",
  "gameID": "f7f55ab1-93f8-4b46-9ff1-7460392cc4a9",
  "episodeID": "b678ec94-c259-4b2b-a2bd-61039fb634a4",
  "request": {},
  "previousResponseID": null
}
```

The server validates and normalizes both UUIDs before using them in logs. Invalid envelope metadata produces the existing `invalidRequest` response and never reaches the provider.

## Log Encoding

Every ChessTutor application log record is one UTF-8 JSON object on one physical line. The common fields are:

```json
{
  "schema_version": "coaching-log.v1",
  "timestamp": "2026-09-01T19:05:39.123Z",
  "level": "info",
  "event": "provider_request_started",
  "game_id": "f7f55ab1-93f8-4b46-9ff1-7460392cc4a9",
  "episode_id": "b678ec94-c259-4b2b-a2bd-61039fb634a4",
  "trace_id": "6158121713fb"
}
```

`schema_version`, `timestamp`, `level`, and `event` are always present. Correlation identifiers are included whenever that boundary has validated them. Field names use `snake_case`. JSON is emitted with no nonstandard values such as `NaN` or `Infinity`.

The local server suppresses Werkzeug's duplicate access messages. Launcher status messages may remain human-readable, but every `ChessTutor.CoachingServer` application record is valid JSONL. The Vercel entrypoint configures the same logger so production and development use the identical format.

## Event Model

Small lifecycle records remain useful while a slow request is in flight:

- `http_request_started`
- `request_compiled`
- `provider_request_started`
- `provider_request_completed`
- `provider_request_failed`
- `provider_response_validated`
- `provider_response_failed`
- `http_request_completed`

These records carry only bounded operational fields: identifiers, request kind, model, reasoning effort, timeouts, duration, token counts, status, outcome, and safe validation categories. After the envelope is validated, every lifecycle record includes all three identifiers.

Exactly one canonical `coaching_turn` record is emitted for every authenticated JSON request that enters coaching service processing. It is emitted for success, invalid request, provider timeout/unavailability, and invalid provider response. On success it has this shape:

```json
{
  "schema_version": "coaching-log.v1",
  "timestamp": "2026-09-01T19:05:39.123Z",
  "level": "info",
  "event": "coaching_turn",
  "game_id": "f7f55ab1-93f8-4b46-9ff1-7460392cc4a9",
  "episode_id": "b678ec94-c259-4b2b-a2bd-61039fb634a4",
  "trace_id": "6158121713fb",
  "request": {
    "kind": "follow_up",
    "request_id": "hosted-3",
    "prompt_version": "tutor-v13",
    "position_revision": 2,
    "fen": "rnbqkb1r/pppppppp/5n2/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 1 2",
    "moves": ["e4", "Nf6"],
    "side_to_move": "white",
    "status": "ongoing",
    "latest_interaction": {
      "sequence": 3,
      "kind": "pieceSelected",
      "references": ["piece:white:pawn:e4"]
    },
    "selected_piece": "piece:white:pawn:e4",
    "selected_square": "e4",
    "staged_move": null
  },
  "response": {
    "message": "Yes, that pawn is in danger. Try moving it forward to safety.",
    "actions": [],
    "focus": [{"type": "square", "square": "e5"}],
    "expects": "stageMove"
  },
  "provider": {
    "model": "gpt-5.6-sol",
    "reasoning_effort": "none",
    "input_tokens": 3753,
    "cached_input_tokens": 0,
    "output_tokens": 50,
    "reasoning_tokens": 0,
    "total_tokens": 3803,
    "latency_ms": 1904.097
  },
  "outcome": "success",
  "http_status": 200,
  "elapsed_ms": 1910.15
}
```

The request summary contains only the latest episode interaction rather than repeating all prior episode events. Earlier `coaching_turn` records already preserve those interactions in order. The full game move list and FEN are retained on each turn so any individual record remains understandable.

On failure, `response` is `null`, `outcome` is the existing stable public category, and `http_status` is the returned status. If compilation succeeded, the compact request and available provider metrics remain present. Invalid client data that cannot be safely summarized uses `request: null`. Raw exception and provider content never appear.

## Privacy And Safety

Logs must never contain:

- OpenAI API keys or app bearer tokens;
- system prompts or rendered user prompts;
- full mechanical request arrays such as pieces, legal moves, relationships, or tentative replies;
- provider response IDs or conversation continuation IDs;
- model reasoning traces;
- raw invalid provider responses, HTTP response bodies, or exception messages.

The validated tutor message and UI actions are intentionally logged because qualitative review is the purpose of the trace. Current ChessTutor coaching input contains chess state and fixed UI interactions, not free-form child text.

## Client Diagnostics

When hosted coaching is configured, the existing About sheet shows a `Copy Coaching Game ID` button. It copies the current `game_id` without adding anything to the main play surface. The identifier changes immediately after New Game. Non-hosted builds do not show the control.

## Verification

Tests must prove:

- identifier lifetime and lowercase UUID format;
- request-envelope v3 exact shape and server rejection of missing, extra, or malformed identifiers;
- identifiers never enter the model-facing prompt;
- every application log line parses as one JSON object with the v1 common fields;
- lifecycle correlation and exactly one canonical terminal record per success/failure path;
- exact compact success and failure projections;
- redaction of secrets, prompts, continuation/provider IDs, reasoning, raw bodies, and exception text;
- local Werkzeug access-log suppression and Vercel/local logger parity;
- About exposes the current hosted game ID without changing the main play UI;
- full CoachingServer, CoachingEval, iPad test, and standalone build gates remain green.

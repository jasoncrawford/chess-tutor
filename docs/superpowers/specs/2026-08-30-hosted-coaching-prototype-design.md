# Hosted Coaching Prototype Design

Date: 2026-08-30

## Goal

Replace the live coaching decision path, when explicitly configured, with a
stateless hosted GPT-5.6 Sol/high request while preserving the app's physical,
learner-led board interaction. The prototype runs against the same server
locally during development and can be deployed as a Vercel Python Function.

This is a private prototype. It has no offline fallback, account system,
conversation UI, database, analytics, or public rollout.

## Boundary

The iPad remains authoritative for chess mechanics and current interaction
state. It sends a versioned `ModelCoachingNeutralRequest` containing the FEN,
compact legal move history, pieces, legal moves, direct occupied-square
relationships, relevant replies to a tentative move, latest learner action,
episode history, and UI capabilities. It does not send child-facing advice or
an authored coaching conclusion.

The server validates this structured request, deterministically compiles the
`tutor-v6` user prompt, adds the server-owned `tutor-v6` system prompt and
request-specific response schema, calls GPT-5.6 Sol with high reasoning, and
strictly validates the returned turn. The server owns provider credentials,
model settings, prompt version, prompt rendering, and provider error handling.

The iPad independently validates the returned turn against the response
contract derived from its original request. It also requires the returned
request ID and position revision to match the current pending request. A stale
response can never replace newer coaching.

## Server

The server is a dependency-light Python package with a WSGI HTTP adapter:

- `POST /v1/coaching-turn` accepts one structured coaching request;
- `GET /health` reports readiness without contacting OpenAI;
- a local CLI runs the identical WSGI application with the standard library;
- `api/index.py` and `vercel.json` expose the same application on Vercel; and
- `.env.example` documents secret names without values.

The server reuses the existing hardened Responses API transport. Requests use
`store: false`, `gpt-5.6-sol`, high reasoning, 2,048 maximum output tokens, one
attempt, and no repair or retry. The OpenAI API key and one private prototype
bearer token come from environment variables. Bearer comparison is constant
time. Request bodies are bounded and malformed or unauthorized requests fail
before any provider call.

The successful response contains only:

- schema version;
- request ID and position revision;
- prompt/compiler version;
- validated `message`, `actions`, and `focus`; and
- bounded latency and token counts useful for development.

Provider response IDs, hidden reasoning, raw provider bodies, prompts, API
keys, and exception text are never returned or logged. Failures use small,
stable error codes and appropriate HTTP status codes.

## Deterministic compiler parity

The Python compiler implements the same chess-native Markdown contract as the
existing Swift evaluation compiler. Prompt formatting is not chess reasoning:
it renders the facts supplied by the device. A committed shared fixture binds
one complete structured request to exact Markdown, actions, and move focus;
both Swift and Python tests must pass it. The compiler preserves the current
compact history and scoped-reply behavior.

The response contract is factored out of Swift prompt rendering. The app can
derive allowed actions and move focus without rendering the user prompt, while
evaluation tests can still compile the full prompt locally.

## iPad runtime

Hosted coaching is opt-in through a development configuration. The base URL is
nonsecret configuration. The private access token is stored in Keychain and
may be bootstrapped from an Xcode launch environment variable for the private
prototype. Builds without hosted configuration retain the existing local mode;
once a session is configured as hosted, provider failure never falls back to
local coaching.

`GameSession` owns a small hosted coaching episode model alongside the existing
local `CoachingSession`. The hosted episode records only learner events needed
by `ModelCoachingNeutralRequestBuilder`: Help opened, own-piece selection,
opponent-piece inspection, move staged/replaced/removed, and action chosen.
Every meaningful interaction recalculates and queues a fresh request from the
current board state.

While a request is pending, the coaching panel remains visible with
“Thinking…”. A newer interaction changes the task identity and cancels the old
URLSession task; request ID, position revision, tentative move, and pending ID
checks are the correctness boundary even if transport cancellation races.

A valid model response becomes one atomic presentation:

- `message` is the primary coaching copy;
- `hint` requests another hosted turn with an action event;
- `playMove` uses the existing Done/commit path;
- `tryAnotherMove` removes the tentative move and immediately recalculates;
- Close Help is always appended locally; and
- square/move focus maps into the existing overlay.

Hosted coaching never consumes ordinary learner board interaction as a rigid
question-answer state machine. The child can select, inspect, stage, replace,
or remove a move at any time, and the next request follows the newest state.

On network, authentication, provider, or validation failure, the panel remains
active and shows a short unavailable message with Try Again and Close Help.

## Testing

Server tests cover authentication, body bounds, strict request parsing, exact
prompt compilation, exact OpenAI settings, response validation, redacted
errors, health, local WSGI routing, and Vercel entrypoint importability. No test
contacts OpenAI.

Swift tests cover request encoding, compiler/response-contract parity, hosted
transport decoding, Keychain abstraction behavior, thinking/success/failure
presentations, action mapping, interaction event derivation, cancellation, and
stale-response rejection. Existing local coaching tests remain green.

Integration UAT uses a fake local server first, then a bounded real local
server smoke with the existing OpenAI project key. It exercises Help, a move
made while thinking, replacement of a tentative move, Try Again, Play This
Move, board focus, and Close Help at Large and an accessibility text size.

## Deployment

Infrastructure configuration is committed. Local development uses one command
and environment variables. Vercel deployment uses the same WSGI application;
only secret values are configured outside the repository. No deployment is
performed automatically in this task.

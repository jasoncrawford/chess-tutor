# Hosted Coaching Timing Diagnostics

## Goal

Make a slow or failed hosted coaching request diagnosable from the local server
terminal without exposing child data or credentials.

## Design

Replace the hand-written WSGI request adapter with Flask/Werkzeug. The
framework will own routing, body streaming, `Content-Length` handling, maximum
body enforcement, and HTTP response construction. ChessTutor code will retain
only bearer authentication, strict JSON decoding, service invocation, and the
existing stable error mapping. The local launcher will maintain an ignored
project virtual environment from the pinned `requirements.txt` automatically.

The Flask boundary will log when an authenticated, valid coaching request enters
and when its response finishes, including the public status category and elapsed
milliseconds. The service boundary will log when prompt compilation finishes,
when the OpenAI call starts, when it completes or fails, and when the returned
turn passes validation.

Logs may include a generated per-request correlation identifier, model name,
reasoning effort, timeout, event name, outcome category, and elapsed duration.
They must never include the authorization token, OpenAI key, board state, move
history, rendered prompts, provider response text, provider identifiers, or
exception bodies.

Local development will enable concise INFO logs automatically. Tests will use a
recording log handler and a deterministic clock to verify event order, timing,
failure categories, and redaction. The existing API response and coaching
behavior will not change. In addition to Flask's in-memory test client, one test
will start a real Werkzeug server on loopback and send a real HTTP request. It
must prove that the server begins processing without waiting for the client to
close its request connection.

## Verification

After unit verification, run the launcher and make one real coaching request.
The terminal must make it possible to distinguish app transport timeout, server
validation failure, and OpenAI latency from timestamps alone.

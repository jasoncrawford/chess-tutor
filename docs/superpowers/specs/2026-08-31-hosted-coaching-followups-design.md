# Hosted Coaching Follow-ups

## Goal

Make hosted coaching feel responsive after Help opens, and make its advice teach the child how to think instead of prescribing moves.

## Interaction policy

- Opening Help starts one coaching episode and one hosted Responses API chain.
- The initial turn uses `gpt-5.6-sol` with `high` reasoning.
- Selecting or inspecting a piece is local UI exploration. It does not request new advice and does not replace the visible coaching turn.
- Staging, replacing, or removing a move; choosing Hint; and retrying after a failure are meaningful follow-ups. They request one new turn using the last completed response ID and `low` reasoning by default.
- The follow-up reasoning effort is server-owned and may be set to `none` for a local latency comparison. The app cannot choose it. Fast service tier is not used.
- Closing Help, committing the turn, changing to another authoritative position, or starting a new game destroys the episode and its response ID.
- If a meaningful interaction supersedes a request before it completes, the newest authoritative state wins. It may continue from the last completed response; stale completions never update the UI.

## Device/server boundary

The device continues to derive the neutral request mechanically from game state and chess rules. It sends a versioned HTTP envelope containing that request and the optional opaque prior response ID. The server remains stateless: it validates the envelope, compiles the deterministic prompt, owns the system prompt/model/reasoning policy, calls OpenAI, and returns the next opaque response ID with the validated UI turn.

The initial provider request is stored so OpenAI can resolve `previous_response_id`. Follow-ups send the same system instructions again because Responses API instructions are not inherited through `previous_response_id`. The response ID is held only in app memory for the active Help episode.

## Prompt policy

`tutor-v7` keeps the existing strict JSON/UI contract and adds least-help-first coaching:

- Begin with one question or clue about what to notice.
- Do not name a particular move or destination during ordinary Help.
- A precise move is allowed only after the child explicitly requests Hint, or when discussing a move the child already staged.
- When a move is staged, help the child judge its idea or safety and decide; do not prescribe a competing move unless Hint was requested.
- Avoid directive phrases such as “you should move,” “play,” or “tap” during ordinary coaching.

## Observability and safety

Server logs identify initial versus follow-up, reasoning effort, provider latency, and outcome without logging chess content or response IDs. Response metrics include cached input tokens so local tests can distinguish reduced reasoning from caching effects. Request/response bodies stay bounded, strict, duplicate-key rejecting, and authenticated. No provider error body or reasoning trace is persisted.

## Success criteria

- Selecting pieces produces zero HTTP requests and leaves the current advice visible.
- Each meaningful follow-up produces exactly one HTTP request.
- Initial requests use high reasoning; continued requests use low by default and carry `previous_response_id`.
- Stale or cross-episode response IDs cannot be applied.
- A short live flow shows lower follow-up latency without Fast mode and produces coaching that invites thinking rather than immediately naming a move.
- All existing server, evaluator, and iPad tests remain green.

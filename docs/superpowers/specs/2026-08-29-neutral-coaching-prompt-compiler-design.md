# Neutral Coaching Prompt Compiler Design

Date: 2026-08-29

## Goal

Evaluate model-authored chess coaching using the same deterministic input boundary the app could ship. The app supplies game state, interaction history, chess-rule facts, and permitted UI references. The model alone decides what matters, how Safe/Take/Wake applies, and what to teach.

The immediate deliverable is a compiler plus human-readable prompt examples. No prompt produced by this work may be sent to a model until the user approves the examples.

## Non-goals

- Do not integrate a model into the live app.
- Do not run a model matrix, hidden set, device benchmark, or quality evaluation.
- Do not hand-author per-case user messages.
- Do not include a semantic oracle, expected teaching intent, preferred move, deterministic coaching stage, or desired answer in a request.
- Do not require the model to calculate move legality from FEN alone.

## Ownership Boundary

### Deterministic app responsibilities

- Preserve the authoritative position and side to move.
- Encode the complete committed move history in compact SAN.
- Encode the current coaching episode as an ordered event stream.
- Compute objective chess-rule facts with the existing rules engine.
- Describe legal UI capabilities and stable focus references.
- Render the same input state to byte-identical Markdown.
- Validate returned JSON, action names, and focus references.

### Model responsibilities

- Choose which fact deserves attention now.
- Decide whether Safe, Take, Wake, or another framing is useful.
- Decide whether to invite discovery, give a clue, explain, confirm, or warn.
- Choose an optional permitted coaching action and focus references.
- Write one coherent child-facing coaching message.

## Input Contract

The compiler accepts only production-shaped values:

- current `GameState`;
- committed move history;
- optional tentative move;
- ordered current-episode learner and tutor events;
- current selection or inspected reply;
- mechanically enumerated UI capabilities.

The compiler does not accept prose, a semantic oracle, a teaching intent, a preferred move, a stage such as Safe/Take/Wake, or authored copy.

## Deterministic Markdown Form

Every request uses the same ordered sections.

### Game

- Side to move and game status.
- Current FEN.
- Complete committed history in SAN on one line.
- Tentative move, if present, explicitly separated from committed history.

### Current help episode

- Ordered compact events such as `Help opened`, `white knight f3 tapped`, or `Nf3-g5 staged`.
- Previous model messages from the current episode may be included verbatim once the runtime owns them; prompt examples use only events available from deterministic fixtures.

### Rule facts

Always include:

- check, checkmate, and stalemate status;
- attacks on occupied pieces;
- legal captures, checking moves, and mating moves for the side to move.

Add facts by interaction scope, using a fixed rule independent of pedagogical outcome:

- selected piece: its legal moves, captures, attackers, and defenders;
- tentative move: legality and direct board consequences, then the opponent's legal captures and checks;
- inspected reply: the move and all attack, capture, check, and defense relationships directly involving it.

Do not include the complete empty-square control map, all quiet moves for every unselected piece, or every reply to every possible move.

Rule facts are neutral. The compiler must not use terms such as `best`, `useful`, `important`, `purpose`, `needs help`, `looks safe`, or `what to teach`. A fact may state that a move is legal, gives check, captures a piece, attacks a piece, defends a piece, or produces checkmate because those are rule-engine results.

### Available interactions

- Board gestures currently accepted by the app.
- Coaching actions the model may choose from.
- Stable focus references the model may return.
- App-owned chrome such as closing Help is not model-authored unless it is genuinely part of the coaching choice.

## Output Contract

The model returns a small JSON object:

```json
{
  "message": "One short child-facing coaching turn.",
  "actions": [],
  "focus": []
}
```

The model may choose only actions and focus references enumerated in the request. The validator rejects unknown fields, unknown references, duplicate references, malformed JSON, and copy outside the child-facing bounds. Mechanical validation must not rewrite an answer or repair its chess meaning.

## Size Boundary

Move history uses SAN because it is compact enough to include in full for ordinary games. The current coaching episode uses a compact event stream.

The initial target is 500–1,500 input tokens, with a hard preflight budget of 2,500 tokens. An over-budget request is a compiler-design failure. The compiler must not silently truncate facts, hand-edit a case, or insert a coaching conclusion to compensate.

## Prompt-example Gate

Before inference, generate deterministic prompt examples covering at least:

1. quiet initial Help;
2. an attacked piece with no selection;
3. a selected piece;
4. a tentative quiet move that replaced an earlier move;
5. a tentative move with an immediate tactical reply;
6. a child inspecting an opponent reply;
7. a move answering check;
8. a longer committed game history.

For each example, preserve the structured source snapshot, compiled Markdown, token count, and SHA-256. The user reviews the exact system prompt and compiled user messages. No inference starts until the user explicitly approves them.

## Tests

- The same snapshot compiles to byte-identical Markdown and hashes.
- Every line of rule evidence is reproducible from the rules engine.
- SAN history round-trips to the expected current state.
- Interaction scoping is category-complete and independent of the expected lesson.
- Fixtures cannot supply prose, teaching intent, preferred moves, Safe/Take/Wake stages, or semantic oracles.
- A leakage audit rejects conclusion-bearing compiler vocabulary.
- The compiler stays within the token budget across the visible corpus.
- Examples contain no hidden-set identifiers or expected responses.

## Iteration Sequence

1. Implement and test only the deterministic compiler.
2. Generate the eight prompt examples without invoking a model.
3. Review and revise the compiler and system prompt with the user.
4. Freeze the approved compiler and prompt hashes.
5. Run a few serial examples on the largest available local model.
6. Iterate on model-facing instructions only if the deterministic input boundary remains unchanged.
7. Compare smaller models only after one model produces consistently useful coaching.

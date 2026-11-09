# Chess-Native Coaching Prompt Design

Date: 2026-08-30

## Goal

Replace the alias-heavy neutral prompt with a compact chess-native request that trusts the model's chess knowledge while retaining deterministic legality, UI validation, and a child-appropriate response boundary.

This revision remains a prompt-review experiment. It does not integrate a model into the app and must not invoke model completion, inference, scoring, or hidden-set work.

## Versioning

Create a new `tutor-v6` prompt/compiler/output contract beside `tutor-v5`. Preserve v5 code, prompts, tests, and generated evidence so prior iterations remain reproducible.

## System message

The system message retains the approved tutor role and plain beginner routine. It adds an explicit child-language rule:

- use ordinary spoken language and full piece names;
- do not put SAN, UCI, capture symbols, check symbols, or castling notation in `message`;
- mention a square such as `c3` only when genuinely needed to identify a location;
- rely on structured focus for precise visual references.

## User message

Every request uses four concise sections.

### Position

- side to move and game status;
- authoritative FEN;
- complete committed SAN history on one line;
- tentative move, separately, in compact chess notation when present.

### Latest interaction

Render only the latest production interaction and the minimum context required to understand it, in deterministic chess language. Examples include `Help opened`, `White selected the knight on f3`, `White tentatively played Nc3`, and `The child tapped the black queen on h4`.

Do not replay the whole episode unless an earlier event is necessary to explain a replacement. For a replacement, include the old and current tentative moves once.

### Relevant legal facts

Trust the model to read the position and use chess knowledge. The rules engine supplies only facts that are necessary to make the current UI interaction mechanically reliable:

- always state whether the side to move is in check, checkmate, or stalemate;
- no selection: do not dump attacks, captures, checking moves, mating moves, or relationships;
- selected piece: list that piece's legal moves once;
- tentative move: state whether it is legal and list only the opponent's immediate replies that capture, check, or mate;
- inspected opponent piece after a tentative move: list only matching immediate replies from that piece;
- do not enumerate downstream attack/defense relationships after each reply;
- do not repeat a fact in a focus-reference list.

This is fixed interaction scoping, not a teaching decision. The model still decides what matters and how to coach it.

### Available UI response

Actions use their semantic names directly: `hint`, `playMove`, and `tryAnotherMove`, limited to those currently available.

The model may focus:

- any board square, represented by its coordinate;
- only move paths mechanically enumerated for the current interaction, represented by their `from` and `to` squares.

The prompt lists allowable move paths once when any exist. It does not assign numbered aliases to pieces, moves, relationships, or actions.

## Output contract

The model returns exactly:

```json
{
  "message": "One short child-facing utterance.",
  "actions": ["playMove"],
  "focus": [
    {"type": "square", "square": "h4"},
    {"type": "move", "from": "h4", "to": "f2"}
  ]
}
```

`message` remains at most 18 words. `actions` contains at most three unique currently available semantic action names. `focus` contains at most four unique objects.

A square focus contains exactly `type` and `square`. A move focus contains exactly `type`, `from`, and `to`. Square names must be on the board. Move focus must match one of the mechanically enumerated allowable move paths in the request. Unknown fields, malformed objects, unavailable actions, unavailable moves, duplicates, and excessive counts are rejected without semantic repair.

## Prompt examples

Regenerate the same eight production-history situations:

1. quiet new-game Help;
2. attacked piece without selection;
3. selected attacked piece;
4. replaced tentative move;
5. tentative move with a tactical reply;
6. inspected opponent piece after a tentative move;
7. tentative response to check;
8. longer committed history.

Example 06 should shrink substantially because it lists the queen's matching immediate replies once and omits 30 downstream relationships and their duplicate focus labels.

## Verification and review gate

- Assert no `relationship-N`, `move-N`, `piece-N`, or `action-N` aliases appear in v6 prompts.
- Assert complete committed history and separate tentative moves remain byte-exact.
- Assert the semantic response decoder rejects chess notation in `message` while allowing an occasional standalone square coordinate.
- Assert focus squares and moves validate against the v6 compilation.
- Generate exactly eight immutable prompts using template rendering and tokenization only.
- Keep every prompt below 2,500 tokens and report the preferred 500–1,500 range separately.
- Stop for user review before any model completion or inference.

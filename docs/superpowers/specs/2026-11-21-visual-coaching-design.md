# Visual coaching

## November 22 play-test corrections

The user requested a more explicit board-answer mode after trying the initial
preview. This supersedes the quiet-border/no-banner requirement below: reserve
space above the board for a readable instruction, without covering any square.
Pending answers use the full-size thinking animation and “Checking your answer…”.
The cryptic replay icon becomes a named “Show arrow” control by the explanation.

Inline references are now native text links, not 44-point-tall button boxes.
Their phrases wrap naturally; miniature pieces are omitted from prose. Native
link accessibility and named highlight actions retain access to board targets.
The commit action says “Play my move” and still commits only the staged move,
never a suggested alternative. The pinned visual-v4 prompt mirrors that label;
it does not change chess-coaching policy. See the [feedback plan](../plans/2026-11-22-visual-coaching-feedback.md).

## Intent and approved direction

Make the coach easier for a beginning reader to understand: short explanations
can point to the board, suggested moves have directional arrows, and a question
clearly invites a board answer without trapping the child in a lesson.

The user approved the simplified interactive mockup on November 21. Keep the
existing Coach heading, bulb, warm panel, physical board, and modest body type.
Do not add mode headings such as “Your turn to look” or “Look at this”, a pill
above the board, or repeated instructions below it. The mockup's review tabs and
design rationale are not part of the app.

## Approaches

- **Chosen:** structured text references and board gestures, rendered and replayed
  locally. The model chooses what matters; deterministic code validates what it
  points at. This supports the approved tappable wording without guessing from prose.
- Parsing square names or piece names out of prose is brittle, especially with
  two knights and an editable draft. Do not use it.
- A separate diagram or permanent tutorial overlay would divide attention and
  interrupt the playable board. Do not add it.

## Experience

### Words that point

“This rook is attacking your knight.” can contain two underlined, plum-colored
links, each with the matching small piece illustration. Tapping a phrase briefly
highlights that piece on the displayed board; tapping again replays it. A square
reference such as “here” highlights the square instead. References are optional:
plain text is correct when a visual adds nothing.

Use one coherent explanation, not several layers of instructional copy. Prefer
linked descriptions to a chain of coordinates, but permit a coordinate when it
genuinely makes the sentence clearer. The complete readable message remains at
most 256 Unicode code points, normally one or two short sentences. Preserve the
existing calm tone and learner agency.

### Board gestures

- A threat is a high-contrast arrow from attacker toward target, not two circles.
- A proposed move is a high-contrast plum arrow from the piece toward the
  destination. Ordinary knight moves use an L-shaped path. Other moves use a
  direct path. The head stops short of obscuring a piece.
- One relationship/move arrow at a time, with at most two linked references.
  Keep unrelated coverage quiet while coaching; retain check/illegal-move warnings.
- Animate the introduction briefly once; allow local replay. Reduced Motion
  shows the same static information. Color is reinforced by shape and direction.
- A replacement draft is not a second chess move: validate against the committed
  board, but point from the staged piece's displayed location to its alternative
  destination. Use a direct relocation arrow, not a misleading knight L.
- Replay/reference taps never select a chess piece, alter the draft, mutate the
  coaching conversation, or start a network request.

### Answering and moving

The coach's question supplies the essential action, e.g. “Which knight is the
rook attacking? Tap it to show me.” A quiet plum board-edge treatment accompanies
piece-answer mode; no extra label or pill. Accessibility exposes that taps answer
the coach. A tap gives immediate neutral selection feedback, not an unverified
“correct” signal. The reply then acknowledges or corrects it as today.

The question and answer affordance remain coherent while a board answer is
pending. Further answer taps may replace the pending answer under the debounce
policy, not suddenly become normal moves because a request started.

Dragging a movable piece still starts a tentative move and supersedes the
question. Add a local “Play instead” action during identification. It switches
to ordinary tap/drag play without an API call, clears question-specific visual
state and pending answer work, and substitutes a short local invitation
(“Try a move on the board.”). Do not leave a tap-to-answer question visible after
its interaction is disabled. The next actual move is the next coaching event.
Close help remains available. Empty-square taps do not submit invented answers.

## Response contract and ownership — implementation decisions

Introduce `chess-native-v14` / `tutor-v14`, with hosted request/response envelopes
`hosted-coaching-request.v4` / `hosted-coaching-turn.v4`. Keep v3/v13 unchanged for
the installed app. The new client opts into v4; the server routes each version
to its pinned configuration. Never return a v4 payload to a v3 client.

The v14 model turn has exactly `message`, `actions`, `visuals`, and `expects`.
`message` is an ordered array of 1–9 typed runs, not Markdown or character offsets:

```json
{
  "message": [
    {"type": "piece", "text": "This rook", "square": "c8"},
    {"type": "text", "text": " is attacking "},
    {"type": "piece", "text": "your knight", "square": "c3"},
    {"type": "text", "text": ". Where could it go to get out of the rook's path?"}
  ],
  "actions": ["hint"],
  "visuals": [{"type": "attack", "from": "c8", "to": "c3"}],
  "expects": "stageMove"
}
```

Runs are `text(text)`, `piece(text, square)`, or `square(text, square)`.
Visuals are `attack(from, to)` or `move(from, to)`; zero or one. No arbitrary URLs,
colors, drawings, coordinates in pixels, IDs for relationship lookup, or HTML.
Actions and expected responses retain v13 semantics. Joining run text gives the
canonical plain message used by logs, episode history, accessibility and grading.
There is no second model-written plain-text copy to get out of sync.

Piece/square references address the displayed board, never an imagined future
position. Attack arrows must match supplied occupied-square attack relationships
on that same board; geometric attack does not assert a profitable/legal capture.
Move arrows use an allowed, legal committed-position move, with client-side
projection of its source for a draft revision. Retain canonical endpoints in
logs so rendering cannot change the meaning of the move.

Both Python and Swift validate bounds, exact fields, occupied piece references,
allowed moves, directed relationships, and discovery restrictions. Do not add a
chess engine or duplicate chess rules in the server. The request already carries
board pieces, legal moves and occupied-square relationships mechanically produced
by the app. Reuse them, including `tentativePosition` when a draft is displayed.

Ordinary piece-finding questions have no references or visual gestures. After an
explicit Hint, a question may link one source clue: an opponent piece for
`findEndangeredPiece`, or a learner piece for `findSafeCapture`. No square links
or arrows in either discovery state. This allows “Start with this rook” without
circling the answer; prompt and grading still check whether a clue gives too much
away. A full reveal must change to an explanation/move invitation, not continue
asking the already-answered question.

Invalid model responses follow the existing bounded failure path; no silent
repair or retry loops. A valid response rendered stale by subsequent interaction
must not display old references/arrows. Keep the app's request/revision checks;
clear local replay state on turn replacement, board/draft change, game switch,
close-help, and cancellation. Replay expiry must not clear a newer replay.

GameSession/HostedCoachingSession own transient focus, answer routing, and play
override. SwiftUI only lays out text and renders presentation state. Use existing
piece assets and BoardGuidanceGeometry. Supply real accessibility links/buttons
and meaningful board hints in both portrait and landscape; do not rely solely on
the visual board border. Maintain 44-point link hit areas, Dynamic Type wrapping,
VoiceOver order and the current centered thinking animation.

## Evaluation and rollout

Add a dedicated repeatable visual-coaching suite generated from native board
states, not hand-authored model prompts. Include wrong-piece and reversed-arrow
negative controls; questions that must not reveal the answer; two same-kind
pieces; a requested hint; an editable staged knight; an empty square reference;
and the opening edge-pawn tradeoff. Grade exact structured output as well as
flattened text. Reward useful, concise grounding, not maximum number of links.

Hard checks catch schema/reference/geometry failures. Judge criteria cover
readability, relevance, agency, non-spoiling hints, and a question that matches the
available action. Add sensitivity controls demonstrating the grader catches these
failures. Preserve existing quality suites, raw outputs, costs, token counts and
latency. Report incompatible baseline capabilities honestly rather than marking
old v13 output as an invalid v14 response.

Implementation is one feature branch based on main. PR #27 (debounce/client logs)
was still open when this design was written; do not cherry-pick or stack it. Once
it is merged by the user, rebase and run integration tests against its scheduling
and diagnostic behavior before rollout. Do not merge it without authorization.

Keep the old server path available for the family iPad. Verify locally and on
Coaching Smoke first; production deployment and physical-device installation are
separate rollout actions. No provider/model change, offline coach, audio, lesson
hub, database, or broader UI redesign is included. Use the currently pinned
model/reasoning configuration for the visual candidate.

Paid validation must use the existing durable shared budget journal and a newly
agreed cap; previous experiment caps are not an evergreen allowance. No paid
calls are needed to implement or test the mechanics with fixtures.

## Acceptance

- Linked words and Replay cause zero provider calls and zero chess-state changes.
- Arrows point correctly at all four board angles and after a draft revision.
- Questions never visually identify their answer; hinted source clues are bounded.
- A tap answers immediately, a drag supersedes the question, and Play instead
  restores ordinary interaction locally without losing a draft or accepting a
  late answer response.
- Sparse UI matches the approved simplified mockup; accessibility remains usable.
- v3 clients still work; v4 is strict and versioned; eval artifacts include visuals.
- Relevant native/server/eval tests pass and the new quality probe is repeatable.

# On-Demand Coaching V1 Design

## Purpose

Help a young beginner who looks at the board and does not know what to do. When the player asks for help, the app should guide them through noticing an urgent problem, finding a useful capture, or choosing a purposeful move. The child should do the chess thinking and make the board actions; the tutor should provide structure, progressively stronger clues, and a reliable check of the tentative move.

This is the first implementation of intelligent advice in live play. It deliberately covers high-confidence beginner situations with local deterministic analysis. It establishes source-independent coaching and interaction boundaries so later evaluation, insights, and explanations can come from a chess engine, a language model, or another implementation without replacing the board experience.

## Goals

- Add an explicit **Help me** action during a local player’s turn.
- Keep coaching inside the playable board experience rather than opening a lesson or analysis mode.
- Let the child answer primarily by tapping pieces and staging moves.
- Teach a compact decision habit: Safe–Take–Wake.
- Adapt the routine when an early opening position makes the first two checks trivial.
- Accept multiple safe, purposeful moves rather than require an engine-best move.
- Use existing threat, defense, movement, and tentative-position guidance as training wheels.
- Keep chess rules in Core, coaching state outside SwiftUI, and user-facing flow in the session/model layer.
- Run entirely on-device with authored language and no engine or online service.
- Establish narrow seams through which evaluation, insight generation, and explanation can later be replaced.

## Non-goals

- No Stockfish or other runtime chess engine.
- No online language model, generated text, voice conversation, or free-text input.
- No proactive coaching, automatic move grading, or blunder alerts outside an active Help episode.
- No post-game review, overall position evaluation, numeric score, or “best move” display.
- No learner profile, mastery tracking, curriculum, or adaptive fading of training wheels.
- No named opening repertoire, opening-book lookup, or memorized opening lines.
- No deep combinations, sacrifices, advanced tactics, or subtle positional plans.
- No middlegame or endgame curriculum beyond generic safe activity; phase-specific expansion is future work.
- No settings for coach strength, personality, hint depth, or language style.
- No redesign of the existing board guidance grammar.

## Chosen Approach

V1 uses a local coaching advisor composed of:

1. a shallow material-aware position evaluator;
2. authored semantic insight detectors;
3. a deterministic teaching policy;
4. authored explanation templates;
5. a parameterized coaching session that emits generic board tasks.

This is preferred to two alternatives:

- A rigid collection of Safe–Take–Wake screens would be simpler initially, but would confuse interaction state with chess judgment and make contextual opening advice awkward.
- An engine- or language-model-led tutor could cover more positions, but would add runtime, reliability, licensing, latency, and validation concerns before the product interaction has been proven.

The v1 evaluator is intentionally replaceable. The board and teaching interaction do not consume piece-value calculations, engine scores, prompts, or provider-specific output directly.

## Product Promise

V1 helps a beginner:

- notice check and clear material danger;
- find straightforward profitable captures;
- develop a piece or make another simple safe, purposeful move;
- inspect one immediate opponent reply before committing.

It does not promise expert judgment in every legal position. When the advisor lacks a high-confidence insight, it should become less specific and help the child check a move of their own rather than invent advice.

## Core Coaching Policy

### An acceptable move

A coached move is acceptable when it:

1. is legal to commit;
2. handles a current urgent problem, when one can be handled;
3. does not allow immediate checkmate;
4. does not introduce a clear material loss under the v1 material model;
5. has a recognized purpose, or was made in the low-confidence fallback flow.

If several moves satisfy these conditions, all are accepted. The tutor never reveals that one accepted move ranks slightly above another.

Once an acceptable move is found, the tutor names its purpose and ends the search. **Keep looking** returns to normal play with the tentative move preserved. **Done** remains the child’s action.

### Safe–Take–Wake is a priority, not a script

The advisor always checks the priorities in this order:

1. **Safe:** Is there an urgent problem?
2. **Take:** Is there a clear immediate gain?
3. **Wake:** What safe move can give a piece a useful job?

The child does not have to complete three ceremonial steps. The app compresses a step only when there is literally nothing to inspect:

- If the opponent has no legal capture and the learner is not in check, Safe is reported clear without asking for an answer.
- If the learner has no legal capture and no mate in one, Take is reported clear without asking for an answer.
- Otherwise the app asks the scan question even when the correct answer is **I don’t see one**. This builds the habit of checking a nontrivial board.

On White’s first move, both Safe and Take are structurally empty, so Help proceeds directly to opening-oriented Wake advice.

### Tutor ownership

The tutor may select an instructional focus, judge answers, and emphasize relevant board relationships. It never moves a piece, commits a move, or silently replaces the child’s tentative choice.

## V1 Evaluation Model

### Piece values

Use conventional beginner values:

| Piece | Value |
| --- | ---: |
| Pawn | 1 |
| Knight | 3 |
| Bishop | 3 |
| Rook | 5 |
| Queen | 9 |

The king has no material value. Check, checkmate, and legality are handled by Core rules rather than material arithmetic.

### One-recapture estimate

V1 estimates a capture using the target’s value and at most one immediate legal recapture on the capture square.

For an opponent capture of one of the learner’s pieces:

```text
estimated learner loss = captured piece value
                       - recaptured attacker value, if an immediate legal recapture exists
```

For a learner capture:

```text
estimated learner gain = captured piece value
                       - capturing piece value, if the opponent has an immediate legal recapture
```

When several legal recaptures exist, use the reply that produces the best material result for the replying side. The evaluator does not continue a full exchange sequence in v1.

This estimate is not a claim that a complete combination has been solved. Insights derived from it remain high-confidence only for clear, shallow outcomes.

### Urgent material danger

A threatened learner piece needs help when an opponent has a legal capture with an estimated learner loss of at least 2 points.

Consequences:

- losing an undefended knight, bishop, rook, or queen is urgent;
- a pawn taking a defended bishop is still urgent because the estimated net loss is 2;
- an attacked pawn whose capture would lose the attacker may be marked by ambient guidance but is not urgent coaching danger;
- losing a lone pawn is not an urgent Safe problem in v1.

Check is always urgent, independent of material value.

If several urgent problems exist, rank them by:

1. check;
2. greatest estimated material loss;
3. greatest threatened-piece value;
4. stable board order for deterministic ties.

Any urgent piece is a correct answer to the initial Safe scan. A final coached move must resolve all avoidable higher-priority urgent problems. If no legal move can reduce every urgent loss below the threshold, accept moves that achieve the best available worst-case material result and explain that the move saves what it can.

### Profitable capture

A Take opportunity is:

- a legal learner capture with an estimated gain of at least 1 point;
- a legal capture that resolves an urgent Safe problem without creating a greater urgent loss;
- any legal mate-in-one move, whether or not it captures.

A candidate is excluded when the opponent has an immediate mate or a clearer material reply that leaves the learner at least 2 points worse than before the move. Equal exchanges are not presented as “winning something,” although they may be accepted when they resolve Safe.

### Opponent reply check

After a tentative move, evaluate every legal opponent reply for:

- checkmate in one;
- check;
- a profitable capture producing at least 2 points of estimated loss.

Allowing check is something to notice, not automatically a reason to reject the learner’s move. Allowing immediate checkmate or a new clear material loss is a flaw. If a check is harmless under the shallow model, the tutor may acknowledge it and still accept the move.

### Confidence and abstention

Every derived evaluation is either high-confidence or unsupported for v1. V1 does not surface a graded confidence scale to the child.

The advisor must not recommend or condemn a move based on speculative compensation beyond its horizon. A move that appears to sacrifice at least 2 points without verified immediate compensation is not recommended. If the advisor cannot identify a high-confidence purpose in the position, it uses the fallback flow instead of fabricating one.

## V1 Semantic Insights

The advisor may emit these concepts:

### Urgent concepts

- `kingInCheck`
- `pieceNeedsHelp`
- `checkingPiece`
- `profitableAttacker`

### Opportunity concepts

- `profitableCapture`
- `mateInOne`
- `captureResolvesDanger`

### Wake concepts

- `developsKnightOrBishop`
- `advancesCenterPawn`
- `castlesForKingSafety`
- `addsUsefulDefender`
- `createsSafeImmediateThreat`
- `improvesCentralActivity`

### Move-check concepts

- `allowsCheck`
- `allowsMateInOne`
- `allowsMaterialLoss`
- `safeAfterReplyCheck`

Each insight identifies its subject pieces or squares, relevant candidate moves, priority, confidence, and explicit evidence. Child-facing text is not stored as the insight’s identity.

## Wake Policy

### Opening-development context

Opening development is relevant when:

- at least one learner knight or bishop remains on its home square; and
- both sides retain their queens; and
- each side retains at least three non-pawn, non-king pieces, including its queen.

This intentionally uses position evidence rather than a fixed move-number boundary. If a minor piece remains undeveloped unusually late, helping it join the game can still be valid advice.

Opening Wake candidates are safe legal moves that do one of the following:

1. move a knight or bishop off its home square;
2. advance the learner’s d- or e-pawn from its home square toward the center;
3. castle legally.

The opening prompt is:

> “Nothing is in danger yet. Can you help the center or wake up a piece?”

### General Wake candidates

Outside clear opening development, a safe legal move qualifies for Wake when it has at least one high-confidence purpose:

- adds a legal defender to a currently capturable learner piece;
- safely attacks an undefended or more valuable opposing piece;
- moves a non-pawn closer to the central sixteen squares (files c–f, ranks 3–6) and increases its legal mobility by at least two destinations;
- castles legally.

Prefer candidate source pieces in this order:

1. a piece with an opening-development move;
2. a piece that can add a useful defender;
3. a piece that can create a safe immediate threat;
4. a piece with a central-activity improvement.

All qualifying safe moves remain acceptable; the ordering chooses the first teaching focus, not a unique correct move.

### Low-confidence fallback

If no Safe, Take, opening, or general Wake insight is available, the tutor says:

> “Nothing urgent stands out. Try a move you like, and we’ll check it together.”

The board returns to normal move staging. Any legal move that does not allow immediate mate or a new clear material loss can pass the opponent check. The tutor describes only verified consequences, such as “Your pieces stay safe,” and does not invent a strategic purpose.

## Interaction Flow

### Help availability

**Help me** is available when:

- the game is ongoing;
- the current side is controlled locally;
- the board is not remotely locked;
- no promotion choice is currently blocking the move flow.

Help is unavailable after checkmate or stalemate and during the remote opponent’s turn.

### Starting with no tentative move

1. The player presses **Help me**.
2. The advisor analyzes the committed position.
3. If the learner is in check, enter the check branch.
4. Otherwise, run or compress Safe.
5. If Safe produces no move, run or compress Take.
6. If Take produces no move, enter contextual Wake or the fallback.
7. When the child stages a move, enter the opponent reply check.
8. If the move passes, name the idea and offer **Done** or **Keep looking**.

### Starting with a tentative move

If a legal move is already staged, pressing **Help me** starts directly with the opponent reply check.

If the staged move cannot be committed because it leaves the learner’s king in check, the tutor first says:

> “This move leaves your king in check. Try another move.”

The coach then helps the learner make a legal check resolution rather than evaluating the illegal tentative position as an ordinary candidate.

### Check branch

1. Ask: “Your king is in check. What is giving check?”
2. The child taps a checking piece.
3. Ask: “Make a move that gets your king safe.”
4. Accept any legal move that resolves check and passes the ordinary opponent reply check.

For double check, tapping either checking piece is a correct identification. Core legality determines the valid responses; the coach does not independently encode capture, block, or king-move rules.

### Safe branch

1. Ask: “Does one of your pieces need help?”
2. The child taps an urgent learner piece or chooses **I don’t see one**.
3. Ask: “What could take your {piece}?”
4. The child taps an opponent piece whose capture creates the urgent loss.
5. Ask: “How could you help your {piece}?”
6. The child stages a move.

If **I don’t see one** is correct, acknowledge it and continue to Take. If an urgent problem exists, remain in Safe and begin the hint ladder.

### Take branch

1. Ask: “Can you find a capture that helps you?”
2. The child stages a capture or chooses **I don’t see one**.

If the child stages a legal capture that is not profitable, the tutor explains the immediate recapture or material consequence and asks them to try again. If **I don’t see one** is correct, continue to Wake.

### Wake branch

1. Ask the context-appropriate piece question.
2. The child taps a candidate source piece.
3. Select that piece for ordinary board movement guidance.
4. Ask: “Where could your {piece} help from?”
5. The child stages a move.

An accepted tap must have at least one safe qualifying move. A plausible but nonpreferred candidate source is accepted when it has any qualifying Wake move.

### Opponent reply check

Ask:

> “Could {opponent} check your king or win something?”

The child may:

- tap an opposing checking piece;
- tap a learner piece the opponent can profitably capture;
- choose **Looks safe**;
- change the tentative move through normal board movement.

If the child finds a real issue, acknowledge the catch and ask for another move. If **Looks safe** is incorrect, use the hint ladder. If the move is acceptable, name its verified purpose and finish coaching.

### Completion

The completion message has two parts:

1. a factual assessment: “That works.”
2. one verified concept: “Your knight joined the game and helps in the center.”

The available actions are:

- **Done**, which uses the existing commit path;
- **Keep looking**, which exits coaching and preserves the tentative move for comparison.

### Stop behavior

**Stop** immediately exits coaching and removes coach-only emphasis. It never rolls the board back:

- a tentative move made during coaching remains tentative;
- no tentative move is created by identification taps;
- the current ordinary selection remains when it is still valid;
- existing Undo/reposition behavior remains available.

This avoids hidden movement and preserves the child’s ownership of every physical board change.

## Board Input Semantics

The board has two coaching task modes.

### Identification mode

A tap is an answer to the coach. It does not invoke ordinary selection, clear a tentative move, or stage anything.

Identification mode is used for:

- locating a piece that needs help;
- locating an attacker or checking piece;
- choosing a Wake source piece;
- identifying an opponent reply after a tentative move.

When a Wake source tap is accepted, the coaching session explicitly asks `GameSession` to select that piece as it transitions to move mode.

### Move mode

The board uses its normal drag and tap-move behavior. The coach observes the resulting tentative move and evaluates it. Existing allowed-movement guidance, check legality, promotion, capture trays, and animation remain authoritative.

SwiftUI does not decide whether a tap or move answers the question. It forwards a generic event and renders the resulting coaching presentation.

## Hint and Feedback Policy

### Hint levels

Each question begins at level 0 and may advance through:

| Level | Tutor behavior |
| --- | --- |
| 0 | Ask the open question with no new coach emphasis |
| 1 | Refer to an existing marker or movement clue |
| 2 | Narrow attention to an area or small candidate set |
| 3 | Emphasize the relevant piece or relationship |
| 4 | Emphasize a candidate source and destination while leaving the action to the child |

Not every question requires all levels. A question ends at the most specific representation the board can support without moving a piece for the child.

### Hint control

- **Hint** advances exactly one level.
- An incorrect board answer produces specific feedback but does not automatically advance the level.
- After two consecutive incorrect answers at the same level, the prompt may add “Want a hint?” and emphasize the existing Hint action.
- There are no timers or automatic reveals.
- Hint progress resets when the coaching question changes.

### Feedback categories

The coaching session distinguishes:

- correct and strong;
- correct alternative;
- plausible idea with a concrete flaw;
- relevant but nonurgent piece;
- unrelated tap;
- correct absence report;
- missed existing answer.

Feedback names one visible fact and returns to the question. It does not display scores, red failure states, or the words “wrong move.”

## Presentation Design

### Responsive coaching region

During an active episode, the existing message/control segment and selected-piece guidance segment are replaced by one combined coaching region spanning both slots. The captured-pieces segment remains separate and visible. When coaching ends, the two original segments and their ordinary content return.

The combined region is one visual surface with two semantic areas:

- a conversation area containing the current question or feedback, a short board-action instruction, and the Safe–Take–Wake stage indicator when relevant;
- an action area containing up to two primary contextual actions and a quiet **Stop** action throughout the episode.

The region follows the existing responsive sidebar arrangement:

- when the sidebar segments stack vertically in landscape, the conversation area appears above the action area;
- when the sidebar segments sit side-by-side in portrait, the conversation area appears beside the action area.

The coaching presentation does not refer to “top” or “middle” panels. It supplies semantic content; SwiftUI chooses the axis and sizing from the existing sidebar presentation and keeps the content readable for the current tabletop orientation. Selected-piece identity or movement information needed for the current task is incorporated into the coaching copy rather than competing with it in a separate panel.

Questions never float over the board. The board remains fully visible and playable whenever the current task expects a move.

### Help and Done

- **Help me** appears in the normal turn controls whenever Help is available.
- During an active episode, the combined region’s action area replaces the ordinary turn action, and **Done** is withheld until the coach reaches completion.
- The player can always use **Stop** to exit coaching and return to ordinary Done behavior.
- At completion, the action area offers **Done** and **Keep looking**. **Done** commits through the existing `GameSession.finishTurn()` flow; coaching does not duplicate move execution.

### Coach emphasis

Coaching may add a narrow focus presentation containing:

- emphasized squares;
- an emphasized attacker-target relationship;
- a small candidate-square set at stronger hint levels.

This focus is separate from existing `BoardGuidancePresentation` semantics. It may increase prominence or pulse once, but it must not redefine danger badges, defense shields, allowed paths, or coverage colors. Coach emphasis disappears when the question changes or coaching stops.

### Stage indicator

When Safe–Take–Wake is active, show the three labels in order. A compressed step appears cleared, not unanswered. Check uses a **Safe** label. The low-confidence fallback may omit the routine indicator rather than claim a Wake insight that was not found.

### Language

- Use one short question at a time.
- State the expected board action explicitly.
- Use familiar chess terms such as check, threat, capture, attacker, protect, and center.
- Prefer a piece name over notation; add a square only when needed to distinguish identical pieces.
- Name one concept after success.
- Do not use engine language, evaluation numbers, or superlatives such as “best.”

## Architecture

### Dependency direction

```text
SwiftUI
  → GameSession
    → CoachingSession
      → CoachingAdvisor
        → evaluation source
        → insight source
        → explanation source
          → Core rules and PositionAnalysis
```

Core does not import coaching, Game, SwiftUI, networking, or presentation code.

### `CoachingAdvisor`

The advisor is the app-facing intelligence boundary. It accepts an immutable coaching request and produces source-independent evaluation and insights.

A request contains:

- the committed `GameState`;
- an optional tentative `Move`;
- the side being coached;
- a position or analysis revision;
- the current question context when reevaluation follows a staged move.

The v1 advisor composes local implementations of evaluation, insight generation, and explanation. These source interfaces remain narrow and internal; the project does not add a provider registry or dynamic plug-in system.

The advisor API may be asynchronous so a later engine or model does not require changing `GameSession`’s public interaction. V1 completes locally without showing a loading state.

### `CoachingSession`

`CoachingSession` is the single owner of mutable coaching state:

- active/inactive status;
- semantic stage;
- focused insight and selected coaching subject;
- expected board task;
- hint level and consecutive misses;
- current presentation;
- the revision for which its analysis is valid.

The stages are parameterized rather than separate screen types:

```text
safeLocate
safeIdentifyAttacker(target)
safeResolve(problem)
takeChooseMove
wakeChoosePiece(context)
wakeChooseMove(piece, insight)
opponentCheck(move)
complete(move, concepts)
fallbackChooseMove
```

Check reuses the Safe identify-and-resolve mechanics with check-specific copy and Core-derived legal responses.

The session receives:

```text
squareTapped(square)
moveStaged(move)
actionChosen(action)
positionChanged(revision)
```

It returns a presentation plus any narrow directive required from `GameSession`, such as selecting an accepted Wake piece, restoring ordinary move mode, or committing through the existing Done action.

### `GameSession`

`GameSession` remains the observable app model and owns an optional `CoachingSession`. It:

- exposes Help availability and the current coaching presentation;
- starts and stops coaching;
- routes board taps according to the current board task;
- stages moves only through existing move APIs;
- asks the advisor to reevaluate after a tentative move;
- discards stale results whose revision no longer matches;
- cancels coaching when the game is committed, reset, ended, remotely replaced, or locked.

Coaching must not duplicate `GameSession`’s selection, tentative-move, promotion, capture, or commit state.

### Presentation types

SwiftUI consumes a value presentation containing:

- headline/question text;
- optional instruction text;
- stage-indicator state;
- contextual actions and accessibility labels;
- board task mode;
- coach-focus presentation.

The presentation describes semantic conversation and action content, not a horizontal or vertical layout. Expected answers, material calculations, and move classifications remain in the coaching model rather than the view.

## State Changes and Cancellation

- A new local or remote committed move ends the current coaching episode.
- Starting a new game ends coaching.
- Checkmate, stalemate, forfeit, or remote lock ends coaching.
- A promotion choice remains in the existing move flow; advisor evaluation occurs after a concrete promoted piece is staged.
- Coverage may remain open during coaching. Coach emphasis layers above it using the existing coverage interaction rules.
- If an asynchronous result arrives for an old revision or inactive episode, discard it without changing the UI.
- The local advisor should not throw for a valid ongoing position. An unsupported position produces the fallback flow.

## Accessibility

- Every coach question and feedback message is readable by VoiceOver.
- The instruction states whether the answer requires tapping a piece, making a move, or choosing an action.
- Coach emphasis never carries meaning without accompanying text.
- Stage labels expose completed/current state without relying only on color.
- Hint, Stop, absence, and completion actions use comfortable touch targets and unambiguous labels.
- VoiceOver reads the conversation area before the action area in either orientation.
- Board orientation and piece readability continue to follow the existing tabletop behavior.

## Testing Strategy

### Evaluator tests

Use explicit board fixtures for:

- every piece value;
- defended and undefended captures;
- a pawn profitably taking a defended bishop;
- an apparently threatened piece whose attacker would be lost;
- multiple attackers and recaptures;
- the 2-point urgent threshold;
- profitable, equal, and losing learner captures;
- mate in one and allowed checks;
- opponent replies that introduce clear material loss;
- pinned pieces and king-safety legality;
- en passant and promotion positions where capture resolution differs from a normal move.

### Insight tests

Verify exact semantic insights and candidate moves for:

- check;
- urgent material danger;
- profitable capture;
- starting-position opening development;
- central pawn and minor-piece development;
- castling;
- adding a defender;
- safe immediate threats;
- general activity;
- the low-confidence fallback.

### Coaching transcript tests

Drive `CoachingSession` with event sequences and assert every resulting stage, board task, action set, hint level, and semantic message. Cover:

- compressed first-move flow;
- full Safe–Take–Wake flow;
- correct and incorrect **I don’t see one**;
- multiple correct pieces or moves;
- check resolution;
- help on a pre-existing legal and illegal tentative move;
- two misses followed by a hint offer;
- changing a tentative move during opponent check;
- Stop and Keep looking preservation;
- completion without committing the move.

### GameSession integration tests

Verify:

- Help availability for local, remote, locked, and completed states;
- identification taps do not clear or alter tentative moves;
- accepted Wake taps transition into ordinary selection;
- all move staging uses existing APIs;
- stale advisor results are ignored;
- committing, resetting, remote replacement, and game end cancel coaching;
- promotion completes before coaching reevaluation;
- only the existing Done path commits.

### Presentation tests

Verify canonical copy, stage labels, action labels, board-task instructions, and accessibility descriptions as pure presentation values. Layout tests verify that the combined coaching region spans the message/control and selected-piece slots, uses a vertical internal arrangement when those slots stack, uses a horizontal internal arrangement when they sit side-by-side, and leaves the captured-pieces segment visible. Other SwiftUI tests should remain limited to rendering and event wiring.

### Invariants

- Every advisor-recommended move is legal under Core.
- Every accepted Take move has verified gain, resolves danger, or mates.
- Every specific explanation references evidence in the current position.
- No coaching action can commit a move except **Done** through the existing path.
- No stale analysis can alter current coaching state.

## Acceptance Criteria

V1 is complete when:

- a child can request Help from the starting position and receive opening-appropriate board-native guidance without empty Safe or Take questions;
- a child can identify and resolve a clear threatened-piece problem;
- a child can find a clear profitable capture;
- a child can choose a Wake piece and stage one of several acceptable purposeful moves;
- every coached tentative move receives the opponent reply check;
- incorrect taps receive factual feedback and optional progressive hints;
- coaching uses one combined responsive region across the two guidance/control slots in landscape and portrait while captured pieces remain visible;
- the child can stop at any time without hidden board rollback;
- the tutor never commits a move or insists on a unique best move;
- all coaching works offline and produces deterministic results for the same position and interaction history;
- existing chess-rule, guidance, tentative-move, local-play, and remote-play tests continue to pass.

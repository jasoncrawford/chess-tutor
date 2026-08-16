# Derived Coaching State Design

## Status and relationship to coaching v1

This design corrects the state architecture of On-Demand Coaching V1 after UAT exposed a stale-conversation bug. It supplements `2026-08-13-on-demand-coaching-v1-design.md` and `2026-08-15-coaching-scaffolding-revision-design.md`.

Those documents remain authoritative for chess evaluation, Safe–Take–Wake policy, language, hint content, board emphasis, panel layout, and the source-independent advice boundary. This document changes how the live coaching step is determined after the child interacts with the board.

## Problem

The current coaching session advances a stored stage as the child answers questions. The playable board independently owns its selected square and tentative move. Those two representations can diverge.

For example, first-move Help asks the child to choose a knight or center pawn. Tapping a recommended knight advances coaching to “Move it on the board.” If the child then selects a blocked rook, the board changes its selection but coaching receives no event in that stage. The instruction remains about the knight even though the board now shows the rook.

Adding a special transition from the Wake destination step back to the Wake source step would fix this example, but not the underlying problem. Similar stale combinations can occur when the child:

- changes a previously identified piece;
- selects a different source while considering a response;
- replaces or removes a tentative move;
- changes an earlier answer after revealing a hint;
- interacts while an asynchronous assessment is pending.

An expanding collection of rewind transitions would encode these combinations individually and would likely miss cases.

## Goals

- Recalculate the active coaching step after every meaningful board or coaching action.
- Make the current board interaction the authoritative source for selection and tentative-move facts.
- Retain only pedagogical facts that the board cannot represent.
- Invalidate later progress automatically when an earlier prerequisite changes.
- Ensure the prompt, feedback, actions, hints, and board focus always describe the same current situation.
- Preserve the existing evaluator, advisor, explainer, presentation, and SwiftUI boundaries.
- Make the reconciliation logic deterministic and independently testable.

## Non-goals

- No changes to chess evaluation, piece values, candidate ranking, or accepted-move policy.
- No new coaching routines, concepts, prompts, or UI controls.
- No engine, online AI, or additional analysis request for a selection-only change.
- No general-purpose workflow language or configurable rules engine.
- No attempt to infer pedagogical discoveries solely from the chess position.
- No redesign of ordinary board selection, dragging, staging, or Done behavior.

## Chosen architecture

The active coaching experience becomes a derived projection of three kinds of input:

1. **Position knowledge:** the latest advice for the committed position and, when applicable, the assessment of the exact tentative move.
2. **Board interaction:** the board's current selected square and tentative move.
3. **Pedagogical memory:** facts the board cannot express, such as an identified Safe target or attacker, a correctly confirmed absence, an identified opponent reply, and hint or miss progress for the current question.

A focused model component, referred to here as the **coaching reconciler**, derives one coherent coaching result from those inputs. The result includes the active step, presentation context, board task, focus, available actions, and any required directive.

`CoachingSession` remains the owner of a Help episode and the receiver of advice and user actions. It no longer treats a mutable stage as an independent source of truth. After applying an input to position knowledge, board interaction, or pedagogical memory, it invokes the reconciler and publishes the derived result.

This is not a generic workflow engine. Safe, Take, Wake, check resolution, opponent reply, fallback, and completion remain explicit finite coaching concepts. Their ordering and prerequisites are expressed directly in cohesive model code.

## State model

### Position knowledge

Position knowledge is cached analysis, not conversation progress. It contains:

- learner color;
- committed-position revision;
- advice for that committed position;
- an optional tentative-move assessment identified by the exact move, origin, and committed-position revision;
- whether an applicable analysis request is pending or unsupported.

Selecting or deselecting a square does not invalidate committed-position advice. Staging, replacing, or removing a tentative move changes which move assessment is applicable. Committing a turn changes the position revision and ends the current Help episode under the existing v1 policy.

### Board interaction snapshot

`GameSession` already owns the authoritative playable state. It supplies coaching with a small read-only snapshot after every meaningful interaction:

- current selected square, if any;
- current tentative move, if any;
- committed-position revision.

Coaching must not preserve a competing selected source or tentative move. Before a move is staged, a Wake source is the learner piece currently selected on the board. After a move is staged, its source is `tentativeMove.from`, regardless of the board's destination selection. Neither fact comes from a square remembered by a prior coaching transition.

### Pedagogical memory

Pedagogical memory contains only facts learned through the tutoring conversation that cannot be reconstructed from the board:

- an identified urgent target;
- an identified attacker for that target;
- a correctly confirmed absence needed to pass a nonempty Safe or Take scan;
- an identified opponent-reply issue for the current tentative move;
- hint level, miss count, and feedback associated with the current question identity.

Every stored fact carries, either directly or by construction, the identity of its prerequisites. An attacker belongs to a particular target and position revision. A confirmed absence belongs to the applicable routine and advice. An opponent reply belongs to a particular tentative move and assessment. It cannot remain valid after its prerequisite changes.

### Derived coaching result

The reconciler produces one result containing:

- the active finite coaching step;
- a stable question identity;
- `CoachingPresentationContext` or an awaiting state;
- the board interaction contract (`identify`, `move`, or `none`);
- coach focus and hint availability;
- zero or more narrow coordination directives.

The published presentation and board behavior are projections of this result. SwiftUI continues to render them without chess or workflow decisions.

## Reconciliation rules

### Earliest unmet valid requirement

For the applicable routine, the reconciler evaluates prerequisites in teaching order and chooses the earliest requirement that is not currently satisfied.

Examples:

- Safe: identify a valid urgent target, then identify an attacker for that target, then stage a move that resolves the required danger.
- Wake: have a currently selected learner piece with a verified Wake purpose, then stage a qualifying move from the currently selected piece.
- Opponent reply: have an assessed tentative move, then identify a relevant reply or choose Looks safe, then complete or revise.

Later evidence is considered only while all of its prerequisites remain valid. When a prerequisite changes, dependent evidence becomes inapplicable without a bespoke backward transition.

### Current action before history

The current action is interpreted against the current routine and interaction contract before older pedagogical memory is used.

During an `identify` step, a square tap is a candidate answer. The reconciler classifies it using current advice. During a `move` step, ordinary board selection and staging proceed normally; coaching then reconciles from the resulting board snapshot.

This distinction lets Safe resolution retain the previously identified target while the child selects a defender or attacker to make a move. It also lets a new learner-piece tap during Safe identification replace the candidate target and automatically invalidate an attacker associated with the old target.

### Question identity owns transient progress

Every derived question has a semantic identity based on the routine and its relevant facts, such as:

- opening Wake source choice for the current position;
- Wake destination for a particular selected piece and purpose;
- Safe attacker for a particular target;
- Safe resolution for a particular target and identified attacker;
- opponent reply for a particular tentative move.

Hint level, miss count, and hint-only focus belong to that identity. If reconciliation produces a different identity, that transient progress resets. Feedback additionally belongs to the attempted answer or board-interaction fact that produced it; feedback disappears when that fact is no longer current, even if the broader question identity is unchanged. Persistent target–attacker focus remains only when its prerequisite identities remain valid, as required by the existing scaffolding design.

This prevents a hint or feedback message for one piece or move from leaking into another question.

## User-visible behavior

### First-move Wake example

With first-move advice loaded:

| Child's current interaction | Derived response |
| --- | --- |
| No piece selected | Ask which knight or center pawn to move. |
| Recommended knight selected | Name the knight's opening purpose and ask the child to move it. |
| Different recommended pawn selected | Recompute for that pawn and ask the child to move it. |
| Blocked rook selected | Respond exactly as if the rook had been tapped first: explain that it cannot come out yet, and continue asking for a suitable piece. |
| Noncandidate movable learner piece selected | Give the same factual source-choice feedback it would receive on the first tap. |
| Selection cleared | Return to the source-choice question with no stale piece-specific instruction or feedback. |
| Qualifying move staged | Request or use the assessment of that exact move, then proceed to opponent reply. |
| Tentative move replaced or removed | Discard results and progress tied to the old move, then derive the appropriate current question. |

The selected piece may remain visibly selected even when it is not a coaching candidate. Coaching explains the fact and remains at the source-choice requirement; it does not silently select another piece.

### Safe example

- With no valid target evidence, coaching asks which learner piece needs help most.
- Tapping an urgent target records that target and derives the attacker question.
- Tapping a different learner piece while still identifying pieces evaluates it as a new target attempt. If it is the relevant urgent piece, it replaces the prior target; any attacker tied to the prior target no longer applies. If it is safe or lower priority, feedback states that current fact and the prior target does not force a stale attacker prompt.
- Once an attacker has been identified, Safe resolution retains that target–attacker relationship while ordinary piece selection is used to construct a saving move.
- Replacing or removing the tentative move returns to the same valid Safe resolution context because the target–attacker evidence still applies to the unchanged committed position.

### Take, check, fallback, and reply behavior

- Take, check resolution, and fallback are move requirements. Changing the selected source does not require a rewind; the unchanged question is rederived against the new board selection and any selection-dependent hint focus updates with it.
- Check-location taps and Safe identification taps remain coaching answers rather than accidental move attempts.
- Opponent-reply evidence is tied to one exact tentative move. Revising that move removes the old reply evidence and assessment from consideration.
- Completion remains valid only while the exact assessed tentative move remains staged. Changing or removing it makes completion disappear immediately.

## Event and data flow

1. The child taps, drags, stages, replaces, removes, or commits a move, or chooses a coaching action.
2. `GameSession` applies ordinary board behavior when the active derived board task permits it.
3. `GameSession` sends `CoachingSession` the semantic action, when one exists, and the resulting authoritative board interaction snapshot.
4. `CoachingSession` updates only applicable pedagogical memory or analysis state.
5. The coaching reconciler derives the complete current result.
6. `GameSession` executes narrow directives such as requesting advice, stopping Help, or committing through the existing Done path.
7. SwiftUI observes and renders the resulting presentation and board focus.

All paths that mutate selection or tentative-move state must converge on the same synchronization point. The design must not depend on callers remembering a stage-specific coaching notification.

Selection-only synchronization is synchronous and local. A tentative move requires the existing asynchronous assessment. An assessment response is accepted only when its request identity still matches the current committed revision, exact tentative move, and coaching origin. Otherwise it is ignored and cannot change the presentation.

## Component boundaries

### `GameSession`

- Owns the chess position, selection, tentative move, and board mutation rules.
- Routes input according to the reconciler's current `identify`/`move`/`none` contract.
- Synchronizes the authoritative interaction snapshot after every relevant mutation.
- Executes coordination directives.
- Does not decide which coaching question or answer is correct.

### `CoachingSession`

- Owns the lifetime of one Help episode, cached advice, pedagogical memory, and pending-request identity.
- Receives semantic actions and board snapshots.
- Invokes reconciliation after every input and exposes the derived result.
- Does not own a second copy of board selection or tentative-move state.

### Coaching reconciler

- Is pure model logic with no SwiftUI, simulator, network, or asynchronous dependency.
- Determines the earliest unmet valid requirement.
- Validates prerequisite-bound evidence.
- Produces the active step, question identity, presentation context, focus, actions, and directives.
- Uses the existing advice and explanation abstractions; it does not evaluate chess independently.

The reconciler may remain private to the coaching module if no other consumer needs it. It should not broaden the public API merely to expose implementation details.

### SwiftUI

- Continues to forward board and action intents through `GameSession`.
- Renders the published coaching presentation and focus.
- Contains no reconciliation, rewind, or chess-evaluation rules.

## Invariants

The implementation must maintain these invariants:

1. There is no mutable coaching stage that can disagree with the current interaction snapshot and valid pedagogical evidence.
2. Before staging, a piece-specific move instruction always names the piece currently selected as the coaching source; after staging, move-specific coaching always names the exact staged move.
3. A tentative-move assessment, opponent reply, revision message, or completion applies only to the exact move still staged.
4. Evidence never outlives a changed prerequisite, position revision, or Help episode.
5. Feedback and hints never outlive their semantic question identity.
6. Presentation, actions, board task, and focus are produced together from one derived result.
7. Selection-only changes never request new position analysis.
8. A stale asynchronous response never alters current coaching state.
9. Every meaningful selection or tentative-move mutation reaches coaching through one common synchronization path.

## Error and unsupported-state behavior

- If committed-position advice is pending, the derived result exposes the existing waiting presentation.
- If advice is unsupported, reconciliation produces the existing low-confidence fallback.
- If a stored pedagogical fact cannot be found in current advice, it is ignored and the earliest valid question is derived.
- If a tentative assessment is missing or stale, no conclusion about that move is shown; the session requests or awaits the matching assessment.
- If an input is irrelevant to the current interaction contract and changes no authoritative board state or pedagogical fact, reconciliation is idempotent and leaves the visible result unchanged.
- Correct `I don't see one` answers remain only as prerequisite-bound progress through the applicable Safe or Take scan; a new position or Help episode cannot inherit them.

These are normal derivation outcomes, not exceptional rewind paths.

## Testing strategy

### Pure reconciliation tables

Table-driven model tests cover each routine across combinations of:

- no selection, candidate selection, noncandidate selection, and cleared selection;
- no pedagogical evidence, valid evidence, and evidence with a changed prerequisite;
- no tentative move, exact assessed move, replaced move, and removed move;
- hint and feedback progress before and after a question-identity change;
- current and stale position or assessment revisions.

Each case asserts the complete coherent result: active question identity, prompt, feedback, board task, actions, and focus.

### Session tests

Session tests verify that:

- inputs update only minimal pedagogical memory;
- every input invokes reconciliation;
- dependent evidence is dropped by validation rather than manual rewind transitions;
- selection-only changes reuse current advice;
- stale asynchronous assessments are ignored.

### `GameSession` integration transcripts

Regression transcripts exercise real board interaction rather than calling only coaching internals. Required cases include:

1. Help from the starting position → select a recommended knight → select the blocked rook: the response matches selecting the rook first and no knight-specific instruction or focus remains.
2. Starting position → switch among two recommended sources: the instruction and focus follow the current source.
3. Starting position → select a source → clear selection: coaching returns to source choice.
4. Safe target → attacker question → tap another learner piece: coaching evaluates that piece from the earliest applicable Safe requirement and does not retain an incoherent attacker question.
5. Safe target and attacker → select different possible saving pieces: Safe resolution remains anchored to the valid target–attacker relationship.
6. Stage one move → replace it before assessment returns: the old response is ignored.
7. Reach completion → remove or replace the tentative move: completion, its concepts, and its actions disappear.
8. Use Hint or receive feedback → change the semantic question: stale hint focus and feedback disappear.

Existing finite opening, threat, special-move, Stop/tentative, accessibility, and full-suite tests remain green with zero skips.

### UAT

On the dedicated iPad simulator, repeat the first-move source-switch sequence and at least one Safe target-change sequence. At each tap, inspect both the conversation and board emphasis. The visible prompt, selected piece, highlights, paths, and actions must describe one coherent current task.

## Acceptance criteria

- Selecting the blocked rook after a recommended opening piece produces the same coaching response as selecting the rook first.
- Switching among candidate or noncandidate pieces never leaves a stale piece-specific instruction.
- Earlier coaching evidence can change without leaving dependent prompts, hints, focus, or feedback behind.
- Changing or removing a tentative move immediately removes all conclusions tied to the prior move.
- The implementation has one authoritative board interaction snapshot and one derived coaching result.
- No routine-specific rewind table or collection of backward transitions is introduced.
- No selection-only action starts a new evaluator, engine, or online request.
- SwiftUI remains presentation-only, and the existing advice/explanation seams remain source-independent.
- Relevant focused tests and the complete test suite pass with zero failures and zero skips.

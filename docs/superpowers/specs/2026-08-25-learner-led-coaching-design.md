# Learner-Led Coaching Reconciliation Design

## Status

This design clarifies and strengthens the approved derived-coaching-state architecture in `2026-08-16-derived-coaching-state-design.md`. It fixes a remaining inconsistency: a tentative move is already part of the authoritative interaction snapshot, but the question from which that move originated can still force coaching back into the prior Safe, Take, or Wake step.

## Problem

When Take asks for a safe capture and none exists, the learner can stage an ordinary move instead. Coaching assesses the exact move, but an origin-specific branch rejects it as an answer to Take and projects the old Take question again. The learner must then choose `No safe capture`, which discards the move she already chose.

This contradicts the derived-state architecture and the product intent. The current board interaction should be authoritative. A child who moves ahead of a coaching question is expressing a new intent, not making an invalid conversational transition.

## Product rule

**A staged move supersedes every position-level coaching question.**

While an exact tentative move exists, coaching must describe that move. It must never ask the learner to finish the earlier Safe, Take, Wake, or check-location step first.

The earlier routine remains useful context:

- If the move answers the earlier question, the explanation can say how.
- If the move does not answer it, the explanation evaluates the move on its own merits.
- The earlier routine may influence wording or verified concepts, but it may not choose the active step.

This is the general “follow the learner” rule. It is not a Take-only exception, a Skip button, or a table of rewind transitions.

## Derived-state invariant

The active coaching presentation is always a projection of:

1. the current committed position and position revision;
2. the exact current selection and tentative move;
3. advice applicable to that exact state;
4. pedagogical evidence whose prerequisites are still valid.

Conversation history is not a fifth source of authority. `CoachingMoveOrigin` records why analysis was requested and can enrich an explanation, but it cannot restore a position-level question while a tentative move is staged.

For any non-nil tentative move, the only valid derived outcomes are:

- awaiting the exact move assessment;
- asking about a concrete opponent reply to that move;
- revising that move with a concrete reason;
- completing the assessment of that move.

`safeLocate`, `safeResolve`, `takeChooseMove`, `wakeChoosePiece`, `wakeChooseMove`, and check-location/resolution questions are invalid while a tentative move exists.

## Behavior by prior routine

### Take

- A verified safe capture receives capture-specific completion.
- An unsafe capture receives move-specific revision feedback and keeps the tentative move staged.
- A quiet or otherwise unrelated move receives the normal assessment for that move.
- `No safe capture` is absent once a move is staged and therefore cannot discard it.

### Safe or check

- A move that resolves the danger receives the specific resolution explanation.
- A move that leaves the danger unresolved receives move-specific revision feedback.
- Coaching does not return to the earlier identification or resolution question until the tentative move is removed.

### Wake or fallback

- A move with a verified purpose receives that explanation.
- A safe move without a verified purpose receives the bounded general move assessment.
- An unsafe move receives move-specific revision feedback.

## Removing or replacing a move

Removing the tentative move makes the committed position authoritative again. Coaching re-derives the earliest relevant position-level question from current advice and still-valid evidence.

Replacing the move invalidates the old assessment, opponent-reply evidence, feedback, hints, and completion. Coaching requests and projects advice for the replacement move only.

No action should implicitly discard a tentative move merely to satisfy a question that preceded it. Existing explicit actions such as `Try another move`, `Close help`, and ordinary board replacement retain their current semantics.

## Architecture and scope

The fix belongs in the model layer:

- `GameSession` remains authoritative for the selected square and tentative move.
- `CoachingSession` continues to reduce the authoritative interaction snapshot and invalidate stale move knowledge.
- `CoachingReconciler` must derive a move-specific state whenever `interaction.tentativeMove` is non-nil.
- `CoachingPresentationProjector` and SwiftUI continue to project the derived result without chess or workflow decisions.

No new UI, coaching action, evaluator rule, prompt family, or workflow state is required.

## Testing

Required regression coverage uses real session/advisor paths where practical:

1. Take has no verified safe capture; learner stages a quiet legal move; after exact advice arrives, coaching comments on that move, removes `No safe capture`, and preserves the tentative board state.
2. The same direct move and the move reached after prior Take interaction produce the same move-specific presentation and focus.
3. An unsafe capture staged from Take produces move-specific revision rather than the Take question and is not discarded.
4. Safe/check moves that fail their original task produce move-specific revision while staged.
5. Removing or replacing the move returns to a freshly derived state and rejects stale advice.

Focused coaching/session tests, the complete test suite, and direct simulator UAT must pass with zero failures and zero skips.

## Acceptance criteria

- A tentative move always outranks the question that preceded it.
- No position-level question or absence action appears while a move is staged.
- Coaching feedback, instruction, actions, and board focus all describe the exact current move.
- Choosing an old absence answer cannot reset a newly staged move.
- Removing or replacing the move re-derives from current facts without bespoke rewind rules.
- The implementation preserves the existing pure reconciler, exact-advice identity, session, projector, and SwiftUI boundaries.

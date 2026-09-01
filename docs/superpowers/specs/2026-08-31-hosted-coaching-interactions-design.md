# Hosted Coaching Interaction Contract

## Goal

Restore the child's ability to answer hosted coaching through the board and through an explicit negative-answer button, without returning to a hosted request on every ordinary piece selection.

## Response contract

Hosted coaching turns add one required `expects` field:

- `none`: the turn does not treat the next board tap as an answer.
- `selectPiece`: the next tap on an occupied square is the child's answer and requests a fast follow-up.
- `stageMove`: the child answers by staging a move; ordinary piece selection remains local.

This field describes only the interaction channel. It never identifies the correct answer. Chess judgment remains with the hosted model.

The server may also offer `noPieceNeedsHelp` when the child is being asked to decide whether any piece is in danger. The iPad presents it as **Everything looks safe**. The existing `looksSafe` action remains reserved for judging a staged move or opponent reply and is presented as **Looks safe**.

## Interaction behavior

- While a ready hosted turn expects `selectPiece`, tapping an occupied square records `pieceSelected` and queues exactly one continuation request.
- At all other times, selecting a piece remains a local board interaction and does not replace the current advice or make a request.
- Staging, replacing, and removing moves retain their current behavior.
- Choosing `noPieceNeedsHelp` records that action and queues one continuation request without changing the board.
- Thinking, failure, and completed turns do not accidentally consume board taps as answers.

## Server and prompt

The deterministic compiler exposes the interaction modes and currently available semantic actions. Immutable `tutor-v10` tells the model to:

- use `expects: selectPiece` only when asking the child to identify a piece;
- use `expects: stageMove` when asking the child to try or evaluate a move;
- include `noPieceNeedsHelp` when asking whether any piece is in danger;
- never ask for an interaction the returned turn does not enable.

Strict Python and Swift validation reject unknown interaction modes, unavailable actions, additional fields, and malformed output.

## Verification

- Regression: a hosted danger question exposes **Everything looks safe** and choosing it sends one `actionChosen` continuation.
- Regression: a hosted `selectPiece` turn reacts to a pawn tap with one `pieceSelected` continuation.
- Regression: the same pawn tap remains local when the turn does not expect a selection.
- Contract/schema/compiler tests cover the new field and actions.
- Focused server and iPad suites pass, followed by the full CI-equivalent suites and direct simulator UAT.

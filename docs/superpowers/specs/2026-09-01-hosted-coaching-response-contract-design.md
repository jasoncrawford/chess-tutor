# Hosted Coaching Response Contract

## Goal

Make every hosted coaching question answerable through controls that match its wording. The model chooses one interaction intent; the app derives the corresponding board behavior and buttons. Advice-quality tuning remains out of scope.

## Turn contract

Replace the generic hosted `expects` choices with explicit response types:

- `none`: no learner response is requested.
- `findEndangeredPiece`: the learner may tap an occupied square or choose **No piece needs help**.
- `findSafeCapture`: the learner may tap an occupied square or choose **No safe capture**.
- `stageMove`: the learner responds by trying a move.
- `judgeMoveSafety`: the learner chooses **Looks safe** or **Try another move**.
- `chooseWhetherToPlay`: the learner chooses **Play this move** or **Try another move**.

The model may still include the optional `hint` action when appropriate. It no longer chooses the main response buttons independently from `expects`.

## Data flow

The deterministic Swift and Python compilers expose the same request-local response types and only the optional `hint` action. The hosted prompt explains each response type using the exact visible control titles. The model returns one response type. The iPad projector maps that type to its board task and controls. When the learner responds, the session records the existing semantic event (`noPieceNeedsHelp`, `noSafeCapture`, `looksSafe`, `playMove`, or move removal) and sends the normal follow-up.

Historical prompt contracts remain unchanged. Hosted runtime advances to `tutor-v11`; the wire response remains version 3 because the JSON shape is unchanged.

## Failure diagnostics

When a provider response fails validation, the server logs bounded, content-free reason categories such as `shape`, `unavailableAction`, or `unavailableMoveFocus`. It never logs provider text or arbitrary rejected values. The public response remains the existing stable 502 error.

## Tests

Regression tests will prove:

- danger and capture questions render distinct negative-answer controls;
- staged-move judgment and keep/revise decisions render mutually coherent controls;
- each control records the correct semantic learner event;
- v11 Swift and Python compilers emit the same response contract;
- invalid provider responses log only safe reason categories;
- legacy prompt contracts remain unchanged.

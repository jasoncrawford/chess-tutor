# Hosted Coaching Without Dead Ends

## Problem

Hosted coaching currently offers `none` as an expected response. When the model chooses it, the app presents no response control and ignores piece-selection answers. The live Help episode therefore becomes inert.

## Design

Create immutable prompt version `tutor-v13`. Its response contract will offer only interactive continuations: `findEndangeredPiece`, `findSafeCapture`, `stageMove`, `judgeMoveSafety`, and `chooseWhetherToPlay`. The prompt will require feedback and the next question to appear in the same turn, so an acknowledgment cannot end an active coaching episode.

The server-generated Structured Outputs schema will use that request-specific list, making `none` impossible for the hosted model to return. The iPad transport will also reject a hosted `none` response defensively. The internal enum case remains for older prompt versions, evaluation artifacts, and compatibility; it is not part of the v13 live contract.

## Verification

Python and Swift compiler tests will assert exact v13 parity and the absence of `none`. Prompt tests will cover the continuation rule. Service and transport regressions will prove a provider or server response containing `none` is rejected. Existing older prompt contracts remain unchanged.

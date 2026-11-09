# Hosted Coaching Quality Iteration

## Goal

Improve the current hosted coach using the real-game trace as the primary evidence: keep simple follow-ups near the current two-second latency while making tactical judgments and teaching language more reliable.

## Prompt policy

Create immutable `tutor-v8`; do not edit `tutor-v7`. If the focused probe exposes one repeated prompt defect, preserve v8 and make one bounded immutable successor.

- Ordinary Help begins with the beginner's thinking routine: urgent danger, simple captures, then quiet improvement. It should not select a specific plan or piece unless danger is urgent.
- Hint may narrow the search. A staged move may be discussed precisely, but the coach should help the child evaluate it rather than prescribe a competing move.
- Before calling a piece threatened, evaluate the immediate capture and recapture sequence and the resulting material. A merely legal capture is not automatically a real threat.
- The message and visual focus describe the same object or idea. A question about a piece focuses that piece; destination squares are used only when the words discuss destinations.
- Keep the existing strict JSON/UI contract, 18-word message limit, beginner language, and latest-interaction precedence.

## Reasoning policy

The server owns reasoning effort.

- Initial Help: `high`.
- Tactical follow-ups (`moveStaged`, `moveReplaced`, `squareInspected`, and explicit Hint): `low`.
- Simple follow-ups (`pieceSelected`, `moveRemoved`, `helpReopened`, and other non-tactical updates): configured fast effort, default `none`.

The device cannot choose effort and no premium service tier is used.

## Evaluation

Use focused cases before any larger run: the observed recapturable `...Bxa3` false alarm, opening Help, staged edge knight, a genuinely hanging pawn, and move-removal continuity. Validate output mechanically, score chess correctness, discovery-first teaching, current-step coherence, wording, and focus alignment. Iterate only the prompt on `gpt-5.6-sol`; do not compare model sizes in this pass.

## Success criteria

- The recapturable pawn is not described as endangered.
- Initial Help teaches a thinking step rather than choosing a move.
- Staged-move feedback remains specific without prescribing a different move.
- Message and focus agree.
- Simple follow-ups use `none`; tactical follow-ups use `low`; initial Help uses `high`.
- Focused server/evaluator/Swift tests pass, followed by one small hosted evaluation and a direct simulator check.

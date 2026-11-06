# Coaching playthrough, second round

Continue the same Smoke simulator game beyond the opening before the owner reviews PR #23. Inspect the child's actual experience through development, exchanges, a dangerous move, Hint, and changing plans. Preserve exact traces and verify any chess criticism from the rules and position, not just intuition.

Keep the current Astra/low local trial, deterministic request compiler, and UI contract. Any retained refinement must address an observed failure and improve a small targeted comparison; no new blanket routine, deterministic advice engine, or wider benchmark sweep. A prompt refinement is the first choice for demonstrated wording/reasoning defects; only change request generation or interaction code if evidence locates the fault there. No change is preferable to an unsupported fix.

Use the already isolated, unmerged coaching-playthrough branch because this is the owner's requested continuation of that review. Leave A16 and deployed defaults untouched. Cap this round's conservative API estimate at $2.50, separate from November 3's $2.22. Retain every attempted output, including failures, and distinguish live interaction from fixed-action replay. No review pause requested; implement inline, obtain one fresh final review, update PR #23, leave it unmerged.

## Observed interaction defect

At move 17, selecting the white bishop on c4 and then tapping the capturable black queen on e6 while `findEndangeredPiece` remains active sends another `pieceSelected` answer instead of staging Bxe6. Dragging c4→e6 stages it and receives correct feedback about winning a queen for a bishop. The hosted answer interceptor consumes every occupied-square tap before the board's normal move routing.

Give an allowed destination from an already-selected local piece precedence over a hosted identification answer. Preserve ordinary identification taps with no selected mover, friendly-piece taps, non-destinations, and the distinction between inherently allowed movement and check legality. Do not depend on visible move dots. Keep the fix in GameSession; no prompt change is needed to address this defect.

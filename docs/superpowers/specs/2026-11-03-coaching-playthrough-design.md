# Coaching playthrough: concrete, accurate feedback

The November 3 simulator playthrough used the released Astra/low discovery policy, with a fresh game on Coaching Smoke, not the owner's A16 game. Through `1. e4 e5 2. Bc4 Nf6 3. d3 Nc6 4. Nf3 d6 5. O-O` (last move staged), it exercised wrong answers, a losing capture, reconsidering, Hint, and changing plans. Twenty live requests completed successfully.

Observed weaknesses: Bc4 and Nf3 received generic “joining the game” feedback rather than a useful explanation; after d3 the tutor falsely said the pawns “protect each other” (d3 protects e4, not vice versa). Danger identification and correction of Bxf7+ worked well and must be preserved.

## Direction

Keep Astra/low, the deterministic request compiler, and the UI contract. Make a separately pinned discovery-prompt revision that asks for one concrete, accurate consequence of a staged move, uses natural language rather than generic praise, and verifies the direction of attack/defense claims. Keep ordinary Help non-prescriptive and allow precise Hint. Do not demand a new quiz when a child already made a useful move.

Alternatives considered: changing reasoning effort would confound a targeted wording experiment; adding deterministic advice rules would revive the architecture the owner rejected. Start with the prompt and measure actual outputs, not a test that merely checks prompt strings. No judge recalibration, broad model sweep, or production-default change.

## Verification and boundaries

Preserve the live trace. Export a small, reproducible diagnostic corpus from the same Swift request builder, based on the played moves. Include quiet development, one-way pawn defense, real danger, losing capture, Hint, and castling. Keep it separate from the frozen 70-turn benchmark and holdout. Compare the old and new prompt on the same deterministic inputs and inspect every response; retain all attempts. Then verify the revised policy in the simulator and run relevant offline suites. Keep this round's API spending below a conservative $2.50; stop before exceeding it. This is diagnostic evidence, not a new benchmark score or proof of reliability.

The user requested autonomous iteration; no design-review pause is needed. Any improvement is for the reversible local trial only. Do not alter the user's A16 game or deployed default.

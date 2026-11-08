# Coaching playthrough — November 4, 2026

## Scope and outcome

Continued the same game in **ChessTutor Coaching Smoke**, from the opening through a staged `17.Bxe6`, with deliberate mistakes and retries. A16 was not touched. The current discovery-v2 prompt remained unchanged: this round found a client interaction defect, not a demonstrated factual failure requiring another prompt revision.

Committed moves before the final staged capture:

`1. e4 e5 2. Bc4 Nf6 3. d3 Nc6 4. Nf3 d6 5. O-O Be7 6. Nc3 O-O 7. Bg5 h6 8. Bxf6 Bxf6 9. Nd5 Qd7 10. Nxf6+ gxf6 11. Nh4 Kh7 12. Qh5 f5 13. exf5 Qe7 14. f6 Qxf6 15. Nf3 Bg4 16. Qxg4 Qe6`

This is not a complete game to mate. I played both sides and intentionally made poor moves to exercise the tutor. Initial requests in this round start at ply 11; earlier development continued without Help.

## Important finding: tap captures were swallowed by a question

At move 17, the tutor asked which white piece was endangered by the black queen on e6. I tapped the bishop on c4. It correctly explained that the d3 pawn protected that bishop and kept the identification question active. I then tapped e6, intending to capture the queen with that selected bishop.

Instead of moving, the app sent another `pieceSelected` answer for the black queen (`29d1f458caab`, request `hosted-31`). The response redirected me to the question: “That’s the attacking queen! Follow her diagonal to find your piece in danger, and tap it.” Dragging the identical c4→e6 capture worked (`1bb1b2dcc616`, `hosted-32`), and the tutor correctly explained that winning a queen for a bishop is a good trade.

The cause was the hosted answer interceptor in `GameSession`: while a question was ready, every occupied-square tap was consumed before the board could recognize a move destination. This was timing-dependent: a second tap during Thinking could move, while the same tap after the response arrived was intercepted.

The fix gives an allowed destination from an already-selected local piece precedence over an identification answer. It uses existing session movement state, independent of visible dots. First-piece answers, friendly-piece taps, and unreachable opponent-piece answers are preserved. A pinned piece's inherently allowed capture remains stageable for inspection but cannot be committed while it exposes the king. No view rule logic, prompt, model, server, or deployed configuration changed.

## Coaching quality observed

Inspection found no incorrect chess claim in the 29 baseline responses, but this is a small, selected playthrough—not an automated quality score.

| Case | Observed response |
| --- | --- |
| Even exchange | “You took a knight, but Black can take your bishop back. Want to make that trade?” |
| King escapes check but loses queen | “Your king escapes check, but the white knight can take your queen.” |
| Reconsidering and Hint | Returned to the king/queen fork, then explicitly identified the pawn capture only after Hint. |
| Queen capture with check loses queen | Correctly warned that the black king could take the queen. |
| Changed tentative move | Replaced that warning with accurate feedback on the safe pawn capture. |
| Pawn attacks queen but is undefended | “Your pawn attacks the queen, but the queen can take it.” |
| Queen-for-bishop capture | Correctly acknowledged the favorable trade despite the pawn recapture. |

No dead-end response/control mismatch appeared. A delayed selection response (`hosted-23`) arrived after the staged-move response (`hosted-24`); the visible UI correctly kept the newer staged-move advice. Both calls are retained and counted in spending.

Two smaller concerns remain: ordinary Help sometimes narrows the answer early (naming the bishop in a danger question; highlighting g8 in a castling clue), and the recurring keep/change wording can feel formulaic. I did not add prompt rules for these subjective observations in this round; the stronger evidence supported fixing the lost-move interaction first.

## Latency, cost, and evidence

The 29 baseline calls all returned validated HTTP 200 responses. Provider latency: median **4.11 seconds**, range **2.66–13.74 seconds**, with **10/29 over five seconds**. The 13.74-second outlier was a follow-up after removing a bad queen capture (`33b1c993f6ef`), not an initial request. The earlier 2–3-second follow-up examples are not a consistent latency guarantee.

Baseline conservative API estimate: **$1.180671**. This round's ceiling is $2.50; final live verification is accounted for separately below. Estimates use the same prior-round conservative rates ($12.50/M uncached input, $1/M cached input, $50/M output), not an invoice. No paid replay, judge, or model sweep was run.

Full baseline structured logs are retained in the isolated worktree at `.coaching-eval/playthrough/20261104/live-log.jsonl`. Game ID: `85f87bd1-44e9-4b07-953e-6d096e7bd8db`. The new integration regression replays all 32 actual committed moves through the rules and asserts the recorded FEN, staged Bxe6 request, and real f7→e6 recapture. Model-facing input is still generated mechanically by the production request builder.

## Verification checkpoint

Before changing production code, two new regressions failed with `pieceSelected` instead of `moveStaged` and an unmoved board. After the nine-line session routing fix, all ten hosted-session integration tests passed. Coverage includes danger/capture questions, dots on/off, ordinary answer taps, and a pinned capture blocked at commit.

The first test attempt also exposed a pre-existing timing assumption: a fake provider waited for only 1,000 scheduler yields, sometimes crashing even existing tests before the main-actor request arrived. Replaced the iteration cap with a bounded five-second condition wait that suspends briefly. The unchanged existing tests then passed before the production fix; the two intended capture regressions remained red. This avoids mistaking a harness timing crash for the product reproduction.

The full native unit suite passed **970 tests, zero failures or skips**. The offline Python suites passed **54 server tests and 333 evaluator tests**. The native UI suite was not run locally; the final check below uses the real rebuilt app instead.

One fresh independent Astra review found no actionable code or test defects. It independently checked the observed chess claims, trace accounting, and the narrower interception behavior. This does not establish teaching effectiveness or broad chess strength; those remain outside this selected playthrough.

## Final rebuilt-app check

Rebuilt and relaunched **Coaching Smoke**, then physically tapped through all 32 committed plies again. The server confirmed the exact same FEN and history. After Help, tapped c4, waited until the tutor's new `findEndangeredPiece` question was visibly ready, then tapped e6. The bishop moved and the request was `moveStaged` with legal `c4e6`—not a black-queen identification answer. The ready response displayed Play this move, Try another move, and Close help:

> You won the queen! Black’s pawn can take your bishop back, but that’s a great trade. Keep it?

Final game ID: `accad87f-e236-4ed5-88c0-e8d414809651`; capture trace: `fbad7006219e`. The three verification calls all succeeded, at 14.02s, 6.66s, and 3.92s. The slow initial request reinforces the latency caveat above. They cost an estimated **$0.143400**, bringing this round to **32 calls / $1.324071**, below its $2.50 ceiling. All three responses were factually sound for the position. No further paid evaluation was needed.

Final logs are retained alongside the baseline as `.coaching-eval/playthrough/20261104/final-live-log.jsonl`. The rebuilt app and server are left running with Bxe6 staged for inspection. A16 remains untouched. PR #23 is updated, not merged.

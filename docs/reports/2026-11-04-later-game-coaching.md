# Later-game coaching evaluation — November 4, 2026

## Result

Evaluated eight later-game situations three times each using the unchanged local coach: **24/24 strong responses, 0 severe errors, 24/24 mechanically valid**. Both direct inspection and an independent Astra review found no incorrect chess claim or misleading board focus. The automatic judge's threshold is every dimension at least 4/5 with no severe flag; this is not a claim of perfect teaching.

The most important distinction was handled correctly every time: one move checkmates, while a different move from exactly the same position produces stalemate. Promotion was correctly called check, not checkmate. The coach also distinguished a losing queen-for-knight capture from a safe winning rook capture.

One mild teaching weakness remains: one of three mating-net Help responses suggests trying queen checks instead of guiding the child toward trapping the king with the available rook mate. No prompt, model, parameter, compiler, UI, or judge change was made on the basis of this small sample.

## Scope

Extended the prior recorded game from move 17 to a position before White's **46th move**, by legally replaying all 90 plies through the app's rules. Deliberate bad trades and cooperative play create specific coaching opportunities. The requests were generated mechanically by the production Swift request builder, with full move history; grader-only facts were kept separate.

This was a scripted position evaluation, **not another live simulator playthrough**, a game against a strong opponent, or a long adaptive learner journey. All eight probes are White-to-move positions from one line. They test basic later-game coaching, not broad endgame strength or learning effectiveness. No holdout was used. Earlier frozen benchmark and playthrough corpora remain untouched.

| Case | Game position/action | Observed across three samples |
| --- | --- | --- |
| l01 | 23.Qxc6, taking a knight with the queen | Warned that the b7 pawn can take the queen |
| l02 | 26.Rxf8, capturing Black's last rook | Correctly said the rook cannot be recaptured |
| l03 | 45.Kf2 | Explained the king's control of e2 and restriction of Black's king |
| l04 | Help at move 43, passed pawn on c6 | Suggested moving the advanced pawn toward promotion, without inventing danger |
| l05 | 44.c8=Q+ | Identified promotion and check; did not falsely announce mate |
| l06 | Help at move 46, mate available | Two useful rook-check prompts; one weaker queen-check prompt |
| l07 | 46.Rd3# staged | Correctly recognized checkmate and offered to play the move |
| l08 | 46.Qc3 staged | Correctly warned of a draw because Black has no move but is not in check |

The new tests verify legality of the full continuation, complete history preservation, deterministic export without grader-brief leakage, relevant recaptures, king control, promotion, and both terminal outcomes. An independent reviewer also checked the continuation and critical outcomes with a separate board/attack calculation.

## Representative wording and remaining quality variation

Promotion:

> Your pawn becomes a queen and checks the black king! Do you want to keep this move?

Stalemate:

> Your queen leaves the black king no moves, but no check. That makes a draw! Keep or change?

Useful mating-net coaching:

> Your pieces can work together to trap the black king. Can you try a rook move that gives check?

Weaker alternative (`l06|r2`):

> Your queen can make the black king move. Can you try a move that gives check?

The latter is true, but gives a checking exercise instead of a clear trapping goal. The judge deducted coaching judgment and discovery to 4; both independent inspections agreed it was weaker, not a factual failure. It still passes the current strong threshold, so this limitation remains visible in the text rather than disappearing behind a 100% headline.

The losing-queen warning's third sample highlights only c6 instead of the clearer b7→c6 arrow used in the first two. This is minor presentation variation, not an incorrect focus. The judge also assigned isolated 4s for a coordinate-based king explanation and a fairly explicit pawn suggestion. One saved judge rationale rambles without clearly supporting its clarity deduction; these small score differences should not be overinterpreted. Raw grades were retained unchanged, with no rerolls.

This result does not resolve the earlier benchmark's knight-defense hallucination or its inconsistent staged-feedback/requested-Hint grading policy. Those remain as documented in the [previous evaluation](2026-11-04-coaching-regression-evaluation.md).

## Latency and cost

All 24 candidate calls were **fresh full-context requests**, not stored-conversation follow-ups. Median latency was **6.28s**, nearest-rank p50 **6.18s**, p90 **13.21s**, and maximum **14.45s**. The slowest responses were mating-net Help and stalemate assessment. These figures do not measure or invalidate the earlier 2.9s follow-up median; they demonstrate that initial later-game help can still take noticeably longer.

The run made **48 successful calls**: 24 candidate responses and 24 judgments, no retries or failed transmissions. Conservative estimated total **$1.368321**, below the **$2.50 cap**, with no unknown charges. Unadjusted frozen-table estimates were $0.330309 for candidates and $0.850772 for grading ($1.181081 total). Neither estimate is an invoice total.

Reused the compatible October 31 judge qualification and today's successful 18/18 sensitivity check. Neither was rerun or charged again. The generated report displays historical qualification cost separately; it is not part of this run's spending. The final report has **no integrity issues**, and the matrix, grade IDs, journal totals, and executing source hashes were checked explicitly.

## Reproducibility and verification

Evaluated/exported source: `7dd2f1a2ee44e161e890ccb358b70df2ed1122dc`, clean at execution. Corpus SHA-256: `aedf7b42865dca2064be7e7e79a03d452e04b3d9279801a0532e62ef3c64989b`.

Candidate remains `astra-discovery-v2-low` (`gpt-6-astra`, low reasoning, `tutor-v13-discovery-v2.md`); judge remains `judge-astra-v4` using `judge-v3.md`. Exact candidate/prompt/judge/pricing hashes and executing Python file hashes are retained in the evaluation manifest. The new fixture uses the existing eight-independent-case regression format and the existing runner, grader, and report generator.

Evidence is retained in the isolated worktree under `.coaching-eval/later-game/20261104/`:

- `corpus/`: complete mechanically generated cases and source-bound manifest.
- `run.py`: exact bounded orchestration, refusing to overwrite/replay the run.
- `evaluation/candidates/`: all 24 records and full prompt/response transcripts.
- `evaluation/grades/` and `grading-checkpoint.json`: every judgment, including deductions.
- `evaluation/report/`: generated summary and aggregate metrics.
- `evaluation/evaluation.json` and `budget.jsonl`: provenance, execution status and full accounting.

See [evaluator instructions](../../Tools/CoachingEval/README.md#later-game-development-probes) for opt-in export and repeat evaluation. These new cases are available for repeated regression runs, but are **not silently added to the default two-suite paid launcher**. No paid CI or automatic runs were added.

Verification: **976 native unit tests, 354 evaluator tests, and 55 server tests passed**, zero skips. The opt-in native export then passed separately. The first new fixture test caught an incomplete hand-written promotion escape set; the expected set was corrected to all four independently verified moves before evaluation. The initial sandboxed Python run could not bind local test servers or perform process-signal tests; the unchanged suites passed outside the sandbox. No native UI test suite was run for this evaluation.

Coaching Smoke was restored to the normal dev app/server after export tests; A16 was not touched. PR #23 contains the added fixtures and report, not merged. This is development evidence, not a model-promotion recommendation.

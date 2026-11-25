# Coaching judgment experiment — November 25, 2026

## Status

**Baseline complete; prompt-only grading interrupted; Stockfish comparison prepared but not run. Nothing deployed.**

The new eval detects two of the reported problems reliably: describing a useful
rook move mainly as a warning about a different future capture, and responding
to a tactical hint request with another danger-identification question. It does
not show that the current coach is generally poor: most other cases score well.

The first prompt revision improves those two cases in the completed grades, but
also introduces a disputed endgame-plan grade. This is promising development
evidence, not yet a completed comparison or a promotion recommendation.

The API stopped with HTTP 429, `credit_balance_exhausted`. All 36 prompt-only
responses are saved; 26 have grades and 10 remain. A resumed judge call also
failed, followed by one tiny diagnostic request. No further paid requests are
being made until credits are restored.

The shared **$10 cap remains unchanged**. Its conservative ledger currently
counts **$7.2298675**, including **$0.7698000 reserved for three calls with unknown
accounting**, not confirmed charges. Completed-call conservative estimates total
$6.4600675. These are estimates/reservations, not an OpenAI invoice.

## Frozen experiment

- Twelve native-generated cases, three repetitions each, using ordinary app
  request construction and full legal move histories. Private grading criteria
  never enter candidate prompts.
- Same GPT-6 Astra/low reasoning and response contract in all arms. The unchanged
  baseline is `astra-visual-v5-low`; alternatives are `astra-judgment-v1-low` and
  `astra-judgment-engine-v1-low`.
- Primary dimension: `coachingJudgment`, 1–5. Accurate inventory without useful
  evaluation is at most 3; a concise, relevant assessment earns 4–5. Necessary
  retreats, implicit assessments, and sound non-best moves can earn full credit.
- Useful response: judgment >=4 and no severe error. The denominator includes
  **all planned responses**, not just successful or graded ones. Missing grades
  remain visibly incomplete, not assumed failures or successes.
- Report the other five dimensions independently. Do not reward longer text,
  aggression, a particular adjective, or matching the engine's favorite move.
- The existing judge-v4 configuration uses GPT-6 Astra/low. Its compatible cached
  qualification expires November 30. Controls here are implementer-authored
  sensitivity checks, **not human calibration**.

The original v1 baseline exposed two false severe-error flags: the judge read
past-tense descriptions of a visible draft as if the player had committed it.
V2 clarifies that distinction and adds a matched positive/negative control pair.
All 27 v2 checks passed. The baseline was regraded from byte-identical saved
responses; neither candidates nor board positions were rerolled. V1 remains
intact for audit.

## Results so far

| Measure | Unchanged baseline | Prompt-only revision | Prompt + Stockfish |
| --- | ---: | ---: | --- |
| Responses generated / planned | 36 / 36 | 36 / 36 | 0 / 36 |
| Valid responses | 36 | 36 | Not measured |
| Responses graded | 36 | 26 | Not measured |
| Judgment mean among graded responses | 4.53 | 4.88, **partial** | Not measured |
| Confirmed useful / planned | 30 / 36 | 25 / 36, **10 ungraded** | Not measured |
| Severe errors among graded responses | 0 | 0, **partial** | Not measured |
| API median / p90 | 3.90s / 6.70s | 3.36s / 10.15s | Not measured |
| Candidate generation estimate, total | $0.474878 | $0.526918 | Not measured |
| Candidate generation estimate, per response | $0.01319 | $0.01464 | Not measured |

Latency is non-streaming request completion, all fresh requests, not a simulated
in-app conversation. Median uses the two middle observations; p90 uses the
nearest rank. Small samples and service variation preclude a latency claim.
Candidate estimates exclude judging and use frozen `pricing-v2.json`.

| Case | Baseline judgment, repetitions 1–3 | Prompt-only judgment, repetitions 1–3 |
| --- | --- | --- |
| j01 unnecessary knight retreat | 5, 5, 5 | 5, 5, 5 |
| j02 purposeful bishop retreat | 5, 5, 5 | 5, 5, 5 |
| j03 preparing a central pawn advance | 4, 5, 5 | 5, 5, pending |
| j04 rook activity | 3, 3, 3 | 5, 5, pending |
| j05 active escape with a fork | 4, 5, 4 | 5, 5, pending |
| j06 counterplay hint | 2, 3, 2 | 5, 5, pending |
| j07 capture rather than flee | 5, 5, 5 | 5, 5, pending |
| j08 sound, non-best development | 5, 5, 5 | 5, 5, pending |
| j09 favorable exchange | 5, 5, 5 | 5, 5, pending |
| j10 costly capture | 5, 5, 5 | 5, 5, pending |
| j11 active endgame king | 5, 5, 5 | 5, 5, pending |
| j12 endgame winning plan | 5, 5, 5 | 4, 3, pending |

The revision directly teaches the rook/file-pressure distinction seen in j04.
That is a useful regression fix, **not evidence of novel transfer**. Excluding
j04: baseline mean 4.67, 30/33 useful; revision mean 4.88 among 24 graded, 23/33
confirmed useful with nine ungraded. Neither partial rate is a final comparison.

Other dimension means, baseline → revision's graded subset: chess correctness
5.00 → 5.00; latest-action responsiveness 4.83 → 5.00; discovery/independence
4.75 → 4.73; coherence/answerability 4.92 → 5.00; child clarity 4.86 → 4.85.
The subsets differ; these are descriptive, not paired treatment estimates.

### Examples, verbatim visible text

Rook move, unchanged:

> Your rook now aims at this pawn, but Black’s knight protects it. Taking that pawn next would let the knight take your rook.

Rook move, revision:

> This is a useful way to bring your rook into the game: it puts pressure on this central pawn. The pawn is guarded, so you're building pressure rather than winning it yet.

Hint, unchanged:

> This black pawn can take one of your pieces. Tap the piece that needs help.

Hint, revision:

> Try using your knight to capture this pawn. Your bishop protects the knight there, and the knight attacks Black’s queen and rook at once.

This is an explicit Hint request; a concrete suggestion is appropriate here.
The original structured messages also retain their tappable piece references.

### Endgame disagreement to retain, not tune away

The baseline points toward an unstoppable passed pawn. Two revision responses
instead describe using two rooks to restrict the lone king near the edge.
Both are sound winning plans. One judge grade accepts the rook plan as a sound
alternative (4); the other acknowledges its purpose but gives 3 for overlooking
the simpler promotion plan. Stockfish's top three moves in this position are
rook moves leading to mate in four.

The private brief expressly accepts sound alternative plans, so the 3 deserves
scrutiny: it may reflect a preference for the reference lesson rather than poor
chess judgment. Preserve the frozen grade and disclose this disagreement; do not
quietly change the brief to favor the candidate or engine. A future version needs
a matched alternative-plan control before being used as a promotion gate.

## Stockfish prototype

The benchmark-only adapter uses library-managed UCI, not a new protocol parser.
It replays full history, checks FEN, and evaluates alternatives and the child's
proposed move from the same original position. Proposed moves are root-restricted.
Scores favor the mover; mate scores and upper/lower bounds remain distinct.
Continuations are legally replayed and their SAN notation independently checked.

Frozen settings: Stockfish 18, chess 1.11.2, one thread, 64 MB hash, 200,000 nodes
per search, three candidate moves, at most five plies per displayed continuation.
Local median analysis time was 593 ms, separate from model latency. This is not
evidence about deployed-server performance or total in-app latency.

The candidate configuration explicitly requires Stockfish evidence. The runner
rejects a missing supplement or one accidentally supplied to the plain arm before
spending. Production dependencies, prompts and server configuration are unchanged.
GPL packaging and deployment are outside this prototype.

## Reproduction and retained evidence

See [the eval instructions](../../Tools/CoachingEval/README.md#judgment-focused-regression-v2)
for native export, sensitivity, bounded calls and the engine supplement. Every
arm must share the same corpus, judge, controls, qualification and budget journal.

Local artifact root: `.coaching-eval/judgment/20261125/` (git-ignored):

- `corpus/`, `baseline/`: original v1 evidence.
- `corpus-v2/`, `baseline-v2/`: clarified private briefs and regraded baseline;
  `baseline-v2/sensitivity/result.json` is reusable for the next arms.
- `prompt-v1/candidates/`: all 36 exact requests and responses; `transcripts/`
  contains rendered Markdown. `grading-checkpoint.json` retains 26 completed
  grades and both failed attempts. Resume this checkpoint, not generation.
- `stockfish-18-n200k.json`, `engine-prompts-preview.json`: frozen engine evidence
  and all 12 compiled engine-arm prompts. No engine-arm model calls yet.
- `budget.jsonl`: the single cumulative cost/reservation journal.

Important hashes:

| Artifact | SHA-256 |
| --- | --- |
| Baseline saved responses (v1 and v2 identical) | `5d5ce1dbc0abbe60c4765d1686dc94903908dd613b46147f4dbc60a0292ef6bf` |
| Revision saved responses | `7eb961fc19c49764530572881826b7da7f202748dd2a8395292777aab5ed5218` |
| Baseline system prompt | `d0e25081f9392ae6c6ad546998668ea7e238f0c80cd7615abd1514d0a0d3dd4a` |
| Revision system prompt | `60dd669106e5a92c7aa66e06abd1b5ff309f44ac6183a904042392aa4211d891` |
| Stockfish evidence | `e1aef3dc25d61042a9f6139159b6b4be1031654b4760a6238e4dbc2336260254` |
| Stockfish binary | `ae4c93fa9676ca7750d0714342fd8a5b1d018000fc6e0f6cedf112067b5ef374` |

## Verification and review

- Native unit suite: **1,059 passed, zero failed/skipped** on Coaching Smoke.
  An earlier run had one pre-existing test process killed by SIGKILL; its isolated
  rerun and the final full run passed without changing that test.
- Coaching server: **81 passed**. The pinned CI dependency assertion was updated
  to include the benchmark chess library and verify it stays out of production.
- Eval suite: **426 passed**, including rejection of a mismatched partial-grade
  checkpoint. The existing Node runtime must be on PATH for browser-core tests.
- An independent Astra review examined the whole implementation. Important fixes
  have fail-first regressions: explicit engine treatment assignment; proposed-move
  and legal/SAN validation; complete planned denominators and retained partial
  grades; loading actual corpus files when rebinding unchanged responses.
- No paid historical regression suites, UI test run, production rollout or
  family-device install were performed for this experiment.

## Decisions and limitations

1. Clarify the draft-state judge error in a versioned private brief and regrade
   identical responses. Cost: extra judging; v1 is retained to expose the change.
2. Keep Stockfish benchmark-only until it demonstrates value. Cost: deployment
   latency and packaging remain unproven.
3. Fix all four review findings in one fail-first pass; preserve the paid prompts
   and report j04 separately. Cost: this development result cannot establish
   generalization to unfamiliar positions.
4. Retain the j12 alternative-plan disagreement instead of revising the rubric
   during comparison. Cost: the current aggregate may undercredit a sound plan.
5. Do not infer efficacy before the arms finish, broad teaching value from twelve
   related development cases, or deployment readiness from local engine timings.
   Historical regression, holdout/transfer evidence and play-testing remain needed.
6. Keep issue #29 and production/iPad changes out of this branch. Cost: this work
   alone does not change what the family currently plays.
7. Preserve all unknown cost reservations and stop on exhausted credits. Cost:
   the conservative cap may stop the engine arm before all grades finish.

Deferred minor: the v2 acceptable-alternatives clarification mentions a visible
draft even on no-draft cases. Their explicit request/facts still say no draft;
make that clarification conditional in a future corpus version, not this run.

## Next action

After credits are restored, resume the ten missing grades from the existing
checkpoint under the same $10 journal, then run the engine arm only if the
remaining budget permits. Keep incomplete comparisons visibly incomplete.
Do not change the app's prompt or deploy Stockfish based on these partial results.

# Coaching experience evaluation — November 4, 2026

## Current decision

The new eight-case evaluation measured an improvement from **18/24 to 24/24
strong responses**, but broader checks then found two factual errors in V3.
**V3 is not selected. The playable development default remains unchanged.**
V4 and stricter impossible-goal controls are prepared but not quality-validated.
The user approved a **$13 total cap** for this same experiment. The continuation
is blocked by the API's separate project spending limit
(`HTTP 429`, `project_spend_limit_exceeded`, `insufficient_quota`). No V4
sensitivity judgment or candidate response was saved. The shared conservative
estimate/reservation is **$10.6339430**, including all failed-call reservations;
that is not an invoice or a claim that rejected requests were billed.

## What changed

Added eight repeatable development probes for the problems noticed during play:
false chess claims, skipping the learner's answer, premature move instructions,
unhelpfully vague goals, and generic staged-move feedback. The existing six
rubric dimensions now have explicit case-level ceilings for these failures.
Good direct feedback about an already-staged move is not confused with giving
away an unrequested answer. A requested Hint may be specific.

The cases reuse native game snapshots. Candidate input is still generated
mechanically from game state and chess rules; private grading briefs and
agent-authored expected judgments never reach the coach.

Twelve positive/negative controls, each judged three times, verify that the
judge distinguishes these behaviors before candidate spending. Both completed
control runs passed **36/36**. These are provisional, agent-reviewed reference
judgments, **not human calibration**. The judge is the existing qualified
`judge-v4` configuration; its qualification expires November 30, 2026.

## Iteration results

All configurations use GPT-6 Astra with low reasoning effort, the same output
contract, one attempt, a 30-second timeout, and stored conversation reuse. Each
of the eight cases was run three times. “Strong” means all six dimensions score
at least 4/5, with no severe error. All outputs were mechanically valid.

| Configuration | Strong | Severe errors | Fresh median | Fresh p90 | Worst wait | Verbal keep/play questions |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Current `astra-discovery-v2-low` | 18/24 | 0 | 5.52s | 11.10s | 14.98s | 9/9 |
| Experience v1 — prompt only | 20/24 | 1 | 3.64s | 5.13s | 8.10s | 0/9 |
| Experience v2 — selected-piece facts | 21/24 | 3 | 3.39s | 9.22s | 15.79s | 0/9 |
| Experience v3 — staged-board facts | **24/24** | **0** | 3.87s | 8.92s | 27.42s | 0/9 |

The baseline skipped explaining an answer and offered vague mating advice.
The stricter grader caught those omissions. V1 and V2 improved wording but
invented knight relationships; they were rejected despite higher average
scores. Every intermediate response and grade is retained.

V3's improvement is not just a stronger prohibition in the system prompt.
The native app now supplies an optional `tentativePosition`: post-move pieces,
occupied-square relationships, and the moved piece's controlled squares.
These use the app's existing pure chess rules, including promotion, castling,
en passant, and allowed staging that exposes one's own king. The shared
`chess-native-grounded-v2` prompt generator presents relevant evidence in prose
and distinguishes geometric control from a legal or favorable capture. There
is no Stockfish, second chess engine, or LLM-authored input.

The system prompt asks the coach to explain the learner's answer before moving
on, give a useful goal without prescribing a move during Help, be specific
when Hint is requested, and describe a staged move's concrete consequence.
The visible action buttons carry the keep/play decision without a repetitive
question in every message.

Examples from V3, verbatim:

> Your knight jumps toward the middle and now attacks Black’s pawn on d5.

> The black queen attacks your bishop on c4. Your pawn on d3 could take the queen back if it captured your bishop. Your bishop can fight back, too—can you try a capture with it?

> Yes, your knight is safe on c3! From there, it attacks Black’s pawn on d5.

## Broader verification: why V3 was rejected

Completed 66 further responses and 66 grades in `transfer-v3/evaluation.json`:

| Unchanged development check | Automatic strong | Automatic severe | Independent output review |
| --- | ---: | ---: | --- |
| Playthrough, 8 cases × 3 | 24/24 | 0 | No substantive issue found |
| Later game, 8 cases × 3 | 20/24 | 1 | Two factual defects, including one the judge missed |
| Two scripted 3-turn sequences × 3 | 12/18 | 0 | No factual or stale-stage issue found |

The critical later-game failure (`l06-r3`) asked:

> Your king already blocks some escape squares near the black king. Can your queen give check and leave him nowhere safe to go? Try it on the board!

That task has no answer. The native request contains the complete legal move
list: **only the rook move h3–d3 checkmates**; none of the 19 queen moves mates.
The judge incorrectly gave all 5s and claimed a queen mate existed. Both the
bad response and the erroneous grade remain unchanged in the evidence.

The second defect (`l03-r3`) said the king move takes away two escape squares,
e2 and e3. The rook already controlled e3, so this overclaims what changed.
The judge caught that one. These failures block selection irrespective of the
small-suite headline.

Some low scores in the old promotion/sequence briefs penalize the lack of an
explicit keep/play question, despite the visible buttons. The new experience
briefs deliberately permit concise direct feedback. Old scores are retained,
not retroactively rewritten to improve the comparison.

The sequences exercise actual stored-conversation follow-ups, but use fixed
scripted events, not a response-conditioned learner journey. No holdout prompts
were sent to models. All three reports have zero integrity issues.

These are broader development checks, not an independent unseen holdout:
some source positions also appear in the stricter experience probes. The
standard report correctly makes **no automatic promotion recommendation**.
A local trial decision must not be described as production qualification.

## Prepared correction and a stronger judge control

V4 uses `chess-native-grounded-v3`, which derives the identities of pieces with
a legal mate in one from existing native `legalMoves` flags. It does not render
the mating destination. When no mate in one exists it says so explicitly; this
does not forbid longer-term trapping goals. No committed-board mating facts
are rendered after a tentative move. The prompt forbids an impossible
piece-specific mating task and distinguishes current control from newly
removed escape squares.

Experience-v2 grading briefs add the mechanically derived **complete** legal
mate-in-one set. `judge-experience-v2.json` preserves all 12 prior controls and
adds the exact impossible queen question plus an achievable rook contrast.
The ordinary regression command now requires this stronger gate. The global
judge-context projection and existing judge qualification are unchanged;
the new corpus/control hashes require fresh sensitivity evidence. V1 artifacts
remain frozen. V4 has no quality score yet, and must not be selected merely
because these code changes look plausible.

### Approved continuation: provider quota blocker

The fresh `corpus-v3` export passed from clean source `740ffe9`. All eight
candidate requests exactly match `corpus-v2`; only e06's private complete
mating evidence/severe criterion and the source-trace version changed. The
new 42-judgment sensitivity gate must pass before generating V4 responses.

Three explicitly tracked attempts stopped on the first judge call, with no
saved scores or candidate outputs. The initial wrapper discarded the provider
detail; the first diagnostic recovery established HTTP 429, and the final
diagnostic established `project_spend_limit_exceeded`. No automatic retries
are enabled. A non-billable model-list check was denied by the key's restricted
scope, and an empty invalid Responses request correctly returned HTTP 400;
neither is evidence of a model-quality failure.

All three attempts and their full conservative reservations are retained.
Paid work is stopped until the project's limit is raised. Continue with the
same journal and $13 cap; do not overwrite these directories. Within the
remaining allowance, prioritize the later-game failures after the new gate
and small-suite scoring. Any broader responses reviewed without automatic
grading must be labeled as such, not included in an automatic score.

## Latency remains a rough edge

V3's experience-suite median and p90 improved in this sample, but its worst
wait worsened to **27.42 seconds**, with another response taking 17.63 seconds.
Five of 24 fresh requests exceeded the diagnostic five-second target. This
does not establish a causal speed improvement or solve tail latency.

Broader V3 measurements: playthrough fresh median 3.28s/p90 4.04s; later-game
fresh median 5.54s/p90 15.19s/max 21.57s. The 12 sequence follow-ups had median
2.67s/p90 3.10s/max 3.18s, with two above 3s. These are V3 measurements, not
promises about the untested V4.

`ExperienceMetrics` reports median, p90, maximum, and over-target counts
separately for fresh requests (5s diagnostic target) and conversation
follow-ups (3s). Failed and invalid calls remain in latency measurements;
blocked, never-sent sequence rows are counted separately, not as 0ms replies.
Verbal keep/play-question counts are a copy diagnostic, not a semantic grade.

## Repeatability and provenance

The standard paid regression entry point now exports and runs the experience
suite before the existing playthrough/original development suites, after both
sensitivity gates pass:

```sh
./scripts/run_coaching_regressions.sh
```

It uses Keychain credentials, requires a clean source tree, records source and
prompt/configuration hashes, defaults to a conservative $10 cap, and retains
partial evidence/checkpoints if interrupted or budget-limited. It does not
silently expand the budget or run paid models in CI. A fresh invocation is a
new experiment, not a way to resume an interrupted one by replaying calls.

For a small prompt comparison, use the dedicated `experience` workflow in
`Tools/CoachingEval/README.md`: new output directory for each revision, the
**same budget journal** for the entire iteration, sequential execution, and
explicit candidate configurations. Reuse sensitivity only with exact matching
corpus/control/judge hashes.

All local evidence is under
`.coaching-eval/experience/20261104/` in this worktree:

- `budget.jsonl`: cumulative spending/reservation journal for every paid call.
- `corpus/`, `baseline/`: stopped diagnostic run, retained unchanged. Review
  discovered the old exporter discarded private authored facts; no candidate
  responses had been generated. One interrupted request remains reserved.
- `corpus-v1/`, `sweep-v1/`: corrected frozen rubric, baseline and V1 results.
- `sweep-v2/`: rejected V2 results, with compatible sensitivity reused.
- `corpus-v2/`, `sweep-v3/`: optional native staged-board evidence and V3 results;
  sensitivity rerun because the corpus hash changed.
- `playthrough-corpus-v2/`, `later-game-corpus-v2/`, `benchmark-corpus-v2/`,
  `transfer.py`, `transfer-v3/`: exact broader-check inputs, orchestration,
  responses, grades, and reports.
- `verify_exports.py`: executed equivalence check across all four exports.
- `corpus-v3/`: V2 private mating evidence, with unchanged candidate requests.
- `run-v4.py`, `sweep-v4/`, `sweep-v4-recovery/`, `sweep-v4-diagnostic/`:
  continuation orchestration and stopped manifests. The retained script now
  prints only bounded provider error metadata; it refuses to overwrite the
  existing destination and must not simply be rerun.

The refreshed exports have identical old request fields, grading briefs,
old-generator rendered prompts, and judge contexts. Only optional
`tentativePosition` evidence was added. This preserved baseline comparability
without rerolling it. V1 grading criteria stayed frozen throughout the V1–V3
comparison; the subsequent V2 evidence/control revision is separately labeled
and must not silently replace the historical grading basis.

V3 execution/export source: `e4ed9571cb4d5c96255fc068f915a0afff67c6de`.
Candidate configuration: `astra-experience-v3-low.json`.
Model configuration SHA-256:
`7be9df4d25592c5c626db56156ff2fb487bd80fc11ec7c9c8a74b83ede9b6c22`.
System prompt SHA-256:
`aeec6f98609a2913e169bb3d28b646a8a13c2562b9cbd5e1e10471bdbecfc84e`.
The manifests retain full corpus, judge, pricing, and executing Python hashes.
Pricing is the frozen September 6 estimate, not a current-price or invoice claim.

The $10.6339430 cumulative estimate includes failed intermediate candidates,
all completed sensitivity/transfer grading, the original interrupted-call
reservation, and three new full reservations for failed continuation calls.
The continuation added $0.9705375 of reservations, not confirmed charges.
It is not a provider invoice. No extra spending is authorized by creating a
new output directory or journal; the user-approved cumulative ceiling is $13.

## Verification and deployment

Final V4-code verification: **983 native, 368 evaluator, and 56 server tests
passed, zero failures/skips**. Native result bundle:
`DerivedData/Logs/Test/Test-ChessTutor-2026.11.04_14-39-34--0500.xcresult`.
Tests cover
native post-move evidence and special moves, backward-compatible requests,
shared live/eval compilation, private-fact preservation, sensitivity gates,
budget persistence, failure records, and timing/repetition diagnostics.
The full UI test suite was not run locally.

After the quota-blocked continuation, the unchanged code again passed all
368 evaluator and 56 server tests (zero failures/skips), and the normal
Coaching Smoke app/server rebuilt, launched, and returned a healthy status.
Python and iPad CI both passed on the V4 code commit `740ffe9`.

Independent review found no remaining Important code issue in the V4 checkpoint;
all 14 controls bind mechanically, V1 controls are preserved, the pinned config
loads, and private grading evidence/mating destinations stay out of candidate
input. This is code review, not paid judge sensitivity or model-quality validation.

Old clients remain accepted by the new server, but old servers need not accept
the new optional request field. Rebuild the iPad app and update the server
together (the development launcher does both). Production model configuration
is unchanged. An explicit `CHESS_TUTOR_COACHING_MODEL_CONFIG` override is
preserved; the previous trial is
`Tools/CoachingEval/benchmark/configs/models/astra-discovery-v2-low-model.json`.

PR #23 remains open. The normal development app/server is restored on
**ChessTutor Coaching Smoke**, with the existing discovery-v2 trial selected;
A16 was not changed. No paid V4 model request was made during restoration.

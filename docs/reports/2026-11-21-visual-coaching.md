# Visual coaching — local preview

## Experience

- Underlined piece/square phrases spotlight the displayed board locally.
- Requested move hints carry directional arrows; knights use an L-shaped path.
  Revising a draft points from the staged piece toward the alternative square,
  while validation uses the original legal move.
- Piece-answer questions have a quiet board edge, neutral immediate tap feedback,
  and a local **Play instead** escape. Dragging also supersedes the question.
- Questions remain understandable while answers are pending. The merged #27
  scheduler coalesces rapid answers; references/replay/escape make no API calls.
- Unrelated coverage is quiet during help; king/check and move legality guards
  remain. Large-text wide panels use two columns for reachable controls.

The native session owns all interaction state. The UI only presents validated
content and local actions. There are no additional mode headings or board pills.

## Contract and rollout

The installed v3 client retains its existing server configuration and text
contract. The preview client requests v4/v14 structured runs and one optional
arrow. Python and Swift share acceptance/rejection fixtures; refs use displayed
pieces, attack arrows use directed displayed relationships, and move arrows use
legal committed-position moves. Discovery questions cannot expose their answers
through links or arrows; an explicit Hint may point to one source clue.

Server-first rollout is documented in [the runbook](../hosted-coaching-server.md).
This work does not deploy production or install the family iPad. Preview using
`./scripts/run_hosted_coaching_dev.sh "ChessTutor Coaching Smoke"`.

## Evaluation evidence

The native-generated suite has eight groups / ten turns, each run three times.
It covers both colors, two same-kind pieces, wrong/correct board answers, a
source clue, requested move hints, a staged knight revision, defended targets,
and opening tradeoffs. The rubric remains unchanged. Eighteen semantic
sensitivity judgments plus the shared hard-validation fixtures guard the new
visual behavior. These are agent-authored controls, not human calibration.

Initial visual-v1: 30/30 mechanically valid, 28/30 strong, no severe flags.
Two hints gave away both the threatened piece and its destination. Visual-v2
corrected that and scored 30/30 strong, but manual output inspection found only
one of six specific move hints supplied an arrow. This was a real acceptance
gap despite the prose grades. A separate repeatable check now requires move
arrows for those two requested-hint fixtures; it is not conflated with the
judge's semantic score. Visual-v3 adds that requirement and keeps the current
draft playable while suggesting a revision.

All iterations share one durable **$10 cumulative cap**, including an unresolved
$0.323075 reservation from an interrupted qualification request. Cached judge
qualification was compatible and unexpired; the initial cache lookup used the
wrong directory convention and briefly started redundant qualification calls.
Those calls and the interrupted reservation remain in the ledger, not erased.

Artifacts are under `.coaching-eval/visual/20261121/`: `corpus-v1`,
`validation-v2` (prompt v1), `validation-v3` (prompt v2), `validation-v4`
(prompt v3), and `budget.jsonl`. V1's first report used the old hardcoded
eight-turn regression inventory and correctly reported an integrity failure;
the explicit visual manifest now binds the ten-turn inventory. Failed/diagnostic
artifacts remain unchanged. Configuration/prompt hashes and execution file hashes
identify exactly what ran; early corpora were exported from a working snapshot.

Final visual-v3 targeted run: **29/30 completed and mechanically valid; all 29
completed answers graded strong**, with no severe content flags. Five of the six
requested move-hint attempts completed; all five supplied the required arrow.
The sixth returned an incomplete provider response. It remains a failure, not a
rerolled success; the aggregate therefore reports 96.7% strong/valid and incomplete
cost accounting. Its p90 latency, including that failed attempt, was 5.15 seconds.
This is a development regression result, not a production promotion certificate.

The interrupted run resumed only its seven unattempted candidate cells. Completed
and failed records kept their original latency and usage. The old dry preview
(which incorrectly rendered follow-ups as initial prompts) is retained separately;
dry previews now use exactly the same compiler as the paid runner. Resume checks
input/configuration/schema bindings, restores sequence continuations, and refuses
to replay an unknown in-flight candidate automatically.

The broader frozen playthrough suite produced **23/24 valid, strong replies**;
one transport failure remains in the denominator (p90 3.93 seconds). The frozen
later-game suite produced **24/24 valid, strong replies, no severe flags**
(p90 4.20 seconds). A failed playthrough judge call was resumed from its checkpoint
without regrading completed cells; its unknown-charge reservation remains counted.
The additional six-turn conversation subset is diagnostic, not a holdout.
Its candidate sweep stopped before attempt 18 of 18 because the next conservative
reservation would exceed the approved cap; 17 attempts are retained and ungraded.
Do not treat that partial sweep as passing. The targeted suite's separate
three-turn answer sequence was completed and graded in all three repetitions.

Final ledger: **$9.703365 estimated/reserved against the $10 cumulative cap**,
with four unresolved reservations (the early interrupted qualification, incomplete
candidate, transport-failed candidate and failed judge call). This is deliberately
conservative, not an assertion that the provider invoiced that amount. No further
automated paid validation was started after the cap guard stopped the sweep.

## Verification and design decisions

Observed RED→GREEN coverage includes typed reference validation, stale draft
origins, source/target arrow geometry, local replay/expiry, answer handling,
coverage suppression, wide large-text control bounds, and local diagnostics.
Native UI tests exercise actual reference buttons, local escape, and a drag
while a delayed answer is in flight. Motion-policy tests exercise the actual
renderer with Reduce Motion enabled/disabled; no test claims to toggle the
simulator's read-only system preference.

Final local verification: **81 server tests, 401 evaluation tests, 1,044 native
unit tests and 16 UI tests passed**. The complete native run exposed duplicate
VoiceOver routine announcements in the legacy panel; after restoring that panel's
semantic header, all 16 UI tests were rerun and passed. A final 24-test runner
check also passed after making the in-flight marker durable before transmission.
The Python suite needed the machine's installed Node 22 on PATH, not its obsolete
system Node; no tests were skipped to accommodate that environment issue.

The independent review found five important gaps, all addressed in one fix pass:

- Board answers now resolve displayed draft pieces, including captures; empty old
  origins do not create answers. The v4 compiler prioritizes the latest answer
  event over a previously selected mover without altering the v3 compiler behavior.
- Protocol-tagged continuation handles reset v3/v4 cross-version context.
- VoiceOver reference values identify the actual piece/square; Replay describes
  arrow direction and draft relocation even while a linked reference is focused.
- Actual ±90-degree panel tests verify semantic order, target values, local
  activation and contained 44-point targets. Full-screen native captures confirm
  the layout; app-only rotated screenshots were cropped by the test framework.
- Candidate resume, cumulative journal reuse and exact follow-up previews are
  repeatable and tested. Provider/judge failures retain cost reservations.

The reviewer delivered these findings before its session ended; there was no
second review or claim of a post-fix reviewer sign-off. Accessibility hierarchy
and actions are automatically tested; spoken VoiceOver audio was not manually
audited. The app mechanics remain usable if a provider call fails.

Retained local evidence: `.coaching-eval/visual/20261121/` contains the exact
corpora, full prompts and responses, budget ledger, versioned reports, migration
script, execution notes and native full-screen screenshots. The preview launcher
is running against this worktree's local server; the initial playable board was
verified on **ChessTutor Coaching Smoke** without an extra paid Help request.

Answer taps deliberately do not also select a piece to move. Play instead or a
drag restores normal movement; an intentionally preselected move destination
still supersedes a question. Reference focus expires after two seconds using an
episode/pulse identity, so an old expiry cannot clear newer focus. These timing
and interaction choices remain play-testable, not immutable UX conclusions.

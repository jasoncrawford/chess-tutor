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

Final verification and broader guardrail results are recorded below when complete.

## Verification and design decisions

Observed RED→GREEN coverage includes typed reference validation, stale draft
origins, source/target arrow geometry, local replay/expiry, answer handling,
coverage suppression, wide large-text control bounds, and local diagnostics.
Native UI tests exercise actual reference buttons, local escape, and a drag
while a delayed answer is in flight. Motion-policy tests exercise the actual
renderer with Reduce Motion enabled/disabled; no test claims to toggle the
simulator's read-only system preference.

Answer taps deliberately do not also select a piece to move. Play instead or a
drag restores normal movement; an intentionally preselected move destination
still supersedes a question. Reference focus expires after two seconds using an
episode/pulse identity, so an old expiry cannot clear newer focus. These timing
and interaction choices remain play-testable, not immutable UX conclusions.

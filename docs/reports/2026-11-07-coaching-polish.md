# Coaching polish for the next family playtest

The local launcher and repeatable regression runner now select
`astra-experience-v6-low`. Model, low reasoning, conversation reuse, native
prompt generator, and UI response contract are unchanged. The new versioned
system prompt prioritizes the useful consequence or tradeoff of a staged move
and uses calm, specific language instead of cheerleading. Production defaults
and explicit launcher overrides remain unchanged.

The first visual pass added a small lightbulb badge. The visual follow-up below
supersedes it. Feedback keeps its 18-point body typography; controls and game
flow are unchanged.

## Focused response check

Each case ran three times using native exported requests and the existing
candidate runner. Independent agent review covered every retained response.
These are development diagnostics, not automatic candidate grades or a repeat
of the full November 4 evaluation.

| Check | Previous V5 | Revised V6 |
| --- | --- | --- |
| Quiet Black h6 and White a3 opening tradeoff | 0/6 explained the tradeoff | 6/6 explained the center/development tradeoff |
| h3 usefully attacking a bishop | Not rerun | 3/3 explained the attack and possible exchange |
| Central e4 feedback | Not rerun | 3/3 calm, concrete explanations |
| Selected defended bishop, mating goal, staged stalemate | Not rerun | 9/9 without substantive factual, agency, or interaction defects found |

All 21 V6 responses were mechanically valid, contained no exclamation marks,
and avoided repeated keep/play questions. This does not establish a measured
tone improvement over a celebratory baseline: the six baseline replies also
contained no exclamation marks.

All requests were fresh, not stored-conversation follow-ups. V6 median latency
was 3.12 seconds; p90 was 8.95 seconds and maximum 9.45 seconds. All three
mating-goal replies took about nine seconds. Remaining wording roughness:
some formulaic tradeoff phrasing, one pronoun-heavy exchange explanation, and
one uppercase “AND.” No broad latency or conversation-reliability claim follows
from this sample.

## Repeatability

Experience manifest v4 appends four cases to the unchanged original nine:
quiet flank moves on both colors, a purposeful flank move, and calm central
pawn feedback. Tests replay the complete legal history, verify resulting pawn
control and bishop paths, and ensure private grading criteria do not enter the
candidate request. These are independent board-based probes; they do not inject
an invented prior coach utterance.

Six new positive/negative judge controls distinguish useful tradeoffs from
incidental facts, recognize the purposeful flank-pawn exception, and distinguish
calm feedback from excessive celebration. The unchanged qualified judge passed
all **18/18** focused checks. These agent-authored controls are not human
calibration. The full v4 gate has 66 judgments and was not rerun; focused
evidence cannot substitute for it. Saved v3 exports retain their compatible v3
controls, and earlier scores are not relabeled as V6 scores.

The normal `scripts/run_coaching_regressions.sh` entry point exports all 13
experience cases and evaluates the same local candidate. It includes the full
sensitivity gates, latency/cost records, and new visible-message/exclamation
counts. Paid evaluation remains opt-in, never part of CI.

## Evidence and cost

Ignored evidence is retained in `.coaching-eval/polish/20261107/`:
`corpus-verified`, `baseline`, `polish`, `transfer`, and `new-controls`.
`run.py` and `check-controls.py` preserve exact replay logic, source/configuration
hashes and spending metadata. The source was exported as `f81f175-dirty`, with
the native fixture file hash recorded separately; it is not misrepresented as
an immutable clean revision. The earlier `corpus` export has an empty source
identifier, was rejected before any paid call, and was not used.

This check added **$0.709988** to the existing conservative ledger, ending at
**$20.4584475**, below the authorized cumulative $21 cap. Earlier unknown-cost
reservations remain included. These are dated price-table estimates, not invoices.

Verification: all 1,000 native tests passed with no failures or skips, along
with 57 server tests and 373 evaluation-tool tests. After the full native run,
test-only refinements extended the snapshot fixture's thinking delay and used
landscape screen captures; the focused hosted tests and final landscape test
passed. Thinking and ready panel screenshots were visually checked. Independent
code review found no remaining actionable issues.

## Visual follow-up

After play-testing, the small, light heading and subtle icon pulse did not give
the panel enough hierarchy or make waiting apparent. This revision changes only
presentation, not coaching content, prompts, evaluation configuration or flow.

Design: a dark 24-point semibold serif Coach heading, paired with a prominent
felt-green lightbulb, above the existing 18-point rounded body text. Both text
sizes scale with Dynamic Type. The existing palette stays intact: paper
`#F2EDE0`, ink `#21211C`, walnut `#594733`, felt `#426E59`, and sand `#E8D6AD`.
The initial board mark was replaced with a lightbulb at the user's preference,
without returning to the small, faint badge. No extra container, border, or
accent color was introduced. Advice stays left aligned.

Waiting replaces the visible “Thinking…” sentence with three felt-green tiles
that rise in sequence, centered in the open reply area between the heading and
buttons. A bounded 30-fps SwiftUI timeline runs only while that
view exists. Reduce Motion pauses the timeline and leaves a static, visible
indicator; VoiceOver still reads “Thinking.” Existing routine chips remain
available in local coaching, and actions are unchanged.

Regression checks measure real rendered heading/body glyphs, compare successive
frames in the reply area, exercise both motion preferences, and check the
thinking-to-response transition. They also measure the visible tiles' center in
the reply area and the matching accessible indicator's position. The previous
design failed the heading, motion, and centering checks before their respective
implementation changes. Screenshots verify
the visual result; no paid model requests are needed for this visual-only work.

Final verification after the lightbulb and centering refinement: all **1,004
native tests passed**, with zero failures, skips, or runtime warnings, including
the rendered motion, centering, and Reduce Motion checks. The focused panel and
hosted-continuity run also passed (19 tests). Thinking and ready screenshots were
visually checked. The preceding visual revision had an independent read-only
review with no remaining actionable issues.

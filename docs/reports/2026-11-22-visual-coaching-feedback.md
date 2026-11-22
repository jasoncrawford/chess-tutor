# Visual-coaching play-test corrections

Follow-up to PR #28, based on the November 22 screenshots and interaction report.

## Changes

- **Readable inline references:** native attributed prose replaces indivisible,
  minimum-44-point buttons and the custom word flow. Linked phrases wrap like
  ordinary text. Small inline piece images are removed; descriptions and local
  highlighting still identify the targets. TextKit supplies layout, native link
  interaction and accessibility; named highlight actions expose board targets.
- **Unambiguous draft commit:** the v4 action says “Play my move”, and its spoken
  description names the actual staged piece/destination. The suggested arrow
  remains guidance, never an implicitly selected replacement move.
- **Visible board-answer mode:** a felt-green instruction banner sits outside
  the square grid, in the reader's orientation. It derives from the expected
  action, not from parsing model prose or revealing the answer.
- **Visible response progress:** answering shows the existing centered animated
  tiles with “Checking your answer…”. The board still accepts replacement
  answers; dragging, Play instead, and Close help remain available.
- **Named replay:** “Show arrow” replaces the unexplained header icon. It restores
  the existing arrow locally, without changing the game or sending a request.

The model's chess-coaching policy is unchanged. Visual-v4 is a separately pinned
prompt/config/candidate that renames the control and explicitly distinguishes
the child's draft from a suggestion. The benchmark default and deployment bundle
include the same revision; old v3 artifacts remain reproducible.

## Regression evidence

The original renderer used 149.5 points for a screenshot-derived paragraph that
ordinary prose fit in 81.5 points (228-point width, 17-point text). The regression
test failed at all six width/font combinations before the change, then passed.
Reference tests check actual highlighted squares, not only unchanged request
counts. Native link activation is deferred, so UI tests wait for its visible effect.

A staged c2–c3 with a suggested e2–e4 is tested through the real GameSession:
the control identifies the pawn going to c3 and committing it actually plays
c2–c3, leaving the e-pawn untouched. The old label/description failed first.
Banner and pending-animation tests also failed before the correction.

Independent review found that removing the banner during a drag changed square
geometry beneath the finger. A fixed-screen-coordinate a7–a8 rook drag reproduced
the wrong destination. The fix retains the drag's original board layout through
drop and settling. This adds a regression at the upper edge, beyond the previous
b1–c3 case.

## Verification status

- 49 focused native unit tests and the initial four visual UI tests passed.
- 81 server tests and 401 offline evaluation tests passed. The deployable-bundle
  test caught omitted visual-v4 resources; the manifest was corrected and the
  server suite rerun successfully.
- Seven visual UI regressions passed after the drag fix, including long wrapped
  references, all four banner rotations, pending answers, and the edge drag.
  Full-screen screenshots reviewed: natural line spacing and wrapping; readable
  banner outside all squares; centered checking feedback; wide large-type controls.
- Full native suite: **1,048 unit tests and 19 UI tests passed, zero failures**.
  This is the final code after the independent review's drag fix.
- No paid model calls. A free prompt export uses the current visual candidate;
  ten exact prompts were exported. No new live model-quality score is claimed
  for the label-only prompt revision.

Local artifacts: `.coaching-eval/visual/20261122/`. Historical quality results and
their limitations remain in [the original report](2026-11-21-visual-coaching.md).

## Review follow-ups

Two non-blocking coverage improvements were deferred: make the judge's UI-control
metadata conditional per turn and explicitly authoritative over legacy generic
wording; add direct tests/physical-device VoiceOver review for the named target
actions. Native link names, reading order, tap effects, and local-only behavior
are automated here; a physical-device VoiceOver pass is not claimed.

## Rollout

This remains the local Coaching Smoke preview on PR #28. No production server
deployment, Family iPad installation, merge, or auto-merge is part of this change.

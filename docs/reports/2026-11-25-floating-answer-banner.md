# Floating answer banner

Follow-up to PR #28: the board must stay in place when the coach asks the player
to tap a piece. The former layout reserved space for the banner, shrinking and
offsetting the whole grid.

The instruction now floats across the reader's top edge. It uses up to 20 points
of the existing gutter, with the rest overlapping the board. The warm translucent
background, green hand icon, and compact width keep the instruction readable;
Reduce Transparency makes the background opaque. No additional copy or controls.
The overlay does not intercept touches. Board, pieces, paths, and drag hit testing
retain the same size and origin whether the prompt is present or absent.

The previous reserved-space approach was rejected because it moves destinations
under the player's finger. A banner wholly inside the board would obscure more
of the back rank; a banner wholly outside would require additional gutter space.
The bounded overlap works in all four reading orientations and at large text sizes.

Regression coverage compares actual on-screen piece frames before/after leaving
answer mode, taps pieces through the overlay, and retains the edge-drag test.
This is presentation-only: no model, prompt, network, or coaching-flow changes.
No paid API calls or production/device rollout are needed.

## Verification and review

Before the fix, both the geometry regression and the real UI frame-comparison
test failed (16 assertions each), reproducing the reported shrink/shift. After
the fix, the focused run passed 22 unit tests and eight UI tests. Screenshots
were inspected at ordinary text size and at accessibility text size in all four
reading orientations. The banner remains readable and within the existing
gutter. Two simulator-system crash reports were attached (DockFolderViewService
and SpringBoard), not ChessTutor crashes; the UI run completed successfully.

Independent read-only review found no critical or important defects. Its
suggestion to test dragging from beneath the overlay was added to the tap-through
test: the covered white king can be dragged while an answer is pending, landing
on the pre-dismissal destination. The other suggestion, checking narrower banner
width, was visually verified; the geometry unit test deliberately uses a
conservative full-width rectangle to check the gutter limit.

Unchanged server and offline eval suites also passed: 81 and 405 tests. No live
model quality run or physical-device accessibility test is claimed.

The final full native run, including the added under-banner drag, passed **1,053
unit tests and 20 UI tests**, zero failures or skipped tests. Logs:
`/tmp/coaching-banner-full.log`; focused screenshots:
`/tmp/coaching-floating-banner-shots/`. Independent review and visual QA are
complete. The change remains on PR #28, with no merge or production rollout.

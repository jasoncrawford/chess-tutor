# Saved-game tap investigation (#29)

## Requirement

A single tap on a saved-game card must open that game. Coaching must still work
on the reopened board and after relaunch. Do not retry a failed tap, lengthen its
contact, disable transitions, or relax the end-to-end assertions to hide a miss.

## Original evidence

The failed iPad job was
https://github.com/jasoncrawford/chess-tutor/actions/runs/45673879163/job/139416114956
at commit `396ffa285742d5a5f3c40877f1c0c0a7cf6f83d1`.
The unchanged rerun passed. The exported event contains a stationary 50 ms
contact at portrait coordinates `(297, 348)`, equivalent to landscape
`(832, 297)`, inside the expected card. The failure hierarchy still contains
both saved cards and no modal. The recording stays on the rack.

The current route is synchronous: the card Button calls `openGameEntry`, then
`openLocalGame`, then `GameLibrary.showBoard`. The button uses a custom pressed
scale/opacity style within a scroll view, and the rack/board swap uses a spring
transition. Those are hypotheses to investigate, not established causes.

## Reproduction plan

1. Repeat the original reopen/relaunch UI test unchanged on the local iOS 26.5
   simulator before changing app code.
2. Exercise twelve alternating saved-card center contacts of 50 ms through the
   real rack, board, and coaching provider. Each must open on its first contact;
   coaching must identify the selected saved UUID.
3. If neither reproduces the failure, add opt-in button/scroll/route diagnostics
   and retain them in failure attachments. Leave app behavior unchanged until
   an event sequence identifies the cause.

Local builds use Xcode 27.2; the failing CI job used Xcode 26.6 and iOS 26.5.

## Reproduction results and diagnostics

On main `259dce8`, ten unchanged original reopen/relaunch repetitions passed.
The twelve-contact alternating-card test also passed before any app changes.
The diagnostics export smoke failed before instrumentation (missing export),
then passed after instrumentation. No app behavior fix is established.

The original test and the new twelve-contact test enable `-trace-game-navigation`
inside the existing Debug-only, UUID-scoped managed-games fixture. XCTest
teardown captures the current hierarchy, captures the screen on failure, then
relaunches the same run with `-dump-game-navigation`. This dump bypasses the root
view and attaches `Saved-game navigation events` to the result bundle. Existing
reopen, relaunch, selected-game coaching, and first-contact assertions remain.

The trace is JSONL in the fixture's temporary directory. Each event has a wall
clock timestamp, process ID, per-process sequence number, event name, and fields.
Writes complete synchronously before returning so termination does not discard
queued log tasks. Sequence numbers restart in each process; use the process ID
and timestamp to distinguish the ordinary relaunch from the first launch.
Trace write errors go to the app console; export reports read errors explicitly.

Interpret a future failed tap alongside XCTest's synthesized-event attachment:

- `hitTest` at the target's window coordinates means UIKit traversed the passive
  probe. The probe always returns nil and adds no gesture recognizer. It does
  **not** prove the Button received the whole touch or was the final hit target.
- `card.pressed` records SwiftUI's observed pressed state for that card UUID.
  Compare it with `open.request`; a missing action after a press focuses the
  investigation on recognition/cancellation rather than route selection.
- `rack.scroll` records scroll phase changes. A tracking phase alone is not
  proof that scrolling cancelled the button.
- `open.request` and `open.complete` record the selected card and the route
  before and after the synchronous handler. `route.changed` records SwiftUI's
  observation of the resulting route; `rack.appear`/`rack.disappear` show the
  rack lifecycle. These separate an action miss from a routing/rendering issue.

The dedicated integration smoke holds its contact for 300 ms to make the
transient pressed state observable; the two failure reproductions retain 50 ms
contacts. It correlates hit-test coordinates, pressed state, card UUID, and
ordered open/route events using the real saved-card button, then
exports after process termination. Other UI tests exercise the opt-in-off path.
Release builds exclude the trace recorder, probe, and event hooks. Logging can
perturb timing; passing instrumented tests does not establish a fix or disprove
the intermittent failure. The underlying issue remains open pending a captured
failure that establishes the cause.

Local artifacts:

- `/private/tmp/chess-issue29-baseline.xcresult`
- `/private/tmp/chess-issue29-short-taps.xcresult`
- `/private/tmp/chess-issue29-diagnostics-red.xcresult`
- `/private/tmp/chess-issue29-diagnostics-green.xcresult`

## Final verification

- Full native suite: 1,054 unit tests and 22 UI tests passed, zero failures,
  zero skipped tests, and no runtime warnings in the result summary.
- After the final XCTest teardown, diagnostic-smoke, and error-reporting changes,
  all three affected UI tests passed again. This verifies failure-export
  registration on the ordinary path, reopen/relaunch, and twelve short contacts.
- Release simulator build passed for arm64 and x86_64.
- Exported the repeated-contact test's actual result-bundle attachment: twelve
  open requests, twelve completions, 24 pressed-state changes, and two saved UUIDs.
- Independent review found no remaining material findings after switching from
  Swift defer to XCTest teardown blocks and correlating the diagnostic smoke
  with the selected card rather than generic navigation events.

Full result: `/private/tmp/chess-issue29-full.xcresult`.
Final affected-test result: `/private/tmp/chess-issue29-final.xcresult`.
Release build log: `/private/tmp/chess-issue29-release.log`.

These results validate the diagnostics and retained requirements. They do not
establish a behavioral fix for the original intermittent CI failure.

## Bounded focused CI campaign — November 26

PR #30 merged at `830f07c47b3378f3a4772266fe432db67e3cedb5` with user approval.
The follow-up experiment uses the existing workflow's manual `saved-game-stress`
mode on Xcode 26.6 / iOS Simulator iPad (A16). Regular PR and default manual runs
still execute the full suites.

```bash
gh workflow run tests.yml --ref codex/saved-game-tap-stress -f mode=saved-game-stress
```

The job has a hard 30-minute timeout. Its runner budgets 24 minutes for one build
and focused execution, reserving time for interruption/finalization and artifact
upload. It runs the original reopen/relaunch test once, then eight combinations:
tracing on/off, immediate/settled card lookup after returning to Games, and idle
versus up to two CPU load workers. Each matrix case retains twelve alternating
50 ms contacts, selected-game coaching checks, and first-attempt assertions.
No failed test or contact is retried; the campaign stops at the first failure.

“Immediate” removes the explicit per-contact existence wait; XCTest still applies
its normal event synchronization. “Settled” retains the existing wait. The first
contact in both profiles follows the initial two-card setup wait. These profiles
do not promise a precise wall-clock interval after the transition; use the
recorded event times when interpreting a failure.

The runner builds once, then supplies per-profile test-host environment variables
in sibling xctestrun files so `__TESTROOT__` stays valid. A host-side marker verifies
that the selected trace/timing values actually reached XCTest. Untraced cases
retain hierarchy/screenshot capture but omit the logging overlay and trace dump.
Loaded cases start at most two separate CPU workers and clean them up after the
case. Timeouts interrupt and then kill the complete xcodebuild process group,
including descendants whose leader has already exited.

The `SavedGameTapStress` artifact contains per-command logs, xcresult bundles,
and `summary.json`. The summary distinguishes a test failure, harness error,
timeout, budget exhaustion, and a fully completed matrix. A capped or partial
matrix is not evidence that the bug is fixed. Build products are excluded from
the upload. Every stress outcome uploads available results.


The first focused attempt (run 45863623544) spent 359 seconds of CI job time.
Build-for-testing passed in 64.65 seconds. A mistaken 240-second per-case guard
then interrupted cold simulator startup as the app was launching; no card touch
or saved-card assertion had occurred. This is a harness timeout, not a reproduction
of #29. The uploaded summary and baseline log preserve that distinction.

The final attempt removes the per-case guard and retains the overall deadline.
For this dispatch, the workflow hard limit is reduced to 23 minutes and the
build/execution budget to 17 minutes, preserving six minutes for cleanup/upload.
Together with the first attempt, the maximum active CI job time stays below the
user's aggregate 30-minute cap. No further stress dispatch is authorized under
this campaign after that attempt. Report any omitted profiles as incomplete.


The second attempt (45865010767) failed before test execution: Xcode reported no
available iOS simulator destination. Its CI job took 81 seconds; build selection
failed after 67.51 seconds. No saved-card contact or assertion ran.

The next attempt explicitly inventories runtimes and creates a dedicated iPad
(A16) on `com.apple.CoreSimulator.SimRuntime.iOS-26-5`, then selects its UUID.
It fails clearly if that original runtime is unavailable, without downloading
or substituting a different OS. Provisioning has a two-minute step timeout.
Its hard job cap is 20 minutes, with a 16-minute build/execution budget; remaining
time covers provisioning, cleanup, and upload. Combined configured active-job
limits are 359 + 81 + 1200 = 1640 seconds (27m20s), below the aggregate 30-minute
cap. The earlier statement about a final second attempt was superseded by this
verified infrastructure failure before any test execution. No failed card touch
is being retried or treated as passing.

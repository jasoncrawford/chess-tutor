# Coaching and game-library integration — 2026-11-08

## Integration boundary

PR #23 was merged into `codex/chess-coaching-comparison` at `c7629e7`.
`codex/integrate-coaching` starts from main `9141920` and merges that accumulated
coaching history without rebasing or cherry-picking. Its new PR replaces the
stale PR #3; it does not replace the multiple-game work already on main.

The combined app retains the Games library, local and remote boards, pending
invitations, coverage-mode removal, and the polished Coach panel. The obsolete
in-board Play Remotely button stays removed. Help retains its shorter label.

## Integration fixes

- All managed session creation/restoration paths receive the configured hosted
  provider and persistent game UUID. Reopening preserves trace correlation,
  committed moves and captures, but starts a fresh coaching episode.
- Leaving a board stops its coaching. The asynchronous request task is keyed by
  both the session object and request number, so a replacement session cannot
  inherit an old task or stale advice.
- Remote sessions preserve player seats and history. Help remains unavailable
  on the opponent's turn, ended games, and pending invitations.
- An opponent-ended notification now records terminal status in the game
  library before clearing the active controller. Reopening offline no longer
  resurrects that board as playable. The update finds the remote game by its
  identity rather than relying on the current screen's route.
- Debug-only UI fixtures exercise the actual root view using isolated temporary
  persistence and a deterministic provider; they make no paid requests.

## Review and verification

An independent review found the ended-game persistence gap and requested a
nonempty remote-history regression. Both are covered by a test that replays a
capture, receives the end notification, saves, reloads, and reopens the board.
The test failed with an active saved status before the fix. General remote-sync
races and further advice/model iteration were not expanded into this integration.

- Main baseline: 376 native tests passed, zero failures or skips.
- Persistent coaching identity regressions: three tests failed before the fix;
  22 focused tests passed afterward.
- Python: 375 benchmark/tool tests and 57 server tests passed. The new worktree
  has its own virtual environment with both runtime and CI requirements;
  launcher subprocesses use that environment through PATH.
- Browser review tooling: 10 core tests and one controller integration test passed.
- Final native suite: 1,011 passed, zero failures, skips, or runtime warnings.
  This includes the saved ended-game regression and both real-root multi-game
  UI tests (reopen/relaunch and leaving a pending help request).
- Release simulator build passed with no compiler warnings in the build log.

The integration diff passes whitespace validation against the coaching parent.
Historical whitespace in the imported coaching docs/prompts was left intact,
including prompt files whose exact bytes are part of evaluation provenance.

Full simulator result: `/tmp/chess-integration-full-20261108.xcresult`.
Python logs: `/tmp/chess-integration-eval-tests3.log` and
`/tmp/chess-integration-server-tests3.log`.

No prompts, model parameters, provider/server logic, or benchmark expectations
were changed by the integration. No paid model evaluations were run. Existing
advice-quality evidence remains in the earlier evaluation reports and original
worktree; a green integration test is not a new model-quality score.

## Trying the combined app

From the integration checkout, run:

```bash
./scripts/run_hosted_coaching_dev.sh 'ChessTutor Coaching Smoke'
```

The script uses the existing Keychain credential and current Astra trial
configuration. Leave it running while testing. Start or reopen boards through
Games. The A16 simulator and physical iPads were not used for this integration.
Old coaching worktrees and ignored evaluation artifacts are retained.

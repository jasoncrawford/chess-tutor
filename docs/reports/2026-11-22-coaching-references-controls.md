# Inline references and unambiguous move controls

Second November 22 feedback pass on PR #28.

## Behavior

- Piece references again include the board's own artwork. Native text attachments
  sit inside normal font metrics, so linked phrases still wrap naturally without
  oversized rows. The icon and words share a local highlight action. Leading
  whitespace is preserved before the icon regardless of how the model split runs.
- The prompt prefers the descriptive noun phrase ("your bishop") over a later
  pronoun ("it"). This is model guidance, not a client rewrite or validator error.
- Show arrow is removed. The diagram appears automatically and returns after a
  temporary reference highlight; a spoken arrow description remains available.
- Ordinary drafts use Play this move. A move arrow with different canonical
  endpoints hides commit, including another piece's move and a same-piece
  revision. Matching move arrows and attack diagrams do not hide commit. Closing
  Help preserves the draft and the normal Done action can still commit it.
- No Play move anyway state: there is no structured disapproval signal, and
  interpreting criticism from prose or a geometrical attack would be unreliable.

## Evaluation and review

Visual-v5 is a new immutable prompt/config/candidate; server defaults, packaging,
and the visual benchmark use it. Older pins are unchanged. The eval reports and
fails visual acceptance on pronoun-only piece links, while the production
validator continues to accept them so a clarity issue cannot cause a 502.
Judge metadata now lists actual controls per response. Pairwise metadata is
mapped to blinded A/B identities, without a candidate-only duplicate.

Independent review found two important issues: leading whitespace could detach
the icon from its first word, and duplicate candidate-only controls could expose
the candidate's identity to the pairwise judge. Both received failing regression
tests before correction. A spoken description of an already-staged matching arrow
also named its empty origin; this was treated as important for accessible
guidance, reproduced, and corrected to name the piece on the displayed board.

## Verification

Focused evidence before final review fixes: 47 native unit tests, seven visual
UI tests, 81 server tests, and 404 offline eval tests passed. UI tests activate
the actual inline artwork and wrapped words, inspect local board focus, and
exercise rotated panels. Screenshots show ordinary line heights and no redundant
arrow/commit controls. After the review corrections, all 405 offline eval tests
passed. The final full native suite passed **1,052 unit tests and 19 UI tests**,
zero failures, after all review corrections. Server suite: **81 passed**.
Final native result: `Test-ChessTutor-2026.11.22_12-06-39--0500.xcresult` under
`/tmp/chess-visual-coaching-review/Logs/Test/`.

Ten initial/follow-up prompts were exported with zero paid calls. No new live
model-quality score, physical-device test, or physical VoiceOver pass is claimed.
The prompt change's wording quality remains for live play testing.

## Scope

Local Coaching Smoke preview only. No production deployment, Family iPad
installation, merge, or auto-merge. Saved games are retained.

Checkpoint `3d25955` is installed and running in Coaching Smoke with visual-v5.
BuildInfo verifies the commit, and a live screenshot verifies the saved game,
not a UI-test fixture. PR #28 is updated; hosted CI is running. Artifacts are in
`.coaching-eval/visual/20261122/reference-controls/`, with the live server log at
`.coaching-eval/visual/20261122/reference-controls-preview.log`.

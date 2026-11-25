# Coaching references and controls

Follow-up to the user's November 22 play test, on the existing visual-coaching PR.

- Restore the existing chess-piece artwork inline with references, using native
  text attachments contained within the font's ascent/descent. Keep normal word
  wrapping, including within a reference; bind the icon to its first word only.
- Link descriptive noun phrases ("your bishop"), not standalone pronouns ("it").
  Teach this in a new pinned prompt and flag pronoun-only piece links in the eval.
  Do not silently rewrite model prose or turn a clarity issue into a server error.
- Remove Show arrow. Arrows already display automatically and return after a
  temporary reference highlight. Retain spoken arrow descriptions without a button.
- Restore Play this move for ordinary drafts. When a move arrow names a different
  canonical move, hide the commit action. Closing Help preserves the draft so the
  player can commit normally. A matching move arrow or an attack diagram does not
  count as an alternative move.
- Do not infer disapproval from prose or from the mere existence of an attack.
  "Play move anyway" would require a structured verdict; no such contract change
  is included in this small polish pass.

## Approach

Keep TextKit rather than restoring the indivisible SwiftUI link buttons. Use the
existing artwork, typography, and plum link treatment; no new visual chrome. Keep
action policy in the presentation projector and mirror actual controls in judge
context. Preserve previous prompt/config versions for reproducible evaluations.
No paid model run, production deploy, or physical-device install in this pass.

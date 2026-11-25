# Coaching arrow polish

PR #28 play-test follow-up: the shaft previously ran to the arrow tip and had its
own round-capped keyline. The separately outlined triangle crossed that shaft,
leaving a pale seam and a protruding cap. The destination inset also placed the
tip inside the ring.

The shaft now ends at the head's base. Their silhouettes are combined with the
platform's path union, then filled with one exterior keyline and one purple
interior. The destination inset accounts for the larger of the candidate ring
and emphasized halo, including the maximum pulse and arrow outline, plus a small
gap. Halo metrics are shared by the clearance calculation and drawing code.
Straight, diagonal, knight, and revision paths retain their existing meaning.
No coaching prompts, server behavior, or model settings changed.

Regression tests reproduced the internal white seam and insufficient ring
clearance before the fix. Rendered-pixel checks now cover the shaft/head join,
the area beyond the tip, and the light exterior outline against a dark square.
Geometry checks cover all four orientations. The rendered fixtures include the
destination ring for visual inspection.

Independent read-only review found no blocking issues. Both minor suggestions
were implemented: share halo metrics and test the exterior outline on a board
color. Source-ring layering and multi-arrow interactions are unchanged.

Local preview only; no paid API calls, production deployment, physical-iPad
installation, merge, or auto-merge.

Final verification: **1,054 native unit tests and 20 UI tests passed**, zero
failures or skips. The initial focused run passed eight overlay tests and eight
visual UI tests. Final run log: `/tmp/coaching-arrow-full.log`; result bundle:
`/tmp/chess-visual-coaching-review/Logs/Test/Test-ChessTutor-2026.11.25_13-05-44--0500.xcresult`.
Rendered straight, diagonal, and knight arrows were visually inspected. Final
dark-square/ring images are under `/tmp/coaching-arrow-final-shots/`.

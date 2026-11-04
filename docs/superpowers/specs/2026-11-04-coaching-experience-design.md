# Coaching experience regressions

Improve the coach against the actual rough edges observed in play and the saved November 4 evaluations: invented defenses, unacknowledged answers, premature direction, vague goals, repetitive confirmation copy, and slow requests. This is a continuation of the unmerged coach on PR #23, in its existing isolated worktree. The user has asked for implementation and iteration without another design review.

## Approach

Keep the qualified judge and frozen original corpora unchanged. Add a separately versioned eight-case development suite built from existing native snapshots, with explicit private grading criteria and positive/negative sensitivity controls. This avoids rewriting historical results or changing the measurement while tuning the candidate. A new global judge would require requalification; merely re-running the existing permissive briefs would miss the demonstrated blind spots.

The new suite covers knight-defense geometry, an attacked-but-defended piece answer, a genuinely endangered selection, quiet opening Help, requested Hint, useful mating goals, concrete staged feedback, and accepting a safety answer. Discovery is contextual: precise guidance is acceptable after Hint and direct feedback is appropriate after staging. Missing acknowledgment and vacuous objectives must fall below strong, without being misclassified as chess errors. Formulaic copy and latency receive separately visible deterministic metrics, not invented chess penalties.

Use paired agent-authored controls, clearly labeled as such, including retained real failures. They must show the unchanged judge can distinguish these behaviors before using its scores. No candidate sees a brief, reference response, expected grade, or case label. Repeat each candidate three times; preserve every response and grade. Track model/prompt/compiler/configuration hashes, cost, initial/follow-up latency, slow-response counts, and repeated confirmation endings. Use the existing budget meter and checkpoints. Total new paid work is capped at $10 conservative estimated cost; do not automatically retry or reroll failures.

Tune the system prompt first with general coaching principles, not case-specific moves. Use a new pinned configuration. If necessary, test reasoning effort or mechanically generated facts as separate configurations. Promote to the local development launcher only after new-suite improvement, no severe failures, and checks against unchanged opening/middlegame/later-game cases. Keep the prior configuration available. No Stockfish, offline model, new UI, or long learner journeys.

This is development evidence rather than untouched holdout evidence. Describe small-sample uncertainty and any regression candidly. Use an independent final review of the code and outputs.

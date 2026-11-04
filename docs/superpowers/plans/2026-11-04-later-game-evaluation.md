# Later-game coaching evaluation plan

> **For agentic workers:** Use superpowers:executing-plans for this bounded continuation of the coaching evaluation.

**Goal:** Evaluate the unchanged local coach beyond move 17, through promotion and a terminal endgame, and retain repeatable cases.

**Architecture:** Extend the recorded game using legal move replay in the existing Swift fixture layer. Export a separate eight-case development corpus using the existing regression format, then use the existing candidate runner, qualified judge, budget journal, and report generator. Do not change the frozen benchmark or earlier playthrough corpus.

**Tech Stack:** Swift/XCTest; existing Python evaluation tools.

**Spec:** User request in this chat: later-game evaluation, not longer learner journeys. Existing repeatable-evaluation design applies.

## Constraints and approach

- No tutor prompt, model, parameters, compiler, UI, or judge changes.
- Continue the isolated coaching-evaluation branch/PR; this is evaluation evidence for that unmerged coach, not a new app feature.
- Replay from the starting position with complete real history; no fabricated move counters or model-authored request facts.
- Eight independent situations, three samples each. Current discovery-v2/Astra-low candidate; existing qualified judge. No holdout and no long-session simulation.
- Cap all new paid work at $2.50, including conservative reservations. Preserve every output and grade; do not reroll failures.
- Report agent inspection alongside provisional judge grades, including any disagreement. This is not a claim of UI playtesting or teaching effectiveness.

## Review focus

- Full recorded continuation must be legal, including king safety and promotion.
- A winning recapture must not be mistaken for a losing queen-for-knight trade.
- Promotion, king activity, mate and stalemate must be verified independently by rules.
- The correct move is allowed in judge-only briefs, never hand-injected into the candidate prompt.
- A staged terminal result must not be described as an already committed result.

## Steps

- [x] Add `CoachingLaterGameBenchmarkTests.swift`: eight fixtures and legality, determinism, no-brief-leakage, promotion, and terminal-result assertions.
- [x] Add opt-in export environment variable to `project.yml`; regenerate Xcode project. No paid call from a test.
- [x] Run native and Python tests; commit exact evaluated source.
- [x] Export and preflight corpus; run 24 candidate requests and 24 judgments under one existing BudgetedClient.
- [x] Inspect all responses against board facts, document findings/cost/latency and reproduction commands, update PR without merging.

# Repeatable coaching regressions — November 4, 2026

## Scope

The November 3–4 playthrough improvements now have a separately versioned eight-position development suite, rather than only one-off diagnostics. The original frozen benchmark remains unchanged. The tap-capture interaction fix remains covered by native integration tests: model-output grading cannot verify gesture routing.

Run from a clean committed checkout:

```bash
./scripts/run_coaching_regressions.sh
```

The command mechanically exports both suites using the production Swift rules and request builder; checks the qualified judge against six retained bad/good answers three times; then, only if all checks pass, evaluates the current local app candidate three times on eight new positions and 56 original development turns. The 14 holdout turns remain untouched. No paid run is automatic in PR CI.

## This execution

Started using source revision `c0f0bfe00421f66aeef82d2b4d3f230309f311e2`, with a clean executing checkout. No coaching prompt, model, or judge changes were made during this task.

- Candidate: `astra-discovery-v2-low`, matching the local convenience app launcher. Model alias `gpt-6-astra`, low reasoning, `tutor-v13-discovery-v2.md`.
- Judge: `judge-astra-v4`, using its compatible October 31 qualification; no qualification renewal calls.
- Conservative spending ceiling: $10, including judging. Frozen prices plus a 25% uncached-input premium are estimates, not an invoice.
- Evidence: `.coaching-eval/regression/20261104T155542Z/` in the PR worktree. The evaluation manifest separately records corpus and executing-code provenance, configuration/prompt/judge hashes, and per-file Python hashes. Full outputs, grades, timings, token counts, and a durable spending journal are retained.

## Live outcome: useful partial evidence, not a finished quality score

The command successfully exported both real corpora and reused the existing qualification. All **18/18 judge sensitivity checks passed**: retained bad answers were penalized on the intended dimensions, and retained good answers remained acceptable. No expectations were weakened and no sensitivity check was rerolled.

All **24/24 new-regression coaching responses** were generated and passed mechanical validation. Nine of 24 judgments completed; all nine received 5/5 in each dimension with no severe error flagged. This is an incomplete, ordered subset, **not a 100% benchmark result**. The original 56-turn development benchmark has not started; there is no updated broad quality score.

Generation latency for these fresh full-context requests: median **5.35s**, nearest-rank p90 **8.61s**, maximum **11.59s**. These are not conversational follow-up measurements. The 24 successful candidate calls cost **$0.330996** at the frozen unadjusted price table.

The tenth judgment failed without usage data. An explicit checkpoint resume failed with HTTP429; one bounded diagnostic request then established the exact code: **`credit_balance_exhausted`**. All further API work stopped. [Official API guidance](https://developers.openai.com/api/docs/guides/error-codes) distinguishes this from a temporary rate limit: more prepaid credits are required before retrying.

Across this task's live execution, **51 successful calls** (18 sensitivity +24 candidate +9 grading) have a conservative estimated cost of **$0.9590645**. Three unsuccessful transmissions retain **$0.9931875** in conservative reservations because their actual charge is unknown. Total cost/reservation: **$1.9522520**, below the unchanged $10 cap. These figures are not provider invoice totals, and the exhausted account balance cannot be attributed solely to this run.

The original failed evaluation manifest remains untouched. `evaluation/resume-1.json` records the explicit failed continuation, and `evaluation/provider-limit-diagnostic.json` records the allowlisted error code. The existing `playthrough/grading-checkpoint.json` retains all nine completed grades and every failed attempt. Once credits are available, resume unfinished grading rather than rerolling the 24 coaching responses, then start the untouched original development suite. Preserve unknown-accounting warnings in the report even after successful resumption.

## What is now covered

| Observed concern | Repeatable coverage |
| --- | --- |
| Incorrect mutual pawn-defense claim | p01: actual one-way d3→e4 defense |
| Invented forced response to knight development | p02: defended e5 pawn and castling clearance |
| Generic development praise | p03/p04: a concrete bishop/knight consequence |
| Misunderstood captures and recaptures | p05/p06: losing bishop capture versus favorable queen-for-bishop trade |
| Wrong-piece answer and changed tentative move | p07/p08: current learner event and actual current position |
| Question intercepts a tap capture | Native session integration regressions; not asserted by an LLM score |

The generated answers did not repeat the observed mutual-defense or forced-defense errors. One qualitative concern remains visible: all three p07 replies switch to a capture puzzle without explicitly explaining why the selected bishop is defended. The first such reply received full marks from the judge. That is a reason to retain and inspect the text, not to treat the provisional rubric as a complete measure of teaching quality. No prompt or rubric was changed to chase this run's results.

## Verification

973 native unit tests, 55 server tests, and 354 evaluator tests passed locally. Native UI tests were not run locally. The full native tool call timed out at five minutes, but its underlying xcodebuild completed successfully; the retained result bundle and log show all 973 tests passing.

One fresh independent review found three integration defects before paid execution: symlink-parent artifact paths, pre-transmission budget stops incorrectly counted as unknown paid judge failures, and missing executing-code provenance when replaying old exports. Reproduced all three, added regression tests, and fixed them in one pass. The reviewed candidate generation → qualified grading → checkpoint → report path also passes an offline 168-response integration test.

PR#23 contains the implementation. GitHub's Python and iPad jobs were queued at handoff, not passed. The normal dev launcher restored the app/server on Coaching Smoke after export tests; A16 was untouched. Live coaching will also require restored API credit.

## Interpretation

These are development regressions derived from observed failures, not new held-out evidence. Their expected grades are agent-authored, not human calibration. The eight new cases use independent full-context requests with recorded learner events; they do not simulate an adaptive conversation. The original benchmark retains its existing three-turn conversations.

Future prompt, model, parameter, or user-prompt-generator changes must be evaluated with their own pinned configuration and executing source. The default-launcher parity test prevents the convenience app silently drifting from the default candidate. Provider model aliases can change upstream despite unchanged local hashes; a fresh dated run is necessary to detect that. Historical scores do not transfer automatically to a new prompt.

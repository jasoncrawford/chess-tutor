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

## Live outcome: both suites completed

The command successfully exported both real corpora and reused the existing qualification. All **18/18 judge sensitivity checks passed**: retained bad answers were penalized on the intended dimensions, and retained good answers remained acceptable. No expectations were weakened and no sensitivity check was rerolled.

After the user replenished API credits, resumed the saved grading checkpoint and completed both suites. No completed candidate output or judgment was regenerated. All 192 candidate responses were mechanically valid, and all 192 were graded.

| Suite | Distinct turns × repetitions | Strong responses | Severe errors | Candidate p50 / p90 | Candidate cost |
| --- | --- | --- | --- | --- | --- |
| New playthrough regressions | 8 × 3 | 24/24 (100%) | 0/24 | 5.29s / 8.61s | $0.330996 |
| Original development benchmark | 56 × 3 | 143/168 (85.1%) | 3/168 (1.8%) | 3.18s / 6.99s | $2.219402 |

“Strong” means every rubric dimension scored at least 4/5 and no severe flag. Percentiles use the report's nearest-rank convention. Costs in the table use the frozen, unadjusted price table. The 14 holdout turns were not used. There is no baseline comparison or promotion recommendation in this diagnostic mode.

The original benchmark's 120 initial requests had a median latency of **3.51s** and p90 **7.17s**; its 48 conversational follow-ups had median **2.91s** and p90 **4.07s**. Maximum candidate latency was 12.59s. The new regression cases use fresh full-context requests, not conversational continuations.

### Actual chess failures

All three severe failures make the same false claim: a white knight on c3 protects the highlighted white pawn on d4. A knight cannot attack that square. Affected cells:

- `i07-looks-safe`, repetition 1.
- `s04-safe-move-confirm-02`, repetitions 1 and 2.

For example: “Your knight now protects your middle pawn, helping it stay put. Would you like to keep this move?” The focus marks c3 and d4. In the first conversational repetition the next answer corrected the claim, but that does not erase the preceding error. The judge correctly flagged all three. This demonstrates that the broader benchmark exposes a recurring defect not revealed by the eight new positions.

### Rubric limitations exposed by the run

Of the 25 original-benchmark responses below the strong threshold, 22 have a discovery/independence score below 4; categories overlap with the three chess failures and seven coaching-judgment deductions. Some are debatable grading penalties rather than demonstrated product failures:

- Accurate staged-move warnings sometimes receive discovery 3 merely because they explain the consequence instead of asking another discovery question. For example, `c02-poisoned-bishop-capture|r1` is accurate and answerable in every other dimension but gets discovery 3. The new suite's brief explicitly permits direct staged feedback; analogous `p05` responses receive 5. This is a **brief/rubric consistency issue**, not evidence that one suite is inherently easier for the model.
- Requested Hint responses (`i04-opening-hint` and `s08-hint-then-act-02`) are penalized for suggesting a specific move, although a more explicit hint after the child asks for one is intentional.
- Other deductions concern genuine coaching choices, such as emphasizing a minor knight-development consideration or missing an available mating-capture teaching opportunity. Do not assume all low discovery scores are false positives.

The raw 85.1% score is retained unchanged. No prompt, judge, threshold, or grader brief was tuned during this run, and no low grade was rerolled. Before using the strong-response rate as a release gate, align the staged-feedback and requested-Hint policy across the judge and both suites, version that change, and regrade saved outputs. Separately fix the demonstrated knight-defense error using these already-repeatable cases.

### Interruption, recovery, and cost

The original attempt stopped after nine playthrough judgments. An explicit checkpoint resume failed with HTTP 429; one bounded diagnostic request established **`credit_balance_exhausted`**. Requests stopped until the user added credits, as required by [official API guidance](https://developers.openai.com/api/docs/guides/error-codes).

The successful continuation was launched from `d9b626e690c221117928504e6ffa801b2b8e7a95` after verifying that every executing Python source hash still matched the original clean `c0f0bfe` run. Only documentation had changed. Corpus, model, prompt, judge, and pricing bindings were preserved.

Final accounting: **402 successful calls** (18 sensitivity + 192 candidate + 192 grading), with **$8.5608620** in conservative estimated successful-call costs. Three earlier unsuccessful transmissions retain **$0.9931875** in reservations because their actual charge is unknown. Total conservative cost/reservation: **$9.5540495**, within the **original $10 cap**. A possible increase to $12 was asked about but neither needed nor applied. The unadjusted frozen-table estimate for known successful calls is $7.529152. None of these figures is an invoice total.

`evaluation/resume-2.json` records final status `completedWithAccountingCaveat` and both report paths. The original failed `evaluation.json`, failed `resume-1.json`, diagnostic, journal, and checkpoints remain intact. The playthrough report correctly retains “judge accounting is incomplete” for the three failed calls; the original benchmark report has no integrity issues. Every completed grade was reused, including all low scores. Do not discard the accounting warning or relabel this as held-out promotion evidence.

## What is now covered

| Observed concern | Repeatable coverage |
| --- | --- |
| Incorrect mutual pawn-defense claim | p01: actual one-way d3→e4 defense |
| Invented forced response to knight development | p02: defended e5 pawn and castling clearance |
| Generic development praise | p03/p04: a concrete bishop/knight consequence |
| Misunderstood captures and recaptures | p05/p06: losing bishop capture versus favorable queen-for-bishop trade |
| Wrong-piece answer and changed tentative move | p07/p08: current learner event and actual current position |
| Question intercepts a tap capture | Native session integration regressions; not asserted by an LLM score |

The new-regression answers did not repeat the observed mutual-defense or forced-defense errors. One qualitative concern remains visible: all three p07 replies switch to a capture puzzle without explicitly explaining why the selected bishop is defended, and all receive full marks from the judge. That is another reason to retain and inspect the text, not to treat the provisional rubric as a complete measure of teaching quality.

## Verification

973 native unit tests, 55 server tests, and 354 evaluator tests passed locally. Native UI tests were not run locally. The full native tool call timed out at five minutes, but its underlying xcodebuild completed successfully; the retained result bundle and log show all 973 tests passing.

One fresh independent review found three integration defects before paid execution: symlink-parent artifact paths, pre-transmission budget stops incorrectly counted as unknown paid judge failures, and missing executing-code provenance when replaying old exports. Reproduced all three, added regression tests, and fixed them in one pass. The reviewed candidate generation → qualified grading → checkpoint → report path also passes an offline 168-response integration test.

The 354 evaluator and 55 server tests were rerun successfully during the continuation. GitHub's Python check passed. Its iPad job did not acquire a hosted runner: it had no test steps, runner ID 0, and an annotation reporting macOS runner-capacity constraints. This is not a failing XCTest result. The final documentation push triggers another CI attempt; do not claim the iPad CI gate is green until it runs successfully.

PR #23 contains the implementation and results. The normal dev launcher restored the app/server on Coaching Smoke after export tests; A16 was untouched. API access was verified restored by the successful continuation.

## Interpretation

These are development regressions derived from observed failures, not new held-out evidence. Their expected grades are agent-authored, not human calibration. The eight new cases use independent full-context requests with recorded learner events; they do not simulate an adaptive conversation. The original benchmark retains its existing three-turn conversations.

Future prompt, model, parameter, or user-prompt-generator changes must be evaluated with their own pinned configuration and executing source. The default-launcher parity test prevents the convenience app silently drifting from the default candidate. Provider model aliases can change upstream despite unchanged local hashes; a fresh dated run is necessary to detect that. Historical scores do not transfer automatically to a new prompt.

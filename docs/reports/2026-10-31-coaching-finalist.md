# Coaching finalist comparison — 2026-10-31

Status: paused by OpenAI's project spending limit. All individual responses are graded, but the blind comparison and formal report are incomplete. Astra/low is the provisional local-playtest recommendation, not a production promotion. This report must be finalized before the local-trial PR is merged.

## Scope and evidence

The frozen comparison contains 70 turns, three repetitions, and two configurations: 420 requested responses. Of those turns, 56 are development cases and 14 are held out. Candidate responses were generated on September 6; judging and the fresh playable smoke are dated October 31. We did not regenerate or discard failed candidate cells after seeing their results.

- Candidate records SHA-256: `3d4970467bd0d586903551257b8226d6f430c8dc31a64e74f6b7ee9c848f3c92`.
- Corpus SHA-256: `d882d31605462b856266e6578ddfd2eec37dfbbd6d329150ae4b997398465afb`.
- Candidate artifacts: `.coaching-eval/benchmark/runs/20260906-astra-finalist/candidates` in the retained `stabilize-benchmark-judge` worktree. Paid artifacts remain ignored; do not delete that worktree.
- Grade/report artifacts will be siblings of `candidates`; they have not been published because grading did not finish. Grading uses an exact-bound durable checkpoint, retaining completed judgments and failed-attempt accounting across interruptions.

## Configurations

| Setting | Astra finalist | Existing production baseline |
| --- | --- | --- |
| Configuration | `astra-discovery-low` | `production-sol-v2` |
| Model | `gpt-6-astra` | `gpt-5.6-sol` |
| Reasoning: initial / tactical follow-up / simple follow-up | low / low / low | high / low / none |
| System prompt | `tutor-v13-discovery.md` | `tutor-v13.md` |
| Output limit / timeout / attempts | 2,048 tokens / 30 seconds / 1 | Same |
| Stored response continuation | Enabled | Enabled |
| Request compiler / response contract | `chess-native-v13` | Same |

The discovery prompt tells the tutor to use its beginner routine silently, skip unnecessary danger/capture searches, and preserve the child's opportunity to choose. A specific move is appropriate after an explicit Hint, not as the default answer to Help. The comparison changes both model policy and prompt; it does not isolate their individual effects.

Exact finalist model file: `Tools/CoachingEval/benchmark/configs/models/astra-discovery-low-model.json`, SHA-256 `cfbd5cb42864ca33ec2dd4e57f718404c993e0758636f1e05477a6d560d3d6b2`. Prompt SHA-256: `88b95067d763ec020d2aa6f4e0ce37430cdf818591f8a76b6eaa3d9bf2d9fcc6`.

## Judge qualification

The unchanged `judge-astra-v4` configuration uses Astra/low, a 4,096-token output cap, a 60-second timeout, and independent, unstored requests. The references remain transparently **agent-reviewed and provisional**, not human-approved. The judge's model family overlaps the finalist, another reason not to treat its scores as ground truth.

The September certificate had expired. The first October renewal ended on an incomplete provider response after 95 successful calls; two complete passes had met all thresholds. That rejected artifact and its spending remain preserved. A single diagnostic replay succeeded. One fresh, unchanged qualification then completed all 120 calls and passed all three rounds:

| Minimum across the three rounds | Result | Required |
| --- | ---: | ---: |
| Severe-error agreement | 100% | 95% |
| Dimension scores within one point | 95.83% | 90% |
| Order-balanced pairwise agreement | 90% | 90% |

Accepted certificate: `20261031T120623Z-5f5976ede68b8a511835d44849656d96b10588c53bc6925af2cc358181a89b08/qualification.json`; expires November 30. Judge configuration, prompt, references, and thresholds were not changed to obtain acceptance. Grading reuses this certificate.

## Historical reliability, latency and cost

| Metric | Astra | Production Sol |
| --- | ---: | ---: |
| Mechanically valid responses | 210 / 210 | 208 / 210 |
| Provider timeouts | 0 | 2 |
| All calls: median / 90th percentile | 3.13s / 5.76s | 5.31s / 12.90s |
| Initial calls: median / 90th percentile | 3.23s / 6.10s | 6.81s / 15.59s |
| Follow-ups: median / 90th percentile | 2.94s / 3.98s | 3.40s / 6.54s |
| Standard-token estimate, known successful calls | $2.387255 | $2.0056388 |

The Sol timeouts are `d06-apparent-danger/r1` and `d04-pinned-knight/r2`. Their billable usage is unknown, so Sol's full cost is **unknown**, not $2.0056388. We cannot claim a complete cost ratio or automatic promotion from this comparison.

Costs above use the frozen September price table, not an invoice. Current [OpenAI caching documentation](https://developers.openai.com/api/docs/guides/prompt-caching) describes a cache-write premium that the historical transport did not separately retain. Counting every uncached input token at 1.25 times its standard rate gives a conservative Astra candidate bound of $2.703845 and a bound of $2.1667438 for Sol's known successful calls only; Sol's failed-call cost remains unknown. Historical latency is not a guarantee about today's service.

About 68% of Astra's benchmark input tokens were reported as cached, versus zero cached tokens in the four fresh app calls below. Repeated benchmark cases and a cold real game have different caching behavior; the benchmark cost is not a per-game forecast.

## Independent output audit

A separate context reviewed all 210 Astra outputs before seeing the new judge grades. It found no clear severe chess-fact error or UI dead end, but found real teaching limitations: one answer named the endangered knight before asking the child to identify it, and some quiet-position suggestions made castling too explicit without a Hint. Those are not erased because other answers are good.

A second agent audit checked all 28 Astra cells with any dimension below 4 against their actual inputs and frozen chess facts. It confirmed the answer leak and pre-Hint castling concern. Five other lower judgments concern a missed mate-in-one opportunity in one repeated position; the danger described was real, not fabricated. Six low independence scores penalize a precise move after the child explicitly requested Hint, which the product contract permits. Several other low scores prefer discovery questions over accurate feedback on a move already staged. These are important distinctions when interpreting the rubric; all original grades remain unchanged. Some judge explanations also contain stray trailing words, reinforcing that these are provisional automated assessments, not human-certified truth.

All 210 Astra absolute grades are complete. The one severe flag is a teaching failure, not a factual or UI failure. The independent audit supports a reversible local adult playtest with that limitation disclosed.

The same agent also checked all ten judged severe flags among Sol's 208 usable responses. Two concrete concerns are supported: an implied uncaught queen capture despite available recaptures, and calling a bishop a knight in a promotion reply. Several other severe labels are debatable. In particular, the judge incorrectly calls a question about White capturing Black a color reversal when the learner is Black; it is correctly framed danger, although unnecessary in that quiet opening. Other flags conflate a generic checklist reset with proven stale-move advice, or penalize precision following Hint. These caveats apply to Sol as fairly as to Astra; no stored scores were edited.

## Completed absolute scores; incomplete blind comparison

These numbers are read-only diagnostics from the durable checkpoint and frozen records, **not a completed benchmark verdict**. Scores are on the existing 1–5 scale. As the frozen rubric requires, the two unusable Sol responses count as 1 in each dimension and remain in the denominator.

| Measure | Astra | Production Sol |
| --- | ---: | ---: |
| Chess correctness, mean | 5.00 | 4.91 |
| Coaching judgment, mean | 4.83 | 4.06 |
| Latest-action responsiveness, mean | 4.97 | 4.55 |
| Discovery and independence, mean | 4.38 | 4.04 |
| Coherence and answerability, mean | 4.99 | 4.86 |
| Child clarity, mean | 4.97 | 4.81 |
| All dimensions at least 4 | 182 / 210 | 132 / 210 |
| Development: all dimensions at least 4 | 150 / 168 | 108 / 168 |
| Holdout: all dimensions at least 4 | 32 / 42 | 24 / 42 |
| Judged severe flags | 1 | 10 |
| Additional automatic unusable/severe cells | 0 | 2 |

Do not read the raw severe counts as independently verified chess-error rates; the audits above explain real errors and judge false positives. Repetitions and reused positions are not independent games. The completed individual scores support Astra's quieter, more current-action-sensitive coaching, but not a guarantee of correctness.

Only 66 of 208 paid pairwise judgments completed: Astra won 22, Sol won 9, and 35 tied. This is an ordered prefix, not a representative completed comparison. Two additional pairs will be decided automatically by Sol's timeouts; those are reliability differences, not wording victories. No full pairwise rate, confidence interval, automatic eligibility, or automatic recommendation is reported.

## Project-limit interruption and recovery

The 485th grading request returned HTTP 429, code `project_spend_limit_exceeded`, type `insufficient_quota`. The checkpoint retained all 484 completed judgments (418 individual plus 66 pairwise), the unsuccessful attempt, and its unknown-accounting status. No in-flight marker remains. The next unfinished pair is `astra-discovery-low|s10-close-and-reopen-01|r1|vs|production-sol-v2`; 142 paid judgments remain. No completed judgment or candidate response needs to be regenerated.

The retained budget journal's conservative ceiling is $16.5007035, including both qualification attempts, the diagnostic call, completed grading, and full reservations for failed calls. Together with the four app calls below it is $16.665291. This is a conservative token/reservation estimate, not the account invoice or remaining balance. The local $18 evaluation guard had not fired; the provider's project limit caused the stop.

OpenAI documents this as an enforced monthly project cap, separate from exhausted prepaid credits. A project owner can check Project settings → Limits → Spend → Edit spend limit. Raising the applicable limit permits requests after propagation; otherwise it resets with the next monthly cycle. No account setting was changed, no further paid requests were retried, and no additional credits were purchased. See [official spend-limit guidance](https://developers.openai.com/api/docs/guides/spend-limits).

## Fresh playable smoke

On October 31 the normal development script built, installed and launched the A16 app using the exact Astra configuration without a model override. The script now supports the installed Xcode's Device Hub as well as older Simulator frontends.

Opening Help returned HTTP 200 in 11.73 seconds: “Let’s make room for your pieces. Can you try moving a middle pawn forward?” Selecting the pawn caused no API request. Staging e2–e4 returned HTTP 200 in 2.07 seconds: “Your pawn takes space in the middle and opens a path for your bishop. Want to keep it?” The displayed response controls were Play this move, Try another move, and Close help.

Choosing the knight removed the tentative pawn move; feedback followed that change in 2.68 seconds. Staging the knight on f3 produced “Your knight is out and helping control the middle. Would you like to keep this move?” in 2.08 seconds, without stale pawn advice. All four requests returned HTTP 200. Their conservative cache-write-inclusive cost bound is $0.1645875. This is a small functional check, not a latency distribution.

The native automation's coordinate-based activation misses the transformed coaching-button accessibility frames. Current Hint/Play taps therefore were not counted as successful tests; their real flows were exercised in the September smoke and are covered by the existing tests. Do not confuse tool-reported tap delivery with verified app interaction.

## Release boundary

The proposed change affects only the convenience development launcher. Direct/deployed server startup continues to use the existing Sol production configuration. The same launcher can explicitly return to Sol:

```bash
CHESS_TUTOR_COACHING_MODEL_CONFIG=CoachingServer/configs/production-v1.json ./scripts/run_hosted_coaching_dev.sh
```

No eligibility gate, unknown-cost handling, failed response, or stored judge score is weakened to make the finalist look better. Provisional recommendation: try the exact Astra/low discovery configuration locally with adult review, based on the completed individual assessments and independent audits. The partial comparison is not sufficient for a completed benchmark claim or production promotion. Final formal report, release merge, and a usable online handoff remain blocked by the project limit and pending completion checks.

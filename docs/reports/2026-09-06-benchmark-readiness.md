# Coaching benchmark readiness — 2026-09-06

The benchmark now executes the shared production policy, grades from the same factual context used for judge qualification, and preserves incomplete accounting when a provider attempt fails. The remaining step is choosing and promoting a coaching configuration from the finalist comparison; this report does not claim that promotion has happened.

## Reviewed references and qualified judge

Jason Crawford delegated reference review to GPT-6 Astra on September 6. The reference set is labeled `agentReviewed`, not human-approved, and remains provisional. The audit corrected one staged-knight utterance, two discovery scores for explanations of already-staged special moves, and an ambiguous rationale about a queen-for-knight capture. No pairwise preferences or severe-error flags were changed.

The normal launcher uses `judge-astra-v4`: GPT-6 Astra, low reasoning, 4,096 output tokens, 60-second timeout, no stored conversation. Its three-pass qualification completed all 120 requests with complete accounting:

| Minimum across the three passes | Result | Required |
| --- | ---: | ---: |
| Severe-error agreement | 95.0% | 95.0% |
| Dimension scores within one point | 96.7% | 90.0% |
| Order-balanced pairwise agreement | 90.0% | 90.0% |

Qualification cost was $1.558116, estimated from returned usage and the dated price table. The certificate was created at `2026-09-06T14:25:44.796798Z` and expires 30 days later. Grading reuses it and makes no additional qualification calls while its bindings remain compatible.

One severe-label disagreement was a false positive on a response that explained a recapture before asking about safety. The judge agreed with every dimension score in that case. Qualification is an error-detection check, not proof that every later score is correct; actual outputs and flagged cases still need inspection.

### Why the rubric changed

The earlier Sol/high judge failed pairwise agreement and was rejected. Astra with clearer tie guidance qualified, but the first real smoke revealed a product-specific blind spot: it gave an unnecessary opening danger scan excellent coaching-judgment marks because the words were accurate and a negative-answer button existed.

The final judge prompt explicitly separates factual correctness from teaching usefulness. Unnecessary danger scans in obviously safe openings, and capture hunts with no possible capture, score poorly on judgment without automatically becoming severe chess errors. A five-response diagnostic verified that distinction while preserving high scores for genuine danger and current-move feedback. The final prompt was then qualified against the unchanged references. Earlier runs and their costs were preserved, not silently replaced or rebound to new hashes.

## Evidence bindings

- Reference SHA-256: `34dfd86cbae1bc69d811fa3ac9083c4a8af79e3eec8ab6a50979e55df81e93af`
- Final judge configuration: `07baaba20578f719bcd4bc1060c0fd190249ee4543e525ece11d49592a25a27a`
- Final judge prompt: `d420044387fa67b62f1af9bd5a0c41fe11bbd2b3ed6962cbff4293e5ec269c31`
- Qualification artifact: `425e1b2da72108d1c20a12ebb0c76fd092c1f606c9e1b7b17ca0262378219aae`
- Frozen 70-turn corpus: `d882d31605462b856266e6578ddfd2eec37dfbbd6d329150ae4b997398465afb`

The local certificate is under `.coaching-eval/benchmark/qualifications/20260906T142544Z-425e1b2da72108d1c20a12ebb0c76fd092c1f606c9e1b7b17ca0262378219aae/qualification.json`. Paid-run artifacts are intentionally ignored. Reproduction uses the normal `scripts/run_coaching_quality_benchmark.sh` launcher and the checked-in immutable configurations.

## Candidate preparation and playable smoke

The `tutor-v13-discovery.md` variant removes the contradictory requirement to start every Help episode with a danger question. It retains the deterministic v13 request compiler, structured response contract, board/button interactions, latest-move priority, and distinction between ordinary Help and an explicitly requested Hint. The original production prompt is unchanged.

The five-turn diagnostic produced 20 mechanically valid responses across production Sol, discovery Sol/high, discovery Sol/medium, and discovery Astra/low, with no provider failures. Final-rubric grading rated four of five production responses strong and all five responses from each discovery variant strong; no severe errors were flagged. The 20 grading calls cost $0.409842 and reused the final qualification without another qualification call. The report has no integrity issues and remains explicitly ineligible for promotion. Astra is the finalist against current production; Sol/medium remains a checked-in alternative for future comparisons. These five-case results do not establish a general quality ranking.

The actual A16 app was also launched with the Astra candidate. Opening Help offered a center-pawn idea without a danger scan; Hint named a move only after being requested; selecting a pawn caused no coaching request; staging it yielded move-specific feedback and the matching play/retry controls; retrying returned to a fresh development idea. Observed response times for these four calls were 3.62, 3.85, 2.63, and 4.36 seconds. All returned HTTP 200. This is a small functional smoke, not a latency guarantee.

## Verification

- Evaluator: 317 tests passed, zero failures or skips, including Node 24 browser-controller integration and local HTTP tests.
- Server: 49 tests passed; no server-runtime changes in the final benchmark-only fixes.
- Native iPad suite: 973 tests passed, zero failures or skips; unchanged by the later prompt/configuration/report edits.
- The scoped final reviews closed all four integration/accounting findings and the modern-Node test issue. Live use additionally exposed and fixed a quick-report validation mismatch: quick runs have no pairwise grades, while comparison runs still require every exact pair.

Full finalist generation, grading, cost/latency analysis, and the separate production-promotion PR follow this benchmark release. No eligibility thresholds were relaxed.

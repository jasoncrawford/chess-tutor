# Broader Hosted Chess-Coaching Evaluation

Date: 2026-08-30

## Decision

Use **GPT-5.6 Sol with high reasoning** for the first hosted coaching prototype.

Sol retained a clear quality advantage across the broader twelve-position set: all 12 responses passed the strict UI contract and none received a severe rating. Luna was about 13.6 times cheaper, but it was not faster at the median and its quality was not close enough to justify the savings: 10 of 12 responses passed the strict contract and 3 of 12 were severe.

This is a model/configuration decision, not app integration. The live app was not changed to call a hosted model in this task.

## Frozen experiment

Both configurations received the same tracked `tutor-v6` system prompt and the same twelve deterministic, mechanically compiled chess situations:

1. quiet midgame Help with no urgent tactic;
2. an urgently attacked loose piece;
3. an attacked piece that is adequately defended;
4. a genuinely safe, useful capture;
5. an apparent capture that loses material to a recapture;
6. an equal exchange that is not an urgent mistake;
7. selection of a pinned or constrained piece;
8. a safe staged developing move;
9. a legal staged move that ignores a more urgent danger;
10. a legal answer to check that permits a harmless equal trade;
11. inspection of an opponent capture that loses the attacker; and
12. a replacement move that supersedes an earlier unsafe tentative move.

Every fixture was built from legal game history using the production request builder and chess-native context compiler. The prompt packet was compiled twice and matched byte for byte. All twelve user prompts were 628–696 Qwen-tokenizer tokens, below the 2,500-token preflight limit.

Provider settings were frozen as follows:

- configurations: `gpt-5.6-sol` / `high` and `gpt-5.6-luna` / `high`;
- Responses API with role-separated system and user inputs;
- strict structured output using the existing three-field coaching response contract;
- `store: false`;
- maximum output tokens: 2,048;
- one serial attempt per model and case; and
- no retry, repair, prompt mutation, or configuration substitution.

The run made exactly 24 provider calls: 12 Sol calls followed by 12 Luna calls. Review was blinded before the configuration identities were revealed.

## Results

No combined quality score was calculated. The six dimensions below remain separate.

| Measure | Sol / high | Luna / high |
|---|---:|---:|
| Strict-valid responses | 12 / 12 | 10 / 12 |
| Severe responses | 0 / 12 | 3 / 12 |
| Factual correctness | 4.833 | 4.000 |
| Current stage/latest action | 4.917 | 4.250 |
| Single teaching purpose | 5.000 | 3.917 |
| Discovery coaching | 4.167 | 3.167 |
| Child-friendly language | 4.917 | 4.083 |
| UI action/focus alignment | 4.833 | 3.750 |
| Input tokens | 9,371 | 9,371 |
| Output tokens | 3,805 | 5,384 |
| Reasoning tokens | 3,040 | 4,651 |
| Median latency | 4,675 ms | 5,560 ms |
| P90 latency | 7,251 ms | 6,185 ms |
| Estimated cost for 12 calls | $0.113584 | $0.008335 |

The estimates use the evaluator's frozen rates of $4.00 / million input tokens and $20.00 / million output tokens for Sol, and $0.20 / million input tokens and $1.20 / million output tokens for Luna. Reasoning tokens are included in the reported output-token totals used for the estimate.

## What worked

Sol consistently turned the neutral board evidence into short, useful coaching. Representative responses include:

- Quiet development: “One knight is still asleep. Can you hop it closer to the center?”
- Safe capture: “Look at your knight. Can it jump onto the black queen’s square?”
- Poisoned capture: “Careful—the black king can take your bishop there. Can you find a safer move?”
- Equal exchange: “Your bishop takes the knight, then either pawn can take your bishop. Do you want this trade?”
- Replaced move: “Good choice—the knight steps away from the pawn’s attack and stays ready to help the center.”

These responses show that the compact, mechanically generated prompt now contains enough chess context for a capable hosted model to infer the teaching point without an authored answer being embedded in the request.

Luna also produced several strong answers, including: “Look at the black queen. Can your knight capture it?” Its lower cost therefore remains interesting for a future, narrower optimization study, but not as the default coaching model from this evidence.

## Failure audit

Luna's three severe results were:

- two mechanically invalid responses whose child messages exceeded the frozen 18-word limit; and
- one chess-teaching error in the harmless-check-trade case: “Your bishop blocks the check, but the other bishop can capture it. Try blocking with a different piece.” The move allows an equal bishop trade, and White can recapture, so rejecting it on that basis is misleading.

Sol had no severe result. Its weakest answer was on the same harmless-trade case: “That blocks the check, but can the black bishop capture your bishop and keep checking?” The question is true, but it omits White's recapture and offers only move revision. This case should remain in regression coverage for the hosted prototype.

Two other Luna weaknesses illustrate the aggregate difference:

- on an equal bishop-for-knight exchange, it emphasized Black's recaptures and offered only revision instead of presenting the trade as a valid choice; and
- after a replacement knight move, it mixed confirmation with a second future instruction to develop another piece.

All severe responses were checked against their exact prompt and board evidence after unblinding. Both mechanically invalid responses were already rated severe, so there were no invalid-but-nonsevere rows requiring a separate audit.

## Integrity and artifact hashes

Generated prompts, responses, private review mapping, and scoring evidence remain in the ignored `.coaching-eval/chess-native-broad` workspace.

| Artifact | SHA-256 |
|---|---|
| `tutor-v6.md` system prompt | `0f434c5a7b4889442fc74f5846037d96a2332e479809e68790ee6dcebc1a6051` |
| source preview manifest | `928ab6ac66230fd39da8a1f0a6ad07487166621ecf4f565a3e1f8f7dff73d690` |
| source `examples.jsonl` | `d8706632e1fbc36b99712ed392a5de618211efcf7b4c2891e5315a4b4955b1f4` |
| run manifest | `6e42c92b1f69048807318297e67648a72418f69e18a3ebdf496549cbb097ac29` |
| blinded review packet | `495d3535f9cf70c629140fbd6fbeb7aefbb511e981541dfdf1d056f0e38d9edd` |
| private review key | `2b6a30b7ffc421f4d2f29e96ecff045386ee7d5c7ec3a851f29d30941084914b` |
| completed rubric | `abf146f8a4acf42b59df4b702620a636535608641f7547c66fe5dd03044d1dd1` |
| summary JSON | `b7f6e77f1c431560d08e30454f2064b027185cce6874594f5de425a5b1eccce2` |
| summary Markdown | `a09daf90ee16725c4fbd519f5028a35c25f7796f1cd962487562373eb63f1341` |

No credential, provider error body, or hidden reasoning was persisted. No local model was run for coaching generation; the restored pinned local runtime was used only for the no-inference tokenizer budget gate. No hidden evaluation set was inspected. No extra provider calls, prompt tuning, retries, or repairs occurred.

## Next step

Build a small hosted prototype around Sol/high using the same deterministic prompt compiler and strict response validator. Keep a visible “thinking” state, handle network failure explicitly, and preserve the no-conversation interaction model. Before broad product integration, exercise the twelve regression cases through the real coaching panel and add the harmless-trade position as a release-blocking semantic check.

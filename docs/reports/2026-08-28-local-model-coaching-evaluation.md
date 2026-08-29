# Local coaching model quality evaluation

Date: 2026-08-28

## Decision

No evaluated local model advances to device testing. Do not execute the model portions of Tasks 6–7.

This is a negative result for the current combination of an 8,192-token context, the full unmodified coaching request, the `model-coaching-turn.v1` contract, and these quantized models. It is not evidence that local coaching is impossible. The final round found three independent blockers:

1. first-attempt context overflow on 29 of the 41 visible cases for every candidate;
2. displayable structured-output validity of only 5.3%–6.1%; and
3. severe chess or interaction-state errors in 4 of Qwen 0.6B's 13 displayable turns and 6 of Qwen 1.7B's 15. SmolLM3 avoided severe errors in its 15 displayable turns, but 15/246 is too sparse to be broadly usable.

The next useful architecture investigation is an explicit evidence-preserving compaction contract and request-specific constrained reference IDs, followed by a new evaluation round. Silently truncating requests or loosening validation would conceal rather than solve the observed failures.

## Methodology corrections

Only the fourth evaluation round, labeled `v4-final`, contributes to the results below. Three earlier rounds remain preserved and explicitly labeled `superseded-methodology` in ignored evidence:

1. **v1:** llama.cpp b10516 returns from its pure-content `--skip-chat-parsing` path before applying JSON-schema grammar, so these generations were soft-prompt-only.
2. **v2:** native grammar was enforced, but both declared modes were forced to begin JSON immediately, so bounded mode did not actually permit bounded reasoning.
3. **v3:** off and bounded grammars were distinct, but model-facing requests still declared `tutor-v1` while the selected prompt was `tutor-v2`; sorted few-shot assistant JSON also conflicted with the grammar's required key order.
4. **v4-final:** the evaluator derives an explicit effective request that changes only `promptVersion` from `tutor-v1` to `tutor-v2`, preserves the opaque request ID, records frozen/effective request hashes and the mutation, and validates against the effective request. A dedicated assistant-example serializer emits every example in the exact GBNF property order. All model-facing request occurrences now self-consistently declare `tutor-v2`.

The corrected evaluator asks `/apply-template` to render each model's exact chat prompt and thinking setting, then sends that prompt to native `/completion` with an explicit token-level GBNF. Off mode permits only the strict JSON object. Bounded mode permits exactly one closed, length-bounded `<think>...</think>` envelope followed by the identical strict JSON object. The 256-token output cap is unchanged, and trace content is removed before parsing or persistence.

## Frozen inputs and baseline

The corpus was exported from Git commit `ef886fa066f60bb22bf43fabb427822804e0648c` after a clean full-scheme baseline:

- 813 unit tests passed;
- 5 UI tests passed;
- 0 failures or skips; and
- `xcodebuild test` completed successfully in about 299 seconds.

The immutable corpus contains 41 visible and 11 hidden cases:

| Split | Cases | SHA-256 |
| --- | ---: | --- |
| Visible | 41 | `40779ada9addacdad2f028202cc8fb36ff1a328319b9d77bf4c3dcb3968c30c9` |
| Hidden | 11 | `81e0faf5b9f9b7019849118e37c5ca39e1bed9e6cda82644b38ebaefeb6aad3c` |

The hidden set was not inspected or executed. The advancement rule permits a hidden run only for a finalist configuration, and no visible configuration qualified.

The optional online reference was not run because no credential was available. This did not block the local-model decision.

## Runtime provenance and constrained-output audit

The Mac round used a locally built llama.cpp server:

- exact tag: `b10516`;
- source commit: `b95502ba9aa0eb73a2f4fc8878d7fbe6a847a0b9`;
- server: `0.1.2-dev (build 10516, commit b95502ba9a)`;
- server binary SHA-256: `fa65f946a434fcb34de87520ab76a3f2d576f97ad9f5a81b3a6e4201daff137e`;
- compiler: Apple clang 21.0.0 (`clang-2100.1.1.101`), target `arm64-apple-darwin25.2.0`;
- build: Release, Metal enabled, Accelerate enabled, server enabled, curl disabled;
- context: 8,192 tokens;
- maximum output: 256 tokens;
- temperature/top-p: 0.2/0.9;
- seeds: 1103, 2207, and 3301; and
- modes: each model's manifest-declared `off` and `bounded` modes.

The machine was a MacBook Air (`MacBookAir10,1`) with Apple M1, 8 CPU cores, 8 GPU cores, 16 GiB memory, Metal 4, and macOS 26.2 build 25C56.

Two distinct persisted audits cover the constrained runtime path:

- The ordinary tutor-path audit uses the immutable `tutor-v2` prompt and examples and binds all three models and both modes to their model hash, runtime tag/commit/binary hash, schema and grammar hash, effective prompt bundle, exact `/apply-template` suffix hash/shape, and returned-content parse/strict-validation result. All 6 cells passed. Its artifact is `.coaching-eval/analysis/runtime-template-audit-v4-final.json`, SHA-256 `57b11b1baf538331afdb0f2e75e5b3de47f050bfbc5b599538ab9d5613531cc6`.
- The adversarial audit uses the exact hostile stimulus asking for `{}` with every required field missing. It records the stimulus kind/hash, effective request prompt version/hash, model/runtime/schema/grammar bindings, template suffix, HTTP/generation result, and parse/strict-validation result without retaining output or trace content. All 6 cells received responses, parsed as JSON, and passed the unchanged full request-aware validator. Its artifact is `.coaching-eval/analysis/adversarial-schema-smoke-audit-v4-final.json`, SHA-256 `1c9217dc6aa46bd73aca3148e42059746e100a0c66a784f9777d210c5ee0754c`; the adversarial stimulus SHA-256 is `3bc05b297e540519ec98f5bfdac9c3e86ffb1aae5369e918c1d1b52d58f946a8`.

The native grammar is pinned to canonical schema SHA-256 `0f4c427f07cabeae9a6be611eb8a5959b5b916c8648649265d0f4a23f09f15d7`; the builder refuses any other schema hash. Off and bounded prompts had distinct suffix shapes and hashes, all 369 final evaluation mode pairs had different prompt-envelope hashes, and no reasoning marker, trace content, or provider reasoning field appeared in persisted audit, run, review, summary, or error artifacts. Persisting the adversarial evidence did not rerun or change any matrix, score, or advancement decision.

## Candidate artifacts

Candidates were attempted smallest-first and no substitutions were made.

| Candidate | Outcome | Bytes | Resolved revision | SHA-256 | License |
| --- | --- | ---: | --- | --- | --- |
| Qwen3 0.6B Q4_0 | Run | 428,970,080 | `b5f37287796e5be0ea3dab2e7430873fb3f73e49` | `da2572f16c06133561ce56accaa822216f2391ef4d37fba427801cd6736417d4` | Apache-2.0 |
| Gemma 3 1B QAT Q4_0 | Not run: license access unavailable | — | — | — | Gemma Terms |
| Qwen3 1.7B Q4_K_M | Run | 1,282,439,264 | `daeb8e2d528a760970442092f6bf1e55c3b659eb` | `d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5` | Apache-2.0 |
| SmolLM3 3B Q4_K_M | Run | 1,915,305,312 | `4965cb60b150737b68a0408c36aeefb65078f894` | `8334b850b7bd46238c16b0c550df2138f0889bf433809008cc17a8b05761863e` | Apache-2.0 |

Gemma reported the required Gemma Terms acceptance and `HF_TOKEN` guidance and downloaded no substitute.

## Prompt experiment

The visible-only immutable prompt experiment produced `tutor-v2`. It changes only the mechanical contract: the prompt explicitly names and orders the eight required fields, requires a nonempty evidence array, caps action references, and prohibits unknown fields. The semantic example data is unchanged; a dedicated serializer now emits assistant examples in the exact schema/GBNF order instead of hash-canonical sorted order.

Every final effective request differs from its frozen corpus request only in `promptVersion: tutor-v1 -> tutor-v2`; `requestID` remains stable. Each record preserves the frozen and effective request SHA-256 values and the explicit mutation. Every final candidate ran the same complete 246-record matrix (41 cases × 2 real modes × 3 seeds). No output-specific tuning was performed between candidates or modes, and the hidden corpus remained untouched.

Prompt provenance:

- `tutor-v1` SHA-256: `e3b988d525b6b985cf87f2ba20d43d11918ae11399345ed403c77fb88c3a613a`;
- `tutor-v2` SHA-256: `787101c311ce7a851c1e553858b84b98bb6fc4d71cc8d7f7c7e40c6da38ffd5d`; and
- examples bundle SHA-256: `a685f71686f49bde1e092cda103ea07bcac56804c54cd4518af22ac8f29f7239`.

## Visible-set mechanical results

Each complete run contains exactly 246 records, with 123 per mode and 82 per seed. No request was compacted or truncated.

| Model / prompt | First valid / displayable | Repairs / valid | Provider-success records | Context-overflow outcomes | First-overflow cases | All-attempt p50 / p90 | Non-transport-error p50 / p90 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Qwen3 0.6B / v2 | 13 / 13 (5.3%) | 11 / 0 | 72 | 178 | 29/41 | 104 / 4,549 ms | 3,812 / 10,196 ms |
| Qwen3 1.7B / v2 | 15 / 15 (6.1%) | 12 / 0 | 72 | 180 | 29/41 | 100 / 6,820 ms | 6,397 / 12,497 ms |
| SmolLM3 3B / v2 | 12 / 15 (6.1%) | 31 / 3 | 72 | 190 | 29/41 | 51 / 15,498 ms | 8,339 / 31,636 ms |

“Context-overflow outcomes” includes an overflow on either the first attempt or the optional repair. The low all-attempt median is not a sign of responsiveness: most requests failed quickly at the context boundary. The non-transport-error columns better describe generation latency on the Mac.

The conservative byte preflight warned on 23/41 visible cases. Actual first-attempt tokenizer/server rejection covered 29 cases for every candidate. This is the dominant feasibility blocker.

Mode-level displayable validity:

| Model | Off | Bounded |
| --- | ---: | ---: |
| Qwen3 0.6B | 4/123 | 9/123 |
| Qwen3 1.7B | 9/123 | 6/123 |
| SmolLM3 3B | 8/123 | 7/123 |

The explicit grammar prevents completed objects from omitting required fields or adding unknown fields, but it cannot enforce membership in request-specific reference sets. Across the matrix, 54 outputs triggered the one permitted repair and only 3 repaired successfully. Many completed mechanical failures used unavailable action/task IDs or invalid supporting-evidence references.

## Blinded review

A combined public packet was generated from exactly the three `v4-final` run directories; the hardened renderer refuses ambiguous recursive/model-root inputs that could mix run sets. Every v1–v3 artifact was excluded.

- review rows: 738;
- public packet SHA-256: `e5172269d4741064d17fb35a70f4dc8a818490f09f35a145b21fa980284adfe9`;
- blank rubric SHA-256: `dee7cf6b3787f6b8a7af668cc788b311bcc3882dc4e47284e544af7d99c86eb5`; and
- completed rubric SHA-256: `d61c6cdff4b9289ba5c78d4eb31a42e9c5edc34f46af8837782983cf5996ecca`.

The public packet and rubric contained no model, prompt, or runtime identity. An independent reviewer scored all 738 unique rows in packet order before unblinding. The reviewer treated absent, mechanically incomplete, unusable, or clear request/reference-mismatch turns as six 1s plus `severeError = 1`, with the other negative flags left 0. Complete turns were judged against the current interaction, available operations, success criteria, and severe-failure criteria.

Overall blinded scores:

| Positive dimension (1–5) | Mean |
| --- | ---: |
| Factual correctness | 1.26 |
| One coherent step | 1.36 |
| Responsive to latest action | 1.31 |
| Answerability | 1.28 |
| Child clarity | 1.43 |
| Pedagogical usefulness | 1.21 |

| Negative dimension | Count | Rate |
| --- | ---: | ---: |
| Unnecessary interrogation | 7 | 0.9% |
| Mixed stages | 52 | 7.0% |
| Severe error | 671 | 90.9% |

The low negative-flag counts do not offset the severe rate: absent or unusable turns were scored severe without also being labeled as interrogation or mixed-stage problems.

Mode-level blinded quality:

| Model / mode | Fact | One step | Latest action | Answerable | Child clarity | Useful | Interrogation | Mixed | Severe |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Qwen3 0.6B / bounded | 1.23 | 1.27 | 1.24 | 1.23 | 1.31 | 1.18 | 0 | 8 | 115/123 |
| Qwen3 0.6B / off | 1.23 | 1.34 | 1.33 | 1.24 | 1.40 | 1.18 | 0 | 12 | 114/123 |
| Qwen3 1.7B / bounded | 1.22 | 1.28 | 1.24 | 1.23 | 1.34 | 1.19 | 1 | 5 | 114/123 |
| Qwen3 1.7B / off | 1.24 | 1.46 | 1.33 | 1.22 | 1.64 | 1.15 | 3 | 17 | 110/123 |
| SmolLM3 3B / bounded | 1.34 | 1.37 | 1.33 | 1.28 | 1.43 | 1.28 | 3 | 7 | 110/123 |
| SmolLM3 3B / off | 1.32 | 1.45 | 1.42 | 1.48 | 1.46 | 1.30 | 0 | 3 | 108/123 |

### Unblinded verification

After scoring completed, an automated audit followed all 738 review-key pointers and proved that every public packet's position, history, current interaction, latest action, candidate turn, success criteria, and severe-failure criteria matched its exact source record.

Of the 671 severe rows, 661 were mechanically invalid and could not be displayed; 10 were mechanically valid but still severe. Every one of those 10 was manually checked against the FEN, latest action, evidence, permitted references, and oracle:

- Qwen 0.6B produced unrelated opening advice after an attacker tap in two seeds, declared an attacked knight safe after an irrelevant king move, and ignored a supplied mate-in-one hint.
- Qwen 1.7B missed an encoded castling/rook-check state, treated an attacker tap as if the endangered knight had moved in three seeds, invented a knight move to f2, and invented a king/pawn sequence after a staged pawn move.
- SmolLM3 had no severe error among its 15 displayable turns.

Thirty-four additional rows looked usable enough to the blind reviewer to score non-severe but were mechanically invalid. All 34 were inspected after unblinding and remain correctly rejected: each used at least one unavailable or unknown action, board-task, or evidence reference. This does not indicate a validator false positive.

Of the 43 displayable turns, 33 were non-severe. Twenty-eight were non-severe and scored at least 4 on every positive dimension—3.8% of all 738 attempts. Sixteen earned 5 on every positive dimension. This small good subset is real, but much too sparse to satisfy the “broadly usable without editing” advancement rule.

## Advancement rule

The rule is to advance the smallest model whose turns are broadly usable without editing and have no systematic severe failure class, with a second model only for a product-significant quality advantage.

No model meets that rule:

- Qwen 0.6B produced displayable turns on 13/246 attempts (5.3%); 4/13 were severe.
- Qwen 1.7B produced displayable turns on 15/246 attempts (6.1%); 6/15 were severe.
- SmolLM3 produced no severe errors among 15 displayable turns, but only 15/246 attempts (6.1%) were displayable, and only 3/31 repairs succeeded. This is not broad usability.

Result: zero finalists. The hidden set remains unspent, and device model execution is skipped.

## What this round changes

The evaluation supports continuing with provider-neutral coaching contracts, but not integrating any tested GGUF into the app. Before another local-model round:

1. design and test an evidence-preserving compact request that fits the intended device context;
2. extend the corrected grammar with request-specific permitted-reference alternatives so invalid IDs cannot consume a generation;
3. re-evaluate model families or sizes against the new versioned contract on Mac; and
4. advance to iPad latency/thermal testing only after visible outputs are broadly usable and severe-error classes are absent.

Online coaching remains a separate future option. This round does not compare an online reference because no credentialed endpoint was available.

# Local coaching model quality evaluation

Date: 2026-08-28

## Decision

No evaluated local model advances to device testing. Do not execute the model portions of Tasks 6–7.

This is a negative result for the current combination of an 8,192-token context, the full unmodified coaching request, the `model-coaching-turn.v1` contract, and these quantized models. It is not evidence that local coaching is impossible. The current round found three independent blockers:

1. first-attempt context overflow on 29 of the 41 visible cases for every candidate;
2. displayable structured-output validity of only 3.3%–10.6%, with no successful repair; and
3. severe chess, reference, and responsiveness errors even among mechanically valid turns.

The best mechanically valid subset was also too slow and too inconsistent to be broadly usable without editing. The next useful architecture investigation is an explicit evidence-preserving compaction contract and request-specific constrained reference IDs, followed by a new evaluation round. Silently truncating requests or loosening validation would conceal rather than solve the observed failures.

## Methodology correction

The quality numbers in the first version of this report were invalid and are superseded. A review found that llama.cpp b10516 returns from its pure-content `--skip-chat-parsing` path before applying JSON-schema grammar. Those generations were soft-prompt-only even though the harness had requested a schema. A first native-grammar rerun was also superseded before scoring because it forced JSON immediately in both declared modes, so its “bounded” mode did not actually permit bounded reasoning.

The final results below come only from a third, corrected run. The evaluator now asks `/apply-template` to render each model's exact chat prompt and thinking setting, then sends that rendered prompt to native `/completion` with an explicit token-level GBNF. Off mode permits only the strict JSON object. Bounded mode permits exactly one closed, length-bounded `<think>...</think>` envelope followed by the identical strict JSON object. The 256-token output cap is unchanged, and the trace is removed before parsing or persistence. The original and intermediate runs and their review packets remain labeled `superseded-methodology` in ignored evidence; none contributes to the final statistics or decision.

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

The optional online reference was not run: credential unavailable. This did not block the local-model decision.

## Runtime provenance

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

The machine was a MacBook Air (`MacBookAir10,1`) with Apple M1, 8 CPU cores (4 performance/4 efficiency), 8 GPU cores, 16 GiB memory, Metal 4, and macOS 26.2 build 25C56.

The checkout was initially shallow, which made the binary self-report build 1. The source history was unshallowed and the server rebuilt; `runtime_provenance.py record` and `verify` then passed with build 10516 and the binary hash above.

The real HTTP investigation found two independent b10516 integration defects. Its PEG-native assistant postprocessor can reject completed structured content with HTTP 500, while `--skip-chat-parsing` bypasses grammar application. Its JSON-schema converter can also embed a negated prose pattern without intersecting it with JSON-string syntax, allowing the regex to consume a closing quote and produce invalid JSON. The corrected path therefore uses the model's own `/apply-template` result with native `/completion` and an explicit grammar pinned to the canonical schema SHA-256 `0f4c427f07cabeae9a6be611eb8a5959b5b916c8648649265d0f4a23f09f15d7`. The grammar builder refuses any other schema hash; the request-aware Python/Swift-compatible validator remains unchanged.

The final adversarial smoke asked each model to emit `{}` or omit required fields, then inspected the returned content, parsed it, and ran the full strict validator against the exact request. Both off and bounded modes passed for Qwen 0.6B, Qwen 1.7B, and SmolLM3. A separate real `/apply-template` audit showed distinct prompts for all three templates: off mode prefilled an empty thinking block, while bounded mode ended at the assistant prefix. All corrected run pairs had different prompt-envelope hashes, and no trace marker, trace content, or provider reasoning field appeared in a persisted record or review artifact.

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

Before the methodology flaw was found, one visible-only immutable prompt experiment produced `tutor-v2`. It changed only the mechanical contract: the prompt explicitly names and orders the eight required fields, requires a nonempty evidence array, caps action references, and prohibits unknown fields. `examples-v2.json` is byte-identical to `examples-v1.json`, so no named-case tuning was introduced.

After the constrained transport was corrected, `tutor-v2` was frozen without any further prompt or example edits. Every final candidate ran the same complete 246-record matrix (41 cases × 2 real modes × 3 seeds). No output-specific tuning was performed between candidates or modes, and the hidden corpus remained untouched.

Prompt provenance:

- `tutor-v1` SHA-256: `e3b988d525b6b985cf87f2ba20d43d11918ae11399345ed403c77fb88c3a613a`;
- `tutor-v2` SHA-256: `787101c311ce7a851c1e553858b84b98bb6fc4d71cc8d7f7c7e40c6da38ffd5d`; and
- v1/v2 examples SHA-256: `a685f71686f49bde1e092cda103ea07bcac56804c54cd4518af22ac8f29f7239`.

## Visible-set mechanical results

Each complete run contains exactly 246 records with 123 per mode and 82 per seed. No request was compacted or truncated.

| Model / prompt | First valid | Repairs | Valid repairs | Provider-success records | Context-overflow outcomes | First-overflow cases | All-attempt p50 / p90 | Non-transport-error p50 / p90 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Qwen3 0.6B / v2 | 8/246 (3.3%) | 4 | 0 | 72 | 174 | 29/41 | 95 / 5,344 ms | 4,458 / 11,158 ms |
| Qwen3 1.7B / v2 | 11/246 (4.5%) | 0 | 0 | 71 | 174 | 29/41 | 242 / 25,467 ms | 17,801 / 61,633 ms |
| SmolLM3 3B / v2 | 26/246 (10.6%) | 27 | 0 | 67 | 187 | 29/41 | 79 / 39,639 ms | 22,476 / 63,972 ms |

“Context-overflow outcomes” includes an overflow on either the first attempt or the optional repair. The low all-attempt median is not a sign of responsiveness: most requests failed quickly at the context boundary. The non-transport-error columns better describe generation latency on the Mac.

The conservative byte preflight warned on 23/41 visible cases. Actual first-attempt tokenizer/server rejection covered 29 cases for every candidate (174/246 attempts each). SmolLM3 had 13 additional overflows during its one permitted repair, producing 187 overflow outcomes total. This is the dominant feasibility blocker.

Mode-level mechanical validity:

| Model | Off | Bounded |
| --- | ---: | ---: |
| Qwen3 0.6B | 4/123 | 4/123 |
| Qwen3 1.7B | 3/123 | 8/123 |
| SmolLM3 3B | 12/123 | 14/123 |

The explicit grammar prevented a completed object from omitting required fields or adding unknown ones. Thirty-one attempts nevertheless hit the unchanged 256-token cap before closing the constrained object and triggered the one permitted repair; none repaired successfully. Most other completed mechanical failures were request-aware identity or permitted-reference mismatches that a schema-only grammar cannot decide. SmolLM3 also hit five generation failures in addition to overflow.

## Visible quality findings

Mechanical validity was necessary but not sufficient. The corrected constrained path did produce a small number of good turns. For example, SmolLM3 answered the supplied mate-in-one hint with “Your queen can checkmate on g7” and “Move your queen to g7.” Other useful turns correctly identified an endangered piece or acknowledged a wrong tap and advanced the board task.

The mechanically valid subset still contained ten severe turns:

- five regressed after a resolved move, speaking as though the knight or pawn remained on its old square;
- two followed an unrelated staged king move while ignoring the still-exposed knight;
- one repeated a target question the learner had already answered; and
- two ignored the supplied situation in favor of generic opening advice or a false check claim.

These are state-following and chess-grounding failures, not copy polish. They occur in every model family evaluated.

## Blinded review

A combined public packet was generated from exactly the three final corrected visible matrices. Every superseded soft-prompt or mislabeled-mode run was excluded.

- review rows: 738;
- public packet SHA-256: `78bbd0326f73f057a9cdff1d2cb402e75000175b926a3896c9a0a8f116b6092d`; and
- blank rubric SHA-256: `dee7cf6b3787f6b8a7af668cc788b311bcc3882dc4e47284e544af7d99c86eb5`.

The public packet and rubric contained no model, prompt, or runtime identity. An independent reviewer scored every row before unblinding. The aggregate rubric results and severe-row verification follow below.

The completed rubric has 738 unique rows in packet order, no blanks, valid ranges, and SHA-256 `dc91f893586e13099c4008b34404488c7215d846b6291bf0ab1c1a30187bcb0f`. The reviewer did not inspect the review key, run records, model identities, or aggregate results. Their scoring rules were:

- null or otherwise unusable candidates received six 1s and `severeError = 1`;
- clear request/reference mismatches were treated the same way; and
- complete turns were judged against the current interaction, available operations, success criteria, and severe-failure criteria.

Overall blinded scores:

| Positive dimension (1–5) | Mean |
| --- | ---: |
| Factual correctness | 1.32 |
| One coherent step | 1.37 |
| Responsive to latest action | 1.20 |
| Answerability | 1.27 |
| Child clarity | 1.41 |
| Pedagogical usefulness | 1.16 |

| Negative dimension | Count | Rate |
| --- | ---: | ---: |
| Unnecessary interrogation | 19 | 2.6% |
| Mixed stages | 51 | 6.9% |
| Severe error | 680 | 92.1% |

The low negative-flag counts do not offset the severe rate: absent or unusable turns were scored as severe without also being labeled as interrogation or mixed-stage problems.

Mode-level blinded quality:

| Model / mode | Fact | One step | Latest action | Answerable | Child clarity | Useful | Interrogation | Mixed | Severe |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Qwen3 0.6B / bounded | 1.19 | 1.20 | 1.14 | 1.17 | 1.23 | 1.14 | 0 | 3 | 116/123 |
| Qwen3 0.6B / off | 1.35 | 1.50 | 1.22 | 1.21 | 1.60 | 1.14 | 0 | 12 | 114/123 |
| Qwen3 1.7B / bounded | 1.37 | 1.40 | 1.09 | 1.32 | 1.42 | 1.07 | 8 | 11 | 112/123 |
| Qwen3 1.7B / off | 1.30 | 1.42 | 1.17 | 1.33 | 1.46 | 1.11 | 6 | 11 | 114/123 |
| SmolLM3 3B / bounded | 1.41 | 1.40 | 1.32 | 1.36 | 1.41 | 1.28 | 3 | 7 | 110/123 |
| SmolLM3 3B / off | 1.31 | 1.31 | 1.28 | 1.25 | 1.33 | 1.24 | 2 | 7 | 114/123 |

### Severe-row verification

After the rubric was complete, the review key was unblinded. An automated audit followed all 738 review-key pointers and proved that each public packet's position, history, current interaction, latest action, candidate turn, success criteria, and severe-failure criteria exactly matched the original run record.

Of the 680 severe rows, 670 were mechanically invalid and could not be displayed; 10 were mechanically valid but still severe. Every one of those 10 was manually checked against its request and oracle, producing the failure classes listed above. The independent reviewer could not see validator diagnostics. Twenty-three additional rows looked complete enough to score non-severe but failed strict enum or permitted-reference membership and remain rejected by the application gate; all 23 were inspected after unblinding. They ranged from an otherwise good confirmation with an unavailable task ID to unrelated king guidance with invented move references.

Of the 45 mechanically valid turns, 35 were non-severe. Only 18 were non-severe and scored at least 4 on every positive dimension—2.4% of all 738 attempts. Eleven earned 5 on every positive dimension. Representative checks confirmed that this small good subset is real, but narrow and surrounded by mechanical rejection, stage mixing, and severe state-following failures.

## Advancement rule

The rule is to advance the smallest model whose turns are broadly usable without editing and have no systematic severe failure class, with a second model only for a product-significant quality advantage.

No model meets the first half of the rule:

- Qwen 0.6B produced displayable turns on only 3.3% of attempts; half were severe.
- Qwen 1.7B produced displayable turns on only 4.5% of attempts and still made a severe resolved-question regression.
- SmolLM3 produced displayable turns on only 10.6% of attempts and had five severe state-following or invented-purpose errors within that subset.

Result: zero finalists. The hidden set remains unspent, and device model execution is skipped.

## What this round changes

The evaluation supports continuing with provider-neutral coaching contracts, but not integrating any tested GGUF into the app. Before another local-model round:

1. design and test an evidence-preserving compact request that fits the intended device context;
2. extend the corrected grammar with request-specific permitted-reference alternatives so invalid IDs cannot consume a generation;
3. re-evaluate model families or sizes against the new versioned contract on Mac; and
4. advance to iPad latency/thermal testing only after visible outputs are broadly usable and severe-error classes are absent.

Online coaching remains a separate future option. This round does not compare an online reference because no credentialed endpoint was available.

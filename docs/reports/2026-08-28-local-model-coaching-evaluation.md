# Local coaching model quality evaluation

Date: 2026-08-28

## Decision

No evaluated local model advances to device testing. Do not execute the model portions of Tasks 6–7.

This is a negative result for the current combination of an 8,192-token context, the full unmodified coaching request, the `model-coaching-turn.v1` contract, and these quantized models. It is not evidence that local coaching is impossible. The current round found three independent blockers:

1. first-attempt context overflow on 28–29 of the 41 visible cases, depending on tokenizer;
2. displayable structured-output validity of only 0.0%–12.2%, with no successful repair; and
3. repeated severe chess, reference, and responsiveness errors even among mechanically valid turns.

The best mechanically valid subset was also too slow and too inconsistent to be broadly usable without editing. The next useful architecture investigation is an explicit evidence-preserving compaction contract and a more reliable constrained-output path, followed by a new evaluation round. Silently truncating requests or loosening validation would conceal rather than solve the observed failures.

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

The real HTTP schema smoke exposed a b10516 integration defect before scoring. The default PEG-native assistant postprocessor rejected generated Qwen content with HTTP 500 after the exact schema had compiled. Focused RED/GREEN tests added the documented `--skip-chat-parsing` pure-content mode and changed the smoke stimulus from “invent a conforming object” to echoing a known-valid exact object. The mandatory real b10516/Qwen 0.6B smoke then passed with canonical schema SHA-256 `0f4c427f07cabeae9a6be611eb8a5959b5b916c8648649265d0f4a23f09f15d7`. The evaluator's strict Python/Swift-compatible validation remained unchanged.

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

Qwen 0.6B first ran the complete 246-record visible matrix with `tutor-v1` (41 cases × 2 modes × 3 seeds). After it produced no mechanically valid output, `tutor-v2` was created as one immutable, visible-only experiment. It changed only the mechanical contract: the prompt explicitly names and orders the eight required fields, requires a nonempty evidence array, caps action references, and prohibits unknown fields. `examples-v2.json` is byte-identical to `examples-v1.json`, so no named-case tuning was introduced.

The focused two-mode, one-seed v2 probe repeated the same missing-field/invalid-JSON class: 0/2 valid. Prompt tuning stopped at that point; no v3 was created. The larger candidates used the frozen v2 contract because their capacity might follow the explicit structure even though 0.6B could not.

Prompt provenance:

- `tutor-v1` SHA-256: `e3b988d525b6b985cf87f2ba20d43d11918ae11399345ed403c77fb88c3a613a`;
- `tutor-v2` SHA-256: `787101c311ce7a851c1e553858b84b98bb6fc4d71cc8d7f7c7e40c6da38ffd5d`; and
- v1/v2 examples SHA-256: `a685f71686f49bde1e092cda103ea07bcac56804c54cd4518af22ac8f29f7239`.

## Visible-set mechanical results

Each complete run contains exactly 246 records with 123 per mode and 82 per seed. No request was compacted or truncated.

| Model / prompt | First valid | Repairs | Valid repairs | Provider-success records | Context-overflow outcomes | First-overflow cases | All-attempt p50 / p90 | Non-transport-error p50 / p90 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Qwen3 0.6B / v1 | 0/246 (0.0%) | 78 | 0 | 75 | 171 | 28/41 | 220 / 16,031 ms | 14,749 / 20,341 ms |
| Qwen3 1.7B / v2 | 17/246 (6.9%) | 46 | 0 | 72 | 174 | 29/41 | 82 / 21,847 ms | 18,079 / 27,684 ms |
| SmolLM3 3B / v2 | 30/246 (12.2%) | 19 | 0 | 61 | 185 | 29/41 | 48 / 20,872 ms | 9,744 / 42,956 ms |

“Context-overflow outcomes” includes an overflow on either the first attempt or the optional repair. The low all-attempt median is not a sign of responsiveness: most requests failed quickly at the context boundary. The non-transport-error columns better describe generation latency on the Mac.

The conservative byte preflight warned on 23/41 visible cases. Actual first-attempt tokenizer/server rejection covered 28 cases for Qwen 0.6B and 29 for each larger tokenizer. This is the dominant feasibility blocker.

Mode-level mechanical validity:

| Model | Off | Bounded |
| --- | ---: | ---: |
| Qwen3 0.6B | 0/123 | 0/123 |
| Qwen3 1.7B | 17/123 | 0/123 |
| SmolLM3 3B | 13/123 | 17/123 |

Qwen 0.6B's successful transports systematically omitted required metadata; its bounded mode mostly produced empty or invalid content. Qwen 1.7B improved the off-mode shape but still produced invalid JSON, request-ID mismatches, invalid teaching intents, and unknown identifiers. SmolLM3 returned more conforming objects but often chose a board task or evidence identifier that the request did not permit. No repair attempt produced a valid turn for any model.

## Visible quality findings

Mechanical validity was necessary but not sufficient. Spot inspection before blinding found severe mistakes among valid turns:

- Qwen 1.7B claimed a lone king in a quiet position could checkmate on g7 or h8.
- In the mate-in-one case, Qwen 1.7B correctly named the queen's mate but instructed the learner to move the king to g7.
- SmolLM3 sometimes replaced “find the endangered knight” with a question about which black piece the knight could attack.
- SmolLM3 claimed the black king was in check in an unrelated danger case and instructed the child to tap the black king.
- In an endangered-pawn case, SmolLM3 asked which white piece could take the pawn or told the child to tap the attacking bishop rather than help the pawn.

These are not polish issues that could be fixed by editing copy. They reverse the task or invent a chess fact, and they recur across seeds and modes.

## Blinded review

A combined public packet was generated from exactly the three complete visible matrices. The focused v2 probe was excluded.

- review rows: 738;
- public packet SHA-256: `84fa68230ac2d5caf2f421abcd9030d593e83b7c686d4f18702a94817db814bb`; and
- blank rubric SHA-256: `dee7cf6b3787f6b8a7af668cc788b311bcc3882dc4e47284e544af7d99c86eb5`.

The public packet and rubric contained no model, prompt, or runtime identity. An independent reviewer scored every row before unblinding. The aggregate rubric results and severe-row verification follow below.

The completed rubric has 738 unique rows in packet order, no blanks, valid ranges, LF line endings, and SHA-256 `4216e5b916255c12ca2070ea39dfe0de662e4a013503ff6a72247a77600e34df`. The reviewer did not inspect the review key, run records, model identities, or aggregate results. Their scoring rules were:

- absent or mechanically incomplete turns received six 1s and `severeError = 1`, with the other negative flags clear;
- unusable request/reference mismatches were treated the same way;
- complete turns were judged against the current interaction, available operations, success criteria, and severe-failure criteria;
- `unnecessaryInterrogation` marked repeated or already-resolved questioning; and
- `mixedStages` marked incompatible task, message, and instruction phases.

Overall blinded scores:

| Positive dimension (1–5) | Mean |
| --- | ---: |
| Factual correctness | 1.22 |
| One coherent step | 1.25 |
| Responsive to latest action | 1.17 |
| Answerability | 1.19 |
| Child clarity | 1.30 |
| Pedagogical usefulness | 1.15 |

| Negative dimension | Count | Rate |
| --- | ---: | ---: |
| Unnecessary interrogation | 20 | 2.7% |
| Mixed stages | 14 | 1.9% |
| Severe error | 700 | 94.9% |

The low negative-flag counts do not offset the severe rate: absent or unusable turns were scored as severe without also being labeled as interrogation or mixed-stage problems.

Mode-level blinded quality:

| Model / mode | Fact | One step | Latest action | Answerable | Child clarity | Useful | Interrogation | Mixed | Severe |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Qwen3 0.6B / bounded | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 0 | 0 | 123/123 |
| Qwen3 0.6B / off | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 0 | 0 | 123/123 |
| Qwen3 1.7B / bounded | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 0 | 0 | 123/123 |
| Qwen3 1.7B / off | 1.43 | 1.46 | 1.27 | 1.38 | 1.57 | 1.18 | 11 | 6 | 112/123 |
| SmolLM3 3B / bounded | 1.52 | 1.53 | 1.39 | 1.42 | 1.69 | 1.37 | 6 | 4 | 107/123 |
| SmolLM3 3B / off | 1.34 | 1.49 | 1.37 | 1.34 | 1.56 | 1.33 | 3 | 4 | 112/123 |

### Severe-row verification

After the rubric was complete, the review key was unblinded. An automated audit followed all 738 review-key pointers and proved that each public packet's position, history, current interaction, latest action, candidate turn, success criteria, and severe-failure criteria exactly matched the original run record. Every severe row therefore retained its original request evidence.

Of the 700 severe rows:

- 680 were mechanically invalid and could not be displayed. This includes 516 first-attempt context overflows; the other 164 were malformed, incomplete, or reference-invalid structured outputs.
- 20 were mechanically valid but still severe. Each of these 20 was manually checked against the corresponding request and oracle. The failures divide into 15 invented or reversed chess facts/illegal actions, 4 repetitions of a question the learner had already answered, and 1 response that reinforced the learner's wrong piece selection.

The independent reviewer could not see validator diagnostics. Eleven additional rows looked structurally complete in the public packet and were scored non-severe, but failed the mechanical validator on an enum or permitted-reference mismatch. They remain rejected by the application gate. Of the 47 mechanically valid turns, only 27 were non-severe; 19 scored at least 4 on every positive dimension, just 2.6% of all 738 attempts. A representative check of those non-severe rows found both genuinely useful turns and weak but non-severe turns, so `non-severe` is not being treated as equivalent to `broadly usable`.

Representative anonymized turns illustrate the spread:

- A good turn identified the queen's supplied mate-in-one and instructed, “Move your queen to g7.” The 3B model repeated this correctly in both modes and all three seeds.
- A good quiet-position turn said, “This is a quiet position. Choose a legal king move,” followed by the concrete board instruction to tap the king and a square.
- A severe turn said a lone king could checkmate on g7 or h8, moves the king could not make from the encoded position.
- Another named the queen's correct mate square but then instructed the learner to move the king there.
- Several danger turns reversed the supplied attack relationship, asked the learner to capture a king, or repeated the already-answered endangered-piece question.

These examples confirm that the small number of good turns is real, but narrow and surrounded by both mechanical rejection and systematic coaching failures.

## Advancement rule

The rule is to advance the smallest model whose turns are broadly usable without editing and have no systematic severe failure class, with a second model only for a product-significant quality advantage.

No model meets the first half of the rule:

- Qwen 0.6B produced no displayable turn.
- Qwen 1.7B produced displayable turns on only 6.9% of attempts and made severe chess/task errors within that subset.
- SmolLM3 produced displayable turns on only 12.2% of attempts and still showed systematic task reversal and invented-state errors.

Result: zero finalists. The hidden set remains unspent, and device model execution is skipped.

## What this round changes

The evaluation supports continuing with provider-neutral coaching contracts, but not integrating any tested GGUF into the app. Before another local-model round:

1. design and test an evidence-preserving compact request that fits the intended device context;
2. select or build a structured-output path that reliably enforces all required fields without a brittle assistant postprocessor;
3. re-evaluate model families or sizes against the new versioned contract on Mac; and
4. advance to iPad latency/thermal testing only after visible outputs are broadly usable and severe-error classes are absent.

Online coaching remains a separate future option. This round does not compare an online reference because no credentialed endpoint was available.

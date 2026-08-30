# Zero-shot compact coaching evaluation

Date: 2026-08-29
Decision: **Stop after the visible pilot; zero finalists.**

## Question and safety boundary

Can the three pinned local models produce useful chess coaching when the unchanged evidence-preserving compact Markdown is paired with the zero-shot `tutor-v4` prompt?

This round changed no shipping-app code, chess evidence, validator, grammar, token budget, generation setting, or older prompt bundle. It used only the frozen visible corpus. No full visible matrix, hidden inference, or device measurement was run because no pilot candidate passed all fixed gates.

## Frozen provenance

- Evaluation code checkout: `1f8aa0fc9394fd9a7ce44120295bc3b6879ae345`.
- Corpus v2: 52 cases, split 41 visible / 11 hidden; source Git SHA `129f7ab7be75375cc7e507c9e4dad112f3d71c1f`.
- Visible JSONL SHA-256: `1cf0ce770da13a7da84aeb4fba281921ea473d9caaa86ea07ffee6712b320217`.
- Hidden JSONL SHA-256: `ab0a6c46e822b866f4d3d56729d124f6c6fec3d22f8af8f27c6b960a4a1cef8e`; only its manifest hash and line count were checked.
- Corpus manifest SHA-256: `66f7f1b18d3858e565842aa6d276bfae5172343e6d8e2f2b8e2eb577c27b30a3`.
- Fixed pilot SHA-256: `125c18500953de33d8bff5040962a8978b9ff7b1e044de5000f1c07a84391e1a` (10 declared visible IDs).
- `tutor-v4.md` SHA-256: `9c42eed8118c2faa3e0a5e7aff9937dae9ae6b510e4dc4fcb21091e763751477`.
- `examples-v4.json` SHA-256: `37517e5f3dc66819f61f5a7bb8ace1921282415f10551d2defa5c3eb0985b570`; parsed example count: 0.
- Strict turn-schema file SHA-256: `2a562cfa1eec07ed812ca8eaacc821c2617068d542c18248392196dcafad2b91`.
- Canonical native-grammar schema SHA-256: `0f4c427f07cabeae9a6be611eb8a5959b5b916c8648649265d0f4a23f09f15d7`.
- Request-specific grammar source SHA-256: `b3796cf31effc634c0afcc0a3222782c1edc8a9dfbf5a4fe28908138ec556165`.
- Runtime settings SHA-256: `0a228e448786e3e920162f48d8ab29302bb2d3601a07c37b67f1fa243482fef4`.
- llama.cpp: tag `b10516`, source `b95502ba9aa0eb73a2f4fc8878d7fbe6a847a0b9`, binary SHA-256 `fa65f946a434fcb34de87520ab76a3f2d576f97ad9f5a81b3a6e4201daff137e`.
- Model SHA-256 values: Qwen3 0.6B `da2572f16c06133561ce56accaa822216f2391ef4d37fba427801cd6736417d4`; Qwen3 1.7B `d2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5`; SmolLM3 3B `8334b850b7bd46238c16b0c550df2138f0889bf433809008cc17a8b05761863e`.

Model-store verification passed for those three intended artifacts. The configured gated Gemma artifact remained absent and was not part of this three-model design.

Deterministic schema compatibility passed with no errors. The real-runtime hostile-empty-object audit passed JSON parsing and strict request-aware validation for all 3 models × 2 modes, with zero validation issues. Its ignored artifact is `.coaching-eval/analysis/zero-shot-adversarial-schema-smoke-v1.json`, SHA-256 `e84af645d99c6149bb7955a8659404a5ac86ec6fe602702359598ae6b6ff7a57`.

## Exact token-only preflight

Ignored artifact: `.coaching-eval/analysis/zero-shot-preflight-v1.json`, SHA-256 `07fec9afc1a977d1dcd65bf25b09ef1197f125f1cebf94326c74ebb414d8f1ed`.

The audit rendered and tokenized all 60 model × mode × case cells through each GGUF's real chat template without calling completion. Every cell passed the fixed 4,000-token gate, so pilot inference was permitted. Overall distribution: minimum 621, median 756, p90 817, maximum 850; 0/60 exceeded the preferred 3,000-token target and 0/60 exceeded 4,000.

| Model | Mode | Cells | Min | Median | P90 | Max |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Qwen3 0.6B | off | 10 | 625 | 745 | 808 | 817 |
| Qwen3 0.6B | bounded | 10 | 621 | 741 | 804 | 813 |
| Qwen3 1.7B | off | 10 | 625 | 745 | 808 | 817 |
| Qwen3 1.7B | bounded | 10 | 621 | 741 | 804 | 813 |
| SmolLM3 3B | off | 10 | 658 | 778.5 | 841 | 850 |
| SmolLM3 3B | bounded | 10 | 652 | 772.5 | 835 | 844 |

## Visible pilot mechanical result

Each immutable run contains exactly 20 unique model/mode/case/seed records: the fixed 10 cases, both supported modes, and seed 1103. All 60 records are visible, all have `generationStatus = generated`, and none contains a hidden ID, persisted thinking trace, compiler-budget failure, provider context overflow, transport error, or alias-restoration failure.

| Model | First valid | Repairs attempted | Repaired valid | Displayable | Stable-validator failures | Latency p50 / p90 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Qwen3 0.6B | 1/20 | 8 | 1 | 2/20 | 13 | 2,741 / 5,893 ms |
| Qwen3 1.7B | 5/20 | 4 | 1 | 6/20 | 12 | 5,723 / 11,367 ms |
| SmolLM3 3B | 5/20 | 12 | 2 | 7/20 | 3 | 19,415 / 25,642 ms |

The invalid-output issue counts can exceed record counts because one turn may violate several rules. Qwen3 0.6B first attempts recorded 13 duplicate board-focus, 6 duplicate action, 3 duplicate relationship, and 8 invalid-JSON issues; repairs recorded 2 duplicate board-focus, 2 duplicate action, 1 duplicate relationship, and 5 invalid-JSON issues. Qwen3 1.7B first attempts recorded 7 duplicate board-focus, 3 duplicate action, 1 duplicate relationship, and 4 invalid-JSON issues; repairs recorded 1 duplicate board-focus and 2 invalid-JSON issues. SmolLM3 first attempts recorded 2 duplicate board-focus, 1 duplicate action, and 12 invalid-JSON issues; repairs recorded 10 invalid-JSON issues.

Immutable runs:

- `.coaching-eval/runs/qwen3-0.6b-q4_0/visible-20260830T000505.887374Z`: manifest SHA-256 `a8305c2e2677338a327a3d914157f242b1ced81c393d7b312bb2fb639d19ed59`; records SHA-256 `c15d49e986285b5a232f84b3a1eab310933a8b253c701e36e6a32152c5a9fd20`.
- `.coaching-eval/runs/qwen3-1.7b-q4_k_m/visible-20260830T000749.169835Z`: manifest SHA-256 `a7d5af14ee487ef9d408f2b47671f5de4dd0ce4e0f767d52ceb6978576cdd30f`; records SHA-256 `b1bd9e0f0c8835944dbff2bc4bb492ac77b44b3917c093bd87b6385ddc6fa7f0`.
- `.coaching-eval/runs/smollm3-3b-q4_k_m/visible-20260830T001418.276682Z`: manifest SHA-256 `6e3ccb35a179908c2def93d303254481f6c593dc72fce0fca22a5ba7bc2488e3`; records SHA-256 `a97922d75d4181dd08ff6617717d4ec66a00a48580c9814dfcb4be3eb9e9810a`.

## Blinded review

One combined packet was rendered from exactly those three run directories. An independent reviewer received only the public packet, blank rubric, and scoring rules; the reviewer completed all 60 rows in packet order before the review key was opened.

- Directory: `.coaching-eval/reviews/zero-shot-pilot-v1/`.
- Public packet: 60 unique rows; SHA-256 `a30f6489db981b846075462c3055f662b7a084c75aa6766bf0958f7ca4306b23`.
- Completed rubric: 60 unique complete rows; SHA-256 `3d27be84a597a64a7090e7a159da72f64236021073e42ba6661abd032083e43a`.
- Review key SHA-256 after scoring: `33489f5d7a76dff18b3d1edf58e2ce0320da5237a2f7f9ca91dc4dcb074d634e`.
- Aggregate SHA-256: `7238b91c6c1c863651f22e72dccdad1cc6ae004137de5eaa4fca761a286cb1bb`.
- Summary SHA-256: `5c9cd66c25a3aae652c0d6210d9aafc03b1fa3303bf18400bb8c04fee2689f3d`.

All 60 key pointers resolved to one of the three exact records files, and every public position, history, current interaction, latest action, candidate turn, success criterion, and severe-failure criterion matched the pointed source record exactly.

| Model | Fact | One step | Latest | Answerable | Clarity | Useful | Interrogation | Mixed | Severe |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Qwen3 0.6B | 2.80 | 2.70 | 2.30 | 2.35 | 2.65 | 1.80 | 0 | 5 | 10 |
| Qwen3 1.7B | 3.65 | 3.70 | 3.15 | 3.30 | 3.70 | 2.75 | 2 | 3 | 6 |
| SmolLM3 3B | 2.20 | 1.90 | 2.00 | 1.95 | 2.15 | 1.60 | 0 | 4 | 14 |

Overall positive means were 2.88 factual correctness, 2.77 one coherent step, 2.48 responsiveness, 2.53 answerability, 2.83 child clarity, and 2.05 pedagogical usefulness. The 60 rows contained 2 unnecessary-interrogation flags, 12 mixed-stage flags, and 30 severe errors.

### Verified mechanically valid severe rows

Three severe rows were mechanically displayable. Each was checked against its exact source transcript and request:

- `review-00028`, SmolLM3 bounded, `t12Block`: the legal staged move is bishop b5-e2, blocking the black rook's check on the white king. The turn instead says the black rook “is in check.” Transcript SHA-256: `0adc565c33c50b2156c2418670477b71cec4568ff6149087d50a3493d9e0073c`.
- `review-00042`, Qwen3 1.7B bounded, `t12Block`: the turn incorrectly says b5-e2 exchanges the rook on e8, conflating the staged block with the separate b5-e8 capture, and its message is visibly incomplete. Transcript SHA-256: `143abedbe4e3091e37f77801900c6b2e399b3d045552674334895a8ed815da2d`.
- `review-00047`, SmolLM3 bounded, `t11Safe`: the request says the replacement g1-f3 is legal with no immediate refutation and calls for commit or revision. The turn tells the learner to try another move and ends mid-sentence. Transcript SHA-256: `6d89aa124f949312591e261e9044cbd30f72915bd7b32e66c8ead54c24b49965`.

## Fixed advancement gate

A model needed zero compiler/context failures, at least 16 displayable turns, at most 2 severe turns, and at least 12 non-severe turns scoring at least 4 on every positive dimension.

| Model | Compiler/context | Displayable (need 16) | Severe (max 2) | Strong non-severe (need 12) | Advances? |
| --- | ---: | ---: | ---: | ---: | --- |
| Qwen3 0.6B | 0 | 2 | 10 | 2 | no |
| Qwen3 1.7B | 0 | 6 | 6 | 9 | no |
| SmolLM3 3B | 0 | 7 | 14 | 2 | no |

The smaller zero-shot prompt solved the token-budget blocker but did not produce enough mechanically displayable or consistently useful coaching. No model advances. The full visible matrix, hidden set, and device measurement remain untouched. Hidden run-directory count after the decision: 0.

## Verification

- Full CoachingEval suite: 94 passed, 0 failed, 0 skipped.
- Real model/runtime/schema/corpus/prompt provenance: passed as recorded above.
- Real adversarial grammar audit: 6/6 passed strict validation.
- Exact token-only preflight: 60/60 under budget.
- Pilot integrity audit: 60/60 unique expected visible records; no hidden IDs, persisted traces, compiler/context failures, or transport errors.
- Blinded reconciliation: 60/60 packet rows and pointers matched their source records.
- Hidden run-directory count: 0.

The first sandboxed real-runtime smoke attempt failed with `[Errno 1] Operation not permitted` because the process could not bind a loopback port. It created no audit artifact. The identical command was rerun with approved localhost permission and passed; this was an execution-environment restriction, not a model, runtime, or evaluator failure.

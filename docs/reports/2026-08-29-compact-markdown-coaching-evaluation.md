# Compact Markdown coaching evaluation

Date: 2026-08-29
Decision: **Stop after the contract preflight; zero finalists.**

## Question

Would a compact, deterministic chess context written as readable Markdown make the existing local models usable as a five-year-old's chess tutor, while retaining strict structured output and stable app-facing identifiers?

This iteration changed only the evaluation seam. It did not integrate a model into the shipping iPad app, inspect hidden cases, or change the deterministic tutor.

## Context construction outcome

The app now exports a deterministic `model-coaching-context.v1` beside each complete evidence request. The compiler keeps exhaustive status, danger, and safe-capture conclusions; a bounded set of move ideas and inspected replies; the latest learner action; and complete bind-or-omit accounting for every stable reference. It renders those facts as readable `tutor-v3` Markdown with short request-local aliases.

The evaluator sends that Markdown as the final user message. It renders the complete conversation once through the model's own template, tokenizes those exact bytes, and uses the identical rendered prompt for native grammar-constrained completion. A hard 4,000-token compiler budget stops generation before the server's 8,192-token context limit. Responses may contain only aliases printed in the current context; aliases are restored fail-closed and the restored turn is checked by the unchanged complete-request validator.

Each run is persisted atomically. The bounded JSONL record stores hashes/counts and points to a readable per-case transcript containing the exact input Markdown, exact rendered prompt, trace-free response, alias and stable-ID turns, validation, and evidence accounting.

## Frozen inputs

- Corpus v2: 52 cases, split 41 visible / 11 hidden; source `129f7ab7be75375cc7e507c9e4dad112f3d71c1f`.
- Visible corpus SHA-256: `1cf0ce770da13a7da84aeb4fba281921ea473d9caaa86ea07ffee6712b320217`.
- Hidden corpus SHA-256: `ab0a6c46e822b866f4d3d56729d124f6c6fec3d22f8af8f27c6b960a4a1cef8e` (manifest/hash/count verification only; contents were not inspected or run).
- `tutor-v3.md` SHA-256: `d1c6b0dfc1698015e3ebbdd49d59f6544d84159ecb7752cbc1a454e0562409a8`.
- `examples-v3.json` SHA-256: `f2b8b9cde3ecc17c4828d07754b8685b40e02320d9f48cca515041dd17c3fc0b`.
- Strict turn schema file SHA-256: `2a562cfa1eec07ed812ca8eaacc821c2617068d542c18248392196dcafad2b91`.
- Request-specific grammar source SHA-256: `b3796cf31effc634c0afcc0a3222782c1edc8a9dfbf5a4fe28908138ec556165`.
- llama.cpp: tag `b10516`, source `b95502ba9aa0eb73a2f4fc8878d7fbe6a847a0b9`, binary SHA-256 `fa65f946a434fcb34de87520ab76a3f2d576f97ad9f5a81b3a6e4201daff137e`.
- Verified model artifacts: Qwen3 0.6B `da2572f...6417d4`, Qwen3 1.7B `d2387c...bc7b5`, SmolLM3 3B `8334b8...61863e`. Gemma remained unavailable because the gated artifact was not downloaded.

## Contract preflight result

The first real Qwen 0.6B off-mode run used visible case `t12UnsupportedEntry`. Its exact rendered prompt was 5,108 tokens, so the compiler correctly wrote `compilerBudgetExceeded`, set `generationAttempted` to false, and made no completion or repair request.

Because that single result already made the objective pilot gate impossible, model inference stopped. A render-and-tokenize-only audit then measured the same fixed case for all three models and both thinking modes:

| Model | Mode | Prompt bytes | Exact tokens | Generated? |
| --- | --- | ---: | ---: | --- |
| Qwen3 0.6B | off | 20,331 | 5,108 | no |
| Qwen3 0.6B | bounded | 20,312 | 5,104 | no |
| Qwen3 1.7B | off | 20,331 | 5,108 | no |
| Qwen3 1.7B | bounded | 20,312 | 5,104 | no |
| SmolLM3 3B | off | 20,588 | 5,165 | no |
| SmolLM3 3B | bounded | 20,423 | 5,127 | no |

Ignored audit artifact: `.coaching-eval/analysis/compact-context-smoke-v1.json`, SHA-256 `71797d48bc246e7cb7904f9f7585004e7ebf6d9f6e28cb6fbef2a9609dd84f61`.

The persisted real run is `.coaching-eval/runs/qwen3-0.6b-q4_0/visible-20260829T134301.135244Z`. Its manifest SHA-256 is `b4bc574c6950074802d019b0b209bb90a747abafae7e88ab6f4c2b2bf3e1648b`; its records SHA-256 is `e2a7a6b18816c143db613eed31db67f63febbdf39b9293ed17f682b4d0030c28`.

## Why the prompt is still too large

The current case's own compact Markdown is only 1,123 bytes. The fixed system prompt is 3,481 bytes. The eight few-shot examples contribute about 11,261 bytes of example context plus 3,879 bytes of serialized answers, before model-template syntax. In other words, the deterministic current-position context is no longer the dominant problem; the fixed teaching prompt and especially the eight full examples are.

This is still an improvement in architecture: the exact input is understandable, evidence coverage is explicit, local response aliases are enforceable, and compiler overflow is known before generation. It is not yet a viable prompt configuration under the approved 4,000-token budget.

## Pilot gate and model-quality decision

The fixed advancement rule required all 60 pilot prompts to be at most 4,000 exact tokens and zero compiler-budget failures. All six render/tokenize contract cells exceeded 5,100 tokens on even the smallest compact case. Therefore:

- the 60-record inference pilot was not run;
- no candidate response quality or generation latency was measured in this iteration;
- the full 738-record visible matrix and blinded scoring were not run;
- there are zero finalists;
- hidden and device evaluation were not run.

No prompt was tuned against candidate output. The next meaningful experiment should reduce or remove full few-shot contexts—likely starting with zero to two very short examples—and shorten the system contract while preserving request-specific grammar, stable-ID restoration, and the deterministic compact Markdown compiler.

## Verification at the pilot checkpoint

- Complete Python evaluator suite after Task 5: 80 passed, 0 failed, 0 skipped.
- Focused lifecycle/budget/alias/transcript/review/summary suite: 46 passed, 0 failed, 0 skipped.
- Real fake-server v2-corpus E2E: valid stable turn, 2,000 synthetic tokenizer tokens, transcript hash matched its record, and review/summary completed.
- Runtime provenance, deterministic schema compatibility, three intended model artifacts, corpus counts/hashes, prompt hashes, and examples hashes were re-verified before real inference.
- One harness-only transcript issue was caught by the first real run: Qwen's thinking-off template includes an empty `<think></think>` control block in the exact prompt. The transcript now preserves that empty control syntax but continues to reject non-empty, unclosed, or residual private reasoning.

## Final verification

- Full ChessTutor scheme: 832 passed, 0 failed, 0 skipped, 0 expected failures. Result bundle: `/tmp/chess-compact-markdown-final-20260829.xcresult`.
- Standalone `xcodebuild build` for the iPad (A16) simulator: exit 0.
- Full evaluator suite on the final code: 82 passed, 0 failed, 0 skipped.
- `python3 -m py_compile Tools/CoachingEval/*.py`: passed.
- Runtime provenance, all three intended model artifacts, schema, corpus, prompt, and examples reverified.
- Six-cell render/tokenize audit reverified; all six cells exceeded the compiler budget and none generated.
- Real stopped-run transcript SHA-256 `29253d8f578df025c146a3e655ab0aad188812e3a2a31513704af20e8661d622` matches its record.
- Hidden run count: 0.
- `git diff --check`: clean.

The full UI suite emitted repeated non-fatal `DebuggerVersionStore` / “no debugger version” warnings during simulator launches, as prior green runs did. They did not produce a test failure.

Implementation checkpoints: `109eac7` added exact compact-prompt evaluation and transcripts; `1e59d04` added the fixed pilot selector and recorded the stopped-pilot result. The final conclusion remains: the compact deterministic context is sound and much easier to inspect, but the current eight-example prompt bundle is too large for this evaluation's 4,000-token compiler budget. No claim about local-model tutoring quality can be made from this iteration because inference was intentionally not run after the gate failed.

# Coaching model evaluator

This directory is an evaluation harness, not a shipping tutor. It sends the provider-neutral coaching requests exported by the app to pinned GGUF models on a Mac, validates the returned `ModelCoachingTurn`, and creates blinded human-review artifacts. The ChessTutor target does not import or invoke these tools.

All downloaded models, runtime builds, corpus exports, raw generations, hidden-set results, review keys, and scores live under the ignored `.coaching-eval/` directory. Do not copy credentials or artifacts into this directory or source control.

## Requirements

- Python 3.9 or newer; the harness uses only the standard library.
- Xcode, XcodeGen, and the `iPad (A16)` simulator for corpus export.
- llama.cpp tag `b10516` at source commit `b95502ba9aa0eb73a2f4fc8878d7fbe6a847a0b9`, with `llama-server` built at `.coaching-eval/runtime/b10516/bin/llama-server`.
- Enough local disk space for the selected GGUF candidates.

The runtime settings are fixed in `runtime.json`: 8192 context tokens, at most 256 output tokens, temperature 0.2, top-p 0.9, and seeds 1103, 2207, and 3301. Do not change that file during a comparison round.

## Hosted coaching quality benchmark

The current hosted coach has a separate production-shaped benchmark for comparing a model, reasoning settings, system prompt, or deterministic user-prompt compiler. The simplest development run is:

```bash
./scripts/run_coaching_quality_benchmark.sh quick
```

The script reads `ChessTutor-CoachingEval-OpenAI` from Keychain, exports a fresh 70-turn corpus from Swift, runs the production configuration, calibrates the pinned automatic judge, and writes an ignored report beneath `.coaching-eval/benchmark/runs/<timestamp>/report/summary.md`. It never places the key in a command argument or artifact.

Compare one or more candidate configuration files against production with three repetitions per case:

```bash
./scripts/run_coaching_quality_benchmark.sh comparison path/to/candidate.json
```

Holdout cases require an explicit opt-in:

```bash
./scripts/run_coaching_quality_benchmark.sh comparison --include-holdout path/to/candidate.json
```

Before a paid matrix, use the five-turn diagnostic smoke. It is always marked ineligible for promotion:

```bash
./scripts/run_coaching_quality_benchmark.sh comparison --smoke path/to/candidate.json
```

Each phase can also be run directly:

```bash
python3 -m Tools.CoachingEval.benchmark.cli run \
  --corpus .coaching-eval/benchmark/corpus/<export> --mode comparison \
  --candidate Tools/CoachingEval/benchmark/configs/production-v1.json \
  --candidate path/to/candidate.json \
  --pricing Tools/CoachingEval/benchmark/pricing-v1.json \
  --output .coaching-eval/benchmark/runs/<run>/candidates

python3 -m Tools.CoachingEval.benchmark.cli grade \
  --run .coaching-eval/benchmark/runs/<run>/candidates \
  --corpus .coaching-eval/benchmark/corpus/<export> \
  --judge Tools/CoachingEval/benchmark/configs/judge-v1.json \
  --pricing Tools/CoachingEval/benchmark/pricing-v1.json \
  --output .coaching-eval/benchmark/runs/<run>/grades

python3 -m Tools.CoachingEval.benchmark.cli report \
  --run .coaching-eval/benchmark/runs/<run>/candidates \
  --grades .coaching-eval/benchmark/runs/<run>/grades \
  --pricing Tools/CoachingEval/benchmark/pricing-v1.json \
  --output .coaching-eval/benchmark/runs/<run>/report
```

`report` is entirely offline and can regenerate a report from frozen responses and grades. Reports keep quality separate from operations: they show mechanical validity, severe errors, each of the six rubric dimensions, strong-response rate, pairwise wins/losses/ties, p50/p90 latency, candidate token cost, and separately labeled judge overhead. The Pareto frontier includes configurations not dominated simultaneously on strong-response rate, severe errors, p90 latency, and candidate cost; there is deliberately no opaque combined score.

To test a new prompt or model, copy `configs/production-v1.json`, change only the intended fields, and pin all referenced hashes. To test a new deterministic user-prompt generator, add a named entry to `PROMPT_GENERATORS` in `benchmark/configuration.py` plus compiler and benchmark tests; configuration files cannot load arbitrary code. Pricing is an immutable, dated estimate: add a new `pricing-v<number>.json` from an official source rather than rewriting an old table.

To promote an interesting production trace into the corpus, copy its game ID from the app's About sheet, filter the retained JSONL as described in `docs/hosted-coaching-server.md`, and reproduce the chosen turn mechanically in `CoachingQualityBenchmarkCorpus.swift`. Add the grader brief separately; never copy the model response into the candidate request or derive the oracle from it. A fixture or grader-brief change creates a new corpus version.

Provider and judge calls are intentionally absent from pull-request CI because they require credentials, cost money, and have variable external latency. CI covers the corpus, contracts, fake providers, calibration gates, aggregation, and command workflow.

## Export the real corpus

From the repository root:

```bash
COACHING_EVAL_OUTPUT_DIR="$PWD/.coaching-eval/corpus/v2" \
COACHING_EVAL_SOURCE_SHA="$(git rev-parse HEAD)" \
xcodebuild test -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingCorpusExportTests
```

This creates `visible.jsonl`, `hidden.jsonl`, and `corpus-manifest.json`. The exporter refuses to overwrite a nonempty destination. While tuning the prompt, use only `visible.jsonl`; do not inspect or render hidden outputs. Changing the prompt or examples after a hidden run requires a new version and a complete rerun.

## Model artifacts

List the exact candidates:

```bash
python3 Tools/CoachingEval/model_store.py list
```

Fetch and verify one candidate:

```bash
python3 Tools/CoachingEval/model_store.py fetch qwen3-0.6b-q4_0
python3 Tools/CoachingEval/model_store.py verify
```

Or attempt every candidate in manifest order:

```bash
python3 Tools/CoachingEval/model_store.py fetch-all
```

The resolver turns repository `main` into an immutable revision, chooses the exact configured quantization, streams the bytes, and writes an `artifact-manifest.json` with the revision, byte count, and SHA-256. An existing file is reused only when both its size and SHA-256 match. `fetch-all` continues to later accessible models after an access failure, prints one structured outcome per candidate, and exits nonzero if any candidate failed. `HF_TOKEN` is read only for exact HTTPS requests to `huggingface.co` and is never written. Authorization is stripped on every redirect that changes scheme, host, or effective port. Gemma requires prior acceptance of the Gemma Terms and `HF_TOKEN`; missing and rejected credentials produce that direct guidance instead of substituting another model.

## Pin and smoke-test the runtime

After building the exact tag, record the binary's actual `--version` output and SHA-256:

```bash
python3 Tools/CoachingEval/runtime_provenance.py record \
  --server .coaching-eval/runtime/b10516/bin/llama-server \
  --manifest .coaching-eval/runtime/b10516/runtime-manifest.json
python3 Tools/CoachingEval/runtime_provenance.py verify \
  --server .coaching-eval/runtime/b10516/bin/llama-server \
  --manifest .coaching-eval/runtime/b10516/runtime-manifest.json
```

The runner refuses a missing manifest, a source tag/commit mismatch, changed version output, or changed binary hash. First run the deterministic schema preflight, then prove that the pinned server enforces the exact turn contract through its HTTP grammar path:

```bash
python3 Tools/CoachingEval/schema_compat.py
python3 Tools/CoachingEval/schema_compat.py \
  --smoke-server .coaching-eval/runtime/b10516/bin/llama-server \
  --smoke-model .coaching-eval/models/qwen3-0.6b-q4_0/Qwen3-0.6B-Q4_0.gguf \
  --prompt-version tutor-v2 \
  --runtime-manifest .coaching-eval/runtime/b10516/runtime-manifest.json
```

The real pinned-server smoke is mandatory before model comparisons. It adversarially asks for `{}`, inspects the returned content, parses exactly one JSON object, and applies the complete request-aware validator. The unit suite exercises the hook with a fake server, but that is not evidence that a locally built b10516 runtime enforced the grammar.

Persist an ordinary tutor-path audit binding every exact model artifact and both thinking modes to the runtime, schema/grammar, immutable tutor prompt, applied-template suffix, and parsed/strictly validated returned content:

```bash
python3 Tools/CoachingEval/schema_compat.py \
  --smoke-server .coaching-eval/runtime/b10516/bin/llama-server \
  --runtime-manifest .coaching-eval/runtime/b10516/runtime-manifest.json \
  --prompt-version tutor-v2 \
  --audit-model qwen3-0.6b-q4_0=.coaching-eval/models/qwen3-0.6b-q4_0/Qwen3-0.6B-Q4_0.gguf \
  --audit-model qwen3-1.7b-q4_k_m=.coaching-eval/models/qwen3-1.7b-q4_k_m/Qwen3-1.7B-Q4_K_M.gguf \
  --audit-model smollm3-3b-q4_k_m=.coaching-eval/models/smollm3-3b-q4_k_m/SmolLM3-Q4_K_M.gguf \
  --audit-output .coaching-eval/analysis/runtime-template-audit-v4-final.json
```

The audit manifest contains hashes and pass/fail facts, never rendered prompts, model output, or thinking traces.

Persist the distinct adversarial audit as well. It runs `ADVERSARIAL_SMOKE_PROMPT`, which explicitly asks for `{}` with every required field missing, through the same `/apply-template` plus native grammar path for all three models and both modes:

```bash
python3 Tools/CoachingEval/schema_compat.py \
  --smoke-server .coaching-eval/runtime/b10516/bin/llama-server \
  --runtime-manifest .coaching-eval/runtime/b10516/runtime-manifest.json \
  --prompt-version tutor-v2 \
  --audit-model qwen3-0.6b-q4_0=.coaching-eval/models/qwen3-0.6b-q4_0/Qwen3-0.6B-Q4_0.gguf \
  --audit-model qwen3-1.7b-q4_k_m=.coaching-eval/models/qwen3-1.7b-q4_k_m/Qwen3-1.7B-Q4_K_M.gguf \
  --audit-model smollm3-3b-q4_k_m=.coaching-eval/models/smollm3-3b-q4_k_m/SmolLM3-Q4_K_M.gguf \
  --adversarial-audit-output .coaching-eval/analysis/adversarial-schema-smoke-audit-v4-final.json
```

The adversarial manifest records the stimulus and effective-request hashes, HTTP/generation outcomes, and parse/strict-validation facts without retaining returned content or thinking traces. It is evidence that grammar enforcement defeats the hostile missing-fields instruction; the ordinary audit separately proves the real tutor prompt and examples use the expected template shape.

## Run local models

Place the `b10516` binary at the path above, then run visible cases:

```bash
python3 Tools/CoachingEval/run_eval.py local \
  --model qwen3-0.6b-q4_0 \
  --split visible \
  --corpus .coaching-eval/corpus/v2/visible.jsonl \
  --prompt-version tutor-v3
```

After freezing the prompt and examples, run hidden cases once:

```bash
python3 Tools/CoachingEval/run_eval.py local \
  --model qwen3-0.6b-q4_0 \
  --split hidden \
  --corpus .coaching-eval/corpus/v2/hidden.jsonl \
  --prompt-version tutor-v3
```

Use `--mode off` or `--mode bounded` to select one supported thinking mode, `--case t1Entry` for a focused case, and `--repetitions 1` for a smoke test. Without those overrides, the evaluator runs every model-supported mode and all three pinned seeds. The server is bound to an ephemeral `127.0.0.1` port, must pass `/health`, and is stopped in `finally`; a request timeout terminates its process group.

The committed compact-context pilot is selected with:

```bash
python3 Tools/CoachingEval/run_eval.py local \
  --model qwen3-0.6b-q4_0 --split visible \
  --case-list Tools/CoachingEval/pilots/compact-markdown-v1.json \
  --repetitions 1 --corpus .coaching-eval/corpus/v2/visible.jsonl \
  --prompt-version tutor-v3
```

The runner accepts only the exact immutable ten visible IDs in that manifest, in its declared order. It rejects duplicates, missing cases, hidden cases, a reordered manifest, or combining `--case` with `--case-list`.

The 2026-08-29 compact-context round stopped at its pre-inference gate: the six model/mode render-and-tokenize cells for the small `t12UnsupportedEntry` case were 5,104–5,165 tokens, above the fixed 4,000-token compiler budget. The 60-record pilot, full matrix, hidden set, and device run were therefore not performed. `tutor-v4` is the immutable zero-shot compact-context successor: it removes few-shot examples without weakening the evidence or output validators. See `docs/reports/2026-08-29-compact-markdown-coaching-evaluation.md` before starting another comparison.

## Preview the neutral v5 prompts without inference

The neutral v5 prompt compiler has a separate human-approval gate. First export the eight production-shaped examples from Swift into a fresh ignored directory:

```bash
COACHING_NEUTRAL_PREVIEW_DIR="$PWD/.coaching-eval/neutral-prompt-preview/swift" \
xcodebuild test -quiet -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingNeutralPromptExampleTests
```

Then render the exact system/user conversations through the pinned Qwen3 1.7B chat template and count the rendered tokens:

```bash
python3 Tools/CoachingEval/preview_neutral_prompts.py \
  --source .coaching-eval/neutral-prompt-preview/swift \
  --system-prompt Tools/CoachingEval/prompts/tutor-v5.md \
  --server .coaching-eval/runtime/b10516/bin/llama-server \
  --runtime-manifest .coaching-eval/runtime/b10516/runtime-manifest.json \
  --model .coaching-eval/models/qwen3-1.7b-q4_k_m/Qwen3-1.7B-Q4_K_M.gguf \
  --model-manifest .coaching-eval/models/qwen3-1.7b-q4_k_m/artifact-manifest.json \
  --destination .coaching-eval/neutral-prompt-preview/final
```

Apart from `/health` readiness checks while the local server starts, this command calls only the server's template-rendering and tokenization endpoints. It does not request a completion, import evaluator scoring, or retain a model reply. It writes `preview-manifest.json` plus eight complete logical transcripts under `prompts/`, refuses any existing destination, and fails if a rendered prompt exceeds 2,500 tokens. Review those exact system and user messages before authorizing any model run.

## Preview the chess-native v6 prompts without inference

The chess-native v6 prompt has the same human-approval gate, using its separate Swift export and preview command. Export the eight canonical production-history situations to a fresh ignored directory:

```bash
COACHING_CHESS_NATIVE_PREVIEW_DIR="$PWD/.coaching-eval/chess-native-prompt-preview/swift-export-v2" \
xcodebuild test -quiet -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingChessNativePromptExampleTests
```

Then apply the pinned Qwen3 1.7B chat template and count tokens, without requesting a model response:

```bash
python3 Tools/CoachingEval/preview_chess_native_prompts.py \
  --source .coaching-eval/chess-native-prompt-preview/swift-export-v2 \
  --system-prompt Tools/CoachingEval/prompts/tutor-v6.md \
  --server .coaching-eval/runtime/b10516/bin/llama-server \
  --runtime-manifest .coaching-eval/runtime/b10516/runtime-manifest.json \
  --model .coaching-eval/models/qwen3-1.7b-q4_k_m/Qwen3-1.7B-Q4_K_M.gguf \
  --model-manifest .coaching-eval/models/qwen3-1.7b-q4_k_m/artifact-manifest.json \
  --destination .coaching-eval/chess-native-prompt-preview/final
```

The v6 preview parses the audit-only `preview-manifest.json` solely as a role-and-hash control plane. It renders only the file declared as `modelFacingSystemMessage` and the eight ordered files declared as `modelFacingUserMessage`; the audit-only `examples.jsonl` is never parsed or rendered. The narrow runtime client permits only `/health`, `/apply-template`, and `/tokenize`. The immutable packet contains eight complete system/user transcripts and a hash-bound `preview-manifest.json`, with no assistant message, response, reasoning trace, hidden case, generation, scoring, or inference. Every rendered prompt must stay at or below 2,500 tokens; the manifest separately reports how many fall in the preferred 500–1,500-token range. Review these exact transcripts before authorizing any later model completion.

Before any `tutor-v4` pilot inference, run the token-only preflight against all three exact model artifacts. It starts one pinned server at a time, renders and tokenizes the fixed ten visible pilot cases in off and bounded modes, never calls `/completion`, writes one immutable 60-cell manifest, and exits nonzero if any exact prompt exceeds 4,000 tokens:

```bash
python3 Tools/CoachingEval/preflight_prompts.py \
  --server .coaching-eval/runtime/b10516/bin/llama-server \
  --runtime-manifest .coaching-eval/runtime/b10516/runtime-manifest.json \
  --corpus .coaching-eval/corpus/v2/visible.jsonl \
  --pilot Tools/CoachingEval/pilots/compact-markdown-v1.json \
  --prompt-version tutor-v4 \
  --model qwen3-0.6b-q4_0=.coaching-eval/models/qwen3-0.6b-q4_0/Qwen3-0.6B-Q4_0.gguf \
  --model qwen3-1.7b-q4_k_m=.coaching-eval/models/qwen3-1.7b-q4_k_m/Qwen3-1.7B-Q4_K_M.gguf \
  --model smollm3-3b-q4_k_m=.coaching-eval/models/smollm3-3b-q4_k_m/SmolLM3-Q4_K_M.gguf \
  --output .coaching-eval/analysis/zero-shot-preflight-v1.json
```

The manifest records the exact rendered-prompt byte/token/hash provenance per cell, alongside the immutable prompt, corpus, pilot, model, and runtime hashes. It refuses an existing output path rather than overwriting evidence.

Local generation uses two documented b10516 endpoints. `/apply-template` renders the model's own template and thinking-mode setting without inference. The resulting prompt is sent to native `/completion` with the pinned strict `model-coaching-turn.v1` GBNF, bypassing the PEG-native chat response parser while retaining token-level grammar enforcement. The grammar builder refuses any schema hash other than the immutable contract; its bounded prose rules are JSON-safe and slightly stricter than the schema because they disallow `\\u` escapes. The evaluator then applies the unchanged strict Python/Swift-compatible identity, word-limit, and permitted-reference validator.

For compact `tutor-v3` and zero-shot `tutor-v4`, the final user message is the corpus's exact human-readable compact Markdown—not the complete JSON evidence request. The evaluator renders the full conversation exactly once with `/apply-template`, tokenizes that exact rendered string with `/tokenize`, and passes the same bytes to `/completion`. It refuses generation above the unchanged 4,000 exact-token compiler budget. The response grammar is request-specific: it pins the request ID and permits only the short aliases printed in that Markdown. After generation, aliases are restored fail-closed to stable IDs and the unchanged complete-request validator checks the restored turn. A repair is allowed only for parse/shape failure; its newly rendered prompt is independently tokenized and must also fit the 4,000-token compiler budget.

Off mode constrains generation to the JSON object alone. Bounded mode constrains generation to exactly one closed `<think>...</think>` envelope (at most 128 non-`<` characters, with at most two line breaks on either side) followed by the identical strict JSON object. The total output cap remains 256 tokens. The envelope is removed before parsing and persistence; no reasoning marker or content is written to records or review artifacts.

This explicit grammar is required because b10516's JSON-Schema converter embeds a string `pattern` without intersecting it with JSON string syntax. A negated word class can therefore consume a closing quote and permit invalid JSON even though the server logs a converted grammar. The mandatory real-runtime adversarial smoke protects against that regression.

`runtime.json` selects the immutable `tutor-v1` prompt bundle by default. Use `--prompt-version tutor-v<number>` to select another committed `prompts/tutor-v<number>.md` plus matching `prompts/examples-v<number>.json` pair. The runner creates an effective evaluation request by changing only the frozen request's `promptVersion`; the opaque request ID remains stable. Model-facing requests, few-shot request excerpts, response validation, and recorded evaluation cases all use that effective version. Each record also binds the frozen and effective request hashes plus the explicit mutation. Assistant examples use the exact top-level property order required by the GBNF. Sorted canonical JSON is used only for hashing and user-request serialization. The selected prompt paths and hashes are recorded, and aliases such as `latest` are rejected.

Every record preserves hashes and byte/token counts for the frozen request, effective request, compact Markdown, rendered prompts, grammar, alias turn, and restored stable-ID turn, plus the model artifact hash, runtime tag, settings, validation, timings, split, and bounded errors. Exact rendered prompts are deliberately not duplicated into `records.jsonl`. Each record instead points to `transcripts/<case>--<mode>--<seed>.md` and binds that file by SHA-256. The transcript presents the exact readable Markdown input, exact rendered attempt prompt, trace-free response, alias/stable turns, validation, and complete included/omitted evidence accounting. Runs are written to a temporary sibling directory, fsynced, and atomically renamed; existing destinations and transcript collisions are refused.

Legacy `tutor-v1`/`tutor-v2` records retain their original complete-JSON path for reproducibility. Compact `tutor-v3`/`tutor-v4` paths never truncate either the Markdown or rendered prompt: over-budget prompts become explicit `compilerBudgetExceeded` records before inference, while provider context rejection remains a distinct `contextOverflow` outcome.

Provider `reasoning_content` is ignored. Repeated, prefixed, case-variant, and embedded `<think>…</think>` blocks are removed before persistence; any unresolved trace marker fails closed to empty final content. HTTP error response bodies are discarded at the client boundary. Run records retain only a bounded status/category message, which is rebuilt again at persistence rather than copying exception text. Only sanitized final response content is persisted or scored. Repair is attempted at most once and only for invalid JSON or response shape—not for an identity/reference error or a pedagogically weak turn.

An exact rendered prompt may contain the model template's empty `<think></think>` control block when thinking is disabled. Transcripts retain that empty syntax because removing it would falsify the bytes that were tokenized and sent. The transcript guard allows only an empty whitespace-only block in the prompt; non-empty, unclosed, output, or provider reasoning remains forbidden.

## Optional online reference

The reference runner reads only these environment variables:

```bash
export COACHING_EVAL_REFERENCE_URL='https://provider.example/v1'
export COACHING_EVAL_REFERENCE_MODEL='model-name'
export COACHING_EVAL_REFERENCE_API_KEY='developer-secret'
python3 Tools/CoachingEval/run_eval.py reference --split visible
```

Credentialed reference endpoints must be HTTPS, and Authorization is never forwarded across an origin-changing redirect. Reference payloads omit llama.cpp-only `chat_template_kwargs`. The online result is a comparison ceiling, not an automatic judge. Never place the key in the app, a tracked file, shell history, or a run artifact.

## Blinded review and scoring

Each invocation creates an immutable timestamped run below `.coaching-eval/runs/<model>/`. Create a review packet from one exact timestamped run directory:

```bash
python3 Tools/CoachingEval/render_review.py \
  --run .coaching-eval/runs/qwen3-0.6b-q4_0/visible-<timestamp>
```

For a combined comparison, repeat `--run` for each model and provide `--output <directory>`. The recorded review seed deterministically shuffles outputs. `review-packet.jsonl` shows the position, history, latest action, candidate turn, success criteria, and severe-failure criteria without model identity. Keep `review-key.json` private until scoring is complete.

```bash
python3 Tools/CoachingEval/render_review.py \
  --run .coaching-eval/runs/qwen3-0.6b-q4_0/visible-<timestamp> \
  --run .coaching-eval/runs/qwen3-1.7b-q4_k_m/visible-<timestamp> \
  --output .coaching-eval/reviews/combined-v1
```

The renderer deliberately refuses a model root or any other recursive input so a packet cannot silently mix superseded and current run records.

Fill every score cell in `rubric.csv`:

- `factualCorrectness`, `oneCoherentStep`, `responsiveToLatestAction`, `answerability`, `childClarity`, and `pedagogicalUsefulness`: integers 1–5;
- `unnecessaryInterrogation`, `mixedStages`, and `severeError`: 0 or 1;
- `notes`: optional reviewer context.

Then summarize:

```bash
python3 Tools/CoachingEval/summarize_eval.py \
  --run .coaching-eval/reviews/combined-v1
```

The summarizer refuses missing or incomplete scored rows. It writes `aggregate.json` and `summary.md` with every rubric dimension, first-attempt and repaired validity, severe errors, p50/p90 latency, rendered-prompt token min/p50/p90/max, compiler-budget failures, provider context overflows, alias-restoration failures, stable-validator failures, configurations, and raw examples by case. It intentionally has no single combined score.

## Test-only end-to-end smoke test

The fake model is rejected unless explicitly enabled. It still uses the subprocess, health check, HTTP request, schema validation, review, and summary paths:

```bash
COACHING_EVAL_ALLOW_FAKE=1 python3 Tools/CoachingEval/run_eval.py local \
  --model fake-test-model --split visible --case t12UnsupportedEntry --repetitions 1 \
  --corpus .coaching-eval/corpus/v2/visible.jsonl --prompt-version tutor-v3
python3 Tools/CoachingEval/render_review.py --run .coaching-eval/runs/fake-test-model/visible-<timestamp>
python3 Tools/CoachingEval/summarize_eval.py --run .coaching-eval/runs/fake-test-model/visible-<timestamp>
```

The fake renderer adds an explicitly labeled synthetic rubric row only so this automated path can reach the summary gate. It is never a quality measurement.

## Verification and cleanup

```bash
python3 -m unittest discover -s Tools/CoachingEval/tests -v
xcodebuild test -project ChessTutor.xcodeproj -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingTurnValidatorTests
python3 Tools/CoachingEval/schema_compat.py
git diff --check
```

After safely copying any evidence needed for the report, remove local evaluation artifacts with:

```bash
rm -rf .coaching-eval
```

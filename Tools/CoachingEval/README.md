# Coaching model evaluator

This directory is an evaluation harness, not a shipping tutor. It sends the provider-neutral coaching requests exported by the app to pinned GGUF models on a Mac, validates the returned `ModelCoachingTurn`, and creates blinded human-review artifacts. The ChessTutor target does not import or invoke these tools.

All downloaded models, runtime builds, corpus exports, raw generations, hidden-set results, review keys, and scores live under the ignored `.coaching-eval/` directory. Do not copy credentials or artifacts into this directory or source control.

## Requirements

- Python 3.9 or newer; the harness uses only the standard library.
- Xcode, XcodeGen, and the `iPad (A16)` simulator for corpus export.
- llama.cpp tag `b10516` at source commit `b95502ba9aa0eb73a2f4fc8878d7fbe6a847a0b9`, with `llama-server` built at `.coaching-eval/runtime/b10516/bin/llama-server`.
- Enough local disk space for the selected GGUF candidates.

The runtime settings are fixed in `runtime.json`: 8192 context tokens, at most 256 output tokens, temperature 0.2, top-p 0.9, and seeds 1103, 2207, and 3301. Do not change that file during a comparison round.

## Export the real corpus

From the repository root:

```bash
COACHING_EVAL_OUTPUT_DIR="$PWD/.coaching-eval/corpus/v1" \
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
  --runtime-manifest .coaching-eval/runtime/b10516/runtime-manifest.json
```

The real pinned-server smoke is mandatory before model comparisons. It adversarially asks for `{}`, inspects the returned content, parses exactly one JSON object, and applies the complete request-aware validator. The unit suite exercises the hook with a fake server, but that is not evidence that a locally built b10516 runtime enforced the grammar.

## Run local models

Place the `b10516` binary at the path above, then run visible cases:

```bash
python3 Tools/CoachingEval/run_eval.py local \
  --model qwen3-0.6b-q4_0 --split visible
```

After freezing the prompt and examples, run hidden cases once:

```bash
python3 Tools/CoachingEval/run_eval.py local \
  --model qwen3-0.6b-q4_0 --split hidden
```

Use `--mode off` or `--mode bounded` to select one supported thinking mode, `--case t1Entry` for a focused case, and `--repetitions 1` for a smoke test. Without those overrides, the evaluator runs every model-supported mode and all three pinned seeds. The server is bound to an ephemeral `127.0.0.1` port, must pass `/health`, and is stopped in `finally`; a request timeout terminates its process group.

Local generation uses two documented b10516 endpoints. `/apply-template` renders the model's own template and thinking-mode setting without inference. The resulting prompt is sent to native `/completion` with the pinned strict `model-coaching-turn.v1` GBNF, bypassing the PEG-native chat response parser while retaining token-level grammar enforcement. The grammar builder refuses any schema hash other than the immutable contract; its bounded prose rules are JSON-safe and slightly stricter than the schema because they disallow `\\u` escapes. The evaluator then applies the unchanged strict Python/Swift-compatible identity, word-limit, and permitted-reference validator.

Off mode constrains generation to the JSON object alone. Bounded mode constrains generation to exactly one closed `<think>...</think>` envelope (at most 128 non-`<` characters, with at most two line breaks on either side) followed by the identical strict JSON object. The total output cap remains 256 tokens. The envelope is removed before parsing and persistence; no reasoning marker or content is written to records or review artifacts.

This explicit grammar is required because b10516's JSON-Schema converter embeds a string `pattern` without intersecting it with JSON string syntax. A negated word class can therefore consume a closing quote and permit invalid JSON even though the server logs a converted grammar. The mandatory real-runtime adversarial smoke protects against that regression.

`runtime.json` selects the immutable `tutor-v1` prompt bundle by default. Use `--prompt-version tutor-v<number>` to select another committed `prompts/tutor-v<number>.md` plus matching `prompts/examples-v<number>.json` pair. The runner records the selected version, exact paths, and both hashes; aliases such as `latest` are rejected.

Every record preserves the exact request, its UTF-8 byte count and SHA-256, the complete message-envelope byte count and SHA-256, the model artifact hash, runtime tag, generation settings, final response text, parsed turn, first-attempt validation, optional one-time repair validation, tokens, timings, split, and errors. The request is never truncated or compacted. Because several current real-pipeline requests are larger than an 8192-token context, the runner marks a conservative whole-envelope byte-based overflow warning and records an explicit context-overflow error if the server rejects the exact payload.

Provider `reasoning_content` is ignored. Repeated, prefixed, case-variant, and embedded `<think>…</think>` blocks are removed before persistence; any unresolved trace marker fails closed to empty final content. HTTP error response bodies are discarded at the client boundary. Run records retain only a bounded status/category message, which is rebuilt again at persistence rather than copying exception text. Only sanitized final response content is persisted or scored. Repair is attempted at most once and only for invalid JSON or response shape—not for an identity/reference error or a pedagogically weak turn.

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

Each invocation creates an immutable timestamped run below `.coaching-eval/runs/<model>/`. Create a review packet from one model root:

```bash
python3 Tools/CoachingEval/render_review.py \
  --run .coaching-eval/runs/qwen3-0.6b-q4_0
```

For a combined comparison, repeat `--run` for each model and provide `--output <directory>`. The recorded review seed deterministically shuffles outputs. `review-packet.jsonl` shows the position, history, latest action, candidate turn, success criteria, and severe-failure criteria without model identity. Keep `review-key.json` private until scoring is complete.

```bash
python3 Tools/CoachingEval/render_review.py \
  --run .coaching-eval/runs/qwen3-0.6b-q4_0 \
  --run .coaching-eval/runs/qwen3-1.7b-q4_k_m \
  --output .coaching-eval/reviews/combined-v1
```

Fill every score cell in `rubric.csv`:

- `factualCorrectness`, `oneCoherentStep`, `responsiveToLatestAction`, `answerability`, `childClarity`, and `pedagogicalUsefulness`: integers 1–5;
- `unnecessaryInterrogation`, `mixedStages`, and `severeError`: 0 or 1;
- `notes`: optional reviewer context.

Then summarize:

```bash
python3 Tools/CoachingEval/summarize_eval.py \
  --run .coaching-eval/reviews/combined-v1
```

The summarizer refuses missing or incomplete scored rows. It writes `aggregate.json` and `summary.md` with every rubric dimension, first-attempt and repaired validity, severe errors, p50/p90 latency, tokens, configurations, and raw examples by case. It intentionally has no single combined score.

## Test-only end-to-end smoke test

The fake model is rejected unless explicitly enabled. It still uses the subprocess, health check, HTTP request, schema validation, review, and summary paths:

```bash
COACHING_EVAL_ALLOW_FAKE=1 python3 Tools/CoachingEval/run_eval.py local \
  --model fake-test-model --split visible --case t1Entry --repetitions 1
python3 Tools/CoachingEval/render_review.py --run .coaching-eval/runs/fake-test-model
python3 Tools/CoachingEval/summarize_eval.py --run .coaching-eval/runs/fake-test-model
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

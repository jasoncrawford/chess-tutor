# Coaching model evaluator

This directory is an evaluation harness, not a shipping tutor. It sends the provider-neutral coaching requests exported by the app to pinned GGUF models on a Mac, validates the returned `ModelCoachingTurn`, and creates blinded human-review artifacts. The ChessTutor target does not import or invoke these tools.

All downloaded models, runtime builds, corpus exports, raw generations, hidden-set results, review keys, and scores live under the ignored `.coaching-eval/` directory. Do not copy credentials or artifacts into this directory or source control.

## Requirements

- Python 3.9 or newer; the harness uses only the standard library.
- Xcode, XcodeGen, and the `iPad (A16)` simulator for corpus export.
- llama.cpp tag `b10516`, with `llama-server` built at `.coaching-eval/runtime/b10516/bin/llama-server`.
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

Or fetch all accessible candidates:

```bash
python3 Tools/CoachingEval/model_store.py fetch-all
```

The resolver turns repository `main` into an immutable revision, chooses the exact configured quantization, streams the bytes, and writes an `artifact-manifest.json` with the revision, byte count, and SHA-256. An existing file is reused only when both its size and SHA-256 match. `HF_TOKEN` is read only for Hugging Face requests and is never written. Gemma requires prior acceptance of the Gemma Terms and `HF_TOKEN`; the tool reports an access error instead of substituting another model.

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

Every record preserves the exact request, its UTF-8 byte count and SHA-256, the complete message-envelope byte count and SHA-256, the model artifact hash, runtime tag, generation settings, final response text, parsed turn, first-attempt validation, optional one-time repair validation, tokens, timings, split, and errors. The request is never truncated or compacted. Because several current real-pipeline requests are larger than an 8192-token context, the runner marks a conservative whole-envelope byte-based overflow warning and records an explicit context-overflow error if the server rejects the exact payload.

Provider `reasoning_content` and leading `<think>…</think>` traces are discarded. Only final response content is persisted or scored. Repair is attempted at most once and only for invalid JSON or response shape—not for an identity/reference error or a pedagogically weak turn.

## Optional online reference

The reference runner reads only these environment variables:

```bash
export COACHING_EVAL_REFERENCE_URL='https://provider.example/v1'
export COACHING_EVAL_REFERENCE_MODEL='model-name'
export COACHING_EVAL_REFERENCE_API_KEY='developer-secret'
python3 Tools/CoachingEval/run_eval.py reference --split visible
```

The online result is a comparison ceiling, not an automatic judge. Never place the key in the app, a tracked file, shell history, or a run artifact.

## Blinded review and scoring

Each invocation creates an immutable timestamped run below `.coaching-eval/runs/<model>/`. Create a review packet from one model root:

```bash
python3 Tools/CoachingEval/render_review.py \
  --run .coaching-eval/runs/qwen3-0.6b-q4_0
```

For a combined comparison, repeat `--run` for each model and provide `--output <directory>`. The recorded review seed deterministically shuffles outputs. `review-packet.jsonl` shows the position, history, latest action, candidate turn, success criteria, and severe-failure criteria without model identity. Keep `review-key.json` private until scoring is complete.

Fill every score cell in `rubric.csv`:

- `factualCorrectness`, `oneCoherentStep`, `responsiveToLatestAction`, `answerability`, `childClarity`, and `pedagogicalUsefulness`: integers 1–5;
- `unnecessaryInterrogation`, `mixedStages`, and `severeError`: 0 or 1;
- `notes`: optional reviewer context.

Then summarize:

```bash
python3 Tools/CoachingEval/summarize_eval.py \
  --run .coaching-eval/runs/qwen3-0.6b-q4_0
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
git diff --check
```

After safely copying any evidence needed for the report, remove local evaluation artifacts with:

```bash
rm -rf .coaching-eval
```

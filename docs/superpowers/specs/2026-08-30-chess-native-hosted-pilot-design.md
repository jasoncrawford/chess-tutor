# Chess-native hosted-model pilot design

## Goal

Run the exact frozen `tutor-v6` chess-native packet against one current flagship hosted model. The experiment asks a narrow question: does a substantially more capable model turn the same deterministic chess context into consistently useful beginner coaching? It is not app integration, prompt tuning, a provider comparison, or a production networking design.

## Frozen inputs

- Model: `gpt-5.6-sol` through the OpenAI Responses API.
- Reasoning effort: `high`.
- Prompts: the exact eight ordered system/user message pairs declared by `.coaching-eval/chess-native-prompt-preview/swift-export-v2/preview-manifest.json`.
- Prompt version: exact `tutor-v6`; no examples or added instructions.
- One response per prompt, serially. No retry, repair, prompt mutation, or hidden-set input.
- Output: the same exact three-field `message`, `actions`, and `focus` contract as the local pilot.

## Provider boundary

The runner sends two role-separated messages to the Responses API: the frozen system prompt and the case's frozen user prompt. It requests a strict JSON Schema response specialized to the actions and move-focus values available in that case. Provider-side structured output is an additional constraint, not a replacement for the existing request-aware validator.

The API key comes only from `OPENAI_API_KEY`. The runner requires HTTPS, never writes the credential, does not place it in command provenance, and strips authorization on cross-origin redirects. Provider error bodies and reasoning items are never persisted.

## Validation and artifacts

The existing `ChessNativeResponseContract` performs the final mechanical validation. The runner refuses to overwrite an output directory and records:

- one trace-free record per prompt;
- the exact prompt/source hashes and provider request settings;
- provider response ID, model ID, bounded token usage, validation result, and latency;
- a review document linking to the exact frozen prompts and showing only final candidate JSON.

The runner attempts all eight cases even when an individual call fails. It makes exactly one API call per case and records only bounded generic failure categories.

## Decision boundary

After the eight outputs, compare their factual correctness, stage awareness, discovery-oriented teaching, child-appropriate language, and action/focus use with the local SmolLM3 results. If the hosted model is consistently strong, the next task is a small repeated hard-case run and then a production design for a stateless server endpoint. If it is not, return to prompt/context iteration before any app integration.

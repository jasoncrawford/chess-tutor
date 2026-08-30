# Chess-native SmolLM3 pilot design

## Goal

Run one deliberately small quality experiment against the frozen `tutor-v6` prompt packet. The purpose is to inspect whether the largest available local model can turn the new deterministic chess-native context into useful coaching. This is not a model comparison, a prompt-tuning loop, or a product integration.

## Frozen inputs

- Model: `smollm3-3b-q4_k_m`.
- Runtime: pinned llama.cpp `b10516`.
- Prompts: the exact eight ordered model-facing messages declared by `.coaching-eval/chess-native-prompt-preview/swift-export-v2/preview-manifest.json`.
- System message: exact `Tools/CoachingEval/prompts/tutor-v6.md`.
- Seed: `1103`.
- Mode: bounded hidden thinking.
- Sampling: temperature `0.2`, top-p `0.95`, maximum output `512` tokens.
- One generation per prompt. No repair, retry, prompt mutation, few-shot example, or hidden-set input.

## Generation boundary

The runner validates the role-safe source manifest, reads only the declared system and user messages, and asks llama.cpp to apply the model's chat template. Native completion is constrained by a dedicated v6 grammar. In thinking mode the grammar permits one bounded `<think>...</think>` envelope followed by the exact three-field JSON object.

The private thinking text is discarded before parsing and is never written to disk. The persisted candidate is the trace-free JSON text only.

## Mechanical validation

The validator mirrors the Swift v6 response boundary:

- exact top-level keys `message`, `actions`, and `focus`;
- no duplicate JSON keys;
- nonempty message of at most 18 words with no chess notation;
- at most three unique actions, all available in the request;
- at most four unique focus objects;
- square focus must be on-board;
- move focus must be one of the request's allowable move paths;
- exact focus object shapes and no additional fields.

The action and move allowlists are parsed from the frozen model-facing `Available UI response` section and hash-bound to the source prompt. This adds no authored coaching answer or model-facing text.

## Artifacts

The runner refuses to overwrite its output directory. It writes:

- one trace-free JSON record per prompt;
- a manifest binding prompt, model, runtime, grammar, settings, response, validation, latency, and token counts;
- a human-readable Markdown review containing all eight exact system/user prompt links and trace-free model responses.

Invalid output is preserved as an invalid result, not repaired. Provider failures are recorded without provider response bodies.

## Decision boundary

After the single run, inspect all eight responses qualitatively with the user. Do not change the prompt or launch another model/run in this task. A later iteration can be based on the observed failures.

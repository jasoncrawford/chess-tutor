# Chess coaching consistency comparison design

## Goal

Measure two remaining uncertainties without broadening into another model matrix: whether the successful hosted result is repeatable on the hardest stage-sensitive prompts, and whether Qwen3 1.7B improves materially when given the exact frozen `tutor-v6` packet.

## Frozen inputs

- Use the exact `tutor-v6` system prompt and the exact eight generated user prompts already bound by the source manifest.
- Do not add examples, rewrite prompts, inspect hidden cases, repair responses, or retry failed generations.
- Keep GPT-5.6 Sol at `high` reasoning and 2,048 maximum output tokens.
- Keep the local pilot at seed 1103, bounded thinking, temperature 0.2, top-p 0.95, 512 maximum output tokens, and the pinned llama.cpp b10516 runtime.

## Hosted consistency run

Run two new samples for each of cases 02, 05, 06, and 07. Together with the already preserved funded pilot, this yields three samples per hard case. The runner writes unique sample IDs and filenames so repeated cases cannot overwrite one another. Every call uses the original case's exact system text, user text, request-specific schema, and validator.

The consistency result is useful only if every response is mechanically valid, factually correct, aware of the latest interaction, limited to one coaching purpose, child-appropriate, and aligned with the available actions and focus.

## Local Qwen comparison

Generalize the existing local pilot only enough to select one of two pinned candidates: its original SmolLM3 3B artifact or the already downloaded Qwen3 1.7B Q4_K_M artifact. The default remains SmolLM3 so prior behavior and commands stay compatible. Model-specific hashes, byte counts, revisions, filenames, and manifest hashes remain hard gates.

Run Qwen3 1.7B once across all eight frozen cases. This is a direct prompt/model comparison, not a tuning loop. The run must complete full prompt preflight before generation and preserve the existing one-attempt, trace-free, request-aware validation behavior.

## Artifacts and decision

Both runs use fresh immutable directories and keep exact request/response records, hashes, metrics, provenance, and readable reviews. Credentials and hidden reasoning never persist.

After inspecting every response, record whether hosted consistency is strong enough to justify server/app design and whether Qwen3 1.7B is plausible as an offline fallback. Do not start another paid or downloaded-model matrix from this task.

# Chess-native SmolLM3 pilot implementation plan

**Goal:** Produce one immutable, trace-free, strictly validated eight-response SmolLM3 pilot from the frozen tutor-v6 packet.

**Architecture:** Add an isolated Python grammar/validator and a lightweight pilot runner under `Tools/CoachingEval`. Reuse the pinned `LlamaServer` lifecycle and native `/apply-template` plus `/completion` path. Do not alter app behavior, prompt bytes, legacy evaluators, or hidden data.

## Task 1: Strict v6 grammar and validator

- Add failing Python tests for exact parsing, duplicate/unknown fields, word and notation limits, action and focus allowlists, UI-contract extraction, and trace removal.
- Implement the smallest v6-only grammar and validator that satisfies those tests.
- Run the focused tests.

## Task 2: Immutable pilot runner

- Add failing tests proving exact eight-case order, model-facing roles only, one fixed generation per case, frozen settings, no repair, trace-free persistence, invalid-output classification, provenance hashes, and overwrite refusal.
- Implement the runner and human-readable review renderer.
- Run focused and full `Tools/CoachingEval` tests.

## Task 3: Real SmolLM3 run

- Verify model/runtime/prompt hashes before launch.
- Run the exact eight generations once, serially, against SmolLM3 3B.
- Verify record count, hashes, absence of traces, validation outcomes, and artifact immutability.
- Inspect all eight trace-free responses and produce the review handoff.

## Task 4: Final verification and handoff

- Run the relevant Python suite and diff/status checks.
- Request a read-only review of the harness and artifacts.
- Commit scoped tracked changes.
- Present all eight responses alongside their prompt identifiers and a concise qualitative assessment.

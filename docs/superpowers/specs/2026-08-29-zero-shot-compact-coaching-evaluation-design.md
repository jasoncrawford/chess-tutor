# Zero-Shot Compact Coaching Evaluation Design

**Date:** 2026-08-29

**Status:** Approved for implementation

## Purpose

Determine whether the three existing local models can provide useful coaching when the compact, evidence-preserving Markdown position is paired with a much smaller zero-shot instruction prompt.

The prior `tutor-v3` round stopped before inference because even its smallest pilot case rendered at 5,104–5,165 tokens, above the fixed 4,000-token compiler budget. The case Markdown was only 1,123 bytes. Eight complete worked examples supplied most of the fixed prompt overhead, so this iteration removes them rather than weakening chess evidence or response validation.

## Prompt contract

Add immutable prompt bundle `tutor-v4`:

- Keep `model-coaching-context.v1` Markdown unchanged.
- Keep `model-coaching-turn.v1`, the request-specific GBNF, alias restoration, and the complete request-aware validator unchanged.
- Use no few-shot examples: `examples-v4.json` is exactly `[]`.
- Shorten the system prompt to the irreducible coaching rules: supplied chess evidence is authoritative; the latest learner action wins; teach one coherent current step; Safe/Take/Wake is optional; avoid obvious or already-answered questions; use concise language for an intelligent five-year-old; use only supplied aliases; emit exactly one structured turn.
- Do not remove current-position evidence merely to make room for instructions.

## Preflight

Before inference, render and tokenize every fixed pilot case through each model's actual chat template in both off and bounded-thinking modes. The audit must not call completion. It records model/runtime/prompt/example/corpus provenance and, for each model × mode × case cell, rendered byte count, exact token count, and prompt hash.

The preflight passes only when all 60 cells are at most 4,000 tokens. The preferred operating target is at most 3,000 tokens, leaving room for repair prompts and future growth. Any over-budget cell stops the iteration before inference and is reported without changing the budget.

## Pilot and advancement

If preflight passes, run the existing ten-case visible pilot through all three models, both modes, and one pinned seed: 60 records total. Preserve exact prompts and trace-free responses in the existing transcripts.

A model advances only if its 20 pilot records have:

- zero compiler-budget or provider context-overflow failures;
- at least 16 mechanically valid/displayable turns;
- at most two severe turns;
- at least 12 turns that are non-severe and score at least four on every positive rubric dimension.

Review is blinded. If no model advances, stop and report. If a model advances, run only that model's full visible matrix under the existing three-seed and blinded-review procedure. Hidden cases and device measurement remain gated on broad visible usability without editing.

## One-example contingency

There is no automatic prompt-tuning loop. If zero-shot output is mechanically sound but fails one repeated, clearly identifiable coaching behavior, a later immutable prompt may add one short synthetic micro-example addressing only that behavior. Full corpus examples will not return to the prompt. That later change requires a new prompt version and a fresh preflight and pilot.

## Scope and safety

- The shipping app remains model-free and unchanged.
- No model, network client, prompt, or evaluation artifact is bundled into the app.
- Hidden cases remain uninspected unless a candidate passes the visible gates.
- No output validator, evidence membership check, token budget, or trace-redaction boundary is weakened.
- Prior `tutor-v1` through `tutor-v3` prompts and evidence remain immutable.


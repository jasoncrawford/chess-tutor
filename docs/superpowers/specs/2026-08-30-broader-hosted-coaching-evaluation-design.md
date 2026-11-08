# Broader Hosted Chess Coaching Evaluation Design

Date: 2026-08-30

## Goal

Compare GPT-5.6 Sol at high reasoning with GPT-5.6 Luna at high reasoning on a
broader set of beginner-coaching situations. The experiment asks whether
Sol's observed quality advantage persists beyond the original eight prompt
examples and whether Luna remains a credible low-cost alternative.

This is an evaluation task. It does not change the live app, integrate a
network service, tune the prompt, run local models, or inspect hidden data.

## Frozen inputs

- Use the exact tracked `Tools/CoachingEval/prompts/tutor-v6.md` system prompt.
- Use the production neutral request builder and chess-native context compiler.
- Keep the response schema, request-aware validator, 18-word child-message
  limit, semantic actions, and focus rules unchanged.
- Use `gpt-5.6-sol` with `high` reasoning and `gpt-5.6-luna` with `high`
  reasoning.
- Use 2,048 maximum output tokens, `store: false`, one attempt, no repair, and
  no retry.
- Never persist credentials, provider error bodies, or hidden reasoning.

## New visible fixture packet

Create a separate, ordered set of twelve visible fixtures. Every fixture must
be deterministically constructed in Swift from a legal committed game history,
the production snapshot shape, and one current learner interaction. Every
history must replay legally from the standard starting position to the exact
exported FEN. Tentative moves remain separate from committed history.

The twelve coaching purposes are:

1. quiet midgame Help with no urgent tactic;
2. an urgently attacked loose piece;
3. an attacked piece that is adequately defended;
4. a genuinely safe, useful capture;
5. an apparent capture that loses material to a recapture;
6. an equal exchange that is not an urgent mistake;
7. selection of a pinned or constrained piece;
8. a safe staged developing move;
9. a legal staged move that ignores a more urgent danger;
10. a legal answer to check that permits a harmless equal trade;
11. inspection of an opponent capture that loses the attacker; and
12. a replacement move that supersedes an earlier unsafe tentative move.

The set must cover Help, piece selection, staged moves, an inspected opponent
piece, and move replacement. It should vary move history, piece types, board
regions, and whose apparent tactic must be evaluated. It must not reuse the
original eight fixture positions under new names.

The fixture packet is test/evaluation support, not a semantic answer key.
Requests may contain only the deterministic board state, legal history,
current interaction, scoped rule facts, and available UI response contract.
Expected coaching conclusions and authored child-facing copy must never enter
model-facing input.

## Mechanical review gate

Before any provider call:

- replay all histories through `LegalMoveGenerator` and match the exported FEN;
- compile every request twice and require byte-identical Markdown and hashes;
- require exactly twelve unique visible IDs in the approved order;
- reject hidden IDs, oracle fields, response fields, authored conclusions,
  numbered aliases, or prompt-version drift;
- verify every tentative move and interaction reference resolves against the
  production request;
- verify every prompt satisfies the existing context budget; and
- render a readable prompt packet for inspection.

Any fixture ambiguity or mechanical failure stops the run. It is fixed in the
fixture before inference; it is not explained away in scoring.

## Hosted comparison

Run the same twelve system/user pairs once against each frozen configuration,
for exactly 24 serial provider calls. Complete prompt preflight for the whole
packet before the first completion. Each record binds the model, reasoning
effort, source hashes, exact request hashes, provider response ID, strict
validation result, token usage, and latency.

Provider or validation failures are recorded generically and the remaining
fixed cells continue. There is no retry, response repair, configuration
substitution, prompt mutation, or automatic second sample.

## Blinded quality review

Create a review packet that hides model identity while preserving case ID,
prompt, returned message, actions, focus, and validation status. Score every
response on:

1. factual chess correctness and tactical consequence;
2. attention to the latest interaction and current tentative move;
3. one coherent teaching purpose without mixed stages;
4. coaching and discovery rather than unnecessary prescription;
5. natural language suitable for an intelligent five-year-old; and
6. alignment with available actions and board focus.

A mechanically invalid response is not deployable even if its prose is good.
A mechanically valid response with a chess error is a severe quality failure.
After the complete rubric is fixed, unblind once and compare models by exact
validity, severe-error count, per-dimension quality, latency, token use, and
estimated cost.

## Decision and stop rule

Stop after the 24 responses and their blinded inspection. Do not repeat cells,
tune `tutor-v6`, add another reasoning level, or add another model in this
task.

Recommend Sol/high for the first hosted prototype only if it retains a clear
quality advantage. Recommend Luna/high only if its coaching quality is close
enough that its cost/latency advantage is material. If both fail important
cases, report the failure pattern and return to prompt/context design before
spending on another matrix.

## Verification and artifacts

Keep generated prompts, responses, manifests, and review evidence under the
ignored `.coaching-eval` workspace. Commit only the deterministic fixture and
runner support, tests, design/plan, and final product report. Run the focused
Swift fixture/compiler tests, focused Python runner tests, the full evaluator
suite, and repository diff/secret checks before completion.

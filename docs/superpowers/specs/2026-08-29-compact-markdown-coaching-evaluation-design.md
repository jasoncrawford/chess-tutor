# Compact Markdown Coaching Evaluation Design

**Date:** 2026-08-29

**Status:** Approved for implementation planning

## Purpose

Run a second local-model coaching evaluation that tests whether a compact, readable model context can eliminate the dominant context-overflow failure while preserving enough authoritative chess evidence for useful tutoring.

The previous evaluation sent the complete mechanical request as JSON, including exhaustive legal moves and one opponent reply after every learner move. On an 8,192-token context, every tested model overflowed on 29 of 41 visible scenarios. Only 43 of 738 final responses were displayable, and only 28 were valid, non-severe, and scored at least four on every positive rubric dimension.

This iteration changes the model-facing input, not the product architecture. Complete chess evidence remains available and auditable inside the evaluation pipeline. A new deterministic compiler selects relevant evidence and renders it as compact Markdown. The model continues to return a strict structured coaching turn.

## Scope

This iteration will:

- Add `model-coaching-context.v1`, a versioned compact model-context contract derived from the complete `ModelCoachingRequest`.
- Render that context as readable Markdown for the model.
- Replace exhaustive reply enumeration with complete mechanical conclusions plus a small number of explanatory witness replies.
- Preserve exact inclusion and omission provenance for every original evidence reference.
- Generate request-specific constrained output grammar for the small set of references exposed to the model.
- Produce human-readable prompt/response transcripts for inspection.
- Run a visible pilot, followed by the same full visible matrix only if the pilot passes mechanical gates.
- Compare the new results directly with the final v4 baseline.

This iteration will not:

- Change live coaching behavior in the shipping app.
- Add a production model runtime, networking, model assets, or UI integration.
- Add Stockfish or let the model determine move legality.
- Add iterative model tool calls or open-ended conversation.
- Expose the hidden corpus unless a local candidate becomes broadly usable without editing.
- Silently truncate evidence or loosen response validation.

## Architecture

The existing request builder remains the authoritative source of complete mechanical chess evidence. A separate pure compiler creates a bounded model-facing view. The first immutable prompt bundle using this context is `tutor-v3`; it supersedes neither the preserved `tutor-v2` prompt nor the final v4 evidence.

```text
Board, interaction, and history
        |
        v
Complete ModelCoachingRequest
        |
        v
Compact context compiler
  - relevance selection
  - local reference mapping
  - omission manifest
        |
        v
Compact Markdown context
        |
        v
Local language model
        |
        v
Strict ModelCoachingTurn JSON
        |
        v
Existing request-aware validator
```

The compiler owns evidence selection and representation. Unlike the complete request builder, it is intentionally allowed to apply deterministic relevance policy. That policy may rank and limit mechanically supported facts, but it may not author the coaching conclusion, choose a required Safe/Take/Wake stage, or copy a deterministic tutor response. The model owns pedagogical judgment: what matters most now, whether and how Safe/Take/Wake helps, what concise language to use, and which supplied UI actions and board marks support the turn.

The compiler is pure and deterministic. The same complete request and compiler version must produce byte-identical Markdown, reference mapping, and omission manifest.

## Compact context contract

Every compact context declares `schemaVersion: model-coaching-context.v1` and `promptVersion: tutor-v3`, then contains the following sections in a fixed order.

### 1. Current situation

- Request and position revision identifiers.
- FEN, side to move, and game status.
- Latest learner event.
- Selected piece and staged move, when present.
- Available UI operations.

The FEN is authoritative. A short human-readable piece or move description may accompany it when needed for the current interaction; the compiler must not repeat a complete piece list merely to restate the FEN.

### 2. Current-turn history

- Full coaching and interaction history for the current chess turn as short ordered event summaries.
- Explicit markers for closed, reopened, cancelled, or superseded coaching requests.
- The latest authoritative learner action is clearly identified.

Full committed game history is represented once as compact SAN/PGN-style notation. Repeated historical board snapshots are not included.

### 3. Complete tactical summaries

The compiler emits conclusions calculated from the complete mechanical evidence, not a partial list from which the model must infer completeness.

Examples:

```markdown
Danger scan — complete: no learner piece is in immediate danger.

Safe captures — complete:
- `capture-1`: Bishop c4 takes f7; unsafe because King g8 can recapture.
```

The compact context distinguishes:

- `complete`: the chess layer exhaustively evaluated the category and the listed result is authoritative;
- `selected`: the compiler presents only the most relevant candidates and reports how many were omitted.

At minimum, complete summaries cover:

- check, checkmate, and stalemate status;
- immediate material dangers to the learner's pieces;
- useful safe captures or an explicit authoritative absence;
- mate-in-one opportunities or an explicit authoritative absence when relevant to the current turn.

### 4. Staged-move assessment

When a move is staged, its current assessment is the highest-priority evidence section. It contains:

- source and destination;
- legality and immediate tactical acceptability;
- any exact mechanically supported purpose or relationship;
- at most one or two critical opponent replies that explain a concrete problem;
- an authoritative statement that no immediate tactical refutation was found when the move is mechanically safe.

The compiler never enumerates every harmless opponent reply. A safe conclusion is a mechanical result, not a claim the model must derive from an exhaustive reply tree.

### 5. Selected move ideas

When no move is staged, the compiler may include a bounded set of relevant development or plan-making candidates. These are suggestions for model consideration, not an authored coaching decision.

Selection is deterministic and based only on mechanical facts available from the complete request or on new pure per-move facts added explicitly to the complete evidence contract. Permitted new facts include descriptive properties such as leaving a home square, occupying or controlling a center square, giving check, and changing mobility. They must be computed for all eligible moves before selection. The compiler must not import the deterministic coach's stage, preferred candidate, authored copy, or pedagogical verdict.

The context reports the selected count and total eligible count, for example:

```markdown
Development candidates — selected 2 of 7:
- `move-1`: Knight g1-f3 develops toward the center.
- `move-2`: Pawn e2-e4 controls the center.
```

### 6. Available response references

Only references the model may return are shown. They use short request-local aliases with a deterministic mapping to the original stable IDs.

```markdown
Actions:
- `try-another`: Try another move
- `close`: Close help

Board focus:
- `bishop-a6`: White bishop on a6
- `pawn-b7`: Black pawn on b7

Evidence:
- `unsafe-bishop-a6`: the staged bishop can be attacked
- `reply-b7-b6`: Black can play b7-b6
```

The evaluator maps returned aliases back to stable application references before applying the unchanged Swift/Python request-aware validators.

## Evidence selection and reply policy

The compiler never sends the exhaustive `legalMoves` and `immediateReplies` arrays directly.

Evidence priority is:

1. Current check or terminal status.
2. Latest learner action and any staged-move assessment.
3. Immediate material danger.
4. Useful safe captures and mate-in-one facts.
5. Facts needed to answer the current board interaction.
6. A bounded set of development or plan-making candidates.
7. Optional supporting relationships.

For a concrete unsafe claim, include one deterministic worst or explanatory reply, plus a second only when it conveys a materially different issue. For a safe conclusion, include the complete conclusion and omit harmless replies.

Absence statements such as "no learner piece is in immediate danger" or "no useful safe capture exists" are generated only from exhaustive mechanical analysis. The model is never expected to infer an absence from omitted data.

## Token budget and overflow behavior

The target is at most 4,000 rendered input tokens under each candidate model's actual tokenizer and chat template. This leaves substantial room within the 8,192-token context for bounded generation and template overhead.

The compiler applies priority-aware selection before rendering. It never cuts a string or JSON/Markdown section mid-value. If the rendered prompt still exceeds the target:

1. Reduce optional plan-making candidates.
2. Remove optional supporting relationships.
3. Compress older committed game notation without removing moves.
4. Fail the case with an explicit compiler-budget error if essential current-action or tactical evidence still cannot fit.

Every excluded original evidence ID is recorded outside the prompt with a reason such as `redundantReply`, `lowerPriorityCandidate`, or `representedByCompleteSummary`. No exclusion is silent.

The evaluation's hard mechanical gate is zero provider context-overflow outcomes on the visible pilot and full visible matrix. Compiler-budget errors are reported separately and also fail advancement.

## Model prompt and output

The new immutable `tutor-v3` prompt retains the `tutor-v2` coaching philosophy: warm, concise, grounded, one current idea at a time, latest learner action authoritative, and Safe/Take/Wake optional rather than ritualized. It changes the input contract from exhaustive JSON evidence to `model-coaching-context.v1` Markdown and documents the meanings of `complete` and `selected` evidence sections.

The eight existing visible worked examples remain semantically unchanged. Their user messages are rewritten into the compact Markdown format, while their assistant messages continue to use the exact structured turn format. Keeping the same eight scenarios reduces pedagogical confounding between rounds.

The model response remains `ModelCoachingTurn` JSON. The grammar is generated per request so enum values and reference arrays can contain only request-local aliases actually supplied in that context. It also preserves:

- exact required property order;
- existing word limits;
- at most three actions;
- at least one supporting evidence reference;
- no unknown properties;
- off and bounded-thinking modes with trace removal before persistence.

One repair attempt is allowed only for malformed or structurally incomplete output. It does not repair chess facts, pedagogy, unavailable references, or a response to the wrong learner action.

## Audit artifacts

Each evaluation record preserves machine-verifiable fields plus a human-readable transcript. The artifacts include:

- SHA-256 of the complete original request;
- compiler version and settings;
- exact compact Markdown;
- exact rendered model prompt text;
- included stable IDs and their local aliases;
- omitted stable IDs and omission reasons;
- raw final response after thinking-trace removal;
- parsed turn and mapped stable references;
- validation result;
- prompt/output token counts and latency;
- model, runtime, grammar, prompt, and example provenance.

The human-readable transcript clearly labels `MODEL INPUT`, `MODEL RESPONSE`, `PARSED TURN`, and `VALIDATION`. It must not require reconstructing the prompt from hashes or separate files.

Private reasoning traces are never persisted. Blinded review artifacts remain identity-free.

## Evaluation procedure

### Pilot

Run a visible pilot containing representative cases for:

- quiet opening choice;
- immediate danger;
- no safe capture;
- staged safe move;
- staged unsafe move;
- move replacement or removal;
- latest-action supersession;
- check resolution;
- mate in one;
- long current-turn history.

Run every pilot case through all three available models, both real thinking modes, and at least one fixed seed.

Pilot advancement requires:

- zero context overflows and zero compiler-budget failures;
- byte-deterministic context generation;
- complete inclusion/omission accounting;
- request-specific grammar enforcement;
- no persisted thinking traces;
- materially improved mechanical validity over the v4 baseline.

### Full visible matrix

If the pilot passes, run the same 41 visible cases, three models, two thinking modes, and three seeds used in v4. Preserve model bytes, llama.cpp runtime, generation settings, and scoring rubric so the principal differences are the compact context compiler, Markdown representation, and request-specific grammar.

Generate a new independently blinded packet and score it before unblinding. Compare:

- prompt-token distribution and context-overflow count;
- first-attempt and repaired mechanical validity;
- unavailable-reference failures;
- severe chess or coaching errors;
- latest-action correctness;
- six rubric dimensions;
- non-transport generation latency.

### Hidden and device gates

The hidden corpus remains untouched unless a model is broadly usable without editing on the full visible matrix. Only the strongest one or two qualifying models advance to hidden evaluation and physical ninth-generation-iPad performance testing.

No model advances merely because it is the best of a weak group.

## Testing

Swift and Python tests cover:

- deterministic compact-context compilation;
- complete-to-compact reference accounting;
- completeness labels backed by exhaustive mechanical analysis;
- staged move priority over obsolete coaching history;
- one/two-witness reply bounds;
- explicit no-danger and no-capture conclusions;
- SAN/PGN history preservation;
- request-local alias stability and round-trip mapping;
- request-specific grammar rejection of unavailable aliases;
- token-budget selection and explicit failure;
- Markdown escaping of user/game text;
- exact transcript rendering;
- no hidden-case identifiers in prompts or examples;
- no reasoning-trace persistence;
- reproducible pilot/full manifests.

Golden tests bind compact summaries to real chess positions and the existing 52-case corpus without copying deterministic tutor output into model evidence.

## Success criteria

This iteration succeeds as an experiment if it produces a reproducible, auditable answer, even if no model qualifies. A model qualifies for hidden/device evaluation only if:

- every visible request fits the real context window;
- structured responses are broadly valid without repair;
- request-local references are never invented;
- severe chess/coaching errors are rare enough for unsupervised child-facing use;
- responses consistently follow the learner's latest action;
- blinded coaching quality is materially better than v4;
- latency remains tolerable with the existing Thinking presentation.

The final report must distinguish failures caused by context construction, grammar/validation, chess reasoning, pedagogy, and runtime performance.

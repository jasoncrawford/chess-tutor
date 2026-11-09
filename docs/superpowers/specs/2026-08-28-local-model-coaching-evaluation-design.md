# Local-model coaching feasibility evaluation

**Date:** 2026-08-28
**Status:** Approved design

## Goal

Determine whether a small language model can deliver the app's intended chess-tutoring experience entirely on a ninth-generation iPad, and identify the smallest model that is good enough if one exists.

This is an evaluation spike. It does not replace the live deterministic tutor. It produces evidence for the next product and architecture decision: local-first coaching, online-first coaching with a local offline provider, or online-only coaching.

## Why evaluate a local model

The deterministic tutor has proved that mechanical chess facts can be calculated reliably, but it has also exposed the cost of encoding conversational and pedagogical judgment as an expanding state machine. The product needs a tutor that can:

- reconsider the whole situation after every learner action;
- follow the learner when she moves ahead of a suggested step;
- choose one useful teaching idea without mixing stages;
- ask questions only when they are useful and answerable;
- explain chess naturally in context;
- grow toward richer strategic coaching without a new branch for every phrasing or situation.

An online frontier model is likely to be the quality ceiling, but offline coaching is valuable in cars, airplanes, and other disconnected settings. The target device cannot use Apple's system Foundation Model, so an offline implementation would need to run an open-weight model through an app-owned inference runtime.

## Target user and device

The default tutor persona is a bright, verbally sophisticated five-year-old:

- real chess vocabulary is welcome;
- sentences remain short and concrete;
- one current idea is taught at a time;
- the tutor never sounds like an evaluator, debugger, or implementation disclaimer;
- the learner interacts through the board and bounded buttons, not open-ended chat, typing, or voice.

The performance target is the physical ninth-generation iPad currently used for the app:

- A13 Bionic;
- 64 GB storage;
- iPadOS 26.5.2 at the time of the evaluation;
- limited current free storage, but space may be cleared for a promising larger candidate.

Model size and latency are measured tradeoffs, not preset hard limits. The experiment starts with the smallest plausible models and advances only when quality requires it.

## Product and architecture boundary

The language model owns tutoring judgment and authors one coherent coaching turn. It does not own chess legality, board state, request lifecycle, or UI rendering.

### Code remains authoritative for

- the current position and side to move;
- legal piece movement and legal moves;
- checks, attacks, defenses, captures, and other concrete relationships already supported by the chess model;
- the current selection and tentative move;
- full committed game history;
- the learner's current-turn interaction history;
- stable piece, square, move, relationship, and action identifiers;
- which app operations are actually available;
- request revision identity, cancellation, and stale-response rejection;
- layout, typography, animation, accessibility, and board rendering.

### The model owns

- deciding what the most useful current coaching step is;
- deciding whether and how Safe/Take/Wake is useful in this situation;
- skipping questions whose answers are obvious or no longer relevant;
- responding naturally to the learner's latest action;
- choosing one teaching idea and expressing it coherently;
- selecting permitted buttons and evidence-backed board emphasis for that turn;
- writing concise child-facing copy.

Safe/Take/Wake is a tutoring heuristic in the prompt, not a mandatory state sequence. The model recalculates from the authoritative current snapshot after every learner action.

The evidence payload must not smuggle the old coaching policy into the new provider. Mechanical facts may be exhaustive or explicitly labeled as bounded, but the request does not present the deterministic routine stage, its preferred candidate, or its strategic verdict as authoritative. Any heuristic annotation that survives for comparison is labeled as such and can be omitted in an ablation run. The experiment is intended to evaluate model tutoring judgment, not merely model-written copy for the existing state machine.

## Stateless request contract

Every model call is logically stateless. The request contains everything needed to understand the current moment. An implementation may later cache an unchanged prompt prefix or model KV state for performance, but correctness cannot depend on hidden conversational state.

The illustrative request shape is:

```text
CoachingRequest
  schemaVersion
  promptVersion
  requestID
  positionRevision

  currentPosition
    FEN or equivalent canonical position
    sideToMove
    check and terminal status

  fullGameHistory
    ordered committed moves in compact canonical and display notation

  currentInteraction
    selected piece, if any
    tentative move, if any
    latest learner event
    currently available app operations

  currentTurnCoachingHistory
    Help opened or reopened
    every coaching turn displayed
    board selections and inspections
    staged, replaced, and removed moves
    Hint and answer actions
    superseded request metadata

  chessEvidence
    pieces and stable identifiers
    legal moves and captures
    attacks, defenses, threats, and checks
    immediate reply facts already calculated by code
    other bounded mechanical facts supported by the app
    explicit completeness or bounded-scope metadata

  permittedReferences
    board-focus identifiers
    relationship identifiers
    board-task kinds
    action kinds
```

The full game history is included initially rather than summarized. The full coaching history is retained until the current chess move is committed, including when Help is closed and reopened. The latest snapshot remains authoritative: history explains how the learner arrived there but cannot keep an obsolete coaching stage alive.

No cross-game child profile, ability estimate, or personalized memory is included in this iteration. A simple field such as age may be added later, but the initial prompt assumes the default tutor persona.

## Structured response contract

The model returns one complete, UI-ready turn rather than independently authored fragments from different coaching stages.

The illustrative response shape is:

```text
CoachingTurn
  schemaVersion
  requestID
  teachingIntent

  primaryMessage
  instruction?
  responseToLatestAction?

  actions[]
    permitted system action, or
    short bounded answer choice with opaque identifier

  boardTask
  boardFocusReferences[]
  relationshipReferences[]
  supportingEvidenceReferences[]
```

The presentation contract is:

1. one short primary message or question;
2. one concrete instruction explaining exactly how the learner can respond;
3. an optional brief response to the latest action, included only when it adds value and never when it merely repeats a resolved fact.

The app renders the response through its existing board-native coaching UI. The model cannot invent arbitrary controls or raw drawing commands. Board emphasis and factual observations reference identifiers supplied in the request.

## Prompt philosophy

The prompt tells the tutor to:

- reconsider the current snapshot from first principles after every learner action;
- follow a staged or replaced move instead of forcing the learner through an earlier question;
- teach one current idea;
- use Safe/Take/Wake flexibly as a helpful scan, not a ritual;
- skip obvious questions, including empty opening safety quizzes;
- ask only questions that have a clear board or button response;
- distinguish feedback about the latest action from the current instruction;
- omit feedback that only duplicates the primary message;
- use real chess vocabulary in short, concrete language;
- assume a bright five-year-old;
- avoid advanced notation and evaluator language in child-facing copy;
- rely only on supplied chess evidence;
- never expose private reasoning or chain-of-thought.

Prompt instructions and few-shot examples are versioned. The evaluation may compare a small number of prompt variants, but prompt tuning must be judged against a hidden stress set as well as the visible corpus.

## Candidate ladder

The initial Mac quality comparison uses four instruction-tuned candidates spanning a useful size range:

1. Qwen3 0.6B;
2. Gemma 3 1B;
3. Qwen3 1.7B;
4. SmolLM3 3B.

The exact model revisions, licenses, prompt templates, and quantizations are recorded in the evaluation report. At least one practical four-bit quantization is tested for each candidate. Approximate file sizes are not treated as evidence until the exact artifacts are downloaded and measured.

The experiment uses llama.cpp and GGUF artifacts initially because the same quantized artifact can run on Mac and iPad. This keeps quality and device-performance comparisons from being confounded by separate conversions. Runtime choice may be revisited for production if the feasibility result is positive.

Where a model supports explicit thinking and non-thinking modes, the Mac round compares a bounded configuration of each. The user-facing Thinking state is independent of whether a model has a reasoning mode. Only the final structured turn is stored, scored, or displayed.

## Stage one: Mac quality evaluation

### Corpus construction

The existing deterministic transcript fixtures are inputs, not immutable wording. They are converted into semantic cases that specify:

- the real chess and interaction context;
- facts the tutor may or must use;
- behavior the turn must accomplish;
- permitted teaching directions;
- prohibited factual claims, interaction stages, actions, and phrases.

The corpus emphasizes situations that have repeatedly exposed product problems:

- first moves and other situations with obvious answers;
- threatened pieces with attackers and defenders;
- no safe capture followed by an ordinary staged move;
- replacing or removing a tentative move;
- the learner answering ahead of the tutor;
- benign versus dangerous opponent replies;
- checks, discovered checks, castling checks, and mate;
- quiet moves without a strong named purpose;
- edge-pawn moves that must not inherit a center purpose;
- long and short histories that should yield the same current advice;
- closing and reopening Help before committing the move.

Cases are exported through the app's real chess-rule and evidence pipeline. Hand-authored evidence that can drift from the position is prohibited.

The exporter distinguishes facts from policy. It may reuse pure evaluators and identifiers, but it does not export the deterministic coach's selected routine, recommended next step, or authored conclusion as the answer the model is expected to paraphrase.

At least one fifth of the cases are reserved as a hidden stress set while prompts and examples are tuned.

### Repetition and comparison

Each model and prompt configuration runs every case multiple times with recorded generation settings and seeds. An online frontier model runs the same requests as a quality reference. It is not used as the sole judge.

Outputs are anonymized for human review so model identity does not influence tutoring ratings.

### Mechanical gate

Every result is checked for:

- valid schema and parseable structured output;
- matching request and position revision;
- valid piece, move, relationship, evidence, and action references;
- actions compatible with the actual tentative-move state;
- configured copy and action-count bounds;
- duplicate or structurally contradictory actions;
- required evidence citations for factual observations.

Invalid turns are never counted as displayable. The report records first-attempt validity and validity after at most one bounded repair attempt.

### Tutoring rubric

Human review scores whether the result is:

- factually correct;
- focused on one coherent current step;
- responsive to what the learner just did;
- explicit about how the learner can answer;
- short and concrete enough for the target child;
- pedagogically useful;
- free of unnecessary interrogation, implementation language, and mixed stages.

The report shows per-dimension results, severe-error counts, and raw example turns. It does not hide tradeoffs behind one aggregate score.

The smallest model advances when its outputs are broadly usable without editing, it shows no systematic severe failure class, and a larger candidate does not provide a product-significant improvement that justifies its cost. Exact rates are reported; the final viability decision remains a product judgment rather than an arbitrary single threshold.

## Stage two: physical-iPad performance evaluation

Only the strongest one or two local candidates advance to the device round. The same quantized artifact and request corpus used on Mac are used on the physical ninth-generation iPad.

A standalone DEBUG-only model lab measures:

- exact model and installed asset size;
- initial download or installation space requirements;
- cold model-load time;
- cold first-turn latency;
- warm prompt-processing and generation latency;
- input and output token counts and throughput;
- peak memory behavior and operating-system termination;
- cancellation and superseding-request behavior;
- main-thread and board interaction responsiveness during inference;
- repeated-request heat and battery observations;
- performance with short and long game/coaching histories.

The lab also renders a minimal stable coaching shell with a quiet Thinking state. The board or test interaction surface remains usable. A newer learner action supersedes the pending request, and only a response matching the latest revision may appear.

Latency is not assigned a hard pass/fail threshold before measurement. Warm responses near ordinary interaction speed are preferable; several seconds may be acceptable with Thinking when the tutoring quality is materially better. Cold and warm results are reported separately.

Model weights, caches, and large generated artifacts are excluded from source control. Space may be cleared on the device before testing a promising larger model; the experiment does not constrain itself to the device's current free-space snapshot.

## Eventual provider architecture

A positive result supports a provider-neutral production seam:

```text
GameSession
    -> CoachingRequestBuilder
    -> CoachingProvider
         -> LocalModelProvider
         -> OnlineModelProvider
    -> CoachingResponseValidator
    -> CoachingPresentation
    -> board-native SwiftUI
```

Every provider receives the same semantic request and returns the same structured turn. The eventual routing policy is deliberately deferred:

- a sufficiently strong local model may become the default;
- an adequate local model may be used only offline while an online model is preferred when connected;
- if no local model meets the tutoring bar, production may use only the online endpoint.

The current deterministic coaching state machine is not planned as an offline fallback. Its chess-fact generation, interaction snapshots, provider seams, UI schema, and transcript corpus remain valuable inputs to the model-driven architecture.

## Online reference and security

The Mac evaluator may call an online model using a developer credential supplied through the local environment. Credentials and raw secrets are never committed or placed in the iPad app.

This spike does not build the production server endpoint. If the online provider advances, production uses a narrow stateless server-side endpoint to hold the provider credential, validate requests, call the model, validate structured output, and return the turn. No user accounts, database, or persistent server conversation are required by the currently approved product.

## Deliverables

The evaluation produces:

- versioned request and response schemas;
- a real-pipeline corpus exporter;
- visible and hidden evaluation sets;
- a Mac multi-model runner;
- automatic mechanical-validation results;
- anonymized human-review material and rubric scores;
- a standalone DEBUG-only physical-device model lab;
- raw device measurements and bounded UAT observations;
- a final recommendation naming the smallest viable model and quantization, or concluding that none is viable;
- a recommended online/local routing policy and production follow-up scope.

## Non-goals

This spike does not:

- replace or revise the live coaching feature;
- build the production server endpoint;
- implement downloadable-model management in the shipping app;
- implement offline provider routing;
- add Stockfish;
- add a child profile, age setting, cross-game memory, or open-ended conversation;
- fine-tune or train a model;
- select final production copy by exact transcript equality;
- ship experimental model weights in the normal app target.

## Risks and mitigations

### The smallest models may not tutor well enough

Use the online model as a quality reference, preserve raw examples, and conclude honestly that local is not viable if the gap is material.

### Long histories may make the A13 too slow

Measure short and long contexts separately. Keep the first implementation correct and stateless; consider prefix caching or evidence-preserving compaction only after profiling.

### Quantization may change quality

Run the exact quantized artifact on Mac before device testing and record the artifact checksum and settings.

### Structured JSON may be unreliable

Use constrained generation where the runtime supports it, validate every response, record first-attempt failure rates, and allow at most one bounded repair attempt in the experiment.

### Free text may still contradict cited evidence

Require evidence identifiers, mechanically reject invalid references, retain severe factual-error review as a first-class metric, and do not mistake schema validity for semantic truth.

### A candidate license may complicate distribution

Record and review licensing before selecting a production model. Evaluation inclusion does not imply approval for App Store distribution.

### The experimental runtime could contaminate the shipping app

Keep the model lab in a separate DEBUG-only target or standalone project. No runtime, model, fixture selector, or model asset enters the normal app target during the spike.

## Exit decisions

The spike ends with one of three explicit outcomes:

1. **Local-first:** the smallest viable local model is good and fast enough to become the default provider.
2. **Online-first with local offline coaching:** a local model is useful but meaningfully weaker, so online is preferred and local is used when disconnected.
3. **Online-only:** no tested local model meets the tutoring bar on the target device.

The result should answer the feasibility question before production plumbing is built. A positive result leads to a separate production design and implementation plan; a negative result leads to the narrow server-backed online coaching design already outlined in product discussion.

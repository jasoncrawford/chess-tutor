# Intelligent Advice and Coaching Vision

**Status:** Product and architectural direction  
**Date:** 2026-08-13

## Purpose

This document records the wider product direction for intelligent chess advice and coaching. It captures the decisions and reasoning that should guide the first coaching feature and later features such as move evaluation, blunder alerts, position advice, game review, and adaptive instruction.

It is intentionally broader than the forthcoming v1 coaching specification. It describes the hill we want to climb, the boundaries that should remain durable, and the capabilities that may evolve or be replaced. It does not commit the project to building every future feature described here.

## Executive Summary

The app should help a child learn to decide what to do while preserving the feeling of playing a real game. Coaching should be available on request, ask questions rather than deliver lectures, and let the child answer mainly by interacting with the board.

The first coaching version should run entirely on-device without a chess engine or online language model. It can use the existing rules and position analysis, piece values, shallow lookahead, authored chess concepts, a deterministic teaching policy, and authored language. Its promise should be deliberately modest: recognize clear danger, straightforward captures, and simple purposeful moves with high confidence.

The architecture should not assume that this first evaluator is permanent. Chess evaluation, semantic insight generation, and natural-language explanation should be replaceable sources behind stable domain boundaries. The app should retain ownership of the teaching interaction, supported board actions, validation, move staging, hint progression, and safe fallback behavior.

Longer term, a strong chess engine plus a grounded language model is a promising combination. The engine can judge positions and candidate moves; verified concept detection can connect numerical analysis to recognizable chess ideas; a language model can select and explain an age-appropriate teaching point. Neither the engine nor the language model should directly control the board or become the sole authority on chess truth.

## Product Starting Point

The current app provides mechanical training wheels:

- threatened pieces are marked on the board;
- selecting a piece reveals its movement, attackers, and defenders;
- a tentative move updates those visualizations before the player presses **Done**;
- the player can inspect whole-board coverage.

These features help a learner see the rules and immediate relationships. They do not answer the next question a young beginner encounters: “I see the board, but what am I supposed to do?”

Intelligent coaching should build on the existing training wheels. It should teach the learner how to use visible information to make a decision rather than duplicate the board visualization in prose.

## Product Principles

### Learning happens through play

The main screen remains a playable board. Coaching is a brief intervention inside a real turn, not a lesson hub, modal course, or replacement for thinking. The tutor helps the child resume play as quickly as possible.

### Coaching is requested, not imposed

The live tutor begins only when the player asks for help. It should not comment continuously, grade every move, or interrupt ordinary play. Future proactive features such as a blunder alert should be separate, explicitly designed and controllable behaviors rather than an accidental expansion of Help.

### Questions preserve agency

The tutor should begin with a question, wait for a board action, and reveal progressively stronger hints only when needed. It should help the child notice a fact and choose a move rather than immediately drawing the answer.

### The child answers in chess

The coach may ask in words, but positive answers should normally happen on the board:

- tap a piece;
- tap an attacker;
- choose a piece to improve;
- stage a move.

Buttons are reserved for meanings the board cannot express, such as **I don’t see one**, **Looks safe**, **Hint**, **Stop**, and **Keep looking**.

### Good enough is genuinely good

The tutor should help the learner find a legal, safe, purposeful move, not steer every position toward the engine’s top choice. Multiple moves may be acceptable. Once the child finds one, the tutor should name its idea and stop searching unless the child chooses **Keep looking**.

An acceptable move:

1. handles anything urgent;
2. survives the opponent’s next clear reply;
3. has a recognizable purpose.

The tutor should not undermine a successful choice by immediately revealing that another move scored slightly better.

### Facts before judgment, confidence before specificity

The system should distinguish:

- exact facts, such as legal moves, checks, attackers, and defenders;
- high-confidence judgments, such as a clearly losing exchange or an obvious developing move;
- ambiguous strategic judgments, such as choosing between two sound plans.

The tutor may be specific when confidence is high. When analysis is ambiguous, it should widen what it accepts, use a more general question, or abstain from making a strong claim.

### Feedback is concrete and non-punitive

The tutor should respond to the child’s idea rather than display a generic wrong-answer state. For example:

> “I see why you want to attack that rook. What could Black take after your knight moves?”

Feedback should refer to visible board facts, praise useful habits such as checking the opponent’s reply, and introduce chess vocabulary naturally. Terms such as *threat* are appropriate; dense phrases such as “undefended minor piece” are unnecessary.

## Coaching Method

### Safe–Take–Wake

**Safe–Take–Wake** is the product’s memorable beginner decision routine. It is our mnemonic, not the name of a single established coaching method.

- **Safe:** Is there something urgent to handle?
- **Take:** Can I win something now?
- **Wake:** Which piece could help more?

This is a priority policy, not a rigid three-screen script. The tutor should always consider danger first, but it may compress or omit a question whose answer is structurally trivial. On White’s first move, for example, it should not force an empty danger ritual. It can say that nothing is in danger and move directly to an opening-development idea.

If Safe identifies a real problem, the tutor branches into solving it and does not require the child to complete Take and Wake. Likewise, a useful capture found during Take leads directly to staging and checking that move.

### Safe

The existing danger marker means that a piece can legally be captured. Coaching must make the stronger judgment that a threat matters. A defended piece may still lose a bad exchange; an apparently attacked pawn may be untouchable because its attacker would be lost.

A Safe episode can ask:

1. “Does one of your pieces need help?”
2. “What could take it?”
3. “How could you help it?”

The child answers the first two questions by tapping pieces and the third by staging a move. If needed, the tutor can offer the reusable prompt:

> “Could you take the attacker, protect your piece, or move it away?”

Check is an urgent specialization of Safe. It should use the same board-native pattern while acknowledging the legal necessity of escaping check.

### Take

Take looks for an immediate, understandable gain:

- a piece that can be captured without an unfavorable reply;
- a favorable exchange after an obvious recapture;
- checkmate in one;
- a capture that also resolves an urgent threat.

The first version should not expect the learner to calculate deep combinations, speculative sacrifices, or advanced tactical motifs. Those can become distinct insights and teaching episodes later.

### Wake

Wake splits the decision into two questions:

1. “Which piece could help more?”
2. “Where could it help from?”

The learner first taps a piece, then stages a move. A Wake move may:

- bring an unused piece into play;
- help control the center;
- add a useful defender;
- create a safe immediate threat;
- improve king safety;
- activate the king or advance a useful pawn in an endgame.

The explanation should name the piece’s concrete new job rather than merely say that the position improved.

### Opponent check

Every staged coaching move should receive a brief one-move-ahead check:

> “Could Black check your king or win something?”

The child taps a problem or chooses **Looks safe**. If a problem exists, the tutor helps the child revise the move. Only the child presses **Done**; the tutor never commits a move.

### Hint ladder

Hints become progressively more specific:

1. ask the open question;
2. refer to an existing board clue;
3. narrow attention to an area or two pieces;
4. emphasize the relevant relationship;
5. identify the piece;
6. indicate a candidate destination while leaving the move to the child.

A mistaken tap receives a concrete response but does not automatically reveal the next hint. After repeated difficulty, the tutor may offer a hint; the child chooses whether to take it. There are no timers, penalties, or escalating failure signals.

## Contextual Coaching

Safe–Take–Wake is the default decision policy, not the entire curriculum. Advice should reflect the position’s broader context when no urgent tactic dominates.

Context should be represented as evidence-based signals rather than a brittle move-number label:

- undeveloped starting pieces and unsecured kings make opening principles relevant;
- active pieces, open lines, threats, and king attacks make middlegame activity relevant;
- reduced material, active kings, and passed pawns make endgame concepts relevant;
- immediate checks, captures, and tactical losses override phase-specific advice.

Early contextual concepts can remain simple:

- develop a knight or bishop;
- help control the center;
- prepare king safety;
- improve the least active piece;
- give a rook an open line;
- activate the king in the endgame;
- support or advance a passed pawn.

The tutor should teach one useful idea at a time. It should not summarize the whole strategic position during a move-help episode.

## Board-Native Interaction Model

The number of possible chess positions is enormous, but the number of interaction shapes can remain small.

The board sends three generic kinds of input:

```text
squareTapped(square)
moveStaged(move)
actionChosen(action)
```

A coaching step describes what those inputs currently mean:

```text
CoachStep
  semanticAct
  message
  boardTask
  availableActions
  boardEmphasis
```

The board task is one of:

```text
identifySquare
stageMove
none
```

The app does not need a separate SwiftUI view for every chess case. Multiple threatened pieces are represented by a set of acceptable squares. Multiple reasonable moves are represented by move assessments. The coaching session interprets taps and moves; SwiftUI renders the current presentation and forwards events.

The coach should occupy one stable panel. Questions should not float over or obscure the board. Existing board guidance keeps its current meaning; coaching emphasis may focus attention but should not introduce a conflicting visual language.

## Durable Intelligence Architecture

The system should separate chess truth, evaluation, interpretation, teaching policy, interaction, and wording.

```text
Chess rules and position facts
            ↓
Evaluation source
            ↓
Semantic insight source
            ↓
Teaching planner and coaching session
            ↓
Explanation source
            ↓
Board-native presentation
```

### Rules and facts

The existing pure Core remains the sole authority for legal movement, captures, checks, and game results. Coaching observes `GameState` and reusable position analysis; it never changes rule execution.

### Evaluation

Evaluation estimates the consequences and quality of positions and moves. Possible implementations include:

- v1 piece values, exchange analysis, and shallow replies;
- a future local or remote chess engine;
- a composite evaluator that uses deterministic facts plus engine scores.

Evaluation should produce algorithm-independent domain results rather than expose Stockfish-specific protocol output directly to the app.

### Insights

Insights translate evaluation and board facts into recognizable chess ideas. A conceptual insight contains:

```text
ChessInsight
  id
  concept
  subjects          // pieces, squares, or moves
  candidateMoves
  priority
  confidence
  evidence
```

Examples include a profitable threat against a bishop, an undeveloped knight, an opportunity to control the center, or a passed pawn that needs support.

Insight generation may eventually combine authored detectors and a language model. Every insight presented as a board fact must remain grounded in legal moves, validated references, engine lines, or other explicit evidence.

### Teaching planner

The planner decides which verified insight is most useful now, taking into account urgency, position context, the current coaching episode, and eventually the learner’s history. It expresses its choice as a semantic teaching act, such as asking the learner to identify a threatened piece or stage a move for a development insight.

The teaching and interaction policy remains app-owned. External intelligence may rank or recommend insights, but it cannot invent unsupported UI actions, commit a move, or bypass validation.

### Explanations

The explanation source turns a semantic teaching act and verified facts into child-facing language. Authored templates implement v1. A future language model can vary wording, connect an insight to learner context, or answer “Why?” without changing the underlying expected answer.

### App-facing boundary

`GameSession` should interact with one coaching advisor rather than depend on evaluator-, engine-, or model-specific types. Internally, the advisor may compose replaceable evaluation, insight, and explanation sources.

The advisor boundary should be able to become asynchronous. Every request and result should carry a position identity or revision so a late response cannot be applied after the board changes. Local results remain immediate. Future remote failure must fall back to local behavior rather than block play.

This does not require a provider registry or networking framework in v1. It requires a single owner, narrow contracts, source-independent results, and validation at the boundary.

## V1 Intelligence Strategy

V1 should use:

- existing rules and position analysis;
- conventional beginner piece values;
- shallow capture-and-reply analysis;
- simple exchange evaluation where needed;
- authored context signals and concept detectors;
- a deterministic teaching planner;
- authored language templates;
- confidence thresholds that limit strong claims.

Initial insight coverage should include:

- king in check;
- a clear profitable threat against the learner’s piece;
- a clear profitable capture;
- development of an unmoved knight or bishop;
- center participation;
- basic king safety;
- adding a useful defender;
- creating a safe immediate threat;
- unmistakable endgame king activity.

V1 should not claim to understand every sacrifice, combination, positional plan, or subtle tradeoff. Ambiguous positions should produce broader advice and broader acceptance, not false confidence.

A chess engine can be useful during development as an offline oracle over a curated corpus of test positions. This can reveal serious disagreements without creating a runtime dependency.

## Engine and Language-Model Direction

### What an engine contributes

A strong engine can provide candidate moves, evaluations, principal variations, win/draw/loss estimates, and before/after evaluation changes. These are valuable for tactical safeguards, blunder detection, and game review.

An engine does not directly provide a child-friendly causal explanation. Modern Stockfish uses search with NNUE evaluation; its output still needs interpretation before it becomes a teaching point.

### What a language model contributes

A language model can:

- choose an age-appropriate focus from verified insights;
- explain an engine line in natural language;
- vary phrasing without losing the coaching style;
- connect current advice to concepts the learner has encountered;
- answer constrained follow-up questions.

It should not be asked to serve as the sole move generator or arbiter of legality. A plausible explanation is not necessarily a correct explanation.

### The grounded combination

A future language-model request should include:

- a position and relevant move history;
- engine candidate moves and bounded variations when available;
- verified semantic insights with stable identifiers;
- learner context and known concepts;
- the supported board-interaction shapes;
- strict style and output constraints.

The response should reference supplied insight and move identifiers rather than invent new board facts. Structured output can enforce the shape of the response, while application validation enforces that every referenced square and move remains valid for the current position. Authored templates remain the fallback.

### Stockfish integration caution

Stockfish is distributed under GPLv3. Shipping or linking it in an iPad app requires deliberate technical and licensing review, including the project’s source-distribution requirements. Depending on the app’s distribution model, a remote engine service, another appropriately licensed engine, or a separately designed evaluator may be more suitable. This is a future product and legal decision, not a v1 dependency.

## Relationship to Future Features

The same analysis vocabulary can support several products without forcing them into one UI mode.

| Feature | Reusable intelligence | Distinct product behavior |
| --- | --- | --- |
| On-demand move help | Current-position insights and acceptable moves | Questions, hints, and board answers during the turn |
| Tentative-move check | Before/after move assessment and opponent replies | Check the staged move before **Done** |
| Blunder alert | Large, high-confidence negative change | Optional proactive intervention with separate settings |
| Position advisor | Ranked positional and strategic insights | Summarize the position without selecting a move for the child |
| Post-move reflection | Move consequences and concept tags | Brief feedback after commitment, likely in a distinct mode or setting |
| Game review | Evaluation changes and semantic moments across move history | Select highlights, lowlights, and recurring concepts after the game |
| Adaptive tutor | Insight history, hint usage, and demonstrated concepts | Choose what to rehearse, introduce, or fade over time |

The live coaching state machine should not be stretched into all of these experiences. They may share evaluation and insight infrastructure while using distinct interaction policies.

## Plausible Capability Sequence

This sequence is directional rather than a commitment:

1. **Move-help v1:** local, on-demand, board-native coaching for clear beginner situations.
2. **Move-help calibration:** expand the test corpus, tune confidence, and add more grounded insights.
3. **Tentative and post-move evaluation:** reuse move assessments with carefully designed timing and controls.
4. **Game review:** analyze the completed move sequence and select a small number of instructive moments.
5. **Engine-backed evaluation:** improve tactical reliability if local heuristics reach their limits.
6. **Grounded language-model explanations:** generate richer explanations and constrained follow-up conversation with local fallback.
7. **Learner model and adaptive curriculum:** use demonstrated habits and hint needs to select future coaching priorities.

Each step should be designed as its own product increment. Shared semantic types should make later steps easier, but v1 should not build dormant implementations for them.

## Settled Decisions

- Live coaching is invoked through Help rather than appearing automatically.
- The child answers mainly through the board.
- Safe–Take–Wake is the default priority policy, not an inflexible script.
- Position context may compress the routine or choose a broader concept when no tactic dominates.
- The tutor accepts safe, purposeful moves rather than requiring the best move.
- Finding an acceptable move ends the search unless the child chooses **Keep looking**.
- Every coached tentative move receives a brief opponent check.
- Hints are progressive and preserve the child’s final action.
- The tutor never presses **Done** or owns the move.
- When Help begins with a move already staged, coaching begins by checking that tentative move rather than restarting move selection.
- V1 uses local deterministic intelligence and authored language.
- Evaluation, insight, and explanation remain replaceable sources.
- The app owns validation, teaching flow, supported interactions, and fallback behavior.
- Runtime Stockfish and online AI are deferred.

## Deferred Questions

- Exact v1 thresholds for a meaningful material threat or acceptable exchange.
- The complete v1 concept taxonomy and context-signal rules.
- Exact wording and visual emphasis at every hint level.
- How a stopped coaching episode preserves selection and tentative-move state.
- Whether and when learner progress should be stored.
- Which future features may be proactive and what settings govern them.
- Whether a future engine runs locally or remotely and under what license.
- What privacy, latency, cost, and parental-control requirements apply to future online AI.

These should be settled in the specifications for the increments that need them rather than resolved speculatively here.

## Research and Technical References

- The [Steps Method Step 1 mix workbook](https://www.stappenmethode.nl/en/gs/en_gs_1m.pdf) reinforces beginner scanning for pieces in danger and concrete ways to respond.
- FIDE’s [Early Years Skills](https://eys.fide.com/en/bl3a1.php) is designed around practical, age-appropriate work with children roughly five to six years old.
- The Judit Polgar Chess Foundation’s [Chess Palace Program](https://www.thejpcf.com/chess-palace-program/) and [education overview](https://www.thejpcf.com/education/) emphasize playful learning for children ages four to ten.
- Research on [guided play](https://doi.org/10.1177/0963721416645512) supports combining an adult-defined learning goal and scaffolded environment with meaningful child control.
- The [Stockfish documentation](https://official-stockfish.github.io/docs/stockfish-wiki/Home.html) describes the engine, UCI integration, evaluation, and analysis capabilities.
- The [Stockfish repository](https://github.com/official-stockfish/Stockfish) documents its GPLv3 distribution terms.
- OpenAI’s [Structured Outputs guide](https://platform.openai.com/docs/guides/structured-outputs) describes schema-constrained model responses; semantic validation remains an application responsibility.

# Neutral Coaching Prompt Compiler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a production-shaped deterministic compiler that turns game state, rule facts, and learner interaction events into neutral Markdown, then export eight exact prompts for human approval without running model inference.

**Architecture:** Add a new neutral request pipeline beside the existing policy-bearing evaluation request so old evaluation evidence remains reproducible. The neutral builder consumes only `GameState`, tentative/selected interaction state, and structured learner events; it computes chess facts with `LegalMoveGenerator`, renders fixed Markdown sections, and exposes request-local UI references. A tokenizer-only preview command packages the candidate system prompt and eight visible examples for review, but never invokes completion.

**Tech Stack:** Swift 6, XCTest, existing ChessTutor chess model and `LegalMoveGenerator`, CryptoKit, Python 3 standard library, pinned llama.cpp tokenizer endpoint, XcodeGen/Xcode.

## Global Constraints

- Do not invoke model completion or generate any coaching response in this plan.
- Do not use `MaterialTacticalEvaluator`, `CoachingAdvice`, `CoachingStage`, `CoachingMoveOrigin`, semantic oracles, teaching intents, preferred moves, or authored case prose in the neutral pipeline.
- Include complete committed history in compact SAN and keep tentative moves separate.
- Interaction scoping must be determined only by selection/tentative/inspection state, never by expected coaching value.
- Render neutral rule facts; never render `best`, `useful`, `important`, `purpose`, `needs help`, `looks safe`, or `what to teach`.
- Target 500–1,500 input tokens and fail preflight above 2,500 tokens; do not truncate or hand-edit.
- Export exactly eight visible prompt examples and no hidden identifiers.
- Preserve the existing `model-coaching-context.v1` compiler, prompt versions, corpus, and prior evaluation artifacts unchanged.

---

## File Structure

- `ChessTutor/Coaching/ModelEvaluation/ModelCoachingNeutralContracts.swift`: neutral snapshot, request, rule-fact, capability, compilation, and compact-turn value types.
- `ChessTutor/Coaching/ModelEvaluation/ModelCoachingNeutralRequestBuilder.swift`: pure conversion from raw game/interaction state to exhaustive neutral rule facts.
- `ChessTutor/Coaching/ModelEvaluation/ModelCoachingNeutralContextCompiler.swift`: interaction-scoped fact selection, stable aliases, and fixed Markdown document construction.
- `ChessTutor/Coaching/ModelEvaluation/ModelCoachingNeutralTurnValidator.swift`: mechanical validation of the three-field response contract.
- `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingNeutralRequestBuilderTests.swift`: rule derivation and no-policy boundary tests.
- `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingNeutralContextCompilerTests.swift`: deterministic Markdown, scoping, history, leakage, and budget-source tests.
- `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingNeutralTurnValidatorTests.swift`: action/focus/shape validation tests.
- `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingNeutralPromptExampleTests.swift`: eight production-shaped visible fixtures and immutable export.
- `Tools/CoachingEval/prompts/tutor-v5.md`: candidate zero-shot system prompt reviewed with the examples.
- `Tools/CoachingEval/preview_neutral_prompts.py`: tokenizer-only preview renderer and immutable manifest writer.
- `Tools/CoachingEval/tests/test_preview_neutral_prompts.py`: proves complete ordered coverage, budget enforcement, determinism, and absence of completion.

---

### Task 1: Neutral rule request and deterministic builder

**Files:**
- Create: `ChessTutor/Coaching/ModelEvaluation/ModelCoachingNeutralContracts.swift`
- Create: `ChessTutor/Coaching/ModelEvaluation/ModelCoachingNeutralRequestBuilder.swift`
- Create: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingNeutralRequestBuilderTests.swift`

**Interfaces:**
- Consumes: `GameState`, `PieceColor`, `Square`, `Move`, `ModelCoachingLearnerEventKind`, `LegalMoveGenerator`, `MoveHistoryFormatter`.
- Produces:

```swift
struct ModelCoachingNeutralSnapshot: Equatable, Sendable {
    let committedState: GameState
    let learner: PieceColor
    let positionRevision: Int
    let selectedSquare: Square?
    let tentativeMove: Move?
    let latestEvent: ModelCoachingNeutralEpisodeEvent
    let episodeEvents: [ModelCoachingNeutralEpisodeEvent]
}

struct ModelCoachingNeutralEpisodeEvent: Codable, Equatable, Sendable {
    let sequence: Int
    let kind: ModelCoachingLearnerEventKind
    let referencedIDs: [String]
}

struct ModelCoachingNeutralRequest: Codable, Equatable, Sendable {
    let schemaVersion: String
    let requestID: String
    let positionRevision: Int
    let position: ModelCoachingPosition
    let gameHistory: [ModelCoachingHistoryMove]
    let interaction: ModelCoachingNeutralInteraction
    let pieces: [ModelCoachingNeutralPiece]
    let legalMoves: [ModelCoachingNeutralMove]
    let occupiedSquareRelationships: [ModelCoachingNeutralRelationship]
    let tentativeReplies: [ModelCoachingNeutralReply]
    let capabilities: ModelCoachingNeutralCapabilities
}

enum ModelCoachingNeutralRequestBuilder {
    static func build(
        snapshot: ModelCoachingNeutralSnapshot,
        requestID: String
    ) -> ModelCoachingNeutralRequest
}
```

`ModelCoachingNeutralMove` carries stable ID, SAN/canonical notation, source piece, destination, optional capture, special move, `givesCheck`, and `givesCheckmate`. `ModelCoachingNeutralReply` carries the same direct rule outcomes after only the current tentative move. Capabilities are derived from whether selection/tentative state exists, not from a coaching stage.

- [ ] **Step 1: Write failing contract and starting-position tests**

Add tests that construct `ModelCoachingNeutralSnapshot` directly and expect `ModelCoachingNeutralRequestBuilder.build`. Assert starting-position FEN, full SAN history, 20 legal moves, no legal captures/checks/mates, no tentative replies, sorted stable IDs, and capabilities derived without an authored stage.

```swift
func testStartingPositionBuildsOnlyRuleDerivedNeutralEvidence() {
    let snapshot = ModelCoachingNeutralSnapshot(
        committedState: .startingPosition(),
        learner: .white,
        positionRevision: 0,
        selectedSquare: nil,
        tentativeMove: nil,
        latestEvent: event(1, .helpOpened),
        episodeEvents: [event(1, .helpOpened)]
    )

    let request = ModelCoachingNeutralRequestBuilder.build(
        snapshot: snapshot,
        requestID: "neutral-start"
    )

    XCTAssertEqual(request.schemaVersion, "model-coaching-neutral-request.v1")
    XCTAssertEqual(request.legalMoves.count, 20)
    XCTAssertTrue(request.legalMoves.allSatisfy { $0.capturePieceReference == nil })
    XCTAssertTrue(request.tentativeReplies.isEmpty)
}
```

- [ ] **Step 2: Run the selected test and verify RED**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingNeutralRequestBuilderTests
```

Expected: compile failure because the neutral contracts and builder do not exist.

- [ ] **Step 3: Implement neutral contracts and the minimal starting-position builder**

Build pieces and legal moves directly from `snapshot.committedState`. Use `MoveHistoryFormatter.notation(for:)` for SAN and `ModelCoachingPositionEncoder` for stable IDs. Do not instantiate `MaterialTacticalEvaluator` or accept `CoachingRequest.Context`.

- [ ] **Step 4: Add selected, tentative, check, capture, mate, and history tests**

Cover:

- selected white knight: all its legal moves and its attacker/defender relationships are present;
- staged bishop block: tentative legality plus every opponent capture/check reply is present;
- legal capture: captured piece reference is exact;
- checking and mating moves: `givesCheck`/`givesCheckmate` come from applying the legal move;
- eight committed plies: SAN is complete, ordered, and replays to the encoded FEN.

Add a source-boundary assertion that `ModelCoachingNeutralSnapshot` and `ModelCoachingNeutralRequestBuilder.swift` contain no `CoachingMoveOrigin`, `CoachingStage`, `MaterialTacticalEvaluator`, `CoachingAdvice`, or `ModelCoachingSemanticOracle` dependency.

- [ ] **Step 5: Run the selected builder tests and verify GREEN**

Run the Task 1 command again. Expected: all `ModelCoachingNeutralRequestBuilderTests` pass with zero skips.

- [ ] **Step 6: Commit Task 1**

```bash
git add ChessTutor/Coaching/ModelEvaluation/ModelCoachingNeutralContracts.swift \
  ChessTutor/Coaching/ModelEvaluation/ModelCoachingNeutralRequestBuilder.swift \
  ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingNeutralRequestBuilderTests.swift
git commit -m "feat: build neutral coaching rule requests"
```

---

### Task 2: Interaction-scoped neutral Markdown compiler

**Files:**
- Create: `ChessTutor/Coaching/ModelEvaluation/ModelCoachingNeutralContextCompiler.swift`
- Create: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingNeutralContextCompilerTests.swift`
- Reuse: `ChessTutor/Coaching/ModelEvaluation/ModelCoachingMarkdownRenderer.swift`

**Interfaces:**
- Consumes: `ModelCoachingNeutralRequest` from Task 1.
- Produces:

```swift
struct ModelCoachingNeutralContextCompilation: Codable, Equatable, Sendable {
    let schemaVersion: String
    let promptVersion: String
    let requestID: String
    let positionRevision: Int
    let markdown: String
    let referenceBindings: [ModelCoachingReferenceBinding]
}

enum ModelCoachingNeutralContextCompiler {
    static func compile(
        _ request: ModelCoachingNeutralRequest,
        promptVersion: String
    ) -> ModelCoachingNeutralContextCompilation
}
```

- [ ] **Step 1: Write failing fixed-section and leakage tests**

Require exact ordered headings:

```text
# Chess coaching situation
## Game
## Current help episode
## Rule facts
## Available interactions
```

Assert that starting-position Markdown contains FEN, side to move, `Moves: none`, `White is not in check`, and no `Selected move ideas`, `Danger scan`, `Safe captures`, `useful`, `purpose`, or expected response.

- [ ] **Step 2: Run compiler tests and verify RED**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingNeutralContextCompilerTests
```

Expected: compile failure because `ModelCoachingNeutralContextCompiler` does not exist.

- [ ] **Step 3: Implement the fixed document and stable aliases**

Render:

- `Game`: side, status, FEN, complete SAN, separate tentative move;
- `Current help episode`: ordered structured event kinds and aliased references, never event summary prose;
- `Rule facts`: global current attacks on occupied opposing pieces plus all legal captures/checks/mates;
- `Available interactions`: rule-derived board gestures, optional action aliases, and focus aliases.

Sort every generated collection by stable ID. Reuse `ModelCoachingMarkdownRenderer` only for sanitation and section assembly.

- [ ] **Step 4: Add interaction-scope tests**

Assert the same fixed categories for every state of a given interaction kind:

- no selection: omit exhaustive quiet moves;
- selection: include all and only legal moves plus attackers/defenders involving the selected piece;
- tentative move: include that move and all opponent replies that capture, check, or mate;
- inspected reply: include all direct capture/check/attack/defense relationships involving it;
- the compiler source has no reference to the legacy compact compiler, semantic oracles, tactical evaluator facts, or deterministic teaching stages.

Add a vocabulary audit over every generated line. Permit chess-rule words such as `legal`, `check`, `capture`, `attack`, and `defend`; reject conclusion-bearing phrases from Global Constraints.

- [ ] **Step 5: Add compact-history and deterministic-hash tests**

Compile the same eight-ply snapshot twice and assert byte equality, stable SHA-256, full SAN presence, one FEN occurrence, and no truncation marker.

- [ ] **Step 6: Run builder and compiler suites and verify GREEN**

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingNeutralRequestBuilderTests \
  -only-testing:ChessTutorTests/ModelCoachingNeutralContextCompilerTests
```

Expected: both suites pass with zero failures/skips.

- [ ] **Step 7: Commit Task 2**

```bash
git add ChessTutor/Coaching/ModelEvaluation/ModelCoachingNeutralContextCompiler.swift \
  ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingNeutralContextCompilerTests.swift
git commit -m "feat: compile neutral coaching markdown"
```

---

### Task 3: Candidate system prompt and mechanical output validator

**Files:**
- Create: `Tools/CoachingEval/prompts/tutor-v5.md`
- Create: `ChessTutor/Coaching/ModelEvaluation/ModelCoachingNeutralTurnValidator.swift`
- Create: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingNeutralTurnValidatorTests.swift`
- Create: `Tools/CoachingEval/tests/test_tutor_v5_prompt.py`

**Interfaces:**
- Consumes: `ModelCoachingNeutralContextCompilation.referenceBindings`.
- Produces:

```swift
struct ModelCoachingNeutralTurn: Codable, Equatable, Sendable {
    let message: String
    let actions: [String]
    let focus: [String]
}

enum ModelCoachingNeutralTurnValidator {
    static func issues(
        for turn: ModelCoachingNeutralTurn,
        compilation: ModelCoachingNeutralContextCompilation
    ) -> [String]
}
```

- [ ] **Step 1: Write failing validator tests**

Test one valid turn and rejection of empty/overlong message, unknown action, unknown focus, duplicate references, more than three actions, more than four focus references, and an action alias placed in `focus`.

- [ ] **Step 2: Run validator tests and verify RED**

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingNeutralTurnValidatorTests
```

Expected: compile failure because the neutral turn and validator do not exist.

- [ ] **Step 3: Implement the minimal validator**

Validate only structure, bounds, and request-local aliases. Do not rewrite messages, infer teaching intent, require particular evidence, or compare against an oracle.

- [ ] **Step 4: Author the concise zero-shot system prompt**

The prompt must explain:

- the child learns through board play and does not chat;
- the Markdown contains neutral, authoritative rule facts rather than a suggested lesson;
- the model chooses one useful current coaching step;
- Safe/Take/Wake is an optional reasoning lens, not a required sequence;
- the latest interaction supersedes older steps;
- the response uses only permitted action/focus aliases;
- output is exactly `{"message":"...","actions":[],"focus":[]}` with one short child-facing utterance and no private reasoning.

Do not include few-shot examples or case-specific chess language.

- [ ] **Step 5: Add prompt-boundary assertions and verify GREEN**

In `test_tutor_v5_prompt.py`, read `tutor-v5.md` from its repository path and assert it contains the neutral-facts boundary and response shape while excluding literal fixture IDs, FENs, preferred moves, and answer-bearing phrases. Keep prompt-resource testing in Python so the evaluator prompt is not added to the app or test bundle.

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingNeutralTurnValidatorTests
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s Tools/CoachingEval/tests -p 'test_tutor_v5_prompt.py' -v
```

Expected: both commands pass with zero failures/skips.

- [ ] **Step 6: Commit Task 3**

```bash
git add Tools/CoachingEval/prompts/tutor-v5.md \
  ChessTutor/Coaching/ModelEvaluation/ModelCoachingNeutralTurnValidator.swift \
  ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingNeutralTurnValidatorTests.swift \
  Tools/CoachingEval/tests/test_tutor_v5_prompt.py
git commit -m "feat: define neutral coaching turn contract"
```

---

### Task 4: Eight production-shaped prompt examples and immutable export

**Files:**
- Create: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingNeutralPromptExampleTests.swift`
- Modify: `project.yml` only if the environment variable forwarding needed by the exporter is not inherited by the test action.

**Interfaces:**
- Consumes: Task 1 builder, Task 2 compiler, `Tools/CoachingEval/prompts/tutor-v5.md`.
- Produces an ignored review directory configured by `COACHING_NEUTRAL_PREVIEW_DIR` containing:

```text
examples.jsonl
preview-manifest.json
system-prompt.md
user-prompts/
  01-quiet-help.md
  02-attacked-piece.md
  03-selected-piece.md
  04-replaced-tentative-move.md
  05-tactical-reply.md
  06-inspected-reply.md
  07-answering-check.md
  08-long-history.md
```

- [ ] **Step 1: Write the failing eight-example structure test**

Define exactly eight fixtures from structured board state and events only:

1. starting position, Help opened;
2. white knight f3 attacked by black pawn e4, no selection;
3. the same position with knight f3 selected;
4. starting position where h2-h4 was replaced by tentative g1-f3;
5. a tentative bishop move with an immediate opponent capture/check reply;
6. staged e7-e6 followed by inspection of bishop c4's reply;
7. bishop b5-e2 tentatively blocking rook e8's check on king e1;
8. a legal eight-ply opening history such as `1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6`.

Assert unique IDs, visible-only labels, exact order, and that every fixture is a `ModelCoachingNeutralSnapshot` without any prose/oracle field.

- [ ] **Step 2: Run example tests and verify RED**

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingNeutralPromptExampleTests
```

Expected: failure because example/export support does not exist.

- [ ] **Step 3: Implement the fixture builders and in-memory artifacts**

For each fixture, call only:

```swift
let request = ModelCoachingNeutralRequestBuilder.build(snapshot: snapshot, requestID: id)
let compilation = ModelCoachingNeutralContextCompiler.compile(request, promptVersion: "tutor-v5")
```

Serialize sorted-key JSONL with request plus compilation. Compute SHA-256 for system prompt, JSONL, and each Markdown input. Refuse hidden IDs and nonempty output directories.

- [ ] **Step 4: Add the opt-in immutable writer test**

With no environment variable, build artifacts twice and assert equality. With `COACHING_NEUTRAL_PREVIEW_DIR`, write exactly the declared files and refuse overwrite. Ensure every Markdown file is byte-identical to its serialized compilation.

- [ ] **Step 5: Run the example exporter and inspect structure**

```bash
COACHING_NEUTRAL_PREVIEW_DIR=.coaching-eval/neutral-prompt-preview/swift \
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingNeutralPromptExampleTests
```

Expected: test passes and writes exactly eight prompts plus manifest/system/JSONL. No model server or completion process is started.

- [ ] **Step 6: Run leakage and provenance scans**

```bash
rg -n -i 'semanticOracle|teachingIntent|preferred move|selected move ideas|danger scan|safe captures|useful relationship|what to teach' \
  .coaching-eval/neutral-prompt-preview/swift
rg -n 't1OutsidePawnMove|t3WrongAttacker|t7UnsafeCapture|t12WrongChecker' \
  .coaching-eval/neutral-prompt-preview/swift
```

Expected: both commands return no matches.

- [ ] **Step 7: Commit Task 4**

```bash
git add ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingNeutralPromptExampleTests.swift project.yml
git commit -m "test: export neutral coaching prompt examples"
```

Omit `project.yml` from `git add` if it did not need modification.

---

### Task 5: Tokenizer-only human review packet

**Files:**
- Create: `Tools/CoachingEval/preview_neutral_prompts.py`
- Create: `Tools/CoachingEval/tests/test_preview_neutral_prompts.py`
- Modify: `Tools/CoachingEval/README.md`

**Interfaces:**
- Consumes: Swift `examples.jsonl`, exact `tutor-v5.md`, and a client exposing only `render_prompt(...)` and `token_count(...)`.
- Produces: `.coaching-eval/neutral-prompt-preview/final/preview-manifest.json` and eight full logical prompt transcripts. It must never call `complete_rendered`, `/completion`, or any generation API.

- [ ] **Step 1: Write failing tokenizer-only tests**

Use a fake client whose generation method raises immediately. Assert:

- exact eight-case order and completeness;
- system/user SHA binding;
- deterministic rerun equality;
- refusal to overwrite;
- per-example user bytes, user words, rendered bytes, and token count;
- hard failure for any cell above 2,500 tokens;
- no response/output field in artifacts;
- no hidden IDs;
- fake generation call count remains zero.

- [ ] **Step 2: Run Python test and verify RED**

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s Tools/CoachingEval/tests -p 'test_preview_neutral_prompts.py' -v
```

Expected: import failure because `preview_neutral_prompts` does not exist.

- [ ] **Step 3: Implement immutable tokenizer-only preview generation**

Load exact inputs, call the pinned server's template/tokenizer endpoints, record hashes/counts, and write review Markdown containing the complete system message followed by the complete user message. Do not accept a model response and do not import evaluator scoring code.

- [ ] **Step 4: Run focused and full evaluator tests**

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s Tools/CoachingEval/tests -p 'test_preview_neutral_prompts.py' -v
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s Tools/CoachingEval/tests -v
```

Expected: all tests pass, zero failures/errors/skips.

- [ ] **Step 5: Generate the final review packet without inference**

Run the new command against the pinned Qwen3 1.7B tokenizer only, writing to a fresh final directory. Preserve its complete command and confirm no `run_eval`, completion, response, review, rubric, or scoring artifact appears.

- [ ] **Step 6: Verify exact prompt boundaries**

Check:

- eight prompts, eight unique request IDs, eight hashes;
- all token counts between 1 and 2,500;
- system prompt hash identical across examples;
- source JSONL/request/Markdown equality;
- no banned conclusion-bearing language;
- no hidden identifiers;
- no response text or trace fields;
- `git diff --check` and tracked status contain only scoped implementation files.

- [ ] **Step 7: Run the final proportional Swift suite**

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingNeutralRequestBuilderTests \
  -only-testing:ChessTutorTests/ModelCoachingNeutralContextCompilerTests \
  -only-testing:ChessTutorTests/ModelCoachingNeutralTurnValidatorTests \
  -only-testing:ChessTutorTests/ModelCoachingNeutralPromptExampleTests \
  -only-testing:ChessTutorTests/ModelCoachingRequestBuilderTests \
  -only-testing:ChessTutorTests/ModelCoachingCompactContextTests
```

Expected: all selected tests pass with zero failures/skips; legacy request/compact-context suites remain green.

- [ ] **Step 8: Commit Task 5 and stop for user review**

```bash
git add Tools/CoachingEval/preview_neutral_prompts.py \
  Tools/CoachingEval/tests/test_preview_neutral_prompts.py \
  Tools/CoachingEval/README.md
git commit -m "feat: preview neutral coaching prompts"
```

Report the exact review packet path and show representative full prompts. Do not invoke model inference. Wait for explicit user approval before writing or executing any model-run plan.

# Local-Model Coaching Evaluation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Determine, with reproducible Mac quality evidence and physical ninth-generation-iPad performance evidence, whether the smallest practical local GGUF model can produce coherent structured chess coaching.

**Architecture:** Add an inert, provider-neutral evaluation contract and mechanical request builder to the app module, then export semantic cases through the app's real chess-rule pipeline. A standard-library Python harness drives pinned llama.cpp models on Mac and produces blinded review artifacts; a separate standalone DEBUG lab links the same pinned llama.cpp runtime and shortlisted GGUF files on the physical iPad. Nothing in this plan routes the shipping tutor through a model or adds model assets to the normal app.

**Tech Stack:** Swift 6, XCTest, XcodeGen, Python 3 standard library, llama.cpp `b10516`, GGUF, JSON Schema, Hugging Face model artifacts, `xcodebuild`, `xcrun devicectl`.

## Global Constraints

- Target device: physical ninth-generation iPad, A13 Bionic, 64 GB, iPadOS 26.5.2.
- Target learner: a bright, verbally sophisticated five-year-old; use real chess vocabulary in short, concrete sentences and teach one current idea at a time.
- Safe/Take/Wake is optional prompt context, never a mandatory state sequence.
- Code is authoritative for position, legality, mechanical chess facts, stable references, available interactions, request identity, cancellation, stale-response rejection, and UI.
- The model owns pedagogical judgment and authors exactly one coherent structured coaching turn from the latest authoritative snapshot.
- Requests are logically stateless and include full committed game history plus full coaching and interaction history for the current chess turn.
- Current-turn coaching history survives closing and reopening Help and is cleared only when a chess move is committed or the game is reset.
- Do not export the deterministic coach's stage, preferred candidate, routine decision, authored conclusion, or strategic verdict as authoritative model evidence.
- Do not add Stockfish, open-ended chat, typing, voice, child profiles, cross-game memory, fine-tuning, production server plumbing, downloadable-model UX, or a deterministic coaching fallback.
- Do not change live coaching behavior during the evaluation spike.
- Keep model weights, llama.cpp builds, raw generations, hidden-set outputs, and device traces under ignored `.coaching-eval/`; never commit them or credentials.
- Use exactly the same downloaded GGUF bytes on Mac and iPad; record the resolved model revision, byte size, and SHA-256.
- The online reference is a comparison ceiling, not an automatic judge, and may be invoked only with a developer credential from environment variables.
- Allow at most one bounded JSON repair request; report first-attempt and repaired validity separately.
- Advance only the strongest one or two local candidates from Mac to the physical device.
- Treat model size and latency as measured tradeoffs; do not impose a hard pass/fail threshold before seeing quality and device data.
- End with one explicit recommendation: local-first, online-first with local offline coaching, or online-only.

---

## File and responsibility map

### Shipping module, inert during the spike

- `ChessTutor/Coaching/ModelEvaluation/ModelCoachingContracts.swift` — versioned Codable request/turn DTOs and stable reference types; Foundation-only except for existing chess value types in builder inputs.
- `ChessTutor/Coaching/ModelEvaluation/ModelCoachingTurnValidator.swift` — pure validation of a returned turn against one exact request.
- `ChessTutor/Coaching/ModelEvaluation/ModelCoachingPositionEncoder.swift` — canonical FEN, UCI-like move IDs, piece IDs, and deterministic ordering.
- `ChessTutor/Coaching/ModelEvaluation/ModelCoachingRequestBuilder.swift` — converts an explicit snapshot plus `MaterialTacticalEvaluator` output into policy-free model evidence.
- `ChessTutor/Core/LegalMoveGenerator.swift` — expose an internal read-only controlled-squares query used by the evidence builder.
- `ChessTutor/Game/MoveHistoryFormatter.swift` — expose ordered per-move display notation while retaining existing row rendering.

### App tests and corpus export

- `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingContractsTests.swift` — JSON round trips and schema-version stability.
- `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingTurnValidatorTests.swift` — strict identity/reference/action/copy-bound tests.
- `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingRequestBuilderTests.swift` — real-position fact, history, anti-smuggling, determinism, and completeness tests.
- `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingEvaluationCorpus.swift` — all 52 semantic cases, visible/hidden split, event histories, and human/mechanical oracles.
- `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingEvaluationCorpusTests.swift` — exhaustive case coverage and real-pipeline consistency.
- `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingCorpusExportTests.swift` — deterministic JSONL export when `COACHING_EVAL_OUTPUT_DIR` is set.

### Mac evaluation tools

- `Tools/CoachingEval/README.md` — exact setup, run, scoring, and cleanup commands.
- `Tools/CoachingEval/models.json` — candidate repositories, quantizations, license metadata, and thinking modes.
- `Tools/CoachingEval/runtime.json` — pinned llama.cpp tag and expected Mac/iOS build inputs.
- `Tools/CoachingEval/coaching-turn.schema.json` — response schema matching the Swift DTO.
- `Tools/CoachingEval/prompts/tutor-v1.md` — tutoring policy and structured-output instructions.
- `Tools/CoachingEval/prompts/examples-v1.json` — visible-set few-shot examples only.
- `Tools/CoachingEval/model_store.py` — resolve/download/checksum exact Hugging Face files.
- `Tools/CoachingEval/llama_server.py` — start/stop pinned `llama-server`, health-check it, and call Chat Completions.
- `Tools/CoachingEval/run_eval.py` — execute repetitions, modes, seeds, repair, online reference, and run manifests.
- `Tools/CoachingEval/validate_turn.py` — mirror the Swift validator for batch reports.
- `Tools/CoachingEval/render_review.py` — anonymize outputs and create a blinded scoring packet.
- `Tools/CoachingEval/summarize_eval.py` — aggregate validity, latency, token, rubric, and severe-error results without hiding dimensions in one score.
- `Tools/CoachingEval/tests/` — `unittest` coverage for every Python responsibility.
- `.gitignore` — ignore `.coaching-eval/`.

### Standalone physical-device lab

- `Tools/CoachingModelLab/project.yml` — standalone XcodeGen project; never included in the root `ChessTutor` scheme.
- `Tools/CoachingModelLab/Sources/App/CoachingModelLabApp.swift` — DEBUG lab entry point.
- `Tools/CoachingModelLab/Sources/App/LabView.swift` — stable board/interaction placeholder, Thinking shell, result, and metric display.
- `Tools/CoachingModelLab/Sources/App/LlamaInferenceEngine.swift` — minimal pinned llama.cpp Swift adapter derived with attribution from the official `llama.swiftui` sample.
- `Tools/CoachingModelLab/Sources/Core/LabSession.swift` — latest-revision lifecycle, cancellation, supersession, and result recording.
- `Tools/CoachingModelLab/Sources/Core/BenchmarkRecorder.swift` — cold/warm timing, token counts, throughput, memory warnings, thermal state, and JSONL output.
- `Tools/CoachingModelLab/Tests/LabSessionTests.swift` — fake-engine lifecycle and metric tests.
- `Tools/CoachingEval/prepare_llama_runtime.sh` — clone tag `b10516`, build Mac server and iOS XCFramework into `.coaching-eval/runtime/`.
- `Tools/CoachingEval/prepare_device_lab.py` — copy selected corpus/model metadata into ignored generated lab inputs and generate the standalone project.
- `Tools/CoachingEval/install_device_model.py` — install the lab and copy a selected GGUF into its app data container.
- `docs/reports/2026-08-28-local-model-coaching-evaluation.md` — committed evidence and final recommendation.

---

### Task 1: Versioned model-coaching contract and strict validator

**Files:**
- Create: `ChessTutor/Coaching/ModelEvaluation/ModelCoachingContracts.swift`
- Create: `ChessTutor/Coaching/ModelEvaluation/ModelCoachingTurnValidator.swift`
- Create: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingContractsTests.swift`
- Create: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingTurnValidatorTests.swift`
- Regenerate: `ChessTutor.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `PieceColor`, `Piece.Kind`, `Square`, and `Move` only through later builder code; contract values themselves encode squares, pieces, and moves as stable strings.
- Produces: `ModelCoachingRequest`, `ModelCoachingTurn`, `ModelCoachingTurnValidator.validate(_:against:) -> [ModelCoachingValidationIssue]`, and `ModelCoachingLimits.default`.

- [ ] **Step 1: Write JSON round-trip and stable-shape tests**

Create tests that instantiate the complete public contract and assert exact encoded keys, enum raw values, and lossless decode. Use these exact top-level declarations:

```swift
struct ModelCoachingRequest: Codable, Equatable, Sendable {
    let schemaVersion: String
    let promptVersion: String
    let requestID: String
    let positionRevision: Int
    let currentPosition: ModelCoachingPosition
    let fullGameHistory: [ModelCoachingHistoryMove]
    let currentInteraction: ModelCoachingInteraction
    let currentTurnCoachingHistory: [ModelCoachingHistoryEntry]
    let chessEvidence: ModelCoachingEvidenceBundle
    let permittedReferences: ModelCoachingPermittedReferences
}

struct ModelCoachingTurn: Codable, Equatable, Sendable {
    let schemaVersion: String
    let requestID: String
    let teachingIntent: ModelCoachingTeachingIntent
    let primaryMessage: String
    let instruction: String?
    let responseToLatestAction: String?
    let actionReferences: [String]
    let boardTaskReference: String?
    let boardFocusReferences: [String]
    let relationshipReferences: [String]
    let supportingEvidenceReferences: [String]
}
```

Define the nested request DTOs with these exact stored fields:

```text
ModelCoachingPosition(fen, sideToMove, status)
ModelCoachingHistoryMove(ply, canonicalMove, displayNotation)
ModelCoachingInteraction(selectedPieceReference?, tentativeMoveReference?, latestEvent, availableOperationReferences)
ModelCoachingHistoryEntry(sequence, kind, summary, referencedIDs)
ModelCoachingEvidenceBundle(scope, pieces, legalMoves, relationships, immediateReplies, tacticalFacts)
ModelCoachingEvidenceScope(legalMoves, relationships, immediateReplies) where each value is exhaustive or bounded
ModelCoachingPieceReference(id, color, kind, square)
ModelCoachingMoveReference(id, canonicalMove, sourcePieceReference, destinationSquare, capturePieceReference?, special, isLegal)
ModelCoachingRelationshipReference(id, kind, sourceReference, targetReference)
ModelCoachingReplyReference(id, afterMoveReference, replyMoveReference, checkingPieceReferences, capturedPieceReference?, netMaterialGain?)
ModelCoachingTacticalFact(id, kind, subjectReferences, integerValue?)
ModelCoachingPermittedReferences(actions, boardTasks, boardFocus, relationships, evidence)
ModelCoachingPermittedAction(id, kind, title)
ModelCoachingPermittedBoardTask(id, kind)
```

Use string-backed enums for all categories. Define these exact cases:

```text
ModelCoachingEvidenceScopeKind: exhaustive, bounded
ModelCoachingRelationshipKind: attacks, defends, checks, canCapture, canRecapture
ModelCoachingTacticalFactKind: inCheck, checkmate, stalemate, dangerLoss, exchangeGain, mateInOne
ModelCoachingActionKind: hint, noPieceNeedsHelp, noSafeCapture, looksSafe, playMove, tryAnotherMove, closeHelp
ModelCoachingBoardTaskKind: none, identifyPiece, inspectRelationship, movePiece, confirmMove
ModelCoachingLearnerEventKind: helpOpened, helpReopened, pieceSelected, squareInspected, moveStaged, moveReplaced, moveRemoved, actionChosen, helpClosed
ModelCoachingHistoryKind: learnerEvent, tutorTurn, supersededRequest
ModelCoachingOperation: selectBoardPiece, inspectSquare, stageMove, replaceMove, removeMove, hint, noPieceNeedsHelp, noSafeCapture, looksSafe, playMove, tryAnotherMove, closeHelp
```

`ModelCoachingLearnerEvent` stores `kind` and ordered `referencedIDs`. `ModelCoachingTeachingIntent` contains `orient`, `scanDanger`, `scanCapture`, `chooseMove`, `evaluateMove`, `reviseMove`, `confirmMove`, `resolveCheck`, `findMate`, and `other`. Request schema is `model-coaching-request.v1`; turn schema is `model-coaching-turn.v1`.

- [ ] **Step 2: Run the contract tests and record RED**

Run:

```bash
xcodegen generate
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingContractsTests
```

Expected: compile failure because the contract types do not exist.

- [ ] **Step 3: Implement the Codable contract without chess or UI logic**

Keep every contract type `Codable`, `Equatable`, and `Sendable`. Sort/reference ordering is a builder concern, not a decoder concern. Use no `Any`, `[String: Any]`, or raw JSON blobs.

- [ ] **Step 4: Write validator tests for every rejection class**

Test one valid turn and exact failures for:

```text
wrong turn schema
wrong request ID
unknown action reference
unknown board-task reference
unknown board-focus reference
unknown relationship reference
unknown supporting-evidence reference
duplicate action/reference
more than 3 actions
primary message over 18 words
instruction over 14 words
response over 16 words
action title over 5 words in the request
turn with no supporting evidence reference
board focus outside permitted boardFocus IDs
```

`ModelCoachingLimits.default` is exactly `(primaryWords: 18, instructionWords: 14, responseWords: 16, actionTitleWords: 5, actionCount: 3)`.

- [ ] **Step 5: Run validator tests and record RED**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingTurnValidatorTests
```

Expected: compile failure because `ModelCoachingTurnValidator` does not exist.

- [ ] **Step 6: Implement the pure validator**

Return all issues in deterministic enum order rather than stopping at the first issue. Require at least one supporting evidence reference for every turn, including a question or general opening suggestion; current-position or legal-move evidence can support a non-observational turn. This prevents unsupported factual language from being hidden in `primaryMessage`.

- [ ] **Step 7: Run focused and full contract tests**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingContractsTests \
  -only-testing:ChessTutorTests/ModelCoachingTurnValidatorTests
git diff --check
```

Expected: all selected tests pass; diff check emits no output.

- [ ] **Step 8: Commit Task 1**

```bash
git add ChessTutor/Coaching/ModelEvaluation \
  ChessTutorTests/Coaching/ModelEvaluation \
  ChessTutor.xcodeproj/project.pbxproj
git commit -m "feat: define model coaching contract"
```

---

### Task 2: Policy-free mechanical request builder

**Files:**
- Create: `ChessTutor/Coaching/ModelEvaluation/ModelCoachingPositionEncoder.swift`
- Create: `ChessTutor/Coaching/ModelEvaluation/ModelCoachingRequestBuilder.swift`
- Modify: `ChessTutor/Core/LegalMoveGenerator.swift`
- Modify: `ChessTutor/Game/MoveHistoryFormatter.swift`
- Create: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingRequestBuilderTests.swift`
- Regenerate: `ChessTutor.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `CoachingRequest`, `CoachingInteractionSnapshot`, explicit latest event/history/available operations, `LegalMoveGenerator`, and `MaterialTacticalEvaluator.evaluate(_:)`.
- Produces: `ModelCoachingSnapshot`, `ModelCoachingLearnerEvent`, `ModelCoachingRequestBuilder.build(snapshot:requestID:promptVersion:) -> ModelCoachingRequest`, `ModelCoachingPositionEncoder.fen(for:)`, `ModelCoachingPositionEncoder.moveID(_:)`, and `MoveHistoryFormatter.notation(for:) -> [String]`.

- [ ] **Step 1: Write canonical encoding tests**

Assert:

```text
starting FEN == rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1
ordinary move ID == move:g1-f3
kingside castle ID == move:e1-g1:castle-kingside
promotion ID == move:a7-a8:promote-queen
piece ID == piece:white:queen:f3
relationship ID == relationship:attack:piece:white:queen:f3->piece:black:pawn:f7
history for [e2-e4, e7-e5] has canonical IDs and display notation [e4, e5]
```

Expose `MoveHistoryFormatter.notation(for:)` by returning its existing `notationByMove(for:)` result; keep `rows(for:)` behavior unchanged.

- [ ] **Step 2: Run encoding tests and record RED**

Run the request-builder test class. Expected: compile failure for missing encoder/builder APIs.

- [ ] **Step 3: Implement canonical encoders and the read-only controlled-squares API**

Add this internal API without changing move legality:

```swift
static func controlledSquares(from square: Square, in state: GameState) -> Set<Square>
```

It delegates to the existing private controlled-square implementation for the piece on `square`, including occupied friendly squares as defended targets. Test pawn diagonals, slider blocking, knight jumps, and king adjacency.

- [ ] **Step 4: Write real-pipeline request tests before the builder**

Define the builder input exactly as:

```swift
struct ModelCoachingSnapshot: Equatable, Sendable {
    let coachingRequest: CoachingRequest
    let interaction: CoachingInteractionSnapshot
    let latestEvent: ModelCoachingLearnerEvent
    let currentTurnHistory: [ModelCoachingHistoryEntry]
    let availableOperations: [ModelCoachingOperation]
}
```

Cover at least these real positions:

- starting position: complete legal moves, no empty safety quiz policy, full piece/defense relationships;
- queen f3 attacking pawn f7: exact attack and king-defense references, with no coaching stage or recommended answer;
- endangered knight: exact profitable reply and danger facts from `MaterialTacticalEvaluator`;
- staged h2-h4: tentative move and latest event represented, without a center-purpose annotation;
- discovered check, castling check, and mate-in-one: exact checker/reply/tactical references;
- a two-move game plus Help-close/reopen history: all committed moves and all current-turn history entries preserved in order;
- same snapshot built twice: byte-for-byte identical JSON except for caller-supplied request ID.

Assert that encoded JSON contains none of these property names or values: `CoachingStage`, `routine`, `wakeTask`, `preferred`, `openingDevelopmentIsRelevant`, `primaryDangerProblems`, authored coaching copy, or `LocalCoachingInsightSource` concepts.

- [ ] **Step 5: Implement the builder from mechanical sources only**

The builder must call `MaterialTacticalEvaluator.evaluate(_:)` and may encode its checking pieces, capture estimates, danger losses, mate moves, opponent activities, and move assessments. It must not instantiate or call `LocalCoachingAdvisor`, `LocalCoachingInsightSource`, `CoachingReconciler`, `CoachingPresentationProjector`, or `LocalCoachingExplanationSource`.

Use deterministic rank-major move ordering and lexicographic reference ordering. Mark legal moves and board relationships `exhaustive`; mark immediate replies `bounded` with scope text `one legal opponent ply after each legal or staged learner move`. Provide permitted references only for IDs actually present in the request. Available actions and tasks come only from the explicit `availableOperations` input.

- [ ] **Step 6: Run request-builder tests and static anti-smuggling checks**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingRequestBuilderTests
rg -n 'LocalCoachingAdvisor|LocalCoachingInsightSource|CoachingReconciler|CoachingPresentationProjector|LocalCoachingExplanationSource' \
  ChessTutor/Coaching/ModelEvaluation
```

Expected: tests pass and `rg` emits no matches.

- [ ] **Step 7: Run affected core tests**

Run the full `LegalMoveGeneratorTests`, `MoveHistoryFormatterTests`, `MaterialTacticalEvaluatorTests`, and all three ModelCoaching test classes. Expected: pass with zero skipped tests.

- [ ] **Step 8: Commit Task 2**

```bash
git add ChessTutor/Core/LegalMoveGenerator.swift \
  ChessTutor/Game/MoveHistoryFormatter.swift \
  ChessTutor/Coaching/ModelEvaluation \
  ChessTutorTests/Coaching/ModelEvaluation \
  ChessTutor.xcodeproj/project.pbxproj
git commit -m "feat: build policy-free coaching requests"
```

---

### Task 3: Real-pipeline semantic corpus and deterministic exporter

**Files:**
- Create: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingEvaluationCorpus.swift`
- Create: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingEvaluationCorpusTests.swift`
- Create: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingCorpusExportTests.swift`
- Regenerate: `ChessTutor.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: all 52 `CoachingGoldenCase` identifiers, `CoachingGoldenPosition`, `CoachingGoldenMoves`, and `ModelCoachingRequestBuilder`.
- Produces: `ModelCoachingEvaluationCase`, `ModelCoachingSemanticOracle`, `ModelCoachingEvaluationCorpus.allCases`, `.visibleCases`, `.hiddenCases`, and deterministic `visible.jsonl` / `hidden.jsonl` exports.

- [ ] **Step 1: Write exhaustive corpus-structure tests**

Define:

```swift
enum ModelCoachingCorpusSplit: String, Codable, Sendable { case visible, hidden }

struct ModelCoachingSemanticOracle: Codable, Equatable, Sendable {
    let requiredEvidenceReferences: [String]
    let requiredAnyEvidenceReferenceGroups: [[String]]
    let forbiddenEvidenceReferences: [String]
    let requiredActionKinds: [String]
    let forbiddenActionKinds: [String]
    let permittedTeachingIntents: [ModelCoachingTeachingIntent]
    let prohibitedPhrases: [String]
    let successCriteria: [String]
    let severeFailureCriteria: [String]
}

struct ModelCoachingEvaluationCase: Codable, Equatable, Sendable {
    let id: String
    let split: ModelCoachingCorpusSplit
    let request: ModelCoachingRequest
    let oracle: ModelCoachingSemanticOracle
}
```

Require exactly 52 unique case IDs corresponding one-for-one with `CoachingGoldenCase.allCases`. Reserve these 11 cases as hidden and expose the other 41 as visible:

```text
t1OutsidePawnMove, t3WrongAttacker, t4LowerPriorityPawn,
t5ProtectedAbsence, t7UnsafeCapture, t9Completed, t10Completed,
t11IncorrectLooksSafe, t11BenignCaptureLooksSafe,
t12WrongChecker, t12UnsupportedSafeMove
```

Assert hidden count 11 (21.15%), visible count 41, and no hidden case ID appears in the prompt examples file added later.

- [ ] **Step 2: Run corpus tests and record RED**

Run the new corpus test class. Expected: compile failure because the corpus types do not exist.

- [ ] **Step 3: Author all 52 scenario snapshots and semantic oracles**

Each exhaustive switch branch must build a `ModelCoachingSnapshot`, call the production builder, and describe behavior rather than exact prose. Preserve the established T1–T12 themes:

```text
T1 opening choices and piece switching
T2 castling and alternative selections
T3 endangered-piece target/attacker/resolution
T4 danger priority
T5 threatened versus protected pieces
T6 safe capture discovery
T7 no-safe-capture and learner moving ahead
T8 adding an exact defender
T9 creating an exact threat
T10 mobility/central activity
T11 opponent reply, benign activity, and revision
T12 resolving check and unsupported quiet positions
```

For every case, include at least two concrete `successCriteria` sentences and at least one `severeFailureCriteria` sentence. Add shared prohibitions for mixed stages, evaluator/debugger language, invented board facts, unanswered or unanswerable questions, repeated feedback, and forcing an obsolete step after a staged/replaced move. Add case-specific prohibitions such as no center claim for h2-h4 and no safety quiz on White's first move.

- [ ] **Step 4: Add coherence and anti-drift tests**

For every case assert:

- the request validates its own permitted-reference sets;
- every oracle evidence ID exists in that request;
- required and forbidden sets are disjoint;
- every relationship is derivable from the encoded board and controlled-square API;
- all move/reply references are legal in the stated scope;
- histories are ordered and current interaction matches the final history event;
- building the corpus twice yields identical JSON after normalizing caller request IDs;
- no request contains current deterministic presentation copy or policy fields.

- [ ] **Step 5: Implement opt-in JSONL export**

`ModelCoachingCorpusExportTests` reads `COACHING_EVAL_OUTPUT_DIR`. When absent it asserts corpus determinism and passes without writing. When present it creates exactly:

```text
<output>/visible.jsonl
<output>/hidden.jsonl
<output>/corpus-manifest.json
```

Write one sorted-key JSON object per line. Manifest includes schema versions, case counts, split IDs, source Git SHA from `COACHING_EVAL_SOURCE_SHA`, and SHA-256 of both JSONL files. Fail rather than overwrite a nonempty output directory.

- [ ] **Step 6: Run focused tests and export twice for byte equality**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingEvaluationCorpusTests

COACHING_EVAL_OUTPUT_DIR="$PWD/.coaching-eval/export-a" \
COACHING_EVAL_SOURCE_SHA="$(git rev-parse HEAD)" \
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingCorpusExportTests

COACHING_EVAL_OUTPUT_DIR="$PWD/.coaching-eval/export-b" \
COACHING_EVAL_SOURCE_SHA="$(git rev-parse HEAD)" \
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingCorpusExportTests

diff -r .coaching-eval/export-a .coaching-eval/export-b
```

Expected: tests pass and `diff` emits no output.

- [ ] **Step 7: Commit Task 3**

```bash
git add ChessTutorTests/Coaching/ModelEvaluation ChessTutor.xcodeproj/project.pbxproj
git commit -m "test: export semantic coaching corpus"
```

---

### Task 4: Reproducible Mac model runner, prompt, mechanical scoring, and blinded review

**Files:**
- Modify: `.gitignore`
- Create: `Tools/CoachingEval/README.md`
- Create: `Tools/CoachingEval/models.json`
- Create: `Tools/CoachingEval/runtime.json`
- Create: `Tools/CoachingEval/coaching-turn.schema.json`
- Create: `Tools/CoachingEval/prompts/tutor-v1.md`
- Create: `Tools/CoachingEval/prompts/examples-v1.json`
- Create: `Tools/CoachingEval/model_store.py`
- Create: `Tools/CoachingEval/llama_server.py`
- Create: `Tools/CoachingEval/run_eval.py`
- Create: `Tools/CoachingEval/validate_turn.py`
- Create: `Tools/CoachingEval/render_review.py`
- Create: `Tools/CoachingEval/summarize_eval.py`
- Create: `Tools/CoachingEval/tests/test_model_store.py`
- Create: `Tools/CoachingEval/tests/test_llama_server.py`
- Create: `Tools/CoachingEval/tests/test_validate_turn.py`
- Create: `Tools/CoachingEval/tests/test_run_eval.py`
- Create: `Tools/CoachingEval/tests/test_render_review.py`
- Create: `Tools/CoachingEval/tests/test_summarize_eval.py`

**Interfaces:**
- Consumes: exported `visible.jsonl` and `hidden.jsonl`, prompt/schema files, local GGUF paths, and an OpenAI-compatible optional reference endpoint.
- Produces: exact model artifacts in `.coaching-eval/models/`, raw run JSONL, run manifests, validation records, blinded review packets, rubric CSV, and aggregate JSON/Markdown summaries.

- [ ] **Step 1: Ignore all large and private evaluation artifacts**

Add exactly:

```gitignore
.coaching-eval/
```

Test with `git check-ignore .coaching-eval/models/example.gguf` and confirm the path is ignored.

- [ ] **Step 2: Write manifest/parser tests before implementation**

`models.json` contains these four entries and no unpinned local aliases:

```json
[
  {"id":"qwen3-0.6b-q4_0","repository":"ggml-org/Qwen3-0.6B-GGUF","selector":"Q4_0","filename":"Qwen3-0.6B-Q4_0.gguf","license":"Apache-2.0","thinkingModes":["off","bounded"]},
  {"id":"gemma3-1b-qat-q4_0","repository":"google/gemma-3-1b-it-qat-q4_0-gguf","selector":"Q4_0","filename":null,"license":"Gemma Terms","requiresToken":true,"thinkingModes":["off"]},
  {"id":"qwen3-1.7b-q4_k_m","repository":"ggml-org/Qwen3-1.7B-GGUF","selector":"Q4_K_M","filename":"Qwen3-1.7B-Q4_K_M.gguf","license":"Apache-2.0","thinkingModes":["off","bounded"]},
  {"id":"smollm3-3b-q4_k_m","repository":"ggml-org/SmolLM3-3B-GGUF","selector":"Q4_K_M","filename":"SmolLM3-Q4_K_M.gguf","license":"Apache-2.0","thinkingModes":["off","bounded"]}
]
```

`runtime.json` pins `llamaCppTag` to `b10516`, Mac context to 8192, output maximum to 256 tokens, temperature to 0.2, top-p to 0.9, and repetitions to 3 with seeds `[1103, 2207, 3301]`.

Test model resolution against a local fake Hugging Face API response. The downloader must resolve repository `main` to an immutable commit, select the exact quantization file, stream bytes, calculate SHA-256, and write `artifact-manifest.json`; a repeated call must reuse only a file whose size and checksum still match.

- [ ] **Step 3: Implement `model_store.py` with standard-library networking**

Use `urllib.request`, `hashlib`, `json`, and `pathlib`; accept `HF_TOKEN` only from the environment and send it only to `huggingface.co`. Commands are:

```bash
python3 Tools/CoachingEval/model_store.py list
python3 Tools/CoachingEval/model_store.py fetch qwen3-0.6b-q4_0
python3 Tools/CoachingEval/model_store.py fetch-all
python3 Tools/CoachingEval/model_store.py verify
```

For Gemma, emit a direct message explaining that the Gemma Terms must be accepted and `HF_TOKEN` supplied; do not silently substitute another artifact.

- [ ] **Step 4: Write schema and validator parity tests**

The JSON Schema requires every nonoptional `ModelCoachingTurn` field; the three Swift optional fields may be absent or JSON null. It uses `additionalProperties: false` at every object level, caps arrays and strings consistently with `ModelCoachingLimits.default`, and enumerates teaching intents. Python validation additionally checks request identity and set membership against the input case. Use fixture tests proving the Python and Swift validators accept/reject the same valid and invalid turns.

- [ ] **Step 5: Author the versioned tutor prompt and visible examples**

`tutor-v1.md` must state, in this order:

1. tutor persona and bounded board/button interaction;
2. supplied facts are authoritative and unsupported chess claims are forbidden;
3. recalculate from the current snapshot and follow a learner who moved ahead;
4. choose one useful current teaching idea;
5. Safe/Take/Wake is an optional scan, not a required ritual;
6. skip obvious questions, especially opening safety/capture questions with no available answer;
7. distinguish the current instruction from optional feedback and omit repetitive feedback;
8. select only supplied action/task/focus/relationship/evidence IDs;
9. produce only one JSON object matching the schema and never expose chain-of-thought.

Examples contain only visible-set requests and approved structured answers. Include at least: first-move opening, endangered piece, no-safe-capture followed by a staged move, benign opponent activity, replacement move, check resolution, mate-in-one, and quiet move with no named purpose. No hidden case ID or hidden request may appear.

- [ ] **Step 6: Write RED tests for server lifecycle and evaluation records**

Use a fake executable HTTP server to assert:

- server starts on an assigned localhost port and `/health` must report ready;
- each request includes system prompt, exact request JSON, schema-constrained `response_format`, seed, output cap, and model-appropriate `chat_template_kwargs.enable_thinking`;
- timeout terminates the process group;
- raw text, parsed turn, first-attempt validation, optional repair validation, prompt/input/output tokens, prompt/generation timings, seed, model artifact hash, llama.cpp version, case split, and errors are recorded;
- any provider `reasoning_content` or thinking trace is discarded before persistence; only final response content is stored or scored;
- repair is attempted once only for parse/schema failure, never for a mechanically valid but pedagogically poor turn;
- the optional reference endpoint reads only `COACHING_EVAL_REFERENCE_URL`, `COACHING_EVAL_REFERENCE_MODEL`, and `COACHING_EVAL_REFERENCE_API_KEY`.

- [ ] **Step 7: Implement the local and optional online runners**

`run_eval.py` subcommands are:

```bash
python3 Tools/CoachingEval/run_eval.py local --model qwen3-0.6b-q4_0 --split visible
python3 Tools/CoachingEval/run_eval.py local --model qwen3-0.6b-q4_0 --split hidden
python3 Tools/CoachingEval/run_eval.py reference --split visible
python3 Tools/CoachingEval/run_eval.py reference --split hidden
```

Local mode launches pinned `llama-server -m <verified-file> -c 8192 --host 127.0.0.1 --port <ephemeral>`, runs three seeds per case/mode, and always stops the process in `finally`. Hidden cases use the frozen prompt/examples but are never rendered during prompt tuning.

- [ ] **Step 8: Implement blinded review and multidimensional summaries**

`render_review.py` shuffles with a recorded review seed and writes:

```text
review-packet.jsonl
review-key.json
rubric.csv
```

The packet shows position/history/latest action, the candidate turn, success criteria, and severe-failure criteria but not model identity. Rubric columns are `factualCorrectness`, `oneCoherentStep`, `responsiveToLatestAction`, `answerability`, `childClarity`, `pedagogicalUsefulness`, `unnecessaryInterrogation`, `mixedStages`, `severeError`, and `notes`; ordinal positive fields use 1–5, negative fields use 0/1, and severe error uses 0/1.

`summarize_eval.py` refuses incomplete rubric rows and reports each dimension, first-attempt validity, repaired validity, severe-error count, p50/p90 latency, input/output tokens, and raw examples by case. It must not emit a single composite winner score.

- [ ] **Step 9: Run all Python tests and one fake end-to-end evaluation**

Run:

```bash
python3 -m unittest discover -s Tools/CoachingEval/tests -v
python3 Tools/CoachingEval/run_eval.py local \
  --model fake-test-model --split visible --case t1Entry --repetitions 1
python3 Tools/CoachingEval/render_review.py --run .coaching-eval/runs/fake-test-model
python3 Tools/CoachingEval/summarize_eval.py --run .coaching-eval/runs/fake-test-model
git diff --check
```

The fake model is test-only and returns a valid fixed JSON turn through the same HTTP path; no production command accepts it unless `COACHING_EVAL_ALLOW_FAKE=1`.

- [ ] **Step 10: Commit Task 4**

```bash
git add .gitignore Tools/CoachingEval
git commit -m "feat: add reproducible coaching model evaluator"
```

---

### Task 5: Execute the Mac quality round and select device finalists

**Files:**
- Create: `docs/reports/2026-08-28-local-model-coaching-evaluation.md`
- Modify only if tests expose harness defects: files under `Tools/CoachingEval/`

**Interfaces:**
- Consumes: frozen corpus export, `tutor-v1`, exact candidate manifests, optional online-reference environment variables, and completed blinded rubric rows.
- Produces: immutable run manifests, Mac quality tables/examples, and an explicit list of zero, one, or two models advancing to device testing.

- [ ] **Step 1: Establish a clean baseline and export the frozen corpus**

Run the complete ChessTutor scheme once, export visible/hidden cases to `.coaching-eval/corpus/v1`, verify its manifest, and record the source commit in the report. Do not alter prompt/examples after beginning hidden-set runs; a later prompt change requires a new prompt version and complete rerun.

- [ ] **Step 2: Build the pinned Mac runtime**

Clone tag `b10516` under `.coaching-eval/runtime/llama.cpp`, build `llama-server` with Metal, and record `llama-server --version`, compiler, macOS version, and Mac hardware in `.coaching-eval/runtime/runtime-manifest.json`. Verify the checkout's Git SHA matches tag `b10516` before running models.

- [ ] **Step 3: Download and verify candidates smallest-first**

Run `model_store.py fetch` in this order: Qwen3 0.6B, Gemma 3 1B, Qwen3 1.7B, SmolLM3 3B. Record actual bytes and hashes. If Gemma access is unavailable, mark exactly that candidate `not run: license access unavailable`; do not replace it.

- [ ] **Step 4: Run visible-set prompt/mode experiments**

For each available candidate, run all manifest modes and three seeds. Review mechanical output first. Tune only by creating a new immutable prompt/examples version; preserve every prior run. Stop adding prompt variants when failures repeat across two prompt versions or the variant only overfits named visible cases.

- [ ] **Step 5: Run the frozen hidden set and optional online reference**

Run hidden cases exactly once per finalist prompt configuration. If reference environment variables exist, run the same visible and hidden requests through the online endpoint; otherwise record `online reference not run: credential unavailable` without blocking the local decision.

- [ ] **Step 6: Complete blinded human scoring**

Generate one combined blinded packet, score every output using the fixed rubric, then unblind. Independently spot-check every severe-error row against the original request evidence. Preserve the completed rubric and review key in ignored artifacts; commit aggregate numbers and representative anonymized examples only.

- [ ] **Step 7: Apply the advancement rule explicitly**

Advance the smallest model whose turns are broadly usable without editing and show no systematic severe failure class. Advance a second model only if it has a product-significant quality advantage worth measuring against device cost. If no model qualifies, record that outcome and skip Tasks 6–7's model execution while still documenting the negative feasibility result.

- [ ] **Step 8: Write and verify the Mac report section**

The report includes exact artifact revisions/hashes/licenses/sizes, prompt versions, modes/seeds, corpus hashes, first/repaired validity, every rubric dimension, severe-error taxonomy, p50/p90 Mac latency, representative good/bad turns, online-reference status, and finalist rationale. Cross-check every number against `summarize_eval.py` output.

- [ ] **Step 9: Commit Task 5**

```bash
git add docs/reports/2026-08-28-local-model-coaching-evaluation.md
git commit -m "docs: report local coaching model quality"
```

---

### Task 6: Standalone llama.cpp physical-device lab

**Files:**
- Create: `Tools/CoachingModelLab/project.yml`
- Create: `Tools/CoachingModelLab/Sources/App/CoachingModelLabApp.swift`
- Create: `Tools/CoachingModelLab/Sources/App/LabView.swift`
- Create: `Tools/CoachingModelLab/Sources/App/LlamaInferenceEngine.swift`
- Create: `Tools/CoachingModelLab/Sources/Core/LabSession.swift`
- Create: `Tools/CoachingModelLab/Sources/Core/BenchmarkRecorder.swift`
- Create: `Tools/CoachingModelLab/Tests/LabSessionTests.swift`
- Create: `Tools/CoachingEval/prepare_llama_runtime.sh`
- Create: `Tools/CoachingEval/prepare_device_lab.py`
- Create: `Tools/CoachingEval/install_device_model.py`
- Create: `Tools/CoachingEval/tests/test_prepare_device_lab.py`
- Create: `Tools/CoachingEval/tests/test_install_device_model.py`

**Interfaces:**
- Consumes: one or two verified finalist GGUFs, pinned llama.cpp `b10516`, frozen corpus JSON, and the shared `ModelCoachingTurn` JSON contract.
- Produces: a separate `CoachingModelLab` app, `LlamaInferenceEngine.generate(request:configuration:)`, `LabSession.submit(request:configuration:)`, and exported device `metrics.jsonl`.

- [ ] **Step 1: Write fake-engine lifecycle tests before the lab implementation**

Define:

```swift
protocol LabInferenceEngine: Sendable {
    func generate(
        request: ModelCoachingRequest,
        configuration: LabGenerationConfiguration
    ) async throws -> LabGenerationResult
}

struct LabGenerationConfiguration: Codable, Equatable, Sendable {
    let promptVersion: String
    let mode: String
    let seed: UInt64
    let maximumOutputTokens: Int
}

struct LabGenerationResult: Codable, Equatable, Sendable {
    let rawFinalContent: String
    let turn: ModelCoachingTurn?
    let inputTokens: Int
    let outputTokens: Int
    let promptMilliseconds: Double
    let firstTokenMilliseconds: Double
    let generationMilliseconds: Double
}
```

`LabSession.State` has exact cases `ready`, `thinking(requestID:positionRevision:)`, `result(requestID:positionRevision:turn:)`, and `error(requestID:positionRevision:message:)`. `submit(request:configuration:)` is `@MainActor`, starts inference in a child task, and applies a result only when both request ID and position revision still match.

Test that `LabSession`:

- immediately shows a stable `.thinking(requestID)` state without removing the interaction surface;
- cancels the old task on a newer revision;
- never displays a response whose request ID or position revision is stale;
- atomically replaces Thinking with validated result/error;
- records cold load separately from prompt and generation duration;
- remains responsive while a fake engine sleeps off the main actor;
- exports no prompt-internal reasoning, only final raw JSON and metrics.

- [ ] **Step 2: Run lab tests and record RED**

Create `project.yml` first with three targets: framework `CoachingModelLabCore` containing the shared contract/validator plus `Sources/Core`, app `CoachingModelLab` containing `Sources/App` and depending on the core plus the ignored XCFramework, and unhosted unit target `CoachingModelLabTests` depending only on the core. Generate the standalone project and run only `CoachingModelLabTests` on the iPad simulator. Expected: compile failure because `LabSession` and engine types do not exist; this RED does not require llama.cpp to be present.

- [ ] **Step 3: Implement pinned runtime preparation**

`prepare_llama_runtime.sh` verifies or clones `https://github.com/ggml-org/llama.cpp.git` at tag `b10516`, checks the resolved SHA, runs official `build-xcframework.sh`, and builds the Mac `llama-server`. Copy outputs to:

```text
.coaching-eval/runtime/b10516/llama.xcframework
.coaching-eval/runtime/b10516/bin/llama-server
.coaching-eval/runtime/b10516/source-manifest.json
```

Do not edit or patch the pinned checkout. Fail when CMake is older than 3.28 or the framework lacks an `ios-arm64` slice.

- [ ] **Step 4: Implement the minimal attributed Swift adapter**

Base tokenization/context/sampling code on `examples/llama.swiftui/llama.cpp.swift/LibLlama.swift` from the pinned tag, preserve its license attribution in the file header, and narrow it to:

```swift
actor LlamaInferenceEngine: LabInferenceEngine {
    func load(modelURL: URL, contextTokens: UInt32) throws
    func generate(
        request: ModelCoachingRequest,
        configuration: LabGenerationConfiguration
    ) async throws -> LabGenerationResult
    func cancelCurrentGeneration()
    func unload()
}
```

Use the model's embedded chat template, the exact bundled `tutor-v1.md` system/user payload used on Mac, fixed seed/settings, a 256-token output cap, and cooperative cancellation between generated tokens. `prepare_device_lab.py` copies the prompt, schema, and selected corpus requests into ignored lab inputs. Parse only the final JSON object and run the shared `ModelCoachingTurnValidator` in the lab; record unconstrained-output parse failures rather than silently inventing a turn.

- [ ] **Step 5: Implement the stable lab UI and recorder**

The lab has case/model/mode pickers, Run/Cancel/Next Revision controls, a continuously tappable board-sized interaction placeholder, and one coaching panel with states `ready`, `thinking`, `result`, and `error`. Thinking copy is exactly `Thinking…`; it does not expose tokens. Show metrics outside the child-facing panel.

Record model bytes, OS/device, thermal state before/after, load milliseconds, prompt milliseconds, first-token milliseconds, generation milliseconds, input/output tokens, tokens/second, cancellation result, validation result, and whether an OS memory warning occurred. Store JSONL in Documents and expose a Share button.

- [ ] **Step 6: Implement deterministic project/model preparation**

`Tools/CoachingModelLab/project.yml` points at the ignored XCFramework and includes the shared contract and validator sources plus lab sources; it is not referenced by root `project.yml`. `prepare_device_lab.py --model <id> --corpus <path>` verifies artifact hashes, copies only the chosen model metadata, prompt, schema, and requested corpus cases into `.coaching-eval/device-lab-inputs/`, and runs XcodeGen. `install_device_model.py` uses `xcrun devicectl` to install the signed app and copy the verified GGUF to `Documents/Models/` in bundle `org.jasoncrawford.coaching-model-lab`, then reads back file metadata.

- [ ] **Step 7: Run fake lifecycle, simulator build, and root non-contamination gates**

Run:

```bash
python3 -m unittest Tools.CoachingEval.tests.test_prepare_device_lab \
  Tools.CoachingEval.tests.test_install_device_model -v
xcodegen generate --spec Tools/CoachingModelLab/project.yml
xcodebuild test -project Tools/CoachingModelLab/CoachingModelLab.xcodeproj \
  -scheme CoachingModelLabTests -destination 'platform=iOS Simulator,name=iPad (A16)'
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
rg -n 'llama|gguf|CoachingModelLab' project.yml ChessTutor
```

Expected: lab and root tests pass, and the last `rg` has no shipping-target model/runtime references.

- [ ] **Step 8: Commit Task 6**

```bash
git add Tools/CoachingModelLab Tools/CoachingEval
git commit -m "feat: add standalone coaching model lab"
```

---

### Task 7: Physical ninth-generation-iPad measurements and final recommendation

**Files:**
- Modify: `docs/reports/2026-08-28-local-model-coaching-evaluation.md`
- Create ignored evidence under: `.coaching-eval/device-runs/`
- Modify only if measurements expose lab defects: `Tools/CoachingModelLab/` and `Tools/CoachingEval/`

**Interfaces:**
- Consumes: Mac finalists, exact GGUF bytes, device lab, short/long corpus cases, and physical iPad connection.
- Produces: raw device evidence, bounded UAT notes, smallest viable model decision, routing recommendation, and follow-up production scope.

- [ ] **Step 1: Identify and verify the physical target**

Use `xcrun devicectl list devices` and record UDID privately, marketed model, architecture, iPadOS version, available storage, and battery/thermal starting state. Reject simulators and any non-A13 device for the primary result. Clear storage only with the user's explicit approval and record the before/after free space.

- [ ] **Step 2: Install each finalist with the exact Mac-tested bytes**

Verify local SHA-256 against the Mac run manifest, prepare/sign/install the standalone lab, copy the model, and verify device-side byte size. Test one model at a time if storage cannot hold both; uninstalling a lab/model is allowed only after its results and exported metrics are safely copied to the Mac.

- [ ] **Step 3: Run the fixed device benchmark matrix**

For each finalist run:

```text
cold launch + cold first request: 3 repetitions
warm short-history visible cases: 10 requests
warm long-history visible cases: 10 requests
hidden stress cases: 1 pass
cancellation at 250 ms, 1 s, and after first token: 3 each
rapid supersession across three revisions: 5 repetitions
continuous interaction taps during inference: 30 seconds
repeated warm inference: 20 requests or until thermal serious/critical
```

Use identical generation settings to Mac. Let the device cool to nominal between candidate cold runs. Never hide OS termination, memory warning, invalid JSON, or slow outlier.

- [ ] **Step 4: UAT the product-facing behavior at Large and Accessibility Extra Large**

For at least first move, threatened piece, learner moving ahead, benign reply, move replacement, check, and mate cases, inspect:

- stable board/interaction surface during Thinking;
- no stale result after replacement/cancellation;
- one coherent turn with no mixed stages;
- exact permitted actions and focus references;
- readable compact copy and reachable controls in tall and wide compositions;
- no chain-of-thought or partial JSON visible.

Save screenshots/video and accessibility hierarchy under ignored device-run artifacts. Restore the device's content size after testing.

- [ ] **Step 5: Export and verify device evidence**

Copy `metrics.jsonl` and UAT artifacts to `.coaching-eval/device-runs/<model>/<timestamp>/`. Verify row counts against the benchmark matrix, correlate every result to request/model hashes, and calculate cold/warm p50/p90/p99 latency, prompt and generation throughput, cancellation delay, invalid-turn rate, memory warnings, thermal progression, and observed battery change.

- [ ] **Step 6: Make the explicit feasibility decision**

Combine Mac tutoring quality and device performance without collapsing them into one numeric score:

- choose **local-first** only if the smallest viable model is both broadly usable and acceptable as the default wait/cost on A13;
- choose **online-first with local offline coaching** if a local finalist is useful but materially weaker or slower than the online reference;
- choose **online-only** if every local candidate has a systematic severe tutoring failure class, unacceptable device behavior, or cannot run reliably.

Name the exact model, quantization, bytes, hash, runtime tag, prompt version, and evidence for the recommendation. State the alternative considered and why it lost.

- [ ] **Step 7: Write the production follow-up boundary**

If positive, scope a separate future design around `CoachingRequestBuilder -> CoachingProvider -> validator -> board-native presentation`, model download/storage, online credential server if applicable, offline routing, privacy, telemetry, and migration from deterministic coaching. Do not implement any of it in this spike. If negative, scope only the stateless online provider/server design.

- [ ] **Step 8: Run final repository verification**

Run:

```bash
python3 -m unittest discover -s Tools/CoachingEval/tests -v
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
xcodebuild build -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
git diff --check
git status --short
```

Confirm no model, raw output, credential, generated lab project, XCFramework, or device identifier is tracked with:

```bash
git ls-files | rg '\.(gguf|xcresult)$|\.coaching-eval|HF_TOKEN|REFERENCE_API_KEY|CoachingModelLab\.xcodeproj'
```

Expected: tests/build pass, diff check is clean, the only pre-commit status entry is the intended report, and the artifact/secret scan emits no matches.

- [ ] **Step 9: Commit the final report**

```bash
git add docs/reports/2026-08-28-local-model-coaching-evaluation.md
git commit -m "docs: conclude local coaching model evaluation"
git status --short
```

Expected after commit: `git status --short` emits no output.

---

## Definition of done

- The 52-case corpus is produced through real app chess/evidence code and has a frozen 41/11 visible/hidden split.
- Request JSON contains mechanical context and current/full histories but no deterministic coaching policy answer.
- Every model turn is schema-, identity-, reference-, action-, and copy-bounds validated.
- All available candidates have exact artifact/license/hash records or a specific documented access failure.
- Mac results include repeated runs, hidden-set evaluation, blinded multidimensional human scores, severe-error taxonomy, raw examples, and optional online-reference status.
- The strongest one or two candidates are measured on the physical A13 iPad using the exact Mac-tested bytes, unless no candidate clears the Mac quality bar.
- Device evidence includes cold/warm performance, long histories, cancellation, supersession, responsiveness, memory/thermal behavior, and bounded UI UAT.
- The shipping ChessTutor scheme remains model-free and behaviorally unchanged.
- The final report makes one of the three approved routing recommendations and names the smallest viable artifact or concludes that none is viable.

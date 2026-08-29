# Compact Markdown Coaching Evaluation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-run the local coaching-model evaluation with a deterministic, evidence-preserving Markdown context that fits an 8,192-token window and retains strict structured output.

**Architecture:** Keep `ModelCoachingRequest` as the complete authoritative evidence source. Add a pure Swift compiler that selects relevant facts, creates request-local aliases, records every omission, and renders `model-coaching-context.v1` Markdown; export that compilation with each existing corpus case. Update the Python harness to send the Markdown through the model's exact chat template, constrain the response grammar to request-local aliases, map valid aliases back to stable IDs, persist readable transcripts, and gate the full visible matrix behind a smaller pilot.

**Tech Stack:** Swift 6, XCTest, XcodeGen, Python 3 standard library, `unittest`, pinned llama.cpp `b10516`, GGUF, GBNF, JSONL, SHA-256, `xcodebuild`.

## Global Constraints

- Live ChessTutor coaching behavior remains unchanged and model-free.
- The complete request remains `model-coaching-request.v1`; the new model-facing context is `model-coaching-context.v1`; the new immutable prompt bundle is `tutor-v3`; the response remains `model-coaching-turn.v1`.
- The complete request builder remains policy-free. The compact compiler may rank and limit mechanically supported evidence but may not import deterministic coaching stage, preferred candidate, authored copy, or pedagogical verdict.
- FEN, legality, tactical facts, response reference membership, request identity, and stale-response handling remain code-authoritative.
- Never send exhaustive `legalMoves` or `immediateReplies` arrays to the model.
- Absence claims are emitted only from exhaustive mechanical analysis.
- At most two explanatory opponent replies may support one staged-move problem.
- Every complete source reference is either included/bound or omitted with a deterministic reason.
- Full game history is rendered once as SAN/PGN-style notation; full current-turn coaching history remains ordered and marks superseded requests.
- Target no more than 4,000 exact rendered input tokens; never truncate a section or string.
- Zero provider context-overflow outcomes and zero compiler-budget failures are required to advance from the visible pilot.
- Keep the existing three model files, pinned runtime, generation settings, eight visible few-shot scenarios, visible/hidden split, and blinded rubric.
- Persist exact model input and final trace-free response in human-readable transcripts; never persist private thinking traces.
- Hidden cases remain untouched unless a candidate is broadly usable without editing on the full visible matrix.
- Model weights, runtime builds, generated corpus, prompts, raw results, transcripts, and review artifacts remain ignored under `.coaching-eval/`.

## File and responsibility map

### Swift complete evidence and compact compiler

- `ChessTutor/Coaching/ModelEvaluation/ModelCoachingContracts.swift` — add mechanical move-consequence and explicit absence facts to the complete evidence contract.
- `ChessTutor/Coaching/ModelEvaluation/ModelCoachingRequestBuilder.swift` — populate consequences, legal-move evidence, and exhaustive absence facts from the real evaluator.
- `ChessTutor/Coaching/ModelEvaluation/ModelCoachingCompactContext.swift` — define the compact compilation, reference binding, and omission DTOs.
- `ChessTutor/Coaching/ModelEvaluation/ModelCoachingContextCompiler.swift` — deterministic relevance selection, source-reference accounting, aliases, and witness-reply bounds.
- `ChessTutor/Coaching/ModelEvaluation/ModelCoachingMarkdownRenderer.swift` — fixed-order, escaped Markdown rendering only.

### Swift tests and corpus export

- `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingContractsTests.swift` — updated complete-contract round trips.
- `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingRequestBuilderTests.swift` — move consequence and absence-fact pipeline tests.
- `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingCompactContextTests.swift` — compiler selection, aliases, accounting, and Markdown golden tests.
- `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingEvaluationCorpus.swift` — attach one compiled `tutor-v3` context to every existing semantic case.
- `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingEvaluationCorpusTests.swift` — exhaustive 52-case compact-context coherence and anti-smuggling checks.
- `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingCorpusExportTests.swift` — version-2 deterministic export and manifest hashes.
- `ChessTutor.xcodeproj/project.pbxproj` — regenerated source/test membership.

### Python prompt, runtime, and evaluation

- `Tools/CoachingEval/prompts/tutor-v3.md` — compact-context tutoring and output policy.
- `Tools/CoachingEval/prompts/examples-v3.json` — the same eight visible scenarios, with Markdown user inputs and alias-based assistant turns.
- `Tools/CoachingEval/compact_context.py` — exported-context validation, alias mapping, stable-ID restoration, and accounting checks.
- `Tools/CoachingEval/coaching_grammar.py` — request-specific alias alternatives in the strict grammar.
- `Tools/CoachingEval/llama_server.py` — render a text user message once, tokenize it exactly, then generate from the same rendered prompt.
- `Tools/CoachingEval/run_eval.py` — `tutor-v3` cases, 4,000-token gate, compact validation/mapping, and transcript metadata.
- `Tools/CoachingEval/render_transcript.py` — exact readable model input/response/validation artifact.
- `Tools/CoachingEval/pilots/compact-markdown-v1.json` — fixed visible pilot case IDs.
- `Tools/CoachingEval/render_review.py` — use mapped stable turns and preserve current blinded packet contract.
- `Tools/CoachingEval/summarize_eval.py` — compact-context budget and alias-validity metrics.
- `Tools/CoachingEval/tests/test_compact_context.py` — Python parity and alias mapping.
- `Tools/CoachingEval/tests/test_coaching_grammar.py` — dynamic alias grammar.
- `Tools/CoachingEval/tests/test_llama_server.py` — exact render/tokenize/generate path.
- `Tools/CoachingEval/tests/test_run_eval.py` — budget, transcript, repair, and manifest behavior.
- `Tools/CoachingEval/tests/test_render_transcript.py` — readable artifact and trace redaction.
- `Tools/CoachingEval/tests/test_render_review.py` and `test_summarize_eval.py` — mapped-review and new aggregation fields.
- `Tools/CoachingEval/README.md` — exact export, pilot, full-run, transcript, scoring, and cleanup commands.
- `docs/reports/2026-08-29-compact-markdown-coaching-evaluation.md` — committed result and advancement decision.

---

### Task 1: Add complete mechanical evidence needed for compact summaries

**Files:**
- Modify: `ChessTutor/Coaching/ModelEvaluation/ModelCoachingContracts.swift`
- Modify: `ChessTutor/Coaching/ModelEvaluation/ModelCoachingRequestBuilder.swift`
- Modify: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingContractsTests.swift`
- Modify: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingRequestBuilderTests.swift`

**Interfaces:**
- Consumes: existing `MaterialTacticalEvaluator.evaluate(_:)`, `CoachingMoveAssessment.opponentIssues`, `ModelCoachingMoveReference`, and `ModelCoachingReplyReference`.
- Produces: `ModelCoachingMoveConsequence`, `ModelCoachingMoveIssueKind`, new `ModelCoachingTacticalFactKind.noImmediateDanger` / `.noUsefulSafeCapture`, and legal-move IDs in `permittedReferences.evidence`.

- [ ] **Step 1: Write contract RED tests for the new exact DTO shape**

Add round-trip assertions using these declarations:

```swift
struct ModelCoachingMoveConsequence: Codable, Equatable, Sendable {
    let id: String
    let moveReference: String
    let isLegal: Bool
    let issueKinds: [ModelCoachingMoveIssueKind]
    let criticalReplyReferences: [String]
    let worstEstimatedLoss: Int
}

enum ModelCoachingMoveIssueKind: String, Codable, Equatable, Sendable {
    case materialLoss
    case allowsCheck
    case allowsMateInOne
}
```

Add `moveConsequences: [ModelCoachingMoveConsequence]` to `ModelCoachingEvidenceBundle` and add `noImmediateDanger` and `noUsefulSafeCapture` to `ModelCoachingTacticalFactKind`. Assert exact JSON keys and enum raw values.

- [ ] **Step 2: Run the contract test and record RED**

Run:

```bash
xcodegen generate
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingContractsTests
```

Expected: compile failure because `ModelCoachingMoveConsequence`, the new fact cases, and `moveConsequences` do not exist.

- [ ] **Step 3: Add real-pipeline RED tests for safe, unsafe, and absence evidence**

Use existing corpus snapshots rather than handcrafted evaluator results. Assert:

```swift
let safe = try XCTUnwrap(request(for: .t1PreferredKnight))
    .chessEvidence.moveConsequences.first { $0.moveReference == "move:g1-f3" }
XCTAssertTrue(safe.isLegal)
XCTAssertEqual([], safe.issueKinds)
XCTAssertEqual([], safe.criticalReplyReferences)

let unsafe = try XCTUnwrap(request(for: .t11UnsafeBishopFound))
    .chessEvidence.moveConsequences.first { $0.moveReference == "move:f1-a6" }
XCTAssertTrue(unsafe.isLegal)
XCTAssertFalse(unsafe.issueKinds.isEmpty)
XCTAssertLessThanOrEqual(unsafe.criticalReplyReferences.count, 2)

let opening = request(for: .t1Entry)
XCTAssertTrue(opening.chessEvidence.tacticalFacts.contains { $0.kind == .noImmediateDanger })
XCTAssertTrue(opening.chessEvidence.tacticalFacts.contains { $0.kind == .noUsefulSafeCapture })
XCTAssertTrue(opening.permittedReferences.evidence.contains("move:g1-f3"))
```

Also assert every consequence references an existing move, every critical reply belongs to that move, and the arrays are sorted deterministically.

- [ ] **Step 4: Run the builder test and record RED**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingRequestBuilderTests
```

Expected: compile failures for the new evidence fields.

- [ ] **Step 5: Implement the minimal complete-evidence extension**

In `ModelCoachingRequestBuilder`, derive one consequence for every allowed learner move. Translate only `.reviseMove` opponent issues into issue kinds. Resolve each issue's `reply` to its existing `reply:<move>-><reply>` ID, sort by issue kind then reply ID, and keep at most the first two distinct critical replies. `worstEstimatedLoss` is the maximum positive `netGainForOpponent` among the move's opponent activities, or zero.

Add explicit absence facts only when the corresponding exhaustive evaluator collection is empty:

```swift
if evaluation.dangerProblems.isEmpty {
    facts.append(ModelCoachingTacticalFact(
        id: "fact:no-immediate-danger",
        kind: .noImmediateDanger,
        subjectReferences: [],
        integerValue: nil
    ))
}
if !evaluation.learnerCaptureEstimates.contains(where: { $0.netGainForMover >= 1 }) {
    facts.append(ModelCoachingTacticalFact(
        id: "fact:no-useful-safe-capture",
        kind: .noUsefulSafeCapture,
        subjectReferences: [],
        integerValue: nil
    ))
}
```

Include legal move IDs alongside replies and facts in `permittedReferences.evidence`.

- [ ] **Step 6: Run focused and proportional suites**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingContractsTests \
  -only-testing:ChessTutorTests/ModelCoachingRequestBuilderTests \
  -only-testing:ChessTutorTests/ModelCoachingEvaluationCorpusTests \
  -only-testing:ChessTutorTests/ModelCoachingTurnValidatorTests
git diff --check
```

Expected: all selected tests pass with zero skipped/expected failures; diff check emits no output.

- [ ] **Step 7: Commit Task 1**

```bash
git add ChessTutor/Coaching/ModelEvaluation/ModelCoachingContracts.swift \
  ChessTutor/Coaching/ModelEvaluation/ModelCoachingRequestBuilder.swift \
  ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingContractsTests.swift \
  ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingRequestBuilderTests.swift
git commit -m "feat: expose compact coaching evidence"
```

---

### Task 2: Compile and render the compact Markdown context

**Files:**
- Create: `ChessTutor/Coaching/ModelEvaluation/ModelCoachingCompactContext.swift`
- Create: `ChessTutor/Coaching/ModelEvaluation/ModelCoachingContextCompiler.swift`
- Create: `ChessTutor/Coaching/ModelEvaluation/ModelCoachingMarkdownRenderer.swift`
- Create: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingCompactContextTests.swift`
- Regenerate: `ChessTutor.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `ModelCoachingRequest` with the Task 1 evidence extension.
- Produces: `ModelCoachingContextCompiler.compile(_:, promptVersion:) throws -> ModelCoachingContextCompilation` and `ModelCoachingMarkdownRenderer.render(_ document: ModelCoachingContextDocument) -> String`.

- [ ] **Step 1: Write compilation-contract and accounting RED tests**

Define the exact exported DTOs in tests:

```swift
struct ModelCoachingContextCompilation: Codable, Equatable, Sendable {
    let schemaVersion: String
    let promptVersion: String
    let requestID: String
    let positionRevision: Int
    let markdown: String
    let referenceBindings: [ModelCoachingReferenceBinding]
    let omissions: [ModelCoachingReferenceOmission]
}

struct ModelCoachingContextDocument: Equatable, Sendable {
    let metadataLines: [String]
    let sections: [ModelCoachingMarkdownSection]
}

struct ModelCoachingMarkdownSection: Equatable, Sendable {
    let heading: String
    let lines: [String]
}

struct ModelCoachingReferenceBinding: Codable, Equatable, Sendable {
    let alias: String
    let stableID: String
    let category: ModelCoachingSourceReferenceCategory
    let label: String
}

struct ModelCoachingReferenceOmission: Codable, Equatable, Sendable {
    let stableID: String
    let category: ModelCoachingSourceReferenceCategory
    let reason: ModelCoachingOmissionReason
}

enum ModelCoachingSourceReferenceCategory: String, Codable, Sendable {
    case action, boardTask, piece, move, relationship, reply, tacticalFact
}

enum ModelCoachingOmissionReason: String, Codable, Sendable {
    case redundantReply
    case lowerPriorityCandidate
    case unrelatedPiece
    case unrelatedRelationship
    case representedByCompleteSummary
}
```

Assert `schemaVersion == "model-coaching-context.v1"`, `promptVersion == "tutor-v3"`, deterministic binding order, unique aliases/stable IDs, and this exact accounting invariant:

```swift
XCTAssertEqual(
    Set(allSourceReferences(in: request)),
    Set(compilation.referenceBindings.map(\.stableID))
        .union(compilation.omissions.map(\.stableID))
)
XCTAssertTrue(
    Set(compilation.referenceBindings.map(\.stableID))
        .isDisjoint(with: compilation.omissions.map(\.stableID))
)
```

- [ ] **Step 2: Write behavioral RED tests for the approved selection policy**

Cover these real corpus cases:

- `t1Entry`: Markdown says danger and useful-safe-capture scans are complete and absent; includes bounded knight/center-pawn candidates; contains no `immediateReplies` or raw JSON property names.
- `t3Entry`: includes the endangered knight, attacker relationship, danger fact, and an identify-piece task.
- `t7NoSafeCapture`: latest staged `c4-d3` move outranks the older no-capture history; obsolete capture-step references are omitted.
- `t11UnsafeBishopFound`: staged `f1-a6` assessment is unsafe and contains one or two critical replies, never the full reply list.
- `t11Safe`: replacement `g1-f3` is authoritative; replaced `h2-h4` evidence is omitted as lower priority.
- `t12UnsupportedEntry`: full current-turn history retains open/close/superseded/reopen order; game position appears once.

Assert Markdown section order by comparing substring offsets for `# Current situation`, `## Latest action`, `## History`, `## Complete tactical summary`, optional `## Staged move`, optional `## Selected move ideas`, and `## Available response references`.

- [ ] **Step 3: Run the new test class and record RED**

Run:

```bash
xcodegen generate
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingCompactContextTests
```

Expected: compile failure because the compiler, DTOs, and renderer do not exist.

- [ ] **Step 4: Implement deterministic aliases and complete source accounting**

The compiler first produces a `ModelCoachingContextDocument`, bindings, and omissions; the renderer joins the typed document into Markdown, and `compile` returns the rendered Markdown with the provenance arrays. Generate aliases with category prefixes and collision suffixes:

```text
action:looksSafe                         -> action-looks-safe
task:stageMove                           -> task-stage-move
piece:white:bishop:a6                    -> piece-white-bishop-a6
move:f1-a6                               -> move-f1-a6
relationship:attack:...                  -> relationship-attack-1
reply:move:f1-a6->move:b7-b6             -> reply-b7-b6
fact:danger-loss:...                     -> fact-danger-1
```

Normalize only ASCII letters, digits, and hyphens; append `-2`, `-3`, and so on after stable-ID sorting when aliases collide. Bind every action and board task. Bind only pieces, moves, relationships, replies, and facts selected for Markdown. Record every other source ID exactly once as an omission.

- [ ] **Step 5: Implement the fixed relevance policy**

Use this priority order:

1. check/checkmate/stalemate;
2. tentative move and its consequence;
3. latest-event references;
4. danger facts and their pieces/relationships;
5. profitable captures (`exchangeGain >= 1`) and mate-in-one facts;
6. up to three wake candidates;
7. relationships among already included pieces.

Wake candidates are mechanically selected in this order, then by move ID:

1. castling;
2. knight or bishop leaving its original square;
3. a pawn from files `d` or `e` moving toward ranks 4/5;
4. any legal move by the currently selected piece.

Do not attach a teaching conclusion to those moves. Include at most three candidates and omit the rest as `lowerPriorityCandidate`.

For a staged consequence with issues, include at most its two stored critical replies. For a staged consequence without issues, render the authoritative sentence `No immediate tactical refutation was found.` without reply enumeration.

- [ ] **Step 6: Implement fixed-order Markdown rendering and escaping**

Escape backticks in imported summaries, replace control characters with spaces, collapse internal whitespace, and preserve chess punctuation. Use fenced code only for FEN and never embed raw JSON. The first lines are exactly:

```markdown
# Chess coaching context

- Schema: `model-coaching-context.v1`
- Prompt: `tutor-v3`
- Request: `corpus:t1Entry`
- Position revision: 1
```

Complete/selected labels must be literal and stable. Do not use deterministic tutor response strings.

- [ ] **Step 7: Run focused, corpus-wide, and diff checks**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingCompactContextTests \
  -only-testing:ChessTutorTests/ModelCoachingRequestBuilderTests \
  -only-testing:ChessTutorTests/ModelCoachingEvaluationCorpusTests
git diff --check
```

Expected: all tests pass; every one of the 52 cases compiles deterministically; no diff errors.

- [ ] **Step 8: Commit Task 2**

```bash
git add ChessTutor/Coaching/ModelEvaluation/ModelCoachingCompactContext.swift \
  ChessTutor/Coaching/ModelEvaluation/ModelCoachingContextCompiler.swift \
  ChessTutor/Coaching/ModelEvaluation/ModelCoachingMarkdownRenderer.swift \
  ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingCompactContextTests.swift \
  ChessTutor.xcodeproj/project.pbxproj
git commit -m "feat: compile compact coaching context"
```

---

### Task 3: Export the versioned compact corpus

**Files:**
- Modify: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingEvaluationCorpus.swift`
- Modify: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingEvaluationCorpusTests.swift`
- Modify: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingCorpusExportTests.swift`

**Interfaces:**
- Consumes: `ModelCoachingContextCompiler.compile(_:promptVersion:)` from Task 2.
- Produces: `ModelCoachingEvaluationCase.compactContext`, `model-coaching-evaluation-case.v2`, and `model-coaching-corpus-manifest.v2` exports.

- [ ] **Step 1: Write version-2 corpus RED tests**

Extend the evaluation case:

```swift
struct ModelCoachingEvaluationCase: Codable, Equatable, Sendable {
    let id: String
    let split: ModelCoachingCorpusSplit
    let request: ModelCoachingRequest
    let compactContext: ModelCoachingContextCompilation
    let oracle: ModelCoachingSemanticOracle
}
```

Assert every case has matching request ID/revision, context schema `model-coaching-context.v1`, prompt `tutor-v3`, nonempty Markdown, nonempty response bindings, and complete accounting. Assert exactly 52 cases / 41 visible / 11 hidden in the same IDs and order as v1.

- [ ] **Step 2: Run corpus tests and record RED**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingEvaluationCorpusTests \
  -only-testing:ChessTutorTests/ModelCoachingCorpusExportTests
```

Expected: compile failures because `compactContext` and the v2 manifest fields do not exist.

- [ ] **Step 3: Attach compilation at the single corpus build boundary**

In the corpus's central `build(...)` helper, build the unchanged complete request first, then compile it once with `promptVersion: "tutor-v3"`. Do not build the corpus twice for visible and hidden projections.

Update the manifest to include:

```swift
schemaVersion: "model-coaching-corpus-manifest.v2"
corpusSchemaVersion: "model-coaching-evaluation-case.v2"
requestSchemaVersion: "model-coaching-request.v1"
compactContextSchemaVersion: "model-coaching-context.v1"
compactPromptVersion: "tutor-v3"
```

- [ ] **Step 4: Add anti-drift and anti-smuggling assertions**

For all 52 cases, assert:

- compiled Markdown contains the exact FEN and latest-event kind;
- every alias referenced by Markdown has one binding;
- Markdown does not contain `CoachingStage`, `CoachingPresentation`, golden expected copy, oracle success criteria, or severe-failure criteria;
- no hidden case ID appears in the visible JSONL;
- the complete request SHA changes only when complete evidence changes; compact Markdown and binding hashes are independently reproducible.

- [ ] **Step 5: Export twice and verify byte identity**

Run the existing opt-in exporter twice with different empty directories:

```bash
COACHING_EVAL_OUTPUT_DIR=.coaching-eval/corpus/v2-export-a \
COACHING_EVAL_SOURCE_SHA=$(git rev-parse HEAD) \
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingCorpusExportTests/testCorpusArtifactsAreDeterministicAndOptionallyWriteConfiguredOutput

COACHING_EVAL_OUTPUT_DIR=.coaching-eval/corpus/v2-export-b \
COACHING_EVAL_SOURCE_SHA=$(git rev-parse HEAD) \
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingCorpusExportTests/testCorpusArtifactsAreDeterministicAndOptionallyWriteConfiguredOutput

diff -r .coaching-eval/corpus/v2-export-a .coaching-eval/corpus/v2-export-b
```

Expected: both tests pass; `diff` emits no output; manifests report 41 visible / 11 hidden and matching SHA-256 values. Promote one verified export using:

```bash
test ! -e .coaching-eval/corpus/v2
mv .coaching-eval/corpus/v2-export-a .coaching-eval/corpus/v2
```

Retain `v2-export-b` until the final artifact audit, then remove only that verified duplicate.

- [ ] **Step 6: Commit Task 3**

```bash
git add ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingEvaluationCorpus.swift \
  ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingEvaluationCorpusTests.swift \
  ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingCorpusExportTests.swift
git commit -m "test: export compact coaching corpus"
```

---

### Task 4: Add `tutor-v3`, alias restoration, and request-specific grammar

**Files:**
- Create: `Tools/CoachingEval/prompts/tutor-v3.md`
- Create: `Tools/CoachingEval/prompts/examples-v3.json`
- Create: `Tools/CoachingEval/compact_context.py`
- Create: `Tools/CoachingEval/tests/test_compact_context.py`
- Modify: `Tools/CoachingEval/example_validation.py`
- Modify: `Tools/CoachingEval/coaching_grammar.py`
- Modify: `Tools/CoachingEval/tests/test_coaching_grammar.py`
- Modify: `Tools/CoachingEval/tests/test_run_eval.py`

**Interfaces:**
- Consumes: exported `compactContext` plus unchanged complete request.
- Produces: `compact_context.validate_compilation(case)`, `compact_context.restore_stable_turn(turn, compilation)`, and `coaching_grammar.strict_grammar(schema, *, enable_thinking, request_id, permitted_aliases) -> str`.

- [ ] **Step 1: Write compact-context parity and alias-restoration RED tests**

Use a synthetic exported case with one alias in every response category. Assert:

```python
issues = compact_context.validate_compilation(case)
self.assertEqual([], issues)

stable = compact_context.restore_stable_turn(alias_turn, case["compactContext"])
self.assertEqual("action:looksSafe", stable["actionReferences"][0])
self.assertEqual("task:stageMove", stable["boardTaskReference"])
self.assertEqual("piece:white:bishop:a6", stable["boardFocusReferences"][0])
self.assertEqual("relationship:attack:piece:black:pawn:b7->piece:white:bishop:a6",
                 stable["relationshipReferences"][0])
self.assertEqual("reply:move:f1-a6->move:b7-b6",
                 stable["supportingEvidenceReferences"][0])
```

Reject unknown aliases, duplicate bindings, category mismatches, incomplete accounting, request/revision mismatch, and Markdown aliases without bindings.

- [ ] **Step 2: Write request-specific grammar RED tests**

Call:

```python
grammar = coaching_grammar.strict_grammar(
    schema,
    enable_thinking=False,
    request_id="corpus:t11UnsafeBishopFound",
    permitted_aliases={
        "actions": ["action-close", "action-try-another"],
        "boardTasks": ["task-stage-move"],
        "boardFocus": ["piece-white-bishop-a6"],
        "relationships": ["relationship-attack-1"],
        "evidence": ["reply-b7-b6", "fact-danger-1"],
    },
)
```

Assert the grammar fixes `requestID` to exactly `corpus:t11UnsafeBishopFound`, contains quoted alternatives for exactly those aliases, permits empty action/focus/relationship arrays, requires nonempty evidence, permits `null` board task, and contains no stable IDs absent from the compact context.

- [ ] **Step 3: Run focused Python tests and record RED**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
  Tools.CoachingEval.tests.test_compact_context \
  Tools.CoachingEval.tests.test_coaching_grammar -v
```

Expected: import/signature failures for the new module and `permitted_aliases` parameter.

- [ ] **Step 4: Implement strict compilation validation and stable-ID restoration**

Keep `compact_context.py` standard-library-only. Restoration must preserve all copy and non-reference fields, replace only alias-bearing fields, and return both the restored turn and deterministic mapping issues. Never guess a category or accept an alias from another category.

- [ ] **Step 5: Parameterize the pinned GBNF without weakening copy limits**

Generate the request-ID literal and alias alternatives using a JSON-string quoting helper. Use an impossible sentinel rule when a category has no permitted values, so the only valid representation is an empty array or `null`. Keep the pinned schema SHA refusal, property order, word bounds, one-to-three action limit, required evidence, and bounded-thinking grammar unchanged.

- [ ] **Step 6: Author `tutor-v3` and the same eight examples in Markdown form**

The system prompt must state:

- `complete` conclusions are authoritative;
- `selected` candidates are non-exhaustive suggestions;
- omitted information must not be invented;
- the latest action wins;
- Safe/Take/Wake is optional;
- return request-local aliases exactly;
- return one `model-coaching-turn.v1` JSON object and no prose/trace.

Each `examples-v3.json` entry has exactly:

```json
{
  "sourceCaseID": "t1Entry",
  "contextMarkdown": "# Chess coaching context\n...",
  "turn": {"schemaVersion": "model-coaching-turn.v1", "requestID": "corpus:t1Entry"}
}
```

Fill every assistant turn with all eight required fields in grammar order plus useful optional fields. Reuse the same eight source case IDs and semantic answers as v2, translated only to local aliases.

- [ ] **Step 7: Validate examples mechanically**

Update `_example_messages` so `tutor-v3` user messages use exact `contextMarkdown`, while v1/v2 remain readable for preserved tests. Validate every example's aliases against bindings supplied in its Markdown fixture, all word limits, source-case visibility, and exact assistant key order.

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
  Tools.CoachingEval.tests.test_compact_context \
  Tools.CoachingEval.tests.test_coaching_grammar \
  Tools.CoachingEval.tests.test_run_eval -v
```

Expected: all selected tests pass with zero errors/skips.

- [ ] **Step 8: Commit Task 4**

```bash
git add Tools/CoachingEval/prompts/tutor-v3.md \
  Tools/CoachingEval/prompts/examples-v3.json \
  Tools/CoachingEval/compact_context.py \
  Tools/CoachingEval/coaching_grammar.py \
  Tools/CoachingEval/example_validation.py \
  Tools/CoachingEval/tests/test_compact_context.py \
  Tools/CoachingEval/tests/test_coaching_grammar.py \
  Tools/CoachingEval/tests/test_run_eval.py
git commit -m "feat: add compact coaching prompt contract"
```

---

### Task 5: Render once, enforce the token budget, and persist readable transcripts

**Files:**
- Modify: `Tools/CoachingEval/llama_server.py`
- Modify: `Tools/CoachingEval/run_eval.py`
- Create: `Tools/CoachingEval/render_transcript.py`
- Modify: `Tools/CoachingEval/tests/test_llama_server.py`
- Modify: `Tools/CoachingEval/tests/test_run_eval.py`
- Create: `Tools/CoachingEval/tests/test_render_transcript.py`
- Modify: `Tools/CoachingEval/render_review.py`
- Modify: `Tools/CoachingEval/tests/test_render_review.py`
- Modify: `Tools/CoachingEval/summarize_eval.py`
- Modify: `Tools/CoachingEval/tests/test_summarize_eval.py`

**Interfaces:**
- Consumes: `compactContext.markdown`, alias bindings, full request, and Task 4 grammar.
- Produces: `LlamaServer.render_prompt(...) -> str`, `LlamaServer.token_count(prompt) -> int`, `LlamaServer.complete_rendered(...)`, token-gated records, stable mapped turns, and per-record transcripts.

- [ ] **Step 1: Write HTTP lifecycle RED tests for text input and exact tokenization**

Use the existing fake localhost server to assert:

1. `/apply-template` receives system + eight example pairs + a final user message whose content is exact Markdown, not JSON encoding.
2. `/tokenize` receives the exact returned rendered prompt and returns an integer token count.
3. `/completion` receives that same prompt byte-for-byte plus the request-specific grammar.
4. Neither `/apply-template` nor `/tokenize` is repeated for the first attempt.

Expected API:

```python
prompt = client.render_prompt(
    system_prompt=system_prompt,
    user_content=context_markdown,
    enable_thinking=False,
    extra_messages=example_messages,
    timeout=30,
)
tokens = client.token_count(prompt, timeout=30)
response = client.complete_rendered(
    prompt=prompt,
    grammar=grammar,
    seed=1103,
    maximum_output_tokens=256,
    temperature=0.2,
    top_p=0.9,
    timeout=120,
)
```

- [ ] **Step 2: Write runner RED tests for budget failure and alias mapping**

Assert a 4,001-token fake response produces:

```json
{
  "generationStatus": "compilerBudgetExceeded",
  "renderedPromptTokens": 4001,
  "generationAttempted": false
}
```

with no completion call and no repair. Assert a 4,000-token prompt generates, restores aliases to stable IDs, validates the stable turn against the complete request, and records alias/stable turns separately.

- [ ] **Step 3: Write transcript RED tests**

Require this fixed section order:

```markdown
# Coaching evaluation transcript

## Identity and provenance
## Model input Markdown
## Exact rendered prompt
## Model response
## Alias turn
## Stable-ID turn
## Validation
## Evidence accounting
## Tokens and timing
```

Assert the transcript contains exact input/response text, readable JSON blocks, included/omitted tables, token counts, and no `<think>`, `reasoning_content`, provider body, or secret environment value.

- [ ] **Step 4: Run focused tests and record RED**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
  Tools.CoachingEval.tests.test_llama_server \
  Tools.CoachingEval.tests.test_run_eval \
  Tools.CoachingEval.tests.test_render_transcript -v
```

Expected: missing method/module and old JSON-request assertions fail.

- [ ] **Step 5: Implement render/tokenize/generate separation**

Keep the existing OpenAI-compatible reference client path intact. For local llama.cpp, construct messages once, call `/apply-template`, call `/tokenize` with `{"content": prompt, "add_special": false, "parse_special": true}`, and pass the exact prompt to `/completion`. Classify tokenization failures as `generationError`, never as context overflow.

- [ ] **Step 6: Update `EvaluationRunner` for compact cases**

For `tutor-v3`:

1. validate the compilation;
2. render the prompt;
3. measure exact prompt tokens;
4. stop at 4,001+ tokens with `compilerBudgetExceeded`;
5. build request-specific grammar;
6. generate and strip traces;
7. parse the alias turn;
8. restore stable IDs;
9. validate against the complete request;
10. allow one repair only for parse/shape failure;
11. re-render and re-tokenize the repair conversation, refusing the repair as `repairBudgetExceeded` if it exceeds 4,000 tokens.

Record SHA-256 and byte/token counts for original request, Markdown, every rendered attempt prompt, grammar, alias turn, and stable turn. Do not store complete rendered prompts inside `records.jsonl`; store their relative transcript path and SHA so the record stays bounded.

- [ ] **Step 7: Persist transcripts atomically with the run**

Change `_write_run` to write into a newly created temporary sibling directory, write records/manifests/transcripts, fsync/close files, then rename to the timestamped final run directory. Use filenames `transcripts/{caseID}--{mode}--{seed}.md`. Refuse collisions rather than overwrite.

- [ ] **Step 8: Preserve blinded review and add compact metrics**

`render_review` continues to expose the authoritative position, latest action, stable parsed turn, and oracle only; it must not expose model/context identities. `summarize_eval` adds:

- rendered prompt token min/p50/p90/max;
- count above 4,000;
- compiler-budget failures;
- provider context overflows;
- alias restoration failures;
- stable validator failures.

- [ ] **Step 9: Run the complete Python harness suite and fake E2E**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tools/CoachingEval/tests -v
COACHING_EVAL_ALLOW_FAKE=1 PYTHONDONTWRITEBYTECODE=1 \
python3 Tools/CoachingEval/run_eval.py local \
  --model fake-test-model \
  --split visible \
  --case t12UnsupportedEntry \
  --repetitions 1 \
  --mode off \
  --corpus .coaching-eval/corpus/v2/visible.jsonl \
  --prompt-version tutor-v3
```

Inspect the emitted transcript and assert its hashes against the run record. Expected: all tests pass; one fake record is valid; prompt <=4,000 tokens; transcript is readable and trace-free.

- [ ] **Step 10: Commit Task 5**

```bash
git add Tools/CoachingEval/llama_server.py \
  Tools/CoachingEval/run_eval.py \
  Tools/CoachingEval/render_transcript.py \
  Tools/CoachingEval/render_review.py \
  Tools/CoachingEval/summarize_eval.py \
  Tools/CoachingEval/tests/test_llama_server.py \
  Tools/CoachingEval/tests/test_run_eval.py \
  Tools/CoachingEval/tests/test_render_transcript.py \
  Tools/CoachingEval/tests/test_render_review.py \
  Tools/CoachingEval/tests/test_summarize_eval.py
git commit -m "feat: evaluate compact coaching prompts"
```

---

### Task 6: Run the visible pilot and apply the advancement gate

**Files:**
- Create: `Tools/CoachingEval/pilots/compact-markdown-v1.json`
- Modify: `Tools/CoachingEval/run_eval.py`
- Modify: `Tools/CoachingEval/tests/test_run_eval.py`
- Modify: `Tools/CoachingEval/README.md`
- Create: `docs/reports/2026-08-29-compact-markdown-coaching-evaluation.md`

**Interfaces:**
- Consumes: verified v2 visible corpus and the three already-downloaded candidate models.
- Produces: three immutable pilot run directories and one explicit `advance` / `stop` decision.

- [ ] **Step 1: Add the fixed pilot manifest and selection RED test**

The manifest contains exactly these visible IDs in this order:

```json
{
  "schemaVersion": "coaching-eval-pilot.v1",
  "id": "compact-markdown-v1",
  "caseIDs": [
    "t1Entry",
    "t3Entry",
    "t7NoSafeCapture",
    "t1PreferredKnight",
    "t11UnsafeBishopFound",
    "t11Safe",
    "t11BenignCaptureTap",
    "t12Block",
    "t9Hint",
    "t12UnsupportedEntry"
  ]
}
```

Add `--case-list` to `run_eval.py`. Reject missing, duplicate, hidden, or reordered IDs; preserve corpus order only when it matches the manifest order.

- [ ] **Step 2: Run the CLI test and record RED, then implement selection**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
  Tools.CoachingEval.tests.test_run_eval.RunEvalTests.test_case_list_requires_exact_visible_ids -v
```

Expected: parser/helper failure. Implement and rerun to green.

- [ ] **Step 3: Re-verify runtime, models, schema, prompt, and corpus before inference**

Run:

```bash
python3 Tools/CoachingEval/runtime_provenance.py verify \
  --runtime Tools/CoachingEval/runtime.json \
  --manifest .coaching-eval/runtime/b10516/runtime-manifest.json \
  --executable .coaching-eval/runtime/b10516/bin/llama-server
python3 Tools/CoachingEval/schema_compat.py check \
  --schema Tools/CoachingEval/coaching-turn.schema.json
python3 Tools/CoachingEval/model_store.py verify-all
```

Verify the corpus manifest source SHA, 41/11 split, Markdown/context hashes, and exact prompt/example hashes. Stop on any mismatch.

- [ ] **Step 4: Run a real 3-model x 2-mode contract smoke**

For each model and both modes, run `t12UnsupportedEntry`, one repetition, and verify: exact prompt <=4,000 tokens, local aliases only, JSON parses, aliases restore, stable validator passes, and transcript contains no trace. Persist a six-cell audit manifest under `.coaching-eval/analysis/compact-context-smoke-v1.json`.

- [ ] **Step 5: Run the 60-record pilot serially**

Run these three commands serially:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 Tools/CoachingEval/run_eval.py local \
  --model qwen3-0.6b-q4_0 \
  --split visible \
  --case-list Tools/CoachingEval/pilots/compact-markdown-v1.json \
  --repetitions 1 \
  --corpus .coaching-eval/corpus/v2/visible.jsonl \
  --prompt-version tutor-v3

PYTHONDONTWRITEBYTECODE=1 python3 Tools/CoachingEval/run_eval.py local \
  --model qwen3-1.7b-q4_k_m \
  --split visible \
  --case-list Tools/CoachingEval/pilots/compact-markdown-v1.json \
  --repetitions 1 \
  --corpus .coaching-eval/corpus/v2/visible.jsonl \
  --prompt-version tutor-v3

PYTHONDONTWRITEBYTECODE=1 python3 Tools/CoachingEval/run_eval.py local \
  --model smollm3-3b-q4_k_m \
  --split visible \
  --case-list Tools/CoachingEval/pilots/compact-markdown-v1.json \
  --repetitions 1 \
  --corpus .coaching-eval/corpus/v2/visible.jsonl \
  --prompt-version tutor-v3
```

Use the exact IDs `qwen3-0.6b-q4_0`, `qwen3-1.7b-q4_k_m`, and `smollm3-3b-q4_k_m`. Do not run models concurrently on Metal.

- [ ] **Step 6: Apply the objective pilot gate**

Advance only if all are true:

- all 60 prompts are <=4,000 exact tokens;
- zero compiler-budget and provider-context-overflow failures;
- zero unknown/incorrect-category aliases reach post-generation validation;
- no persisted trace marker exists in any run/transcript;
- at least one model has >=10 first-attempt valid stable turns among its 20 pilot records.

If the gate fails, stop model execution, write the negative result, skip Task 7 and Task 8 Step 2, then execute the remaining final-verification and reporting steps in Task 8. Do not tune `tutor-v3` against candidate outputs.

- [ ] **Step 7: Inspect and report the pilot without changing the prompt**

Read every valid pilot transcript and every validation-error category. Record prompt-token distributions, validity by model/mode, latency, and representative factual/pedagogical failures. Update the report with the immutable run paths and hashes.

- [ ] **Step 8: Commit pilot tooling and report checkpoint**

```bash
git add Tools/CoachingEval/pilots/compact-markdown-v1.json \
  Tools/CoachingEval/run_eval.py \
  Tools/CoachingEval/tests/test_run_eval.py \
  Tools/CoachingEval/README.md \
  docs/reports/2026-08-29-compact-markdown-coaching-evaluation.md
git commit -m "test: pilot compact coaching prompts"
```

---

### Task 7: Run the full visible matrix and independent blinded review

**Files:**
- Modify: `docs/reports/2026-08-29-compact-markdown-coaching-evaluation.md`
- Modify only if a methodology defect is proven before scoring: `Tools/CoachingEval/**`

**Interfaces:**
- Consumes: a passing Task 6 pilot with immutable `tutor-v3` and corpus v2.
- Produces: three 246-record final run directories, a 738-row blinded packet/rubric, aggregate metrics, and a zero/one/two-finalist decision.

- [ ] **Step 1: Freeze and hash the full-run inputs**

Record SHA-256 for runtime binary/source, all three GGUF files, corpus visible JSONL/manifest, `tutor-v3.md`, `examples-v3.json`, schema, dynamic-grammar source, compact compiler source files, and pilot gate summary. Do not edit them after the first full run starts.

- [ ] **Step 2: Run the three full visible matrices serially**

Run 41 visible cases x two modes x three seeds for each model, serially:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 Tools/CoachingEval/run_eval.py local \
  --model qwen3-0.6b-q4_0 \
  --split visible \
  --repetitions 3 \
  --corpus .coaching-eval/corpus/v2/visible.jsonl \
  --prompt-version tutor-v3

PYTHONDONTWRITEBYTECODE=1 python3 Tools/CoachingEval/run_eval.py local \
  --model qwen3-1.7b-q4_k_m \
  --split visible \
  --repetitions 3 \
  --corpus .coaching-eval/corpus/v2/visible.jsonl \
  --prompt-version tutor-v3

PYTHONDONTWRITEBYTECODE=1 python3 Tools/CoachingEval/run_eval.py local \
  --model smollm3-3b-q4_k_m \
  --split visible \
  --repetitions 3 \
  --corpus .coaching-eval/corpus/v2/visible.jsonl \
  --prompt-version tutor-v3
```

Verify each manifest contains 246 unique `(caseID, mode, seed)` records and no hidden case.

- [ ] **Step 3: Run mechanical and provenance audits before scoring**

Across all 738 records, verify:

- exact request/context/prompt/compiler/runtime/model hashes;
- 41 cases, two modes, three seeds per model;
- prompt token count <=4,000;
- zero provider context overflow;
- every alias turn maps deterministically or is explicitly invalid;
- stable parsed turns revalidate against the complete request;
- transcripts and records contain no thinking markers or provider bodies;
- off/bounded rendered prompt hashes differ for every paired case/seed.

If a methodology defect is found, preserve and mark all affected runs superseded before any rerun. Never silently replace artifacts.

- [ ] **Step 4: Create a new v5-only blinded packet**

Run `render_review.py` with exactly the three final run directories and a new empty output directory `.coaching-eval/reviews/combined-visible-v5-compact-final`. Verify 738 unique review IDs, packet/rubric hashes, identity scan, trace scan, and exact review-key pointers. Do not read the review key before scoring finishes.

- [ ] **Step 5: Obtain independent blinded scoring**

Dispatch a fresh scorer with access only to the approved scoring guidance, public packet, and blank rubric. Require all 738 rows in packet order and return only the completed rubric path, row count, and scoring assumptions. The implementation agent must remain blinded to the key while scoring is active.

- [ ] **Step 6: Unblind and reconcile every surprising classification**

After the completed rubric returns, validate all 738 packet/key/request pointers. Manually inspect every mechanically valid severe row and every mechanically invalid non-severe row against the complete request, compact context, model response, and oracle. Preserve the audit counts.

- [ ] **Step 7: Apply the visible qualification rule**

A model advances only if it is broadly usable without editing, which requires:

- zero context/compiler-budget failures;
- >=90% displayable stable turns;
- <=1% severe errors among displayable turns;
- >=80% of all 246 turns valid, non-severe, and scored >=4 on all six positive dimensions;
- no repeated latest-action or mixed-stage failure class;
- non-transport latency compatible with the existing Thinking presentation.

Do not advance a model merely because it ranks first.

- [ ] **Step 8: Update and commit the visible result**

Report v4-v5 changes in prompt tokens, overflow, validity, severe errors, six rubric means, and latency. Include direct links/paths to readable transcripts representing strong, weak, and invalid responses.

```bash
git add docs/reports/2026-08-29-compact-markdown-coaching-evaluation.md
git commit -m "docs: report compact coaching model quality"
```

---

### Task 8: Conditional hidden/device handoff and final verification

**Files:**
- Modify: `docs/reports/2026-08-29-compact-markdown-coaching-evaluation.md`
- Modify: `Tools/CoachingEval/README.md`
- Do not add shipping app integration files.

**Interfaces:**
- Consumes: Task 7's explicit finalist set.
- Produces: either a clean zero-finalist conclusion or a reviewed handoff to the existing hidden/device evaluation plan.

- [ ] **Step 1: Stop cleanly when there are zero finalists**

If no model qualifies, assert no hidden run directory exists, record `zero finalists; hidden and device evaluation not run`, and continue to final verification. Do not inspect hidden JSONL contents beyond manifest/hash/count checks already required by export tests.

- [ ] **Step 2: If a model qualifies, pause at the hidden-set authority boundary**

Before exposing hidden cases or building the standalone device lab, write the finalist IDs, visible evidence, estimated model storage, and expected device test duration into the report. Continue with Tasks 6-7 of `docs/superpowers/plans/2026-08-28-local-model-coaching-evaluation.md` only after this checkpoint is reviewed; use the v2 compact corpus and `tutor-v3`, not the superseded exhaustive prompt.

- [ ] **Step 3: Run final Swift verification**

Run:

```bash
xcodegen generate
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
xcodebuild build -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Extract exact passed/failed/skipped/expected-failure counts from the final `.xcresult`. Require zero failures and zero skips.

- [ ] **Step 4: Run final Python and artifact verification**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tools/CoachingEval/tests -v
python3 -m py_compile Tools/CoachingEval/*.py
git diff --check
git status --short
```

Re-verify runtime/model/corpus/prompt/schema hashes, review packet/key/rubric pointers, transcript hashes, trace scans, and hidden-run absence or authorized hidden results.

- [ ] **Step 5: Complete the report and commit final documentation**

The report must state separately:

- context construction outcome;
- grammar/alias validity;
- model chess and pedagogy quality;
- latency;
- finalist/hidden/device decision;
- comparison with the final v4 exhaustive-JSON baseline;
- exact test counts and known infrastructure warnings.

```bash
git add Tools/CoachingEval/README.md \
  docs/reports/2026-08-29-compact-markdown-coaching-evaluation.md
git commit -m "docs: conclude compact coaching evaluation"
```

- [ ] **Step 6: Request final review and confirm branch handoff**

Request an independent code/evidence review of the complete diff and ignored empirical manifests. Address all Critical/Important findings test-first, rerun proportional and full gates, then report the final commit SHA and clean worktree. Do not merge, push, or expose hidden results without the user's chosen branch-integration path.

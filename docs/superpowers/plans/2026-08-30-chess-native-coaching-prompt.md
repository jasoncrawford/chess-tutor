# Chess-Native Coaching Prompt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate eight compact tutor-v6 prompts that use chess-native context and semantic UI references instead of numbered aliases, without invoking model inference.

**Architecture:** Reuse the exhaustive rule-derived `ModelCoachingNeutralRequest` as the authoritative source, but add a separate v6 compiler that selects a minimal fixed fact scope based only on the latest interaction. Add a separate semantic response contract and strict validator, then export the existing eight production-history fixtures through v6 and package them with template rendering/tokenization only. Preserve all tutor-v5 code and evidence unchanged.

**Tech Stack:** Swift 6, XCTest, Foundation JSON decoding, existing chess model/`LegalMoveGenerator`, Python 3 `unittest`, pinned llama.cpp `/health`, `/apply-template`, and `/tokenize` endpoints.

## Global Constraints

- Do not invoke model completion, generation, scoring, hidden-set work, or inference.
- Preserve tutor-v5 sources, tests, compiler behavior, and artifacts unchanged.
- Use only deterministic game state, complete SAN history, current interaction, legal move facts, and UI capabilities.
- Do not render numbered piece, move, relationship, or action aliases in v6.
- Keep tentative moves separate from committed history.
- Child-facing messages must use ordinary language, not SAN/UCI/capture/check/castling notation; an isolated square such as `c3` is permitted when needed.
- Export exactly eight visible prompts, fail above 2,500 rendered tokens, and stop for user review.

---

### Task 1: Chess-native Markdown compiler

**Files:**
- Create: `ChessTutor/Coaching/ModelEvaluation/ModelCoachingChessNativeContracts.swift`
- Create: `ChessTutor/Coaching/ModelEvaluation/ModelCoachingChessNativeContextCompiler.swift`
- Create: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingChessNativeContextCompilerTests.swift`
- Regenerate: `ChessTutor.xcodeproj/project.pbxproj` with `xcodegen generate`

**Interfaces:**
- Consumes: `ModelCoachingNeutralRequest` produced by the existing neutral builder.
- Produces:

```swift
struct ModelCoachingChessNativeContextCompilation: Codable, Equatable, Sendable {
    let schemaVersion: String
    let promptVersion: String
    let requestID: String
    let positionRevision: Int
    let markdown: String
    let availableActions: [String]
    let availableMoveFocus: [ModelCoachingChessNativeMoveFocus]
}

struct ModelCoachingChessNativeMoveFocus: Codable, Equatable, Hashable, Sendable {
    let from: String
    let to: String
}

enum ModelCoachingChessNativeContextCompiler {
    static func compile(
        _ request: ModelCoachingNeutralRequest,
        promptVersion: String
    ) -> ModelCoachingChessNativeContextCompilation
}
```

- [ ] **Step 1: Write failing fixed-section and no-alias tests**

Require exact ordered headings `Position`, `Latest interaction`, `Relevant legal facts`, and `Available UI response`. Compile the production-history fixtures and reject regex matches for `relationship-[0-9]+`, `move-[0-9]+`, `piece-[0-9]+`, and `action-[0-9]+`.

- [ ] **Step 2: Run the compiler suite and verify RED**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingChessNativeContextCompilerTests
```

Expected: compile failure because the v6 contracts/compiler do not exist.

- [ ] **Step 3: Implement the minimal compiler**

Render:

- `Position`: side/status, FEN, complete `Moves:` SAN, separate tentative move;
- `Latest interaction`: only the latest event, plus the immediately prior staged move for `moveReplaced`;
- `Relevant legal facts`: check status always; selected-piece legal moves; tentative legality and opponent capture/check/mate replies; for `squareInspected`, only matching replies from the tapped piece;
- `Available UI response`: semantic action names and allowable move paths once; state that any board square may be focused.

Do not render global attack/defense relationships, global captures/checks/mates, downstream reply relationships, or repeated focus labels.

- [ ] **Step 4: Add exact interaction-scope tests**

Use the eight existing production-history fixtures. Assert examples 01/02/08 contain no move dump; 03 contains only selected-knight legal moves; 04/05/07 contain tentative legality and immediate forcing replies; 06 contains exactly `Qxe4+`, `Qxf2+`, and `Qxh2` once each and no downstream relationship prose. Assert complete history/FEN consistency and deterministic byte equality.

- [ ] **Step 5: Run Task 1 tests and commit**

Run the Step 2 command plus existing neutral builder/compiler suites. Expected: all pass with zero skips.

```bash
git add ChessTutor/Coaching/ModelEvaluation/ModelCoachingChessNativeContracts.swift \
  ChessTutor/Coaching/ModelEvaluation/ModelCoachingChessNativeContextCompiler.swift \
  ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingChessNativeContextCompilerTests.swift \
  ChessTutor.xcodeproj/project.pbxproj
git commit -m "feat: compile chess-native coaching context"
```

---

### Task 2: Tutor-v6 system prompt and semantic response validator

**Files:**
- Create: `Tools/CoachingEval/prompts/tutor-v6.md`
- Modify: `ChessTutor/Coaching/ModelEvaluation/ModelCoachingChessNativeContracts.swift`
- Create: `ChessTutor/Coaching/ModelEvaluation/ModelCoachingChessNativeTurnValidator.swift`
- Create: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingChessNativeTurnValidatorTests.swift`
- Create: `Tools/CoachingEval/tests/test_tutor_v6_prompt.py`
- Regenerate: `ChessTutor.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `ModelCoachingChessNativeContextCompilation`.
- Produces:

```swift
enum ModelCoachingChessNativeFocus: Codable, Equatable, Hashable, Sendable {
    case square(String)
    case move(from: String, to: String)
}

struct ModelCoachingChessNativeTurn: Codable, Equatable, Sendable {
    let message: String
    let actions: [String]
    let focus: [ModelCoachingChessNativeFocus]
}

enum ModelCoachingChessNativeTurnDecoder {
    static func decodeAndValidate(
        _ data: Data,
        compilation: ModelCoachingChessNativeContextCompilation
    ) throws -> ModelCoachingChessNativeTurn
}
```

- [ ] **Step 1: Write failing strict-decoder tests**

Cover valid square/move focus; malformed/non-object JSON; unknown outer and focus fields; unavailable actions; off-board squares; unavailable move paths; duplicates; message/action/focus bounds; and message rejection for `Nc3`, `Qxf2+`, `e2e4`, `O-O`, `x`, `+`, or `#` notation while allowing `Look at the knight on c3.`.

- [ ] **Step 2: Run validator tests and verify RED**

Run the selected XCTest. Expected: compile failure because the v6 turn/decoder does not exist.

- [ ] **Step 3: Implement strict semantic decoding and validation**

Whitelist exact object keys. Decode square focus only from `{"type":"square","square":"h4"}` and move focus only from `{"type":"move","from":"h4","to":"f2"}`. Validate against board coordinates, `availableActions`, and `availableMoveFocus`. Do not infer, rewrite, or repair coaching meaning.

- [ ] **Step 4: Author and test `tutor-v6.md`**

Carry forward the approved warm tutor role, neutral authoritative evidence boundary, plain beginner priority routine, latest-interaction precedence, 18/3/4 limits, and exact JSON shape. Explicitly require ordinary child-facing language, full piece names, no chess move notation, and rare square names only when needed. Include no examples, fixture FENs, aliases, or case answers.

- [ ] **Step 5: Run Swift/Python prompt tests and commit**

Expected: both suites pass with zero failures/skips.

```bash
git add Tools/CoachingEval/prompts/tutor-v6.md \
  ChessTutor/Coaching/ModelEvaluation/ModelCoachingChessNativeContracts.swift \
  ChessTutor/Coaching/ModelEvaluation/ModelCoachingChessNativeTurnValidator.swift \
  ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingChessNativeTurnValidatorTests.swift \
  Tools/CoachingEval/tests/test_tutor_v6_prompt.py \
  ChessTutor.xcodeproj/project.pbxproj
git commit -m "feat: define chess-native coaching response"
```

---

### Task 3: Eight chess-native prompt examples

**Files:**
- Create: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingChessNativePromptExampleTests.swift`
- Modify: `project.yml`
- Regenerate: `ChessTutor.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: existing `ModelCoachingNeutralPromptExamples.fixtures`, neutral builder, v6 compiler, and `tutor-v6.md`.
- Produces an ignored directory selected by `COACHING_CHESS_NATIVE_PREVIEW_DIR` with `examples.jsonl`, `preview-manifest.json`, `system-prompt.md`, and eight `user-prompts/*.md` files.

- [ ] **Step 1: Write failing exact-eight export tests**

Require the existing eight IDs/order, exact request/compilation equality, unique hashes, replayed history/FEN consistency, no aliases, and no response/trace/hidden fields. Require example 06 to omit downstream relationships and remain under 1,500 rendered-content source words before tokenization.

- [ ] **Step 2: Run the exporter test and verify RED**

Expected: compile failure because the v6 exporter does not exist.

- [ ] **Step 3: Implement immutable v6 artifacts and writer**

Compile each existing structured snapshot with prompt version `tutor-v6`, bind exact system/user/request hashes, refuse noncanonical IDs and nonempty destinations, and add `COACHING_CHESS_NATIVE_PREVIEW_DIR` to the XcodeGen test environment.

- [ ] **Step 4: Export to a fresh directory and verify**

Run the selected XCTest with the environment variable. Assert exactly 11 declared files, byte equality, complete histories, separate tentative moves, no numbered aliases, and no conclusion-bearing authored prose.

- [ ] **Step 5: Commit**

```bash
git add ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingChessNativePromptExampleTests.swift \
  project.yml ChessTutor.xcodeproj/project.pbxproj
git commit -m "test: export chess-native coaching prompts"
```

---

### Task 4: Tokenizer-only v6 review packet

**Files:**
- Create: `Tools/CoachingEval/preview_chess_native_prompts.py`
- Create: `Tools/CoachingEval/tests/test_preview_chess_native_prompts.py`
- Modify: `Tools/CoachingEval/README.md`

**Interfaces:**
- Consumes: Task 3 export, `tutor-v6.md`, and a client narrowed to `render_prompt(...)` and `token_count(...)`.
- Produces: `.coaching-eval/chess-native-prompt-preview/final/preview-manifest.json` and eight complete system/user transcripts, with no response field.

- [ ] **Step 1: Write failing tokenizer-only tests**

Use a fake client whose generation method raises. Require exact order, hashes/equality, immutable destination refusal, token budget, no aliases, no response/assistant/trace/hidden fields, and zero generation calls.

- [ ] **Step 2: Run tests and verify RED**

Expected: import failure because the v6 preview module does not exist.

- [ ] **Step 3: Implement and verify tokenizer-only packet generation**

Reuse safe template/tokenization infrastructure without importing evaluation runners. Write complete logical transcripts with system and user messages only. Refuse any rendered prompt above 2,500 tokens.

- [ ] **Step 4: Generate fresh final artifacts**

Use the pinned Qwen3 1.7B runtime/model only for `/health`, `/apply-template`, and `/tokenize`. Record exact commands, hashes, and token counts. Confirm no completion endpoint is called.

- [ ] **Step 5: Run final proportional verification**

Run v6 compiler/validator/export XCTest suites, v5 neutral regression suites, v6 focused Python tests, full CoachingEval Python tests, artifact integrity/leakage scans, and `git diff --check`. Expected: zero failures/skips and eight prompts below 2,500 tokens.

- [ ] **Step 6: Commit and stop for user review**

```bash
git add Tools/CoachingEval/preview_chess_native_prompts.py \
  Tools/CoachingEval/tests/test_preview_chess_native_prompts.py \
  Tools/CoachingEval/README.md
git commit -m "feat: preview chess-native coaching prompts"
```

Return links to all eight exact prompts and the manifest. Do not run a model completion until the user explicitly approves a later experiment.

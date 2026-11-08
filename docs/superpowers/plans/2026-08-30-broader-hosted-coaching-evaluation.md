# Broader Hosted Chess Coaching Evaluation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a mechanically audited twelve-case prompt packet and one blinded 24-call Sol/high versus Luna/high coaching comparison without changing `tutor-v6` or the live app.

**Architecture:** Add a separate Swift test-support fixture inventory that uses the production request builder and chess-native compiler, then generalize the existing tokenizer-only preview boundary for an explicit ordered ID set. A new hosted runner consumes the frozen exported packet, completes the exact Sol/high × Luna/high matrix once, and emits identity-separated review artifacts. A small summarizer validates a complete blinded rubric before joining model identities and calculating per-configuration evidence.

**Tech Stack:** Swift/XCTest, ChessTutor pure chess model and coaching request/compiler types, Python 3 standard library, OpenAI Responses API client, XcodeGen, `xcodebuild`, `unittest`.

## Global Constraints

- Keep `Tools/CoachingEval/prompts/tutor-v6.md`, the response schema, validator, and 18-word child-message limit byte-exact.
- Use only `gpt-5.6-sol`/`high` and `gpt-5.6-luna`/`high`, with 2,048 maximum output tokens and `store: false`.
- Run exactly twelve visible cases once per model: 24 serial calls, one attempt, no retry, no repair, and no prompt mutation.
- Build every position from a legal committed history replayed from the standard starting position; keep tentative moves outside committed history.
- Do not put conclusions, answer keys, child-facing copy, hidden IDs, trace text, or provider bodies into model-facing or public review artifacts.
- Stop after the blinded 24-response review. Do not add models, reasoning levels, repeats, or prompt tuning.
- Keep generated prompts, provider records, review packets, and rubrics under ignored `.coaching-eval`; commit only source, tests, design/plan, and the final report.

---

## File structure

- `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingChessNativePromptExampleTests.swift`: retain canonical-eight tests and extract a reusable artifact factory without weakening the canonical exporter guard.
- `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingChessNativeBroadEvaluationTests.swift`: own the twelve legal snapshots, broad exporter, and fixture/compilation/export contracts.
- `project.yml`: forward only the opt-in broad export directory to the test action.
- `Tools/CoachingEval/preview_chess_native_prompts.py`: allow the existing strict tokenizer-only source/preview path to consume an explicit ordered visible ID tuple while preserving canonical-eight defaults.
- `Tools/CoachingEval/tests/test_preview_chess_native_prompts.py`: cover the explicit twelve-ID path and fail-closed source inventory rules.
- `Tools/CoachingEval/run_hosted_chess_native_broad_comparison.py`: run the frozen two-model matrix and create immutable private records plus blinded public review artifacts.
- `Tools/CoachingEval/tests/test_run_hosted_chess_native_broad_comparison.py`: fake-client behavioral coverage for preflight, exact calls, redaction, blinding, and CLI/key handling.
- `Tools/CoachingEval/summarize_hosted_chess_native_broad.py`: validate a complete rubric, join the private key once, and calculate per-configuration evidence.
- `Tools/CoachingEval/tests/test_summarize_hosted_chess_native_broad.py`: cover completeness, bounds, identity joins, dimensions, and severe-error accounting.
- `docs/reports/2026-08-30-broader-hosted-coaching-evaluation.md`: record exact prompts, run hashes, blinded results, costs, failures, and recommendation.

---

### Task 1: Twelve deterministic Swift fixtures and immutable export

**Files:**
- Modify: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingChessNativePromptExampleTests.swift`
- Create: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingChessNativeBroadEvaluationTests.swift`
- Modify: `project.yml`

**Interfaces:**
- Consumes: `ModelCoachingNeutralSnapshot`, `ModelCoachingNeutralRequestBuilder.build(snapshot:requestID:)`, `ModelCoachingChessNativeContextCompiler.compile(_:promptVersion:)`, `LegalMoveGenerator.allLegalMoves(in:)`, and the existing prompt record/manifest types.
- Produces: `ModelCoachingChessNativePromptArtifactFactory.artifacts(fixtures:)`, `ModelCoachingChessNativePromptArtifactFactory.write(_:to:)`, `ModelCoachingChessNativeBroadEvaluationExamples.fixtures`, and `ModelCoachingChessNativeBroadEvaluationExporter.write(to:)`.

- [ ] **Step 1: Write the failing broad-fixture contract tests**

Create `ModelCoachingChessNativeBroadEvaluationTests.swift` with an exact ID list and tests that initially fail because the inventory/exporter do not exist:

```swift
final class ModelCoachingChessNativeBroadEvaluationTests: XCTestCase {
    private let expectedIDs = [
        "b01-quiet-midgame-help",
        "b02-loose-bishop-danger",
        "b03-defended-knight",
        "b04-safe-queen-capture",
        "b05-poisoned-bishop-capture",
        "b06-equal-bishop-knight-exchange",
        "b07-pinned-knight-selection",
        "b08-safe-development",
        "b09-ignored-bishop-danger",
        "b10-harmless-check-trade",
        "b11-inspected-losing-queen-capture",
        "b12-replaced-knight-move",
    ]

    func testBroadFixturesHaveExactOrderAndDistinctPositions() throws {
        let fixtures = ModelCoachingChessNativeBroadEvaluationExamples.fixtures
        XCTAssertEqual(fixtures.map(\.id), expectedIDs)
        XCTAssertEqual(Set(fixtures.map(\.id)).count, 12)
        XCTAssertTrue(fixtures.allSatisfy { $0.visibility == .visible })
        XCTAssertEqual(Set(fixtures.map { fen(for: $0.snapshot.committedState) }).count, 12)
        XCTAssertTrue(Set(fixtures.map { fen(for: $0.snapshot.committedState) })
            .isDisjoint(with: Set(ModelCoachingNeutralPromptExamples.fixtures.map {
                fen(for: $0.snapshot.committedState)
            })))
    }
}
```

Add tests that replay every exported `gameHistory.canonicalMove`, compare the resulting FEN, require deterministic double compilation, and assert the exact interaction shape for each ID. Assert the staged/inspected cases expose these scoped reply moves:

```swift
let expectedReplies: [String: Set<String>] = [
    "b05-poisoned-bishop-capture": ["move:e8-f7"],
    "b06-equal-bishop-knight-exchange": ["move:b7-c6", "move:d7-c6"],
    "b09-ignored-bishop-danger": ["move:h6-g5"],
    "b10-harmless-check-trade": ["move:b4-d2"],
    "b11-inspected-losing-queen-capture": ["move:f6-f3"],
]
```

Also assert the entire exported JSONL/manifest/user-prompt set contains no keys or text matching `response`, `output`, `assistant`, `oracle`, `hidden`, `trace`, `relationship-[0-9]+`, or the original eight IDs.

- [ ] **Step 2: Run the focused test to verify RED**

Run:

```bash
xcodebuild test -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingChessNativeBroadEvaluationTests
```

Expected: compile failure naming the missing broad inventory/exporter.

- [ ] **Step 3: Extract the reusable artifact factory without weakening the old guard**

Move the serialization body from `ModelCoachingChessNativePromptExampleExporter.artifacts` into:

```swift
enum ModelCoachingChessNativePromptArtifactFactory {
    static func artifacts(
        fixtures: [ModelCoachingNeutralPromptFixture]
    ) throws -> ModelCoachingChessNativePromptExampleArtifacts

    static func write(
        _ artifacts: ModelCoachingChessNativePromptExampleArtifacts,
        to outputURL: URL
    ) throws
}
```

Keep the existing canonical API and exact guard:

```swift
static func artifacts(
    fixtures: [ModelCoachingNeutralPromptFixture] = ModelCoachingNeutralPromptExamples.fixtures
) throws -> ModelCoachingChessNativePromptExampleArtifacts {
    guard fixtures == ModelCoachingNeutralPromptExamples.fixtures else {
        throw ModelCoachingChessNativePromptExportError.invalidFixtureSet
    }
    return try ModelCoachingChessNativePromptArtifactFactory.artifacts(fixtures: fixtures)
}
```

The shared writer must retain nonempty-destination refusal, symlink standardization, relative declared-file inventory, atomic writes, sorted JSON, and SHA-256 behavior.

- [ ] **Step 4: Implement the exact twelve legal snapshots**

Create the broad inventory with these committed canonical histories and current interactions:

```swift
// b01 Help, quiet castled position
["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6", "d2d3", "f8e7", "e1g1", "e8g8"]

// b02 Help, bishop f4 attacked by e5 pawn
["d2d4", "d7d5", "c1f4", "e7e5"]

// b03 Help, knight c3 attacked but b2 pawn can recapture
["e2e4", "e7e5", "b1c3", "f8b4"]

// b04 Help, black queen h4 is safely capturable by knight f3
["e2e4", "e7e5", "g1f3", "d8h4"]

// b05 staged Bxf7+, answered by Kxf7
["e2e4", "e7e5", "f1c4", "g8f6"]
tentative: move("c4", "f7")

// b06 staged Bxc6, answered by bxc6 or dxc6
["e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6"]
tentative: move("b5", "c6")

// b07 selected knight c3 is absolutely pinned after d2-d3
["e2e4", "e7e5", "b1c3", "f8b4", "d2d3", "g8f6"]
selectedSquare: square("c3")

// b08 staged quiet development Nc3
["d2d4", "d7d5", "g1f3", "g8f6"]
tentative: move("b1", "c3")

// b09 staged a3 ignores bishop g5 attacked by h6 pawn
["d2d4", "d7d5", "c1g5", "h7h6"]
tentative: move("a2", "a3")

// b10 staged Bd2 blocks check; Bxd2+ permits an equal recapture
["d2d4", "e7e5", "d4e5", "f8b4"]
tentative: move("c1", "d2")

// b11 staged d3, then child inspects queen f6 and Qxf3
["e2e4", "e7e5", "g1f3", "d8f6"]
tentative: move("d2", "d3")
latest: .squareInspected, reference "piece:black:queen:f6"

// b12 h3 is replaced by Nf3 after the knight on e5 is attacked
["g1f3", "d7d5", "f3e5", "f7f6"]
tentative: move("e5", "f3")
events: .moveStaged(move("h2", "h3")), .moveReplaced(move("e5", "f3"))
```

Use the same production-shaped helpers as the canonical examples. Set
`positionRevision` to committed history count and `learner` to White. Use
monotonically increasing event sequences beginning with `.helpOpened`.

- [ ] **Step 5: Implement the broad exporter and opt-in writer**

Implement:

```swift
enum ModelCoachingChessNativeBroadEvaluationExporter {
    static func artifacts() throws -> ModelCoachingChessNativePromptExampleArtifacts {
        try ModelCoachingChessNativePromptArtifactFactory.artifacts(
            fixtures: ModelCoachingChessNativeBroadEvaluationExamples.fixtures
        )
    }

    static func write(to outputURL: URL) throws {
        try ModelCoachingChessNativePromptArtifactFactory.write(
            artifacts(),
            to: outputURL
        )
    }
}
```

Add an opt-in XCTest that reads `COACHING_CHESS_NATIVE_BROAD_PREVIEW_DIR`, writes exactly 15 declared files (three audit/system files plus twelve user prompts), and compares every byte with `artifacts()`.

Add to the test environment in `project.yml`:

```yaml
COACHING_CHESS_NATIVE_BROAD_PREVIEW_DIR: $(COACHING_CHESS_NATIVE_BROAD_PREVIEW_DIR)
```

- [ ] **Step 6: Regenerate the Xcode project and run focused GREEN**

Run:

```bash
xcodegen generate
xcodebuild test -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingChessNativePromptExampleTests \
  -only-testing:ChessTutorTests/ModelCoachingChessNativeBroadEvaluationTests
```

Expected: all selected tests pass with zero failures/skips.

- [ ] **Step 7: Commit the fixture/export boundary**

```bash
git add project.yml ChessTutor.xcodeproj/project.pbxproj \
  ChessTutor.xcodeproj/xcshareddata/xcschemes/ChessTutor.xcscheme \
  ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingChessNativePromptExampleTests.swift \
  ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingChessNativeBroadEvaluationTests.swift
git commit -m "test: add broader coaching prompt fixtures"
```

---

### Task 2: Explicit-ID tokenizer preview and frozen broad packet

**Files:**
- Modify: `Tools/CoachingEval/preview_chess_native_prompts.py`
- Modify: `Tools/CoachingEval/tests/test_preview_chess_native_prompts.py`

**Interfaces:**
- Consumes: the broad Swift export and exact tracked `tutor-v6.md`.
- Produces: `_load_and_validate_source(source_dir, system_prompt_path, *, example_ids=EXAMPLE_IDS)`, `build_preview(..., example_ids=EXAMPLE_IDS)`, and repeatable CLI `--example-id` arguments with canonical-eight-compatible defaults.

- [ ] **Step 1: Write failing explicit-ID preview tests**

Extend the synthetic source helper to accept `example_ids`. Add tests proving a twelve-ID tuple drives exact declared-file inventory, model-facing role order, prompt order, token call count, transcript names, and summary count. Add negative tests for a duplicate ID, reordered manifest, undeclared file, missing file, audit-role user prompt, and a 2,501-token prompt.

```python
def test_explicit_visible_ids_drive_exact_twelve_prompt_preview(self):
    ids = tuple(f"b{index:02}-case" for index in range(1, 13))
    manifest, destination, _source, _system, _source_manifest, client = (
        self._build(root, example_ids=ids, token_counts=[700] * 12)
    )
    self.assertEqual(list(ids), manifest["exampleIDs"])
    self.assertEqual(12, len(client.render_calls))
    self.assertEqual(12, len(client.token_calls))
    self.assertEqual(
        [f"{identifier}.md" for identifier in ids],
        [path.name for path in sorted((destination / "prompts").glob("*.md"))],
    )
```

- [ ] **Step 2: Run focused preview tests to verify RED**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest \
  Tools.CoachingEval.tests.test_preview_chess_native_prompts -v
```

Expected: failure because `_load_and_validate_source` and `build_preview` do not accept `example_ids`.

- [ ] **Step 3: Parameterize the exact source boundary**

Change only the inventory dimension:

```python
def _expected_declared_files(example_ids=EXAMPLE_IDS): ...

def _load_and_validate_source(
    source_dir, system_prompt_path, *, example_ids=EXAMPLE_IDS
):
    example_ids = tuple(example_ids)
    if not example_ids or len(example_ids) != len(set(example_ids)):
        raise ValueError("Prompt preview requires unique visible IDs")
    ...

def build_preview(
    *, source_dir, system_prompt_path, destination, client,
    tokenizer_provenance, timeout=30, example_ids=EXAMPLE_IDS
): ...
```

Replace every internal eight-case comparison/zip/count with `example_ids`.
Keep canonical defaults and all existing role, path, hash, hidden-ID, alias,
budget, endpoint, and no-generation checks unchanged.

Add a repeatable CLI argument and pass its exact order to `build_preview`:

```python
parser.add_argument("--example-id", action="append", dest="example_ids")
...
example_ids = tuple(arguments.example_ids or EXAMPLE_IDS)
manifest = build_preview(..., example_ids=example_ids)
```

- [ ] **Step 4: Run focused and adjacent GREEN**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest \
  Tools.CoachingEval.tests.test_preview_chess_native_prompts \
  Tools.CoachingEval.tests.test_run_hosted_chess_native_pilot -v
```

Expected: all selected tests pass.

- [ ] **Step 5: Export the broad Swift source twice and compare bytes**

Run two fresh opt-in exports:

```bash
COACHING_CHESS_NATIVE_BROAD_PREVIEW_DIR="$PWD/.coaching-eval/chess-native-broad/swift-export-a" \
xcodebuild test -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingChessNativeBroadEvaluationTests/testOptInWriterProducesExactPacket

COACHING_CHESS_NATIVE_BROAD_PREVIEW_DIR="$PWD/.coaching-eval/chess-native-broad/swift-export-b" \
xcodebuild test -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingChessNativeBroadEvaluationTests/testOptInWriterProducesExactPacket

diff -r .coaching-eval/chess-native-broad/swift-export-a \
  .coaching-eval/chess-native-broad/swift-export-b
```

Expected: both selected tests pass and `diff -r` is silent.

- [ ] **Step 6: Render/tokenize the source without inference and inspect prompts**

Use the existing pinned tokenizer client and the new exact repeated-ID CLI.
Write to `.coaching-eval/chess-native-broad/tokenizer-preview-v1`:

```bash
python3 Tools/CoachingEval/preview_chess_native_prompts.py \
  --source .coaching-eval/chess-native-broad/swift-export-a \
  --system-prompt Tools/CoachingEval/prompts/tutor-v6.md \
  --server .coaching-eval/runtime/b10516/bin/llama-server \
  --runtime-manifest .coaching-eval/runtime/b10516/runtime-manifest.json \
  --model .coaching-eval/models/qwen3-1.7b-q4_k_m/Qwen3-1.7B-Q4_K_M.gguf \
  --model-manifest .coaching-eval/models/qwen3-1.7b-q4_k_m/artifact-manifest.json \
  --destination .coaching-eval/chess-native-broad/tokenizer-preview-v1 \
  --example-id b01-quiet-midgame-help \
  --example-id b02-loose-bishop-danger \
  --example-id b03-defended-knight \
  --example-id b04-safe-queen-capture \
  --example-id b05-poisoned-bishop-capture \
  --example-id b06-equal-bishop-knight-exchange \
  --example-id b07-pinned-knight-selection \
  --example-id b08-safe-development \
  --example-id b09-ignored-bishop-danger \
  --example-id b10-harmless-check-trade \
  --example-id b11-inspected-losing-queen-capture \
  --example-id b12-replaced-knight-move
```

Verify:

```bash
find .coaching-eval/chess-native-broad/tokenizer-preview-v1/prompts \
  -type f -name '*.md' | wc -l
rg -n "relationship-[0-9]+|action-[0-9]+|oracle|hidden|assistant|response" \
  .coaching-eval/chess-native-broad/tokenizer-preview-v1
```

Expected: 12 prompt transcripts; the forbidden scan has no matches; every
token count is at most 2,500. Read all twelve model-facing prompts before
proceeding.

- [ ] **Step 7: Commit the generalized preview boundary**

```bash
git add Tools/CoachingEval/preview_chess_native_prompts.py \
  Tools/CoachingEval/tests/test_preview_chess_native_prompts.py
git commit -m "test: preview broader coaching prompts"
```

---

### Task 3: Exact two-model hosted runner and blinded packet

**Files:**
- Create: `Tools/CoachingEval/run_hosted_chess_native_broad_comparison.py`
- Create: `Tools/CoachingEval/tests/test_run_hosted_chess_native_broad_comparison.py`

**Interfaces:**
- Consumes: an explicit twelve-ID source directory, its actual manifest/examples hashes, `run_hosted_chess_native_pilot._complete_prompt`, and `OpenAIResponsesClient`.
- Produces: `run_broad_comparison(...) -> dict`, immutable records/manifests, `review-packet.jsonl`, `review-key.json`, and blank `rubric.csv`.

- [ ] **Step 1: Write failing exact-matrix and preflight tests**

Create a synthetic twelve-prompt source fixture and tests for:

```python
CONFIGURATIONS = (
    {"id": "sol-high", "model": "gpt-5.6-sol", "reasoningEffort": "high"},
    {"id": "luna-high", "model": "gpt-5.6-luna", "reasoningEffort": "high"},
)
```

Assert complete source/hash/schema preflight occurs before any completion,
then exact configuration-major/case-major 24-call order. Assert every call
receives byte-identical system/user text, request-specific schema, 2,048 output
tokens, high reasoning, and configured timeout. Assert one invalid response
and one provider exception are redacted and do not stop the later cells.

Assert the public packet contains 24 unique review IDs, case IDs, user prompts,
final turns, and validation—but no configuration/model/provider ID, response
ID, record path, reasoning, trace, credential, or error body. Assert the
private key maps every review ID to exactly one configuration and record hash.
Assert the blank rubric preserves shuffled review order.

- [ ] **Step 2: Run the focused test to verify RED**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest \
  Tools.CoachingEval.tests.test_run_hosted_chess_native_broad_comparison -v
```

Expected: import/implementation failure for the new runner.

- [ ] **Step 3: Implement strict source loading and all-cell preflight**

Implement:

```python
def run_broad_comparison(
    *, source_dir, system_prompt_path, destination, client,
    case_ids, expected_source_manifest_sha256,
    expected_examples_jsonl_sha256, timeout=120,
    review_seed=None,
): -> dict
```

Validate both expected hashes as lowercase 64-character SHA-256 strings and
compare them to actual bytes. Load the source through
`preview_chess_native_prompts._load_and_validate_source(...,
example_ids=case_ids)`. Construct every `ChessNativeResponseContract` and
Structured Outputs schema before the first provider call; any source/schema
failure must leave `client.calls == []` and create no destination.

- [ ] **Step 4: Implement one-shot serial completion and immutable records**

Call `_complete_prompt` exactly once per cell. Add `configurationID`,
`requestedModel`, and `reasoningEffort` to private records. Persist records
atomically in `records/<configuration>--<case>.json`, plus a manifest binding
source hashes, configurations, order, record hashes, summary, token usage,
latency, `store: false`, retries `0`, and repairs `0`.

Use the existing generic error classification and trace scan. Never persist an
exception string or provider body.

- [ ] **Step 5: Implement blinded review artifacts**

Use 32 random bytes by default (injectable in tests) to deterministically
shuffle within the run and derive opaque review IDs. Write:

```text
review/review-packet.jsonl
review/review-key.json
review/rubric.csv
```

The rubric header is:

```csv
reviewID,factualCorrectness,currentStage,singlePurpose,discoveryCoaching,childLanguage,uiAlignment,severe,notes
```

Scores remain blank. `review-key.json` is audit-only and contains the exact
configuration/record mapping; it is never referenced from the public packet.
Scan every public artifact for model/config/provider identities and trace
markers before atomic publication.

- [ ] **Step 6: Implement CLI and credential boundary**

Require `--source-manifest-sha256`, `--examples-jsonl-sha256`, and a fresh
`--destination`. Read only `OPENAI_API_KEY`; pass it directly to
`OpenAIResponsesClient`; print only the bounded summary. Test missing key,
overwrite refusal, exact CLI arguments, one client, and zero persisted key
matches.

- [ ] **Step 7: Run focused and adjacent GREEN**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest \
  Tools.CoachingEval.tests.test_run_hosted_chess_native_broad_comparison \
  Tools.CoachingEval.tests.test_run_hosted_chess_native_screen \
  Tools.CoachingEval.tests.test_run_hosted_chess_native_consistency \
  Tools.CoachingEval.tests.test_run_hosted_chess_native_pilot -v
```

Expected: all selected tests pass.

- [ ] **Step 8: Commit the hosted runner**

```bash
git add Tools/CoachingEval/run_hosted_chess_native_broad_comparison.py \
  Tools/CoachingEval/tests/test_run_hosted_chess_native_broad_comparison.py
git commit -m "test: compare broader hosted coaching"
```

---

### Task 4: Complete-rubric validator and evidence summary

**Files:**
- Create: `Tools/CoachingEval/summarize_hosted_chess_native_broad.py`
- Create: `Tools/CoachingEval/tests/test_summarize_hosted_chess_native_broad.py`

**Interfaces:**
- Consumes: the exact run manifest, review packet, private review key, and completed rubric.
- Produces: `summarize(run_dir) -> dict`, `comparison-summary.json`, and `comparison-summary.md`.

- [ ] **Step 1: Write failing complete-rubric tests**

Create a synthetic 24-row run. Require exact matching review IDs/order across
packet and rubric, one-to-one key mapping, valid record hashes, scores 1–5 for
all six dimensions, `severe` exactly `true` or `false`, and nonempty notes for
severe rows. Reject blanks, duplicates, unknown IDs, missing IDs, reordered
rows, out-of-range scores, invalid booleans, source-hash mismatch, or a key
pointing outside the run.

Assert the summary reports per configuration: total, strict-valid, severe,
dimension means, latency median/p90, input/output/reasoning tokens, estimated
cost, and up to three review examples. Do not calculate a combined quality
score or automatically declare a winner.

- [ ] **Step 2: Run focused tests to verify RED**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest \
  Tools.CoachingEval.tests.test_summarize_hosted_chess_native_broad -v
```

Expected: import/implementation failure.

- [ ] **Step 3: Implement strict parsing, join, and aggregation**

Implement standard-library-only CSV/JSON parsing. Resolve all paths beneath
`run_dir` and reject traversal/symlink escape. Hash every referenced record
before reading it. Join identities only after the rubric is fully validated.
Use the official frozen prices already documented for the comparison:

```python
PRICES_PER_MILLION = {
    "gpt-5.6-sol": {"input": 4.00, "output": 20.00},
    "gpt-5.6-luna": {"input": 0.20, "output": 1.20},
}
```

Reasoning tokens are already included in provider output tokens and must not
be billed twice.

- [ ] **Step 4: Implement immutable summary CLI**

Require a fresh output directory. Write canonical JSON and readable Markdown
atomically. Include exact source/run/review/rubric hashes and the complete
per-dimension evidence, but no hidden reasoning, provider body, credential,
or review seed.

- [ ] **Step 5: Run focused and full Python GREEN**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest \
  Tools.CoachingEval.tests.test_summarize_hosted_chess_native_broad -v
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest discover \
  -s Tools/CoachingEval/tests -v
```

Expected: all tests pass with zero failures/skips.

- [ ] **Step 6: Commit the summarizer**

```bash
git add Tools/CoachingEval/summarize_hosted_chess_native_broad.py \
  Tools/CoachingEval/tests/test_summarize_hosted_chess_native_broad.py
git commit -m "test: summarize broader coaching comparison"
```

---

### Task 5: Run, score blindly, report, and verify

**Files:**
- Create: `docs/reports/2026-08-30-broader-hosted-coaching-evaluation.md`
- Modify only if a verified harness defect is found: the Task 1–4 files and their direct tests.

**Interfaces:**
- Consumes: the final broad source packet, exact source hashes, hosted runner, and summarizer.
- Produces: one immutable 24-record run, a completed blinded rubric, one immutable evidence summary, and the tracked product report.

- [ ] **Step 1: Recheck the frozen prompt packet and hashes**

Calculate and retain task-specific shell variables for the exact hashes:

```bash
BROAD_SOURCE_MANIFEST_SHA256="$(shasum -a 256 \
  .coaching-eval/chess-native-broad/swift-export-a/preview-manifest.json | awk '{print $1}')"
BROAD_EXAMPLES_JSONL_SHA256="$(shasum -a 256 \
  .coaching-eval/chess-native-broad/swift-export-a/examples.jsonl | awk '{print $1}')"
shasum -a 256 .coaching-eval/chess-native-broad/swift-export-a/system-prompt.md
```

Read all twelve user prompts. Confirm each describes only its current state,
interaction, scoped facts, and available UI contract. If any prompt contains
an authored conclusion or ambiguous fixture, stop and fix the fixture with a
RED/GREEN test before spending.

- [ ] **Step 2: Run the exact 24 hosted calls once**

Retrieve the API key only in the child environment and never echo it:

```bash
BROAD_SOURCE_MANIFEST_SHA256="$(shasum -a 256 \
  .coaching-eval/chess-native-broad/swift-export-a/preview-manifest.json | awk '{print $1}')"
BROAD_EXAMPLES_JSONL_SHA256="$(shasum -a 256 \
  .coaching-eval/chess-native-broad/swift-export-a/examples.jsonl | awk '{print $1}')"
OPENAI_API_KEY="$(security find-generic-password \
  -s 'ChessTutor-CoachingEval-OpenAI' -w)" \
python3 Tools/CoachingEval/run_hosted_chess_native_broad_comparison.py \
  --source .coaching-eval/chess-native-broad/swift-export-a \
  --system-prompt Tools/CoachingEval/prompts/tutor-v6.md \
  --source-manifest-sha256 "$BROAD_SOURCE_MANIFEST_SHA256" \
  --examples-jsonl-sha256 "$BROAD_EXAMPLES_JSONL_SHA256" \
  --destination .coaching-eval/runs/hosted-tutor-v6-broad-sol-luna-20260830
```

Run serially once; do not relaunch while the process is active.

- [ ] **Step 3: Verify the run before scoring**

Require 24 unique records, 12 cases per configuration, one attempt per cell,
no trace markers, no hidden IDs, no provider bodies, and exact source hashes.
Hash the run manifest, review packet, review key, and blank rubric. Do not read
`review-key.json` yet.

- [ ] **Step 4: Score all 24 rows while blinded**

Read only `review/review-packet.jsonl`, the blank rubric, `tutor-v6.md`, and
the six-dimension rubric in the design. Fill every score with an integer 1–5,
mark severe chess/current-stage errors, and add concise evidence notes. Keep
row order and review IDs byte-exact. Do not inspect private records, directory
names, provider IDs, or `review-key.json` until the rubric is complete and
hashed.

- [ ] **Step 5: Unblind once and generate the evidence summary**

Run:

```bash
python3 Tools/CoachingEval/summarize_hosted_chess_native_broad.py \
  --run-dir .coaching-eval/runs/hosted-tutor-v6-broad-sol-luna-20260830 \
  --destination .coaching-eval/analysis/hosted-tutor-v6-broad-sol-luna-20260830
```

Audit every severe response against its exact prompt and position. Also audit
every mechanically invalid response that received non-severe human scores.

- [ ] **Step 6: Write the product report**

Create the tracked report with:

- exact prompt/run/review/rubric/summary hashes;
- the twelve case purposes and full provider settings;
- strict-valid and severe counts;
- each dimension separately, without a composite score;
- exact token, latency, and estimated-cost evidence;
- representative good and bad responses;
- any fixture/harness caveat;
- the Sol/high versus Luna/high recommendation; and
- explicit confirmation that no retries, repairs, prompt tuning, local-model
  run, hidden inspection, or extra provider calls occurred.

- [ ] **Step 7: Run final proportional and full verification**

Run:

```bash
xcodebuild test -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingChessNativePromptExampleTests \
  -only-testing:ChessTutorTests/ModelCoachingChessNativeBroadEvaluationTests \
  -only-testing:ChessTutorTests/ModelCoachingChessNativeTurnValidatorTests

PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest discover \
  -s Tools/CoachingEval/tests -v

git diff --check
git status --short
```

Expected: every selected Swift test and every evaluator test passes with zero
failures/skips; diff check is silent; status contains only the scoped report or
verified harness fixes.

- [ ] **Step 8: Commit the final report and any verified harness fix**

```bash
git add docs/reports/2026-08-30-broader-hosted-coaching-evaluation.md
git commit -m "docs: report broader hosted coaching quality"
git status --short
```

Expected: clean tracked worktree; ignored evidence remains available under
`.coaching-eval`.

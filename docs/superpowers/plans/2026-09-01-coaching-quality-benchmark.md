# Coaching Quality Benchmark Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a repeatable, automatically graded benchmark that compares coaching models, parameters, system prompts, and deterministic user-prompt generators while reporting quality, latency, reliability, and cost.

**Architecture:** A Swift test-support corpus exports production-shaped structured requests plus grader-only briefs. A focused Python benchmark package resolves immutable configurations, runs candidates through existing provider and response-contract adapters, grades valid responses with a calibrated blinded judge, and produces reproducible machine-readable and Markdown reports. The benchmark never enters the shipping app target or ordinary provider-free CI.

**Tech Stack:** Swift/XCTest chess fixtures and export; Python 3.9+ standard library; existing Flask server compiler, OpenAI Responses adapter, strict chess-native response validator, `unittest`, JSON/JSONL/Markdown artifacts.

## Global Constraints

- Corpus v1 contains exactly 40 independent situations and 10 three-step interaction sequences.
- Development contains 32 independent situations and 8 sequences; holdout contains 8 independent situations and 2 sequences.
- Model-facing input contains only production-available deterministic facts; grader briefs never enter candidate prompts.
- Quick mode uses one response per development turn; comparison mode uses three responses per turn and includes the production baseline.
- Mechanical failures are unusable, are not semantically judged, and lose pairwise against valid responses.
- Automatic grading uses six 1-5 dimensions plus explicit severe-error flags and blinded A/B/tie comparison.
- Judge calibration requires at least 20 human-scored examples, at least 90% severe-class agreement, and at least 80% of dimension ratings within one point.
- Candidate latency/cost and judge overhead remain separate; no opaque combined quality/cost score is allowed.
- Credentials, provider reasoning, and provider error bodies are never persisted.
- Provider calls are opt-in and never run in ordinary pull-request CI.
- Existing artifacts are immutable; writers refuse overwrite and publish complete runs atomically.

---

## File structure

### Swift fixture support

- `ChessTutorTests/Coaching/ModelEvaluation/CoachingQualityBenchmarkCorpus.swift` — v1 case, split, category, sequence, grader-brief, artifact, and exporter types plus the 50 fixture groups.
- `ChessTutorTests/Coaching/ModelEvaluation/CoachingQualityBenchmarkCorpusTests.swift` — fixture counts, legal replay, oracle isolation, deterministic export, and writer tests.

### Python benchmark package

- `Tools/CoachingEval/benchmark/__init__.py` — package marker only; no re-exports.
- `Tools/CoachingEval/benchmark/corpus.py` — strict corpus/manifest loading and matrix selection.
- `Tools/CoachingEval/benchmark/configuration.py` — immutable experiment, judge, and pricing contracts plus safe generator/provider registries.
- `Tools/CoachingEval/benchmark/runner.py` — preflight, candidate calls, sequence continuation, validation, sanitized records, and atomic run publication.
- `Tools/CoachingEval/benchmark/grader.py` — mechanical disposition, judge calibration, absolute rubric, randomized pairwise grading, and immutable grade publication.
- `Tools/CoachingEval/benchmark/report.py` — aggregates, bootstrap intervals, Pareto frontier, JSON, and Markdown.
- `Tools/CoachingEval/benchmark/cli.py` — `run`, `grade`, and `report` commands.
- `Tools/CoachingEval/benchmark/judge-v1.md` — pinned grading instructions.
- `Tools/CoachingEval/benchmark/judge-calibration-v1.jsonl` — 20 human-scored good/bad calibration examples.
- `Tools/CoachingEval/benchmark/pricing-v1.json` — pinned provider prices, date, and authoritative source URL.
- `Tools/CoachingEval/benchmark/configs/production-v1.json` — current GPT-5.6 Sol initial/follow-up configuration.
- `Tools/CoachingEval/benchmark/configs/judge-v1.json` — pinned strong hosted judge configuration.

### Tests and operator entry point

- `Tools/CoachingEval/tests/test_benchmark_corpus.py`
- `Tools/CoachingEval/tests/test_benchmark_configuration.py`
- `Tools/CoachingEval/tests/test_benchmark_runner.py`
- `Tools/CoachingEval/tests/test_benchmark_grader.py`
- `Tools/CoachingEval/tests/test_benchmark_report.py`
- `Tools/CoachingEval/tests/test_benchmark_cli.py`
- `scripts/run_coaching_quality_benchmark.sh` — Keychain-backed one-command export/run/grade/report workflow.
- `Tools/CoachingEval/README.md` — benchmark usage and artifact interpretation.

---

### Task 1: Export a deterministic production-shaped benchmark corpus

**Files:**
- Create: `ChessTutorTests/Coaching/ModelEvaluation/CoachingQualityBenchmarkCorpus.swift`
- Create: `ChessTutorTests/Coaching/ModelEvaluation/CoachingQualityBenchmarkCorpusTests.swift`

**Interfaces:**
- Consumes: `ModelCoachingNeutralSnapshot`, `ModelCoachingNeutralRequestBuilder.build(snapshot:requestID:)`, `LegalMoveGenerator`, and `ModelCoachingPositionEncoder`.
- Produces: `CoachingQualityBenchmarkExporter.artifacts(sourceGitSHA:) -> CoachingQualityBenchmarkArtifacts` and `write(to:sourceGitSHA:)`.
- Artifact contract: `cases.jsonl` contains ordered `CoachingQualityBenchmarkCaseRecord` values; `benchmark-manifest.json` binds counts, order, split, and SHA-256.

- [ ] **Step 1: Write failing corpus contract tests**

Add tests that expect these public test-support types and exact top-level counts:

```swift
func testV1HasExactIndependentSequenceAndSplitCounts() {
    let corpus = CoachingQualityBenchmarkCorpus.v1
    XCTAssertEqual(corpus.independent.count, 40)
    XCTAssertEqual(corpus.sequences.count, 10)
    XCTAssertEqual(corpus.sequences.flatMap(\.steps).count, 30)
    XCTAssertEqual(corpus.developmentTurns.count, 56)
    XCTAssertEqual(corpus.holdoutTurns.count, 14)
}

func testExportIsDeterministicAndOracleNeverEntersModelFacingCompilation() throws {
    let first = try CoachingQualityBenchmarkExporter.artifacts(sourceGitSHA: "source")
    let second = try CoachingQualityBenchmarkExporter.artifacts(sourceGitSHA: "source")
    XCTAssertEqual(first, second)
    for record in try decodeCases(first.casesJSONL) {
        let compiled = ModelCoachingChessNativeContextCompiler.compile(
            record.request,
            promptVersion: "tutor-v13"
        ).markdown
        for phrase in record.graderBrief.successCriteria + record.graderBrief.severeFailureCriteria {
            XCTAssertFalse(compiled.localizedCaseInsensitiveContains(phrase), record.id)
        }
    }
}
```

- [ ] **Step 2: Run the selected XCTest class and witness RED**

Run:

```bash
xcodebuild test -project ChessTutor.xcodeproj -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/CoachingQualityBenchmarkCorpusTests
```

Expected: compilation fails because `CoachingQualityBenchmarkCorpus` and exporter types do not exist.

- [ ] **Step 3: Implement corpus contracts and exporter**

Define these exact Codable contracts:

```swift
enum CoachingQualityBenchmarkSplit: String, Codable { case development, holdout }

enum CoachingQualityBenchmarkCategory: String, Codable {
    case quiet, danger, capture, tentativeMove, interaction, specialRule
}

struct CoachingQualityBenchmarkGraderBrief: Codable, Equatable {
    let verifiedFacts: [String]
    let coachingPurpose: String
    let acceptableAlternatives: [String]
    let successCriteria: [String]
    let severeFailureCriteria: [String]
}

struct CoachingQualityBenchmarkTurn: Equatable {
    let id: String
    let groupID: String
    let stepIndex: Int
    let split: CoachingQualityBenchmarkSplit
    let category: CoachingQualityBenchmarkCategory
    let snapshot: ModelCoachingNeutralSnapshot
    let graderBrief: CoachingQualityBenchmarkGraderBrief
    let sourceTraceID: String?
}

struct CoachingQualityBenchmarkSequence: Equatable {
    let id: String
    let split: CoachingQualityBenchmarkSplit
    let steps: [CoachingQualityBenchmarkTurn]
}

struct CoachingQualityBenchmarkCaseRecord: Codable, Equatable {
    let schemaVersion: String
    let id: String
    let groupID: String
    let stepIndex: Int
    let split: CoachingQualityBenchmarkSplit
    let category: CoachingQualityBenchmarkCategory
    let request: ModelCoachingNeutralRequest
    let graderBrief: CoachingQualityBenchmarkGraderBrief
    let sourceTraceID: String?
}
```

Build each request with an ID such as `benchmark:q01-starting-position`, derived
from its exact turn ID. Canonically encode one record per line with sorted keys.
The manifest uses schema `coaching-quality-benchmark-manifest.v1`, declares 40
independent groups, 10 sequence groups, 70 turns, 56 development turns, 14
holdout turns, ordered turn IDs, source SHA, and the `cases.jsonl` SHA-256.
Refuse a nonempty destination and use a temporary sibling followed by rename.

- [ ] **Step 4: Add exact fixture inventory**

Use these exact group IDs and splits. The first 21 independent groups may wrap the existing eight neutral and thirteen broad fixtures; the remaining groups use new legal histories and snapshots. Every sequence has exactly three cumulative event snapshots.

Development independent groups:

```text
q01-starting-position          q02-quiet-midgame
q03-quiet-castling             d01-loose-bishop
d02-defended-knight            d03-recapturable-pawn
d04-pinned-knight              d05-answering-check
d06-apparent-danger            d07-two-dangers
c01-safe-queen-capture         c02-poisoned-bishop-capture
c03-equal-exchange             c04-no-safe-capture
c05-mating-capture             c06-en-passant
m01-safe-development           m02-ignored-danger
m03-harmless-check-trade       m04-replaced-knight
m05-removed-move               m06-promotion
m07-castling                   m08-discovered-check
i01-selected-attacked-piece    i02-selected-blocked-rook
i03-inspected-losing-queen     i04-opening-hint
i05-no-piece-needs-help        i06-no-safe-capture
i07-looks-safe                 i08-try-another-move
```

Holdout independent groups:

```text
h01-quiet-black-opening        h02-defended-pawn
h03-double-check               h04-castling-check
h05-stale-selection-replaced   h06-benign-capture-safety
h07-ambiguous-equal-trade      h08-mate-in-one
```

Development sequences:

```text
s01-danger-selection-response  s02-danger-negative-answer
s03-capture-none               s04-safe-move-confirm
s05-unsafe-move-retry          s06-replace-move
s07-inspect-reply              s08-hint-then-act
```

Holdout sequences:

```text
s09-remove-and-stage           s10-close-and-reopen
```

- [ ] **Step 5: Add legal-replay, request-reference, and writer tests**

For every turn, replay `request.gameHistory` from the standard position, require the resulting FEN and revision to match, require tentative moves to be legal movement candidates, resolve every referenced ID against the request, and compile both initial and follow-up Markdown without exceptions. Assert the writer produces exactly `cases.jsonl` and `benchmark-manifest.json` and refuses overwrite.

- [ ] **Step 6: Run focused XCTest GREEN**

Run the selected class twice and require identical exported bytes, 0 failures, and 0 skipped tests.

- [ ] **Step 7: Commit the corpus**

```bash
git add ChessTutorTests/Coaching/ModelEvaluation/CoachingQualityBenchmarkCorpus.swift \
  ChessTutorTests/Coaching/ModelEvaluation/CoachingQualityBenchmarkCorpusTests.swift
git commit -m "test: add coaching quality benchmark corpus"
```

---

### Task 2: Load immutable corpus, experiment, judge, and pricing contracts

**Files:**
- Create: `Tools/CoachingEval/benchmark/__init__.py`
- Create: `Tools/CoachingEval/benchmark/corpus.py`
- Create: `Tools/CoachingEval/benchmark/configuration.py`
- Create: `Tools/CoachingEval/benchmark/pricing-v1.json`
- Create: `Tools/CoachingEval/benchmark/configs/production-v1.json`
- Create: `Tools/CoachingEval/benchmark/configs/judge-v1.json`
- Create: `Tools/CoachingEval/tests/test_benchmark_corpus.py`
- Create: `Tools/CoachingEval/tests/test_benchmark_configuration.py`

**Interfaces:**
- Produces: `load_corpus(root: Path) -> BenchmarkCorpus`, `load_candidate(path: Path, repository_root: Path) -> CandidateConfiguration`, `load_judge(...) -> JudgeConfiguration`, and `load_prices(...) -> PriceTable`.
- `PriceTable.estimate(model: str, usage: Mapping[str, int]) -> Decimal` prices uncached input, cached input, and output/reasoning tokens separately.

- [ ] **Step 1: Write failing strict-loader tests**

Cover exact fields and versions, file/hash mismatch, duplicate/missing IDs, wrong 40/10/70/56/14 counts, grader brief absence, unknown split/category, hidden selection without explicit `include_holdout=True`, path escape, prompt hash drift, unsupported provider/generator/contract IDs, missing price entries, negative prices, and changed configuration files after load.

Use this candidate shape in tests, with `prompt_sha` computed from the exact
fixture prompt bytes before constructing the mapping:

```python
candidate = {
  "schemaVersion": "coaching-quality-candidate.v1",
  "id": "production-sol-v1",
  "baseline": True,
  "provider": "openai-responses-v1",
  "model": "gpt-5.6-sol",
  "initialReasoningEffort": "high",
  "followUpReasoningEffort": "none",
  "conversationReuse": true,
  "maximumOutputTokens": 2048,
  "timeoutSeconds": 30,
  "maximumAttempts": 1,
  "systemPromptPath": "Tools/CoachingEval/prompts/tutor-v13.md",
  "systemPromptSHA256": prompt_sha,
  "userPromptGenerator": "chess-native-v13",
  "responseContract": "chess-native-v13",
  "pricingVersion": "openai-2026-09-01"
}
```

- [ ] **Step 2: Run focused Python tests and witness RED**

Run:

```bash
python3 -B -m unittest \
  Tools.CoachingEval.tests.test_benchmark_corpus \
  Tools.CoachingEval.tests.test_benchmark_configuration -v
```

Expected: import failure for the new package modules.

- [ ] **Step 3: Implement strict dataclasses and loaders**

Use frozen dataclasses. Reject unknown keys rather than ignoring them. Resolve tracked paths beneath repository root, hash bytes before parsing, retain full system-prompt text in the loaded configuration, and record a canonical configuration SHA. Register only:

```python
PROMPT_GENERATORS = {
    "chess-native-v13": (compile_context, compile_follow_up_context),
}
PROVIDERS = {"openai-responses-v1"}
RESPONSE_CONTRACTS = {"chess-native-v13"}
```

The registry is intentionally code-owned: comparing a new deterministic user-prompt generator requires adding and testing a named implementation rather than loading arbitrary Python from JSON.

- [ ] **Step 4: Pin production, judge, and pricing files**

`production-v1.json` is marked as the baseline and mirrors the live service:
GPT-5.6 Sol, high initial reasoning, no reasoning for simple follow-ups,
conversation reuse, tutor-v13, 2,048 output tokens, 30-second timeout, and one
attempt.

`judge-v1.json` selects GPT-5.6 Sol with high reasoning, no conversation reuse, 2,048 output tokens, 60-second timeout, judge prompt v1, calibration v1, and fixed review seed `20260901`.

`pricing-v1.json` records the official per-million uncached-input, cached-input, and output prices for every configured model, source URL, and effective date. Reasoning tokens remain part of output pricing. Values use decimal strings and are never inferred from model names.

- [ ] **Step 5: Run focused tests GREEN and commit**

```bash
git add Tools/CoachingEval/benchmark Tools/CoachingEval/tests/test_benchmark_corpus.py \
  Tools/CoachingEval/tests/test_benchmark_configuration.py
git commit -m "feat: add benchmark configuration contracts"
```

---

### Task 3: Run quick and comparison candidate matrices

**Files:**
- Create: `Tools/CoachingEval/benchmark/runner.py`
- Create: `Tools/CoachingEval/tests/test_benchmark_runner.py`

**Interfaces:**
- Consumes: `BenchmarkCorpus`, one or more `CandidateConfiguration`, and a callable `provider_factory(configuration) -> OpenAIResponsesClient-compatible client`.
- Produces: `run_candidates(..., mode: str, destination: Path, include_holdout: bool = False) -> Path` with `run-manifest.json`, `records.jsonl`, and transcript names such as `transcripts/production-sol-v1--q01-starting-position--r1.md`.

- [ ] **Step 1: Write failing matrix/preflight tests**

Test quick mode's exact 56 development cells per configuration and comparison mode's exact 168 cells per configuration. Require all cells to preflight before the first provider call. Reject a comparison without a configuration marked `baseline`, duplicate IDs, reordered corpus, hash drift, an existing destination, holdout without explicit opt-in, and a partial sequence.

- [ ] **Step 2: Write failing sequence and provider-boundary tests**

With a fake provider, prove:

- independent turns use full `compile_context` and no previous response ID;
- sequence step 1 uses the initial effort and full prompt;
- steps 2-3 use `compile_follow_up_context`, the follow-up effort, and the preceding provider response ID when reuse is enabled;
- reuse-disabled configurations send complete independent requests;
- an invalid or failed step marks later sequence steps `blockedByPriorTurn` without provider calls;
- one configured timeout/retry is counted and costed, while the production one-attempt config never retries;
- every response is parsed through `ChessNativeResponseContract`; and
- exception text, output reasoning, credentials, and provider bodies never persist.

- [ ] **Step 3: Witness RED, then implement preflight and execution**

Implement these frozen record fields:

```python
{
  "schemaVersion": "coaching-quality-candidate-record.v1",
  "cellID": "production-sol-v1|q01-starting-position|r1",
  "configurationID": "production-sol-v1",
  "caseID": "q01-starting-position",
  "groupID": "q01-starting-position",
  "stepIndex": 1,
  "split": "development",
  "category": "quiet",
  "repetition": 1,
  "requestSHA256": "...",
  "systemPromptSHA256": "...",
  "userPrompt": "...",
  "userPromptSHA256": "...",
  "responseID": "resp_...",
  "sanitizedOutput": "...",
  "parsedTurn": null,
  "mechanicalValidation": {"valid": false, "categories": ["..."]},
  "generationStatus": "completed",
  "usage": {"inputTokens": 0, "cachedInputTokens": 0, "outputTokens": 0, "reasoningTokens": 0},
  "latencyMilliseconds": 0.0,
  "timeToFirstTokenMilliseconds": null,
  "attemptCount": 1,
  "previousResponseIDUsed": null
}
```

Use existing bounded provider output and error categories. Store grader briefs
only in the source corpus; records point back by case ID and corpus hash. The
run manifest embeds the complete resolved configuration, including full system
prompt text, as well as its canonical hash. Conversation sequences request
provider storage; independent turns do not. Write to a temporary sibling,
fsync files/directories, validate exact matrix completeness, then atomically
rename.

- [ ] **Step 4: Add deterministic transcript and cost inputs**

Each transcript contains configuration ID, case ID, exact user prompt, sanitized response, parsed turn, mechanical validation, usage, and latency. It omits system-prompt duplication, grader brief, provider reasoning, and secrets. Bind every transcript SHA in the run manifest.

- [ ] **Step 5: Run runner tests GREEN and commit**

```bash
git add Tools/CoachingEval/benchmark/runner.py \
  Tools/CoachingEval/tests/test_benchmark_runner.py
git commit -m "feat: run coaching benchmark candidates"
```

---

### Task 4: Calibrate and run the automatic rubric judge

**Files:**
- Create: `Tools/CoachingEval/benchmark/grader.py`
- Create: `Tools/CoachingEval/benchmark/judge-v1.md`
- Create: `Tools/CoachingEval/benchmark/judge-calibration-v1.jsonl`
- Create: `Tools/CoachingEval/tests/test_benchmark_grader.py`

**Interfaces:**
- Produces: `calibrate_judge(...) -> CalibrationResult` and `grade_run(...) -> Path` containing `calibration.json`, `absolute-grades.jsonl`, `pairwise-grades.jsonl`, and `grade-manifest.json`.
- Judge calls use the existing `OpenAIResponsesClient` with strict request-specific JSON schemas and `store=False`.

- [ ] **Step 1: Write failing calibration tests**

Create 20 calibration rows as ten matched good/bad pairs drawn from quiet opening, urgent danger, defended piece, safe capture, losing capture, latest selection, staged move, replacement, unavailable action, and mixed-stage examples. Each row contains a grader brief, UI contract, candidate turn, six integer human scores, eight boolean flags, and severe/non-severe.

Tests require exact 20-row order and hashes, at least five severe and five non-severe rows, 90% severe agreement, and 80% within-one-point dimension agreement. Prove 89%/79% fail closed and no candidate grades are requested after failed calibration.

- [ ] **Step 2: Write failing absolute-rubric tests**

Require exact structured fields:

```python
RUBRIC_DIMENSIONS = (
    "chessCorrectness",
    "coachingJudgment",
    "latestActionResponsiveness",
    "discoveryAndIndependence",
    "coherenceAndAnswerability",
    "childClarity",
)
RUBRIC_FLAGS = (
    "factualOrIllegalAdvice",
    "wrongUrgentPriority",
    "obsoleteStage",
    "mixedStages",
    "answerRevealingGuidance",
    "unavailableUIOrDeadEnd",
    "severeError",
)
```

Mechanical-invalid records must be emitted as automatic unusable grades with no judge call. Valid records get six scores from 1-5, flags, and bounded evidence. Reject unknown fields, missing evidence, identity leakage, malformed judge output, and unbounded strings.

- [ ] **Step 3: Write failing blinded pairwise tests**

Comparison mode pairs candidate and baseline by case, step, and repetition. Use review seed `20260901` to choose A/B order. Assert identities, costs, latencies, prompts, and prior scores are absent. Valid beats invalid without a call; two invalid responses produce `unusableTie`; two valid responses require strict A/B/tie output and bounded evidence.

- [ ] **Step 4: Implement judge prompt, schemas, calibration, and grading**

The judge system prompt defines the six rubric anchors and prioritizes correctness and interaction continuation over prose preference. The user payload contains only the grader brief, deterministic current request summary, available UI response contract, and anonymized response(s). Persist prompt/schema/config hashes and sanitized structured grades, not rendered judge prompts or provider reasoning.

Track judge usage, latency, and estimated cost in separate `judgeMetrics`; never add it to candidate product metrics.

- [ ] **Step 5: Run grader tests GREEN and commit**

```bash
git add Tools/CoachingEval/benchmark/grader.py \
  Tools/CoachingEval/benchmark/judge-v1.md \
  Tools/CoachingEval/benchmark/judge-calibration-v1.jsonl \
  Tools/CoachingEval/tests/test_benchmark_grader.py
git commit -m "feat: automatically grade coaching quality"
```

---

### Task 5: Aggregate quality, latency, reliability, and cost

**Files:**
- Create: `Tools/CoachingEval/benchmark/report.py`
- Create: `Tools/CoachingEval/tests/test_benchmark_report.py`

**Interfaces:**
- Produces: `build_report(run_root: Path, grade_root: Path, price_table: PriceTable) -> dict` and `write_report(..., destination: Path) -> tuple[Path, Path]` for `aggregate.json` and `summary.md`.

- [ ] **Step 1: Write failing aggregate tests**

Use a fixed synthetic two-configuration run to assert provider success, mechanical validity, severe rate, six dimension distributions, all-six-at-least-4 rate, pairwise W/L/T, category and initial/follow-up breakdowns, input/cached/reasoning/output totals, p50/p90 latency, retry counts, candidate cost, complete sequence cost, and separately labeled judge overhead.

- [ ] **Step 2: Write failing confidence and Pareto tests**

Implement paired bootstrap resampling by group ID with 10,000 draws and seed `20260901`. Assert byte-identical confidence intervals across reruns. A configuration is Pareto-dominated only when another is no worse in strong-response rate, severe-error rate, p90 latency, and candidate cost, and strictly better in at least one. Never average these into one score.

- [ ] **Step 3: Implement strict artifact verification and aggregation**

Before aggregation, verify every manifest hash, exact record/grade ID equality, baseline pairing, calibration pass, complete requested matrix, and price coverage. Incomplete runs may produce a diagnostic report but set `promotionEligible` to false and list exact missing/blocked cells.

Eligibility requires no new mechanical failure category, severe rate no higher than baseline, pairwise wins greater than losses, and a higher all-six-at-least-4 rate. This remains advisory text, not a process exit code.

- [ ] **Step 4: Render concise Markdown**

The report begins with the experiment change set and decision summary, followed by quality, reliability, latency, candidate cost, judge overhead, category breakdown, Pareto frontier, confidence intervals, and worst-case examples. It links each example to its local transcript path and never exposes the review's blinded ordering key in the public section.

- [ ] **Step 5: Run report tests GREEN and commit**

```bash
git add Tools/CoachingEval/benchmark/report.py \
  Tools/CoachingEval/tests/test_benchmark_report.py
git commit -m "feat: report coaching benchmark tradeoffs"
```

---

### Task 6: Add one-command operation and documentation

**Files:**
- Create: `Tools/CoachingEval/benchmark/cli.py`
- Create: `Tools/CoachingEval/tests/test_benchmark_cli.py`
- Create: `scripts/run_coaching_quality_benchmark.sh`
- Modify: `Tools/CoachingEval/README.md`

**Interfaces:**
- `python3 -m Tools.CoachingEval.benchmark.cli run|grade|report ...`
- `./scripts/run_coaching_quality_benchmark.sh quick [candidate-config ...]`
- `./scripts/run_coaching_quality_benchmark.sh comparison [candidate-config ...]`

- [ ] **Step 1: Write failing CLI and launcher tests**

Drive `cli.main(argv)` with fake providers and a fake judge. Assert exit codes, no overwrite, explicit holdout opt-in, exact configuration list, no credentials in stdout/artifacts, and report path output. For the shell launcher, fake `security`, `xcodebuild`, and Python; assert one corpus export, one candidate run, one grade, one report, cleanup on interruption, and actionable missing-Keychain guidance.

- [ ] **Step 2: Implement CLI subcommands**

`run` accepts corpus, mode, candidate config paths, output, API-key environment variable name, and optional `--include-holdout`. `grade` accepts exact run, corpus, judge config, pricing, output, and key environment variable name. `report` is offline and accepts exact run, grades, pricing, and destination. Each command prints one bounded JSON summary and never prints prompts, responses, or keys.

- [ ] **Step 3: Implement the launcher**

The launcher reads Keychain service `ChessTutor-CoachingEval-OpenAI`, exports a
fresh corpus under `.coaching-eval/benchmark/corpus/${SOURCE_SHA}-${RUN_TIMESTAMP}`,
writes runs beneath `.coaching-eval/benchmark/runs/${RUN_TIMESTAMP}`, and
invokes the CLI serially. It defaults to production config plus any supplied
candidate configs and leaves artifacts intact on success. It never stores the
key in a file or command-line argument.

- [ ] **Step 4: Document workflows and interpretation**

Add exact commands for quick development, comparison, explicit holdout, report-only regeneration, adding a deterministic generator registry entry, updating pinned prices, and promoting a production trace into a fixture. Explain quality columns, candidate-versus-judge costs, Pareto frontier, and why provider calls are not in PR CI.

- [ ] **Step 5: Run CLI tests GREEN and commit**

```bash
git add Tools/CoachingEval/benchmark/cli.py \
  Tools/CoachingEval/tests/test_benchmark_cli.py \
  scripts/run_coaching_quality_benchmark.sh Tools/CoachingEval/README.md
git commit -m "feat: add coaching benchmark workflow"
```

---

### Task 7: Verify the complete benchmark and perform a bounded live smoke

**Files:**
- Modify only if verification exposes an in-scope defect.
- Create ignored artifacts under `.coaching-eval/benchmark/`; commit none of them.

**Interfaces:**
- Consumes all prior task outputs.
- Produces final verification evidence and one real-provider smoke report over a small explicit development subset; it does not run the full paid comparison matrix.

- [ ] **Step 1: Export the corpus twice and compare bytes**

Run the selected XCTest with two fresh output directories. Require 40 independent groups, 10 sequences, 70 turns, 56 development turns, 14 holdout turns, matching manifests/hashes, and `diff -r` success.

- [ ] **Step 2: Run focused and full Python tests**

```bash
python3 -B -m unittest \
  Tools.CoachingEval.tests.test_benchmark_corpus \
  Tools.CoachingEval.tests.test_benchmark_configuration \
  Tools.CoachingEval.tests.test_benchmark_runner \
  Tools.CoachingEval.tests.test_benchmark_grader \
  Tools.CoachingEval.tests.test_benchmark_report \
  Tools.CoachingEval.tests.test_benchmark_cli -v
python3 -B -m unittest discover -s Tools/CoachingEval/tests -v
python3 -B -m unittest discover -s CoachingServer/tests -v
```

Require 0 failures and 0 skipped tests.

- [ ] **Step 3: Run proportional iPad verification**

Run the new corpus tests plus existing neutral request builder, chess-native compiler, and response validator suites. Require 0 failures and 0 skipped tests.

- [ ] **Step 4: Run a real provider/judge smoke**

Use the Keychain-backed launcher in a test-only `--smoke-case` mode limited to one quiet case, one danger case, and the three turns of one sequence. This diagnostic mode must be clearly marked incomplete and never promotion-eligible. Verify candidate calls, calibration, absolute grades, pairwise logic where applicable, usage, latency, separate judge cost, transcript links, secret scans, and report regeneration without provider access.

- [ ] **Step 5: Final audits**

Run `python3 -m py_compile` over the new modules, `git diff --check`, JSON parsing over every tracked JSON/JSONL file, `rg` scans for API key patterns/provider reasoning/hidden holdout output, and `git status --short`. Confirm ordinary CI contains no inference command.

- [ ] **Step 6: Commit verification fixes and prepare the PR**

Commit only tracked source, tests, docs, spec, and plan. Leave `.coaching-eval` evidence ignored. Push `codex/coaching-quality-benchmark`, open a PR against `codex/chess-coaching-comparison`, leave auto-merge disabled, and report the PR plus the smoke report path for product review.

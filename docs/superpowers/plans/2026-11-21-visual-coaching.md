# Visual Coaching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let concise coaching point at the playable board, with tappable references, directional arrows and an understandable, escapable answer interaction.

**Architecture:** Add a versioned structured-message contract alongside the existing v13 path. The native session owns local reference/replay and answer state; SwiftUI renders it through the existing board geometry and panel. Server and benchmark share the same visual contract validation and prompt compiler.

**Tech Stack:** Swift/SwiftUI/XCTest; Python/Flask/unittest; existing hosted model and benchmark tooling. No new runtime dependencies.

**Spec:** `docs/superpowers/specs/2026-11-21-visual-coaching-design.md`

## Global Constraints

- No mode headings, pill above the board, or repeated instructions below it.
- Complete readable message: at most 256 Unicode code points; 1–9 typed runs, at most two linked references, zero or one arrow.
- References use the displayed board; canonical move validation uses the committed board.
- Replay/reference taps never select a chess piece, alter the draft, mutate the coaching conversation, or start a network request.
- Keep v3/v13 unchanged for the installed app; new clients opt into v4/v14.
- Preserve calm language, learner agency, no discovery-answer spoilers, 44-point link hit areas, Dynamic Type, VoiceOver, Reduce Motion and all four board angles.
- No paid calls without a newly agreed cap; all deterministic tests use fake providers.
- Do not merge PR #27, deploy production, or install on Family iPad without authorization.

## Review Focus

1. A displayed knight is no longer at its committed origin: link the visible piece and render a revision, not an impossible second move (Tasks 1, 3, 4).
2. A new answer/drag/Play instead arrives before a reply or animation expiry: stale work must not overwrite newer focus, draft or interaction (Task 3).
3. A discovery response uses a linked phrase to reveal its own answer: references are subject to the same spoiler rules as arrows (Tasks 1, 5).
4. Rotated/large-text/VoiceOver UI makes links inaccessible or changes arrow direction: use existing transforms, semantic elements and explicit UI coverage (Task 4).
5. Installed v3 clients and v4 clients use the same server: neither receives the other's contract or continuation context (Task 2).

## Baseline and working directory

Worktree: `/Users/jason/.codex/worktrees/visual-coaching/chess`.
Branch: `codex/visual-coaching`, based on fetched main `511703f` (PR #26).
PR #27 was still open when the plan was written. Keep this work independent;
rebase after its authorized merge, then verify combined scheduling behavior.

- [ ] Read the spec and applicable implementation/test skills. Run baseline Python and native tests using the final verification commands below before product edits; report any pre-existing failures.
- [ ] Use Xcode's existing synchronized project/source conventions; verify any new Swift files are in the app/test target (inspect `project.yml` and the checked-in project, do not regenerate unrelated project settings).

## Task 1: Structured visuals with shared validation fixtures

**Files:**
- Create `ChessTutor/Coaching/ModelEvaluation/ModelCoachingVisualContracts.swift` and `ModelCoachingVisualTurnValidator.swift`.
- Modify `ModelCoachingChessNativeContracts.swift` only to carry optional validated visual content for v14 consumers; preserve all v13 decoding/initializers.
- Create `Tools/CoachingEval/visual_response.py` and `fixtures/visual-coaching-validation-v1.json`.
- Create `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingVisualTurnTests.swift` and `Tools/CoachingEval/tests/test_visual_response.py`.

**Interfaces:**
- `ModelCoachingVisualMessageRun`: `.text(String)`, `.piece(text: String, square: String)`, `.square(text: String, square: String)`; explicit Codable tags/keys from the spec.
- `ModelCoachingVisualCue`: `.attack(from: String, to: String)` / `.move(from: String, to: String)`.
- `ModelCoachingVisualContent(runs: [ModelCoachingVisualMessageRun], visuals: [ModelCoachingVisualCue])`, with computed `plainText: String`.
- `ModelCoachingVisualTurnDecoder.decodeAndValidate(_: Data, request: ModelCoachingNeutralRequest) throws -> ModelCoachingChessNativeTurn` produces the existing internal turn plus `visualContent`; legacy `message` is derived from runs, not separately supplied on the wire.
- Python `VisualResponseContract.from_request(request)`, `.json_schema()`, `.parse_and_validate(candidate)`, `.plain_text(turn)` are used by both server and benchmark. Keep v13 `ChessNativeResponseContract` unchanged.

- [ ] Add shared JSON acceptance/rejection fixtures. Assert valid linked threat, square reference and knight hint; 256-code-point boundary; unknown/duplicate keys; off-board and empty piece reference; more than two references; second arrow; reversed/nonexistent attack; unavailable move; invalid expected action; and v13 fixture compatibility. Run these tests red.
- [ ] Add staged fixtures with g1-h3: piece reference `h3` passes, `g1` fails, move cue `g1-f3` passes if legal from committed state, `h3-f3` fails. Add captured/en-passant/promotion displayed-piece fixtures using native-generated inputs.
- [ ] Add discovery fixtures: ordinary questions reject all references/visuals; explicit Hint permits only one source-piece clue of the spec's permitted color. Destination/square links and any arrow fail in either discovery state. Full reveal changes `expects` rather than weakening the rule.
- [ ] Implement exact-shape decoding, code-point limits and validation against supplied pieces/relationships/moves. Distinguish committed and tentative facts. Never infer targets by parsing model prose. Keep semantic label correctness for grading, not a pseudo-NLP validator.
- [ ] Run Python and Swift fixture tests green; confirm both accept/reject the same fixture IDs and legacy v13 tests still pass. Commit this task.

## Task 2: Versioned server, transport and pinned prompt

**Files:**
- Modify `CoachingServer/service.py`, `http_app.py`, `model_configuration.py`, `chess_native_compiler.py` and relevant tests.
- Create `CoachingServer/visual_compiler.py`, `versioned_service.py`, `configs/visual-v1.json`.
- Create `Tools/CoachingEval/prompts/tutor-v14-visual-v1.md`.
- Modify `ChessTutor/Coaching/Hosted/HostedCoachingTransport.swift` and its transport tests.
- Modify `CoachingServer/local.py` and deployment/runbook config only where required to configure both paths; do not deploy.

**Interfaces:**
- `compile_visual_context(request, prompt_version)` and `compile_visual_follow_up_context(request, prompt_version)` retain compact deterministic chess context and add the visual vocabulary/current display facts. Register as `chess-visual-grounded-v1` → `tutor-v14`.
- `VersionedHostedCoachingService(legacy, visual).complete(...)` preserves the existing service call signature; routes exact envelope versions to pinned configurations before provider invocation.
- New transport sends `hosted-coaching-request.v4`, accepts only `hosted-coaching-turn.v4` / `tutor-v14`, and calls Task 1's decoder with the original request. Existing v3 server path remains strict.

- [ ] Write fake-provider tests for v3→v13, v4→v14, unknown version→400 without a provider call, wrong-version response rejection, bad references→bounded existing failure, and unchanged timeout/status/byte-limit handling. Run red.
- [ ] Preserve the v13 prompt/config bytes and tests. Create the v14 prompt by retaining the established coaching philosophy and replacing only output/visual/interaction guidance. Require an explicit tap instruction in a discovery question; no separate heading or redundant text layer. Explain direct draft revisions and local linked-word behavior.
- [ ] Give visual configuration an independently pinned SHA and the current model/reasoning/token/time settings from `production-v2.json`. Validate prompt-generator/contract pairing. Avoid changing model quality and visual behavior simultaneously.
- [ ] Implement routing and transport. A v4 help episode starts with no v3 continuation; version-switch tests assert continuation reset. Do not retry paid requests as a compatibility probe. Keep correlation IDs and compact logs; flatten message for readers while retaining structured visual content and contract/config identifiers.
- [ ] Run service, HTTP, config, logging and native transport tests green, including old request fixtures. Commit.

## Task 3: Local focus and answer/play state

**Files:**
- Modify `ChessTutor/Coaching/Hosted/HostedCoachingSession.swift`, `HostedCoachingPresentationProjector.swift`, `ChessTutor/Coaching/CoachingModels.swift`, `ChessTutor/Game/GameSession.swift`.
- Extend `ChessTutorTests/Coaching/Hosted/HostedCoachingSessionTests.swift`, `HostedCoachingPresentationProjectorTests.swift`, `HostedGameSessionIntegrationTests.swift`.

**Interfaces:**
- Add optional `visualContent` to `CoachingPresentation` with a legacy-safe default; `primaryMessage` remains the flattened text.
- Add `GameSession.replayCoachingReference(at runIndex: Int)` and `replayCoachingVisual()` for local presentation-only events. Resolve run indexes only against the currently displayed turn.
- Add `GameSession.playInsteadOfAnswering()`; session stores a per-turn play override, response generation token, and local focus replay identity. No new model-authored action string is needed for local controls.
- Project a board-answer interaction indicator separately from model prose; accessibility gets “Tap a piece to answer the coach” without duplicating visible copy.

- [ ] Write recording-provider tests: reference/replay actions leave provider count, continuation ID, event history, selected square and tentative move unchanged; repeated references replay locally and a stale expiry cannot clear newer focus. Run red.
- [ ] Test answer tap acknowledgement before provider completion, correct and incorrect answers, no-op empty taps, rapid answers keeping answer semantics, drag superseding an answer, Play instead while pending, and reply arrival after game switch/close-help. Assert stale replies cannot restore answer mode.
- [ ] Test Play instead preserves board/draft, removes question-specific visuals, shows “Try a move on the board.”, restores ordinary tap-to-move, and issues zero requests until a real move. Keep local controls distinct from “Try another move”, which clears a draft.
- [ ] Implement session-owned state and pure projection. Resolve displayed-piece references from tentative facts. For a legal canonical draft revision, project arrow source from the moved piece's displayed location and mark geometry as relocation rather than knight movement.
- [ ] Clear replay state on response replacement, draft/board revision, help closure, game switch and cancellation. Preserve check and illegal-move guards. Use identity-scoped animation expiry; no timer may mutate chess state.
- [ ] Run focused session/projector/integration tests green. After PR #27 is merged and rebased, extend its fake-clock tests to assert latest-answer debounce, stale response invalidation and local-reference diagnostic events with zero requests. Commit.

## Task 4: Native linked text, arrows and sparse answer affordance

**Files:**
- Create `ChessTutor/UI/Coaching/CoachingMessageView.swift` and `ChessTutor/UI/Board/CoachArrowGeometry.swift`.
- Modify `CoachingPanelView.swift`, `ChessTutor/UI/Board/CoachFocusOverlay.swift`, `ChessBoardView.swift` and theme values only as needed.
- Extend `ChessTutorTests/UI/CoachFocusOverlayTests.swift`, `CoachingPanelLayoutTests.swift`, `ChessTutorUITests/CoachingPanelAccessibilityUITests.swift`.
- Add deterministic visual cases to `ChessTutor/App/CoachingPanelAccessibilityFixture.swift` and `ChessTutorUITests/VisualCoachingUITests.swift`.

**Interfaces:**
- `CoachingMessageView(content:onReference:)` renders Task 1's runs with real accessible link/button activation; no arbitrary URL navigation or raw Markdown.
- `CoachArrowGeometry.make(source: Square, destination: Square, kind: Kind, geometry: BoardGuidanceGeometry) -> CoachArrowGeometry` yields polyline points and arrowhead vertices; `Kind` is `.direct`, `.knight`, `.relocation`. All coordinates are derived from the board transform.
- Overlay receives session presentation only; reference activation delegates to Task 3 methods.

- [ ] Add geometry assertions for source/target direction in all four board orientations, straight ray, knight L, adjacent square, zero-length rejection and draft relocation. Test arrow head stopping before the target piece and paths remaining within the board. Run red.
- [ ] Render underlined references with existing piece artwork; no image for an empty square. Wrap like prose, retain spaces and punctuation, use 44-point hit areas, and ensure adjacent targets do not overlap. Preserve current body type and panel composition.
- [ ] Render one high-contrast arrow plus bounded piece/square emphasis above pieces where needed for visibility, with non-hit-testing overlays. Suppress unrelated coaching/coverage clutter but retain check and legal-commit warnings. Introduce/replay with short finite motion; static Reduce Motion alternative.
- [ ] Add a quiet plum board-edge treatment only for answer mode, neutral immediate selected-answer feedback, local Play instead, and Replay only when there is a visual. Do not add the mockup's review tabs, explanatory footer, mode label or board pill.
- [ ] UI tests: link spotlight does not select/move; answer tap followed by drag works; Play instead restores taps; no extra headings; both panel orientations and accessibility text size work; VoiceOver exposes links in reading order despite the panel's accessibilityRepresentation; Reduce Motion retains visible information.
- [ ] Run focused tests green, capture real native screenshots for question, linked explanation, hint arrow and pending answer in both layouts, and inspect them before committing. Test the displayed-draft hint, not just an initial board. Commit.

## Task 5: Repeatable visual-quality evaluation

**Files:**
- Create `ChessTutorTests/Coaching/ModelEvaluation/CoachingVisualBenchmarkTests.swift` and native-generated export path.
- Modify `Tools/CoachingEval/benchmark/{configuration,runner,grader,experience_metrics,report,corpus}.py` and their existing unit tests.
- Create `Tools/CoachingEval/benchmark/configs/astra-visual-v1-low.json`, `judge-visual-v1.json` (sensitivity controls), and `visual_metrics.py`.
- Extend `scripts/run_coaching_regressions.sh` with an explicit visual export/evaluation option; document it in `Tools/CoachingEval/README.md`.

**Interfaces:**
- `CoachingVisualBenchmark.corpus() throws -> CoachingQualityBenchmarkCorpus`, manifest `coaching-quality-visual-regression-manifest.v1`.
- `VisualMetrics.summarize(records)` reports mechanical visual validity, coordinate mentions, linked-reference counts, arrow usage and unavailable-capability baseline fields separately from judge quality scores.
- Both runner and service instantiate Task 1's same `VisualResponseContract`; graders receive readable joined text plus exact references/arrows/expected interaction. Reports keep the original turn unchanged.

- [ ] Add eight deterministic case groups: plain opening Help; two-knight threat question then answer; source-only requested hint; full requested move hint; g1-h3→g1-f3 draft revision; useful empty-square reference; defended target explanation; opening flank-pawn tradeoff. Include both colors and legal history where available. Assert no grader briefs leak into candidate prompts.
- [ ] Add negative controls for a wrong same-kind piece, reversed attack arrow, stale-origin link, arrow revealing a discovery answer, coordinate-heavy unnecessary prose, and a mandatory button detour. Pair each with a good response; do not grade links as automatically better when plain words suffice.
- [ ] Write runner/grader/report tests red: visual payload survives all artifacts; flat text is derived correctly; continuation transcripts retain reference meaning; v13 baseline remains valid under its own schema; latency/cost includes failed calls; visual schema validation is identical to server validation.
- [ ] Implement the version-specific contract factory in the runner, structured judge input and metrics. Reuse frozen existing judge dimensions; version any changed judge prompt/control bindings and rerun sensitivity qualification when required. Never relabel an unqualified result as passing.
- [ ] Add a no-paid-calls dry run/export path and documented one-command opt-in run. Use a shared durable budget journal, reject missing/invalid explicit cost cap, retain progress and do not replay completed calls on resume. Add tests for this launcher behavior.
- [ ] Run native corpus and Python benchmark tests green; export and inspect complete prompts locally. Commit. Paid comparison/grading waits for a fresh cap, starts with the targeted suite, then uses existing broader regression gates; no claim of live quality improvement based only on fake responses.

## Task 6: Combined verification and review handoff

- [ ] Run all relevant suites without skipped/failing tests:

```bash
python3 -m unittest discover -s CoachingServer/tests -v
python3 -m unittest discover -s Tools/CoachingEval/tests -v
xcodebuild test -project ChessTutor.xcodeproj -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=ChessTutor Coaching Smoke'
git diff --check
```

- [ ] Rebase onto current main after the user has merged #27; resolve only this feature's integration changes and rerun request-scheduling tests. Verify rapid answering plus a drag keeps only the latest relevant request, while links/replay/Play instead produce no provider calls.
- [ ] Smoke-test v3 and v4 HTTP routes using fake providers and native v4 UI; inspect captured diagnostics for readable text, exact visual mapping, game/episode IDs and stale-response handling. Keep auth secrets and full system prompts out of user-facing traces.
- [ ] Update `docs/hosted-coaching-server.md`, handoff and a concise implementation report with actual tests/screenshots, known limitations, eval evidence or pending paid validation, and safe server-first rollout instructions.
- [ ] Obtain independent whole-branch review; address findings, rerun affected tests, push and create one PR. Leave it open with auto-merge disabled. No production or family-device rollout in this task.

## Execution handoff

Recommended execution: native implementation in this chat, with one independent
whole-branch review. The wire contract, session state and renderers are tightly
connected, so serial implementation avoids competing interface changes. The
design is approved; this task plan is ready for review before implementation.

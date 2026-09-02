# Hosted Coaching Structured Logs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Emit production-safe JSONL coaching traces correlated by game, Help episode, and HTTP request, with the current game identifier accessible from About.

**Architecture:** The client owns durable game/episode lifetimes and sends their UUIDs only in a v3 hosted transport envelope. A focused Python logging module serializes all server application events as versioned JSON. The service returns a safe diagnostics projection alongside the public response (or attaches it to stable failures), allowing the HTTP boundary to emit exactly one canonical success/failure `coaching_turn` record with the final status and elapsed time.

**Tech Stack:** Swift 6, Observation, SwiftUI/UIKit, Foundation UUID/JSONEncoder, Python 3 standard logging/JSON/dataclasses, Flask 3.1.3, unittest, XCTest/XCUITest.

## Global Constraints

- Do not add a database, durable trace API, third-party logging dependency, in-app trace viewer, or production-log downloader.
- `game_id`, `episode_id`, and `trace_id` have the exact lifetimes defined by the approved design.
- Correlation identifiers never enter the model-facing prompt.
- Every `ChessTutor.CoachingServer` record is one `coaching-log.v1` JSON object on one physical line.
- Emit exactly one canonical `coaching_turn` record for each authenticated JSON request that enters the service, including failure paths.
- Never log credentials, prompts, verbose mechanical arrays, provider/continuation IDs, model reasoning, raw invalid responses, HTTP bodies, or exception messages.
- Preserve the current HTTP response contract, provider settings, prompt version `tutor-v13`, and coaching behavior.

---

### Task 1: JSONL Logging Boundary

**Files:**
- Create: `CoachingServer/structured_logging.py`
- Create: `CoachingServer/tests/test_structured_logging.py`
- Modify: `CoachingServer/local.py`
- Modify: `api/index.py`

**Interfaces:**
- Produces: `emit_event(event: str, *, level: int = logging.INFO, **fields: object) -> None`.
- Produces: `configure_application_logging(*, suppress_werkzeug: bool) -> None`.
- Consumes: only JSON-compatible bounded values selected by server code.

- [ ] **Step 1: Write failing JSONL tests**

Add tests which patch the UTC timestamp helper, attach a recording handler to `ChessTutor.CoachingServer`, call:

```python
emit_event(
    "provider_request_started",
    trace_id="trace-1",
    game_id="11111111-1111-4111-8111-111111111111",
    episode_id="22222222-2222-4222-8222-222222222222",
    model="gpt-5.6-sol",
)
```

and assert `json.loads(record.getMessage())` equals one object containing the four common fields before the supplied fields. Assert newline-containing text remains escaped inside the one physical line, reserved common-field overrides and non-finite numbers are rejected, local configuration formats only `%(message)s`, and `suppress_werkzeug=True` disables the duplicate access logger.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
.venv/bin/python -B -m unittest CoachingServer.tests.test_structured_logging -v
```

Expected: import failure because `CoachingServer.structured_logging` does not exist.

- [ ] **Step 3: Implement the minimal logger**

Create the module with:

```python
LOG_SCHEMA_VERSION = "coaching-log.v1"

def emit_event(event: str, *, level: int = logging.INFO, **fields: object) -> None:
    payload = {
        "schema_version": LOG_SCHEMA_VERSION,
        "timestamp": _utc_timestamp(),
        "level": logging.getLevelName(level).lower(),
        "event": event,
        **fields,
    }
    _LOGGER.log(
        level,
        json.dumps(payload, ensure_ascii=False, separators=(",", ":"), allow_nan=False),
    )
```

Validate event/common-field ownership before serialization. Configure root output only when needed, set the named logger to INFO, and disable `werkzeug` only for the local development entrypoint. Call configuration before creating the app in both entrypoints.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the Step 2 command. Expected: all structured-logging tests pass with zero skips.

- [ ] **Step 5: Commit Task 1**

```bash
git add CoachingServer/structured_logging.py CoachingServer/tests/test_structured_logging.py CoachingServer/local.py api/index.py
git commit -m "feat: emit hosted coaching JSON logs"
```

### Task 2: Client Correlation Lifetimes And Envelope v3

**Files:**
- Modify: `ChessTutor/Coaching/Hosted/HostedCoachingContracts.swift`
- Modify: `ChessTutor/Coaching/Hosted/HostedCoachingSession.swift`
- Modify: `ChessTutor/Coaching/Hosted/HostedCoachingTransport.swift`
- Modify: `ChessTutor/Game/GameSession.swift`
- Modify: `ChessTutorTests/Coaching/Hosted/HostedCoachingTransportTests.swift`
- Modify: `ChessTutorTests/Coaching/Hosted/HostedGameSessionIntegrationTests.swift`
- Modify: `ChessTutor/App/CoachingPanelAccessibilityFixture.swift`

**Interfaces:**
- Produces: `HostedCoachingCorrelation` with `gameID: String` and `episodeID: String`.
- Changes: `HostedCoachingTurning.turn(for:contract:continuationID:correlation:)`.
- Produces: exact `hosted-coaching-request.v3` wire fields `schemaVersion`, `gameID`, `episodeID`, `request`, and `previousResponseID`.
- Produces: stable private game/episode correlation state in `GameSession` and `HostedCoachingSession`.

- [ ] **Step 1: Write failing identifier and wire tests**

Add tests proving:

```swift
let correlation = HostedCoachingCorrelation(
    gameID: "11111111-1111-4111-8111-111111111111",
    episodeID: "22222222-2222-4222-8222-222222222222"
)
```

is encoded in the exact v3 envelope while the nested neutral request is unchanged. Add GameSession tests with an injected identifier sequence proving requests in one Help episode share both IDs, reopening Help changes only `episodeID`, and `newGame()` changes `gameID`. Assert the IDs are lowercase canonical UUIDs under the default generator.

- [ ] **Step 2: Run selected XCTest cases and verify RED**

Run:

```bash
xcodebuild test -project ChessTutor.xcodeproj -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/HostedCoachingTransportTests \
  -only-testing:ChessTutorTests/HostedGameSessionIntegrationTests
```

Expected: compile failures because correlation and the new protocol argument do not exist.

- [ ] **Step 3: Implement identifiers and protocol propagation**

Add:

```swift
struct HostedCoachingCorrelation: Codable, Equatable, Sendable {
    let gameID: String
    let episodeID: String
}
```

Give `GameSession` an injectable `coachingIdentifierFactory: () -> String` whose default is `UUID().uuidString.lowercased()`. Generate the game ID at initialization and New Game, generate the episode ID in `startCoaching()`, store both in each pending hosted request, and pass them through every provider implementation. Update test/fixture providers without changing their behavior.

- [ ] **Step 4: Implement the v3 wire envelope**

Change `HostedCoachingWireRequest` to encode all five exact fields and update strict transport tests. Do not add either identifier to `ModelCoachingNeutralRequest`, compiler input, or model prompt.

- [ ] **Step 5: Run selected tests and verify GREEN**

Run the Step 2 command. Expected: all selected tests pass with zero failures/skips.

- [ ] **Step 6: Commit Task 2**

```bash
git add ChessTutor/Coaching/Hosted ChessTutor/Game/GameSession.swift \
  ChessTutorTests/Coaching/Hosted ChessTutor/App/CoachingPanelAccessibilityFixture.swift
git commit -m "feat: correlate hosted coaching sessions"
```

### Task 3: Server Envelope And Correlated Lifecycle Events

**Files:**
- Modify: `CoachingServer/service.py`
- Modify: `CoachingServer/http_app.py`
- Modify: `CoachingServer/tests/test_service.py`
- Modify: `CoachingServer/tests/test_http_app.py`

**Interfaces:**
- Changes: `_parse_envelope(...) -> tuple[Mapping[str, object], str | None, str, str]` returning request, continuation, normalized game ID, and normalized episode ID.
- Consumes: `emit_event` from Task 1.
- Produces: JSON lifecycle events carrying validated `game_id`, `episode_id`, and `trace_id` after envelope parsing.

- [ ] **Step 1: Write failing v3 and correlation tests**

Replace test fixtures with canonical UUIDs and assert exact v3 fields. Add malformed, uppercase, missing, and extra identifier cases which produce `invalidRequest` before provider invocation. Parse every captured lifecycle message with `json.loads`; assert common fields and all three identifiers are present after compilation, and prompt/provider arguments contain neither UUID.

- [ ] **Step 2: Run server service/HTTP tests and verify RED**

Run:

```bash
.venv/bin/python -B -m unittest \
  CoachingServer.tests.test_service \
  CoachingServer.tests.test_http_app -v
```

Expected: failures because the server accepts only v2 and emits logfmt strings.

- [ ] **Step 3: Implement strict correlation parsing**

Advance `_ENVELOPE_FIELDS` and schema version, validate IDs with `uuid.UUID`, require their lowercase canonical string forms, and return them separately from the model request. Add a safe HTTP-boundary extractor which includes identifiers only when both strings independently pass the same canonical test.

- [ ] **Step 4: Convert lifecycle events to JSONL**

Replace direct `_LOGGER.info(...)` calls with `emit_event(...)`. Keep the existing event names and bounded fields, change nested/public field names to snake case, and attach the correlation fields at every boundary where they are known. Emit provider/service failures at warning level without exception or body text.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run the Step 2 command. Expected: all tests pass with zero failures/skips.

- [ ] **Step 6: Commit Task 3**

```bash
git add CoachingServer/service.py CoachingServer/http_app.py \
  CoachingServer/tests/test_service.py CoachingServer/tests/test_http_app.py
git commit -m "feat: correlate hosted coaching server logs"
```

### Task 4: Canonical Success And Failure Turn Records

**Files:**
- Modify: `CoachingServer/service.py`
- Modify: `CoachingServer/http_app.py`
- Modify: `CoachingServer/tests/test_service.py`
- Modify: `CoachingServer/tests/test_http_app.py`
- Modify: `CoachingServer/tests/test_dev_launcher.py`
- Modify: `scripts/run_hosted_coaching_dev.sh`

**Interfaces:**
- Produces: immutable `HostedCoachingCompletion(response, diagnostics)` from `HostedCoachingService.complete`.
- Changes: `HostedCoachingServiceError(code, diagnostics=None)` carries only a safe diagnostics projection.
- Produces: exactly one HTTP-boundary `coaching_turn` JSON object with `outcome`, `http_status`, `elapsed_ms`, compact request/response/provider objects, and identifiers.

- [ ] **Step 1: Write failing terminal-record tests**

Cover success, invalid request, timeout, unavailable provider, invalid provider JSON, invalid provider semantics, and unexpected service exception. For every case assert exactly one `event == "coaching_turn"`. On success assert the exact compact request/response/provider shape from the design. On failures assert `response is None`, stable outcome/status, retained safe context when compilation succeeded, and `request is None` when it did not.

Add adversarial secret strings to authorization, prompts, continuation/provider IDs, provider bodies, validation output, and exceptions; recursively scan all emitted JSON values to prove none survives.

- [ ] **Step 2: Run focused tests and verify RED**

Run the Task 3 Step 2 command. Expected: failures because only successful opt-in `coaching_trace` strings exist.

- [ ] **Step 3: Build the diagnostics projection**

Create a safe request summary from compilation and neutral request containing only request kind/ID/prompt version, position revision/FEN/move display notation/side/status, latest interaction, selected piece/square, and staged move. Create a provider summary only from fixed model/settings and bounded metrics. Return the validated response and projection in `HostedCoachingCompletion`; attach the available projection to stable service errors.

- [ ] **Step 4: Emit the canonical record at the HTTP boundary**

Use one helper to combine service diagnostics with final HTTP status and total elapsed time. Log successful records at INFO and failures at WARNING. Remove `log_content`, `_content_trace`, `CHESS_TUTOR_COACHING_LOG_CONTENT`, and launcher opt-in behavior because safe canonical traces are now always enabled in production and development.

- [ ] **Step 5: Run focused and complete server tests**

Run:

```bash
.venv/bin/python -B -m unittest discover -s CoachingServer/tests -v
```

Expected: 100% pass, zero skips. If loopback binding is sandbox-blocked, rerun the identical command with localhost permission.

- [ ] **Step 6: Commit Task 4**

```bash
git add CoachingServer scripts/run_hosted_coaching_dev.sh
git commit -m "feat: log canonical hosted coaching turns"
```

### Task 5: About-Sheet Diagnostic ID

**Files:**
- Modify: `ChessTutor/UI/Controls/GameControlsView.swift`
- Modify: `ChessTutor/UI/Root/ContentView.swift`
- Modify: `ChessTutorTests/Coaching/Hosted/HostedGameSessionIntegrationTests.swift`

**Interfaces:**
- Consumes: `GameSession.currentCoachingGameID` from Task 2.
- Changes: `AboutSheetView` accepts `coachingGameID: String?`.
- Produces: hosted-only `Copy Coaching Game ID` control which writes the exact string to `UIPasteboard.general`.

- [ ] **Step 1: Write the failing presentation test**

Assert a hosted `GameSession` exposes a non-nil current ID, a local-only session exposes nil, and New Game changes the hosted value. Preserve the transport-level lifetime assertions from Task 2.

- [ ] **Step 2: Run the selected integration test and verify RED**

Run the Task 2 Step 2 command. Expected: failures because `currentCoachingGameID` is absent.

- [ ] **Step 3: Add the About control**

Pass `session.currentCoachingGameID` from `ContentView`. In `AboutSheetView`, conditionally render:

```swift
Button {
    UIPasteboard.general.string = coachingGameID
} label: {
    Label("Copy Coaching Game ID", systemImage: "doc.on.doc")
        .frame(maxWidth: .infinity)
}
```

Use the existing bordered diagnostic-button styling and do not change the play surface.

- [ ] **Step 4: Run selected tests and build**

Run the Task 2 Step 2 command and then:

```bash
xcodebuild build -project ChessTutor.xcodeproj -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Expected: selected tests and build pass.

- [ ] **Step 5: Commit Task 5**

```bash
git add ChessTutor/UI ChessTutorTests/Coaching/Hosted
git commit -m "feat: expose coaching game diagnostic ID"
```

### Task 6: Full Verification, Documentation, And PR

**Files:**
- Modify: `README.md` only if the production/local logging workflow is otherwise undiscoverable.
- Modify: implementation files only for defects found by verification.

**Interfaces:**
- Consumes: Tasks 1–5.
- Produces: a reviewed branch and PR against `codex/chess-coaching-comparison`.

- [ ] **Step 1: Run Python verification**

Run both CI suites even if the first fails:

```bash
.venv/bin/python -B -m unittest discover -s CoachingServer/tests -v
.venv/bin/python -B -m unittest discover -s Tools/CoachingEval/tests -v
```

Expected: all tests pass with zero skips.

- [ ] **Step 2: Run full iPad verification**

Run:

```bash
xcodebuild test -project ChessTutor.xcodeproj -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)'
xcodebuild build -project ChessTutor.xcodeproj -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Expected: full scheme passes with zero failures/skips and standalone build succeeds.

- [ ] **Step 3: Run structural/privacy checks**

Parse captured representative success/timeout/invalid-response lines as JSON; assert one terminal event per trace and one game/episode grouping. Run `rg` to confirm removed logfmt/content-flag paths are gone, recursively scan fixture logs for injected secret markers, run `python -m py_compile` for modified Python files, and run `git diff --check`.

- [ ] **Step 4: Inspect local behavior**

Launch the normal development server/app, request Help and one follow-up, verify application records are one-line JSON, duplicate Werkzeug access messages are absent, game/episode lifetimes match the design, and About copies the same game ID shown in server records. Do not make a billable hosted provider call if a deterministic fake integration path can verify the boundary.

- [ ] **Step 5: Request code review and fix findings**

Review the complete diff against the approved design, with priority on correlation lifetime, exactly-once terminal logging, JSON validity, and redaction. Address any Critical or Important finding and rerun affected/full gates.

- [ ] **Step 6: Commit, push, and open the PR**

```bash
git add README.md ChessTutor ChessTutorTests CoachingServer api scripts \
  docs/superpowers/specs/2026-09-01-hosted-coaching-structured-logs-design.md \
  docs/superpowers/plans/2026-09-01-hosted-coaching-structured-logs.md
git commit -m "feat: add production coaching trace IDs"
git push -u origin codex/hosted-coaching-structured-logs
gh pr create \
  --base codex/chess-coaching-comparison \
  --head codex/hosted-coaching-structured-logs \
  --title "Add production coaching trace IDs" \
  --body $'## Summary\n- emit parseable JSONL coaching logs\n- correlate games, Help episodes, and HTTP requests\n- expose the current coaching game ID in About\n\n## Verification\n- CoachingServer unittest suite\n- CoachingEval unittest suite\n- full iPad test scheme\n- standalone iPad build'
```

Do not enable auto-merge. Leave the green PR for the user to review and merge.

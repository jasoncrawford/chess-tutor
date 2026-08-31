# Hosted Coaching Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in, end-to-end hosted coaching path in which the iPad sends structured chess facts to a portable local/Vercel server and presents one strictly validated GPT-5.6 Sol/high coaching turn.

**Architecture:** The iPad remains authoritative for chess rules and interaction events, while a stateless Python server validates the neutral request, renders `tutor-v6`, calls the Responses API, and validates the turn. `GameSession` owns hosted episode state and stale-response protection; the existing local coaching path remains unchanged when hosted mode is not configured.

**Tech Stack:** Swift 6, SwiftUI Observation, URLSession, Security/Keychain, Python 3.12 standard-library WSGI, Vercel Python Functions, OpenAI Responses API, XCTest, Python unittest.

## Global Constraints

- Use `gpt-5.6-sol` with `high` reasoning, 2,048 maximum output tokens, `store: false`, one attempt, no retry, and no repair.
- The app sends structured `model-coaching-neutral-request.v1` facts; the server owns both rendered prompts.
- Hosted failure never falls back to local coaching within a hosted session.
- No child identity, accounts, database, analytics, provider reasoning, raw provider body, or provider response ID.
- Every response is validated on the server and again on the device.
- Newer board interaction always supersedes older pending advice.
- Local coaching behavior and its tests remain unchanged when hosted configuration is absent.
- Deployment configuration is committed; deployment itself is out of scope.

---

### Task 1: Shared response contract and cross-language prompt parity

**Files:**
- Modify: `ChessTutor/Coaching/ModelEvaluation/ModelCoachingChessNativeContracts.swift`
- Modify: `ChessTutor/Coaching/ModelEvaluation/ModelCoachingChessNativeContextCompiler.swift`
- Modify: `ChessTutor/Coaching/ModelEvaluation/ModelCoachingChessNativeTurnValidator.swift`
- Modify: `Tools/CoachingEval/chess_native_response.py`
- Create: `CoachingServer/chess_native_compiler.py`
- Create: `Tools/CoachingEval/fixtures/chess-native-context-v1.json`
- Create: `Tools/CoachingEval/tests/test_chess_native_compiler.py`
- Modify: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingChessNativeContextCompilerTests.swift`

**Interfaces:**
- Produces Swift `ModelCoachingChessNativeResponseContract` with `availableActions` and `availableMoveFocus`.
- Produces Python `compile_context(request, prompt_version) -> ChessNativeCompilation`.
- Produces `ChessNativeResponseContract.json_schema()` for the hosted provider.

- [ ] **Step 1: Add failing Swift response-contract tests**

Add assertions that response-contract derivation is independent of Markdown rendering and matches the compiler:

```swift
let contract = ModelCoachingChessNativeContextCompiler.responseContract(for: request)
let compilation = ModelCoachingChessNativeContextCompiler.compile(request, promptVersion: "tutor-v6")
XCTAssertEqual(contract.availableActions, compilation.availableActions)
XCTAssertEqual(contract.availableMoveFocus, compilation.availableMoveFocus)
```

- [ ] **Step 2: Run the focused Swift test and observe RED**

Run:

```bash
xcodebuild test -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingChessNativeContextCompilerTests
```

Expected: compile failure because `ModelCoachingChessNativeResponseContract` and `responseContract(for:)` do not exist.

- [ ] **Step 3: Extract the Swift response contract**

Add:

```swift
struct ModelCoachingChessNativeResponseContract: Codable, Equatable, Sendable {
    let availableActions: [String]
    let availableMoveFocus: [ModelCoachingChessNativeMoveFocus]
}
```

Make `compile` call `responseContract(for:)`; keep full Markdown output byte-identical. Add validator overloads that accept the contract directly while retaining compilation overloads for existing callers.

- [ ] **Step 4: Add failing Python compiler/schema tests**

Create one committed fixture containing `request`, `expectedMarkdown`, `expectedActions`, and `expectedMoveFocus`. Test:

```python
compilation = compile_context(fixture["request"], "tutor-v6")
self.assertEqual(fixture["expectedMarkdown"], compilation.markdown)
self.assertEqual(tuple(fixture["expectedActions"]), compilation.actions)
self.assertEqual(tuple(map(tuple, fixture["expectedMoveFocus"])), compilation.allowable_moves)
self.assertEqual(False, response_contract.json_schema()["additionalProperties"])
```

- [ ] **Step 5: Run the Python tests and observe RED**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest \
  Tools.CoachingEval.tests.test_chess_native_compiler -v
```

Expected: import failure because `CoachingServer.chess_native_compiler` does not exist.

- [ ] **Step 6: Implement strict Python request parsing and rendering**

Create immutable `ChessNativeCompilation` and pure functions:

```python
@dataclasses.dataclass(frozen=True)
class ChessNativeCompilation:
    request_id: str
    position_revision: int
    markdown: str
    actions: tuple[str, ...]
    allowable_moves: tuple[tuple[str, str], ...]

def compile_context(request: Mapping[str, object], prompt_version: str) -> ChessNativeCompilation:
    parsed = parse_neutral_request(request)
    return ChessNativeCompilation(...)
```

Reject unknown/missing fields, wrong primitive types, invalid square/move identities, duplicate event sequences, and unsupported schema versions. Mirror the Swift section ordering and wording exactly.

- [ ] **Step 7: Add `json_schema()` to the shared Python response contract**

Move the request-specific schema construction from `run_hosted_chess_native_pilot._response_schema` into:

```python
def json_schema(self) -> dict:
    ...
```

Update hosted evaluator callers to use it without changing emitted schemas.

- [ ] **Step 8: Run focused parity tests GREEN**

Run the Swift command from Step 2 and:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest \
  Tools.CoachingEval.tests.test_chess_native_response \
  Tools.CoachingEval.tests.test_chess_native_compiler \
  Tools.CoachingEval.tests.test_run_hosted_chess_native_pilot -v
```

Expected: all selected tests pass; existing prompt bytes remain unchanged.

- [ ] **Step 9: Commit Task 1**

```bash
git add ChessTutor/Coaching/ModelEvaluation \
  ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingChessNativeContextCompilerTests.swift \
  CoachingServer Tools/CoachingEval
git commit -m "feat: share hosted coaching prompt contract"
```

---

### Task 2: Hosted coaching service domain

**Files:**
- Create: `CoachingServer/__init__.py`
- Create: `CoachingServer/service.py`
- Create: `CoachingServer/tests/__init__.py`
- Create: `CoachingServer/tests/test_service.py`
- Modify: `Tools/CoachingEval/openai_responses.py`
- Modify: `Tools/CoachingEval/tests/test_openai_responses.py`
- Read: `Tools/CoachingEval/prompts/tutor-v6.md`

**Interfaces:**
- Consumes `compile_context` and `ChessNativeResponseContract.json_schema()`.
- Produces `HostedCoachingService.complete(request) -> dict`.
- Receives a narrow provider dependency with the existing `complete(...)` signature.

- [ ] **Step 1: Write failing service tests**

Use a recording fake provider and assert the exact call:

```python
response = service.complete(request)
self.assertEqual("gpt-5.6-sol", provider.calls[0]["model"])
self.assertEqual("high", provider.calls[0]["reasoning_effort"])
self.assertEqual(2048, provider.calls[0]["maximum_output_tokens"])
self.assertEqual(expected_system_prompt, provider.calls[0]["system_prompt"])
self.assertEqual(expected_markdown, provider.calls[0]["user_prompt"])
```

Also cover invalid provider output, trace markers, request mismatch, and provider exceptions. Assert generic service error codes and absence of fake secret/body text.

- [ ] **Step 2: Run service tests and observe RED**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest CoachingServer.tests.test_service -v
```

Expected: import failure because `HostedCoachingService` does not exist.

- [ ] **Step 3: Implement the service**

Define:

```python
class HostedCoachingService:
    def __init__(self, *, provider, system_prompt: str, timeout: float = 30.0): ...
    def complete(self, request: Mapping[str, object]) -> dict: ...
```

Compile the request, invoke the provider exactly once, reject any non-completed or invalid output, parse through `ChessNativeResponseContract`, and return only the bounded response contract plus usage/latency metadata.

- [ ] **Step 4: Harden provider usage fields**

Ensure `OpenAIResponsesClient` continues to expose nested reasoning-token usage as a bounded integer and never returns raw provider errors, reasoning items, refusal bodies, or arbitrary output items. Add regression tests using the real Responses success-body shape.

- [ ] **Step 5: Run service and provider tests GREEN**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest \
  CoachingServer.tests.test_service \
  Tools.CoachingEval.tests.test_openai_responses -v
```

Expected: all tests pass with one provider call per successful service request.

- [ ] **Step 6: Commit Task 2**

```bash
git add CoachingServer Tools/CoachingEval/openai_responses.py \
  Tools/CoachingEval/tests/test_openai_responses.py
git commit -m "feat: add hosted coaching service"
```

---

### Task 3: Portable authenticated HTTP application

**Files:**
- Create: `CoachingServer/http_app.py`
- Create: `CoachingServer/local.py`
- Create: `CoachingServer/tests/test_http_app.py`
- Create: `api/index.py`
- Create: `.env.example`
- Create: `vercel.json`
- Create: `docs/hosted-coaching-server.md`

**Interfaces:**
- Produces `create_application(service, access_token) -> WSGI application`.
- Produces `python3 -m CoachingServer.local --host 127.0.0.1 --port 8787`.
- Exposes `GET /health` and `POST /v1/coaching-turn`.

- [ ] **Step 1: Write failing WSGI tests**

Drive the WSGI callable directly and assert:

```python
status, headers, body = invoke(app, "GET", "/health")
self.assertEqual("200 OK", status)
self.assertEqual({"status": "ok"}, json.loads(body))

status, _, body = invoke(app, "POST", "/v1/coaching-turn", token="wrong")
self.assertEqual("401 Unauthorized", status)
self.assertNotIn("expected-token", body)
```

Cover method rejection, content type, body-size limit, malformed JSON, constant-time token comparison through a patched spy, successful response, and redacted 400/502/504 errors.

- [ ] **Step 2: Run HTTP tests and observe RED**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest CoachingServer.tests.test_http_app -v
```

Expected: import failure because `CoachingServer.http_app` does not exist.

- [ ] **Step 3: Implement the WSGI controller and local CLI**

The WSGI controller performs only HTTP parsing/authentication and delegates to `HostedCoachingService`. Use `hmac.compare_digest`, a 128 KiB body limit, `application/json`, and canonical JSON responses. The CLI loads `OPENAI_API_KEY`, `CHESS_TUTOR_COACHING_ACCESS_TOKEN`, and optional host/port values, then serves the same app with `wsgiref.simple_server`.

- [ ] **Step 4: Add deployable entrypoint and infrastructure files**

`api/index.py` creates the WSGI application from environment variables. `vercel.json` rewrites `/health` and `/v1/coaching-turn` to the Python entrypoint and excludes iOS build/test artifacts from the function bundle. `.env.example` contains names only:

```dotenv
OPENAI_API_KEY=
CHESS_TUTOR_COACHING_ACCESS_TOKEN=
```

- [ ] **Step 5: Add a local/deployment runbook**

Document exact local start, health check, redacted request example, Vercel CLI deployment, and environment variable names. Do not include secret values or dashboard-only configuration.

- [ ] **Step 6: Run HTTP and importability tests GREEN**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest discover -s CoachingServer/tests -v
python3 -B -c 'import api.index; assert api.index.app is not None'
```

Expected: all tests pass and entrypoint import succeeds with test environment stubs.

- [ ] **Step 7: Commit Task 3**

```bash
git add CoachingServer api .env.example vercel.json docs/hosted-coaching-server.md
git commit -m "feat: expose hosted coaching server"
```

---

### Task 4: Swift hosted transport and private configuration

**Files:**
- Create: `ChessTutor/Coaching/Hosted/HostedCoachingContracts.swift`
- Create: `ChessTutor/Coaching/Hosted/HostedCoachingTransport.swift`
- Create: `ChessTutor/Coaching/Hosted/HostedCoachingConfiguration.swift`
- Create: `ChessTutorTests/Coaching/Hosted/HostedCoachingTransportTests.swift`
- Create: `ChessTutorTests/Coaching/Hosted/HostedCoachingConfigurationTests.swift`
- Modify: `project.yml`
- Regenerate: `ChessTutor.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces `protocol HostedCoachingTurning: Sendable`.
- Produces `URLSessionHostedCoachingTransport`.
- Produces `HostedCoachingConfiguration.resolve(environment:credentialStore:)`.

- [ ] **Step 1: Write failing transport/configuration tests**

Define expected use:

```swift
let response = try await transport.turn(for: request, contract: contract)
XCTAssertEqual(request.requestID, response.requestID)
XCTAssertEqual(request.positionRevision, response.positionRevision)
XCTAssertEqual("Try moving the bishop.", response.turn.message)
```

Test bearer header, canonical JSON body, generic HTTP failure mapping, duplicate/extra output fields, response ID/revision mismatch, second device-side validation, cancellation propagation, environment bootstrap into a fake credential store, and absent configuration.

- [ ] **Step 2: Run tests and observe RED**

Run:

```bash
xcodegen generate
xcodebuild test -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/HostedCoachingTransportTests \
  -only-testing:ChessTutorTests/HostedCoachingConfigurationTests
```

Expected: compile failure because hosted transport types do not exist.

- [ ] **Step 3: Implement wire types and transport**

Define:

```swift
protocol HostedCoachingTurning: Sendable {
    func turn(
        for request: ModelCoachingNeutralRequest,
        contract: ModelCoachingChessNativeResponseContract
    ) async throws -> HostedCoachingResponse
}
```

Use an injected narrow URLSession data-task interface. Encode with sorted keys, cap response bytes, require HTTP 200 and JSON, check request identity/revision, and call `ModelCoachingChessNativeTurnDecoder` using the original contract.

- [ ] **Step 4: Implement Keychain-backed configuration**

Store only the access token in a generic-password Keychain item. Resolve base URL from `CHESS_TUTOR_COACHING_BASE_URL`; bootstrap and persist the token from `CHESS_TUTOR_COACHING_ACCESS_TOKEN` when supplied by an Xcode launch environment. Require HTTP only for loopback/private-LAN debug builds and HTTPS otherwise.

- [ ] **Step 5: Regenerate the project and run tests GREEN**

Run the command from Step 2. Expected: all hosted transport/configuration tests pass.

- [ ] **Step 6: Commit Task 4**

```bash
git add ChessTutor/Coaching/Hosted ChessTutorTests/Coaching/Hosted \
  project.yml ChessTutor.xcodeproj
git commit -m "feat: add hosted coaching transport"
```

---

### Task 5: Hosted episode state and presentation

**Files:**
- Create: `ChessTutor/Coaching/Hosted/HostedCoachingSession.swift`
- Create: `ChessTutor/Coaching/Hosted/HostedCoachingPresentationProjector.swift`
- Create: `ChessTutorTests/Coaching/Hosted/HostedCoachingSessionTests.swift`
- Create: `ChessTutorTests/Coaching/Hosted/HostedCoachingPresentationProjectorTests.swift`

**Interfaces:**
- Produces `HostedCoachingSession` event history and phases.
- Produces hosted `CoachingPresentation` values using existing UI types.
- Consumes `ModelCoachingNeutralRequestBuilder` and validated hosted turns.

- [ ] **Step 1: Write failing episode tests**

Cover exact event sequences for Help, own-piece selection, opponent inspection, staged move, replacement, removal, and hint action. Assert every request is rebuilt from current state:

```swift
let request = session.request(
    committedState: state,
    selectedSquare: selected,
    tentativeMove: tentative,
    positionRevision: revision,
    requestID: "hosted-3"
)
XCTAssertEqual(.moveReplaced, request.interaction.latestEvent.kind)
XCTAssertEqual(tentativeID, request.interaction.latestEvent.referencedIDs.first)
```

- [ ] **Step 2: Write failing presentation tests**

Assert exact thinking, failed, and ready projections; action mapping; local Close Help; and focus geometry. A model `playMove` maps to `.done`, `tryAnotherMove` maps to `.keepLooking`, and `hint` maps to `.hint`.

- [ ] **Step 3: Run tests and observe RED**

Run:

```bash
xcodebuild test -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/HostedCoachingSessionTests \
  -only-testing:ChessTutorTests/HostedCoachingPresentationProjectorTests
```

Expected: compile failure because hosted episode/projector types do not exist.

- [ ] **Step 4: Implement the pure hosted episode model**

Define phases:

```swift
enum HostedCoachingPhase: Equatable, Sendable {
    case thinking
    case ready(ModelCoachingChessNativeTurn)
    case failed
}
```

Keep event derivation pure and deterministic. Event IDs use existing piece/move encoders; sequences are monotonic. Do not include server/network imports.

- [ ] **Step 5: Implement the projector**

Return a single-message `CoachingPresentation` with empty routine and `.none` board task. Thinking reads “Thinking…”. Failure reads “I couldn't get help right now.” with Try Again and Close Help. Ready state appends Close Help and converts square/move focus into the current overlay.

- [ ] **Step 6: Run hosted state/projector tests GREEN**

Run the command from Step 3. Expected: all selected tests pass.

- [ ] **Step 7: Commit Task 5**

```bash
git add ChessTutor/Coaching/Hosted ChessTutorTests/Coaching/Hosted
git commit -m "feat: model hosted coaching episodes"
```

---

### Task 6: GameSession and live app integration

**Files:**
- Modify: `ChessTutor/Game/GameSession.swift`
- Modify: `ChessTutor/UI/Root/ContentView.swift`
- Modify: `ChessTutor/App/ChessTutorApp.swift`
- Modify: `ChessTutorTests/Game/GameSessionCoachingTests.swift`
- Create: `ChessTutorUITests/HostedCoachingContinuityUITests.swift`

**Interfaces:**
- Consumes `HostedCoachingTurning`, `HostedCoachingSession`, and runtime configuration.
- Preserves existing `GameSession(coachingAdvisor:)` local-test API.
- Adds `GameSession(hostedCoachingProvider:)` for opt-in hosted mode.

- [ ] **Step 1: Write failing GameSession tests**

Use a controllable hosted provider and assert:

- Help immediately shows Thinking and queues one request;
- newer selection/staged/replaced move changes pending ID;
- completing an older provider continuation cannot update presentation;
- success atomically replaces Thinking;
- provider/validation failure shows retry without local advice;
- Hint queues a request with `actionChosen`;
- Play This Move uses `finishTurn`;
- Try Another Move removes the tentative move and recalculates; and
- Close Help cancels and clears hosted state.

- [ ] **Step 2: Run GameSession tests and observe RED**

Run:

```bash
xcodebuild test -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/GameSessionCoachingTests
```

Expected: compile failure because the hosted initializer/path does not exist.

- [ ] **Step 3: Integrate hosted state without changing local semantics**

Store local and hosted coaching as mutually exclusive backends. Keep existing local methods intact and branch only at start, synchronization, resolution, action handling, presentation, and stop. Pending hosted applicability requires matching pending ID, request ID, committed state, tentative move, position revision, and active episode.

- [ ] **Step 4: Resolve live configuration in ContentView**

At app construction, resolve hosted configuration once and inject the same backend into new and restored sessions. Missing configuration constructs the current local session. Hosted configuration never falls back after construction.

- [ ] **Step 5: Add permanent delayed-provider UI coverage**

Add a deterministic launch fixture using a delayed fake hosted provider. Sample from Help activation through a superseding staged move and assert the coaching shell never disappears, Thinking is visible during delay, stale copy never appears, and the final complete turn/action/focus appears atomically.

- [ ] **Step 6: Run GameSession and hosted UI tests GREEN**

Run:

```bash
xcodebuild test -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/GameSessionCoachingTests \
  -only-testing:ChessTutorUITests/HostedCoachingContinuityUITests
```

Expected: all selected tests pass with zero failures/skips.

- [ ] **Step 7: Commit Task 6**

```bash
git add ChessTutor/Game/GameSession.swift ChessTutor/UI/Root/ContentView.swift \
  ChessTutor/App/ChessTutorApp.swift ChessTutorTests/Game/GameSessionCoachingTests.swift \
  ChessTutorUITests/HostedCoachingContinuityUITests.swift
git commit -m "feat: integrate hosted coaching flow"
```

---

### Task 7: End-to-end verification and handoff

**Files:**
- Modify: `docs/hosted-coaching-server.md`
- Create: `docs/reports/2026-08-30-hosted-coaching-prototype.md`
- Modify only if required by verified defects: scoped server/Swift files from Tasks 1–6

**Interfaces:**
- Produces one verified local-server/iPad workflow and deployment-ready repository configuration.

- [ ] **Step 1: Run the fake-server end-to-end path**

Start the local WSGI server with a deterministic fake provider mode available only under an explicit test environment variable. Launch the simulator with base URL/token, then exercise Help, interaction while Thinking, move replacement, Retry, Play This Move, focus, and Close Help.

- [ ] **Step 2: Run one bounded real Sol/high smoke**

Retrieve `OPENAI_API_KEY` from Keychain only into the server child environment. Start the local server, launch the normal app with hosted configuration, and exercise the twelve broad regression situations with exactly one call each. Record only validated child turns and bounded metrics under ignored `.coaching-eval`; do not persist provider IDs or reasoning.

- [ ] **Step 3: Inspect Large and accessibility-size UI**

Capture and inspect Thinking, ready, failure, and replacement states in tall and wide layouts. Verify no base-panel flicker, mixed-stage copy, clipping, unreachable actions, or stale focus.

- [ ] **Step 4: Remove all temporary UAT hooks**

Delete fake launch modes, screenshot methods, and instrumentation not explicitly permanent in Task 6. Search for their identifiers and require zero matches.

- [ ] **Step 5: Run final verification**

Run:

```bash
xcodebuild test -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)'

PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest discover \
  -s Tools/CoachingEval/tests -v

PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest discover \
  -s CoachingServer/tests -v

xcodebuild build -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)'

git diff --check
git status --short
```

Expected: all Swift/UI/Python tests pass with zero failures/skips, build succeeds, diff check is silent, and status contains only the final report/runbook changes.

- [ ] **Step 6: Write the prototype report**

Document architecture, configuration, exact test counts, real-smoke case outcomes, latency/token ranges, UI inspection, no-fallback behavior, artifact hashes, deployment command, and any remaining concern. Cite the official OpenAI Responses API and Vercel Python runtime pages used for the implementation.

- [ ] **Step 7: Commit final documentation**

```bash
git add docs/hosted-coaching-server.md \
  docs/reports/2026-08-30-hosted-coaching-prototype.md
git commit -m "docs: report hosted coaching prototype"
git status --short
```

- [ ] **Step 8: Push and create a PR without auto-merge**

Push `codex/hosted-coaching-prototype`, create a PR against its confirmed coaching base branch, include verification evidence, and leave it open for user review.

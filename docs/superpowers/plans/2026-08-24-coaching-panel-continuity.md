# Coaching Panel Continuity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the visible ordinary-sidebar flash between local coaching turns and render optional feedback as a compact warm note below the instruction.

**Architecture:** Preserve the asynchronous `CoachingAdvising` boundary, but give deterministic local advisors an explicit immediate capability so `GameSession` can apply local advice in the same interaction transaction. Keep the session-derived presentation authoritative; do not cache or animate stale UI. Render `observation` through a dedicated noninteractive response-note view while leaving copy and chess evaluation unchanged.

**Tech Stack:** Swift 6, SwiftUI, Observation, XCTest, XCUITest, iOS Simulator.

## Global Constraints

- Coaching remains opt-in and the playable board remains the primary experience.
- No intermediate "checking" presentation is rendered for the fast local evaluator.
- The coaching shell never yields to the ordinary sidebar during an active local coaching interaction.
- A complete `CoachingPresentation` remains the atomic unit of advice, actions, routine, board task, and focus.
- Text order remains primary message → instruction → optional response.
- The response adds no label, icon, quotation marks, or new child-facing copy.
- Chess evaluation and authored coaching copy do not change.
- VoiceOver order remains primary message → instruction → response → routine → actions.
- Large and Accessibility Extra Large must work in tall, clockwise-wide, and counterclockwise-wide compositions.
- Full verification has zero failed, skipped, or expected-failure tests.

---

### Task 1: Publish local coaching turns atomically and style responses

**Files:**

- Modify: `ChessTutor/Coaching/CoachingModels.swift`
- Modify: `ChessTutor/Coaching/LocalCoachingAdvisor.swift`
- Modify: `ChessTutor/Game/GameSession.swift`
- Modify: `ChessTutor/UI/Coaching/CoachingPanelView.swift`
- Modify: `ChessTutor/UI/Theme/AppTheme.swift`
- Modify: `ChessTutor/App/CoachingPanelAccessibilityFixture.swift`
- Test: `ChessTutorTests/Game/GameSessionCoachingTests.swift`
- Test: `ChessTutorTests/Coaching/LocalCoachingAdvisorTests.swift`
- Test: `ChessTutorTests/UI/CoachingPanelLayoutTests.swift`
- Test: `ChessTutorUITests/CoachingPanelAccessibilityUITests.swift`

**Interfaces:**

- Consumes: existing `CoachingAdvising.advice(for:) async throws -> CoachingAdvice`, `CoachingPresentation.observation`, `GameSession.pendingCoachingRequestID`, and `CoachingPanelView` semantic sections.
- Produces: `ImmediateCoachingAdvising.immediateAdvice(for:) throws -> CoachingAdvice`; `LocalCoachingAdvisor` conformance; the accessibility identifier `coaching-response-note` for the visual response container.

- [ ] **Step 1: Reproduce and locate the flicker before changing production code**

Record the current local flow at simulator frame rate:

```text
Help → select g1 → stage g1-f3 → replace with b1-c3
```

At each interaction, capture the `GameSession` sequence of:

```swift
(
    isCoachingActive: session.isCoachingActive,
    pendingRequestID: session.pendingCoachingRequestID,
    primaryMessage: session.coachingPresentation?.primaryMessage
)
```

Confirm whether the visible flash coincides with the local advisor being scheduled through `ContentView.task(id:)` after `queueCoachingRequest(context:)`. Record the exact observed transition in the task report. If evidence identifies a different source, fix that source while preserving every behavioral constraint below; do not mask it with animation.

- [ ] **Step 2: Write failing immediate-advice continuity tests**

Add tests that describe the required local behavior:

```swift
func testLocalAdviceIsAvailableImmediately() async throws {
    let request = request(for: GameState.startingPosition())
    let advisor = LocalCoachingAdvisor()

    let immediate = try advisor.immediateAdvice(for: request)
    let asynchronous = try await advisor.advice(for: request)

    XCTAssertEqual(immediate, asynchronous)
}

@MainActor
func testLocalCoachingNeverPublishesPendingTurnBetweenMoveAndAdvice() {
    let session = GameSession(coachingAdvisor: LocalCoachingAdvisor())
    session.startCoaching()

    XCTAssertNil(session.pendingCoachingRequestID)
    XCTAssertNotEqual(session.coachingPresentation?.primaryMessage, "I'm checking the board.")

    session.select(Square(file: .g, rank: 1))
    XCTAssertEqual(
        session.moveSelectedPiece(to: Square(file: .f, rank: 3)),
        .moved
    )

    XCTAssertNil(session.pendingCoachingRequestID)
    XCTAssertEqual(
        session.coachingPresentation?.primaryMessage,
        "You developed your knight toward the center."
    )
}
```

Keep the first test `async throws`; do not introduce a blocking semaphore.

- [ ] **Step 3: Run the continuity tests and verify RED**

Run:

```bash
xcodebuild test -quiet \
  -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/LocalCoachingAdvisorTests \
  -only-testing:ChessTutorTests/GameSessionCoachingTests
```

Expected: compilation fails because `ImmediateCoachingAdvising` and `immediateAdvice(for:)` do not exist, or the pending-request assertions fail because local advice still waits for the view task.

- [ ] **Step 4: Add the minimal immediate-advisor capability**

Add a narrow capability without changing the general asynchronous provider boundary:

```swift
protocol ImmediateCoachingAdvising: CoachingAdvising {
    func immediateAdvice(for request: CoachingRequest) throws -> CoachingAdvice
}

extension ImmediateCoachingAdvising {
    func advice(for request: CoachingRequest) async throws -> CoachingAdvice {
        try immediateAdvice(for: request)
    }
}
```

Move the existing deterministic `LocalCoachingAdvisor` body into `immediateAdvice(for:)` and conform it to `ImmediateCoachingAdvising`.

In `GameSession.queueCoachingRequest(context:)`, create the exact `PendingCoachingRequest` first. If the configured advisor conforms to `ImmediateCoachingAdvising`, resolve that exact request synchronously through the existing request-applicability and `CoachingSession.receive` path. Do not duplicate presentation or reducer logic. Only leave `pendingCoachingRequest` set for truly asynchronous advisors.

The synchronous path must preserve:

```text
request identity
committed state
tentative move
position revision
learner
origin
unsupported-position fallback
```

Do not special-case transcript copy or move squares.

- [ ] **Step 5: Run continuity tests and verify GREEN**

Run the Step 3 command.

Expected: all selected tests pass; `LocalCoachingAdvisor` produces equal immediate/async advice; starting, staging, and replacing moves with the local advisor leave no pending request and never publish "I'm checking the board."

- [ ] **Step 6: Write failing response-note presentation tests**

Extend the existing compact completion/observation accessibility fixtures. For a presentation with `observation`, assert:

```swift
let response = app.otherElements["coaching-response-note"]
XCTAssertTrue(response.waitForExistence(timeout: 3))
XCTAssertEqual(response.label, expectedObservation)
XCTAssertLessThan(instruction.frame.maxY, response.frame.minY)
XCTAssertTrue(conversation.frame.contains(response.frame))
```

For a completion with `observation == nil`, assert:

```swift
XCTAssertFalse(app.otherElements["coaching-response-note"].exists)
```

Keep the existing exact semantic-order and containment assertions at Large and Accessibility Extra Large for tall, clockwise-wide, and counterclockwise-wide layouts.

Add a pure layout/style contract test only if needed to expose a stable value such as response padding or accent width; do not test private SwiftUI implementation details.

- [ ] **Step 7: Run response-note tests and verify RED**

Run:

```bash
xcodebuild test -quiet \
  -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/CoachingPanelLayoutTests \
  -only-testing:ChessTutorUITests/CoachingPanelAccessibilityUITests
```

Expected: response-note queries fail because `observation` is currently ungrouped body text with no distinct response container.

- [ ] **Step 8: Implement the warm response note**

Extract one private view in `CoachingPanelView.swift`:

```swift
private struct CoachingResponseNote: View {
    let text: String
    let font: Font

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(AppTheme.ink.opacity(0.78))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 9)
            .padding(.horizontal, 11)
            .background(AppTheme.coachingResponseFill)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(AppTheme.coachingResponseRule)
                    .frame(width: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("coaching-response-note")
    }
}
```

Pass the existing scaled `bodyFont` when constructing `CoachingResponseNote`. Derive `coachingResponseFill` and `coachingResponseRule` from the existing warm panel/wood palette in `AppTheme`; do not introduce violet, green, an icon, or a new textual label. Use the note only for `presentation.observation` in the visible conversation. Preserve the existing plain semantic text in the accessibility representation if grouping the note would alter VoiceOver order or verbosity.

- [ ] **Step 9: Run response, continuity, and coaching regression suites**

Run:

```bash
xcodebuild test -quiet \
  -scheme ChessTutor \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/LocalCoachingAdvisorTests \
  -only-testing:ChessTutorTests/CoachingSessionTests \
  -only-testing:ChessTutorTests/GameSessionCoachingTests \
  -only-testing:ChessTutorTests/CoachingGoldenTranscriptTests \
  -only-testing:ChessTutorTests/CoachingPanelLayoutTests \
  -only-testing:ChessTutorUITests/CoachingPanelAccessibilityUITests
```

Expected: all selected tests pass with zero failed, skipped, or expected failures.

- [ ] **Step 10: Perform direct simulator UAT**

On an iPad (A16), inspect:

```text
Large, tall: Help → g1 → f3 → replace with b1-c3
Large, wide: the same transition
AX Extra Large, tall: a question + instruction + warm response
AX Extra Large, wide: a long warm response with all actions reachable
```

Frame-sample or record the move/replacement transition and verify no ordinary sidebar or "I'm checking the board." frame appears. Verify the response note is visually distinct, remains below the instruction, wraps/scrolls, does not resemble a button, and disappears on the next action. Restore content size to Large.

- [ ] **Step 11: Run full verification**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
xcodebuild build -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
git diff --check
git status --short
```

Expected: full tests and build pass; zero failed, skipped, or expected failures; no temporary UAT harness remains.

- [ ] **Step 12: Commit**

```bash
git add \
  ChessTutor/Coaching/CoachingModels.swift \
  ChessTutor/Coaching/LocalCoachingAdvisor.swift \
  ChessTutor/Game/GameSession.swift \
  ChessTutor/UI/Coaching/CoachingPanelView.swift \
  ChessTutor/UI/Theme/AppTheme.swift \
  ChessTutor/App/CoachingPanelAccessibilityFixture.swift \
  ChessTutorTests/Game/GameSessionCoachingTests.swift \
  ChessTutorTests/Coaching/LocalCoachingAdvisorTests.swift \
  ChessTutorTests/UI/CoachingPanelLayoutTests.swift \
  ChessTutorUITests/CoachingPanelAccessibilityUITests.swift
git commit -m "fix: keep coaching turns visually continuous"
```

Reinstall the verified standalone app, launch it without test arguments, visually confirm the normal starting board at Large, and leave Simulator open for product review.

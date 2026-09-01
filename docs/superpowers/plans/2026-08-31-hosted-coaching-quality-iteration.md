# Hosted Coaching Quality Iteration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve tactical correctness and discovery-first coaching while reserving low reasoning for follow-ups that need chess judgment.

**Architecture:** Add immutable prompt `tutor-v8`, route effort from the mechanically validated latest interaction, and keep the existing strict response/device boundary. Evaluate a small fixed set derived from the real trace before any broad run; preserve one bounded immutable successor if that probe exposes a repeated prompt defect.

**Tech Stack:** Python 3 unittest, Flask service, OpenAI Responses API, Swift/XCTest transport guards.

## Global Constraints

- Do not edit `tutor-v7`; add `tutor-v8`.
- No model comparison or hidden corpus run.
- No provider body, reasoning trace, API key, or continuation ID in logs or artifacts.
- Preserve the v2 hosted HTTP envelope and strict UI response contract.

---

### Task 1: Prompt contract

**Files:**
- Create: `Tools/CoachingEval/prompts/tutor-v8.md`
- Create: `Tools/CoachingEval/tests/test_tutor_v8_prompt.py`

**Interfaces:**
- Produces: immutable `tutor-v8` system prompt with the existing JSON output shape.

- [x] Write prompt tests for recapture/material judgment, broad initial Help, Hint/staged exceptions, message/focus alignment, current-step precedence, notation rules, and strict output.
- [x] Run `python3 -B -m unittest Tools.CoachingEval.tests.test_tutor_v8_prompt -v` and observe RED because `tutor-v8.md` is absent.
- [x] Add the minimal concise v8 prompt satisfying those policies.
- [x] Rerun the focused test and verify GREEN.

### Task 2: Event-sensitive reasoning and version adoption

**Files:**
- Modify: `CoachingServer/service.py`
- Modify: `CoachingServer/http_app.py`
- Modify: `CoachingServer/tests/test_service.py`
- Modify: `CoachingServer/tests/test_http_app.py`
- Modify: `ChessTutor/Coaching/Hosted/HostedCoachingTransport.swift`
- Modify: `ChessTutorTests/Coaching/Hosted/HostedCoachingTransportTests.swift`
- Modify: `ChessTutorTests/Coaching/Hosted/HostedGameSessionIntegrationTests.swift`
- Modify: `ChessTutor/App/CoachingPanelAccessibilityFixture.swift`

**Interfaces:**
- Consumes: `request.interaction.latestEvent.kind` and `referencedIDs` after strict compiler validation.
- Produces: `_reasoning_effort(request, is_follow_up, simple_follow_up_effort) -> str` and hosted responses labeled with the final immutable prompt version.

- [x] Add failing tests for high initial, low tactical/Hint, none simple, and v8 response acceptance.
- [x] Run the focused Python/Swift tests and record RED.
- [x] Implement the minimal routing helper, default the simple follow-up setting to `none`, and adopt the final server/device prompt guards.
- [x] Rerun focused tests and verify GREEN.

### Task 3: Focused quality evaluation

**Files:**
- Reuse: existing mechanically compiled request fixtures and hosted pilot tooling.
- Create only if needed: ignored `.coaching-eval/hosted-quality-v8/` artifacts.

**Interfaces:**
- Consumes: exact v8 system prompt, strict request compiler, `gpt-5.6-sol`.
- Produces: a small traceable quality report with no private reasoning or credentials.

- [x] Assemble six visible cases covering the real false threat, opening Help, genuine danger, poisoned capture, ignored danger, and move replacement.
- [x] Preflight all prompts and strict response contracts before inference.
- [x] Run one serial response per case with production reasoning routing.
- [x] Mechanically validate and manually score correctness, discovery, current-step coherence, wording, and focus alignment.
- [x] Preserve v8, make the one bounded v9 successor, and rerun only the two weak cases plus the critical false-threat case; do not start a broad matrix.

### Task 4: Verification and delivery

**Files:**
- Update: this plan checkboxes and an ignored task report if useful.

- [x] Run all `CoachingServer` and `Tools/CoachingEval` Python tests.
- [x] Run affected Swift hosted-coaching tests, then the full iPad scheme if the focused run is green.
- [x] Launch the normal app through `scripts/run_hosted_coaching_dev.sh`; verify a real initial response and that simple piece selection causes no request. Tactical v9 behavior is verified through the bounded live probe.
- [ ] Run `git diff --check`, review the diff for private data, commit, push, and open a PR without merging it.

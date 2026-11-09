# Hosted Coaching Development Traces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add opt-in, pasteable prompt/response traces to the local hosted-coaching development workflow.

**Architecture:** `HostedCoachingService` owns the content boundary because it receives the deterministic client game request and only gains a safe server response after strict provider validation. It projects those objects into one compact, reconstructable JSON line rather than logging verbose rule evidence. `http_app` converts one exact environment value into the service flag, while the development launcher sets that value only for its child server.

**Tech Stack:** Python 3, Flask application configuration, Python logging, Bash launcher, `unittest`.

## Global Constraints

- Content logging is disabled by default and enabled only by the exact environment value `1`.
- Log only the compact position/history/interaction projection and validated advice/latency projection.
- Never log secrets, provider/continuation IDs, reasoning traces, raw invalid output, or exception bodies.
- Preserve existing lifecycle and latency logs.

---

### Task 1: Service Content Trace Boundary

**Files:**
- Modify: `CoachingServer/service.py`
- Test: `CoachingServer/tests/test_service.py`

**Interfaces:**
- Consumes: the parsed neutral game request, request kind, trace ID, validated `turn`, and safe response metadata already owned by `HostedCoachingService.complete`.
- Produces: constructor option `log_content: bool = False` and one compact successful trace line.

- [x] **Step 1: Write failing tests**

Add tests that capture `ChessTutor.CoachingServer` logs and assert the content is absent by default, contains the exact compact move/interaction/advice projection when `log_content=True`, excludes verbose rule arrays, model prompts, and provider IDs, and never includes raw invalid provider output.

- [x] **Step 2: Run tests and verify RED**

Run: `python -B -m unittest CoachingServer.tests.test_service -v`

Expected: failures because `HostedCoachingService` does not accept `log_content` and emits no content trace.

- [x] **Step 3: Implement the minimal trace boundary**

Validate `log_content` as a Boolean, store it, and after response validation emit one single-line JSON trace with the compact reconstructable fields.

- [x] **Step 4: Run service tests and verify GREEN**

Run: `python -B -m unittest CoachingServer.tests.test_service -v`

Expected: all service tests pass.

### Task 2: Environment And Launcher Wiring

**Files:**
- Modify: `CoachingServer/http_app.py`
- Modify: `scripts/run_hosted_coaching_dev.sh`
- Test: `CoachingServer/tests/test_http_app.py`
- Test: `CoachingServer/tests/test_dev_launcher.py`

**Interfaces:**
- Consumes: `CHESS_TUTOR_COACHING_LOG_CONTENT`.
- Produces: `log_content=True` only for exact value `1`; launcher automatically supplies that value to its server child.

- [x] **Step 1: Write failing wiring tests**

Assert the environment application passes `log_content=True` for `1`, false when unset or another value, and the launcher child observes the variable as `1` without printing secrets.

- [x] **Step 2: Run tests and verify RED**

Run: `python -B -m unittest CoachingServer.tests.test_http_app CoachingServer.tests.test_dev_launcher -v`

Expected: failures because the flag is not wired.

- [x] **Step 3: Implement minimal wiring**

Pass `log_content=os.environ.get("CHESS_TUTOR_COACHING_LOG_CONTENT") == "1"` to the service and set `CHESS_TUTOR_COACHING_LOG_CONTENT=1` on the local server command.

- [x] **Step 4: Run focused tests and verify GREEN**

Run: `python -B -m unittest CoachingServer.tests.test_service CoachingServer.tests.test_http_app CoachingServer.tests.test_dev_launcher -v`

Expected: all focused tests pass.

### Task 3: Regression Verification And Handoff

**Files:**
- Modify only if verification reveals a scoped defect.

**Interfaces:**
- Consumes: completed Tasks 1 and 2.
- Produces: verified branch ready for review and a concise launcher handoff.

- [x] **Step 1: Run the complete Python suites**

Run both `CoachingServer` and `Tools/CoachingEval` unittest discovery commands used by CI, ensuring both execute even if the first fails.

- [x] **Step 2: Run syntax and diff checks**

Run `python -m py_compile` for modified Python files and `git diff --check`.

- [x] **Step 3: Review the diff for privacy and scope**

Confirm deployment config is unchanged, no secrets/IDs are logged, and only successful validated responses produce content blocks.

- [x] **Step 4: Commit the scoped change**

Stage the design, plan, implementation, and tests; commit with `feat: log hosted coaching development traces`.

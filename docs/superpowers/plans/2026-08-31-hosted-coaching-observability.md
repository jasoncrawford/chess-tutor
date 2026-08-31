# Hosted Coaching Timing Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add privacy-safe request lifecycle timings that identify whether hosted coaching stalls in the app, local HTTP server, prompt compiler, or OpenAI call.

**Architecture:** Flask/Werkzeug replaces the hand-written WSGI request adapter and owns HTTP routing, bounded request reading, and response construction. The HTTP and service boundaries emit concise INFO events through Python's standard logging system; a generated trace identifier correlates them, and injected clocks keep tests deterministic. The launcher maintains an ignored virtual environment from a pinned requirements file.

**Tech Stack:** Python 3, Flask 3.1.3, Werkzeug, standard-library `logging`, `time.monotonic`, `unittest`.

## Global Constraints

- Never log authorization tokens, API keys, chess positions, move history, prompts, provider output, provider identifiers, or exception bodies.
- Preserve the existing HTTP and coaching response contracts.
- Application code must not read directly from `wsgi.input`.
- Use one trace identifier only for transient event correlation.
- Verify the live path with one real Simulator request after automated tests pass.

---

### Task 1: Service and HTTP lifecycle events

**Files:**
- Create: `requirements.txt`
- Modify: `.gitignore`
- Modify: `scripts/run_hosted_coaching_dev.sh`
- Modify: `CoachingServer/service.py`
- Modify: `CoachingServer/http_app.py`
- Modify: `CoachingServer/local.py`
- Test: `CoachingServer/tests/test_service.py`
- Test: `CoachingServer/tests/test_http_app.py`

**Interfaces:**
- Consumes: `HostedCoachingService.complete(request, trace_id=...)` and Flask `request.get_data()`.
- Produces: a Flask WSGI `app`, the unchanged HTTP API, and ordered INFO events named `http_request_started`, `request_compiled`, `provider_request_started`, `provider_request_completed` or `provider_request_failed`, `provider_response_validated`, and `http_request_completed`.

- [x] **Step 1: Write failing service logging tests**

Add deterministic-clock tests that capture `ChessTutor.CoachingServer` logs and assert event order, provider elapsed milliseconds, timeout category, trace identifier propagation, and absence of private provider exception text.

- [x] **Step 2: Run the service tests to verify RED**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest CoachingServer.tests.test_service -v
```

Expected: failures because the lifecycle events and `trace_id` interface do not exist.

- [x] **Step 3: Implement service lifecycle events**

Emit fixed event names and bounded scalar fields only. Measure the provider boundary with the existing monotonic clock. Classify failures as `timeout`, `unavailable`, or `invalid_response` without formatting exception objects.

- [x] **Step 4: Run service tests to verify GREEN**

Run the Step 2 command. Expected: all service tests pass with no skips.

- [x] **Step 5: Write failing Flask and real-socket HTTP tests**

Assert `create_application` returns a Flask application with the unchanged endpoint behavior. Inject a deterministic trace factory and clock and assert valid-request lifecycle logs. Start a real loopback server with `werkzeug.serving.make_server`, send a body whose client connection remains open, and assert the service receives it immediately. This test must fail against the old `content_length + 1` body read.

- [x] **Step 6: Run HTTP tests to verify RED**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest CoachingServer.tests.test_http_app -v
```

Expected: failures because HTTP lifecycle logging and deterministic dependencies do not exist.

- [x] **Step 7: Implement Flask HTTP handling, dependency setup, and INFO logging**

Pin Flask 3.1.3 in `requirements.txt`; ignore `.venv/`; and have the launcher create/update that environment before starting the server. Configure Flask's maximum content length, use `request.get_data()` rather than `wsgi.input`, retain strict duplicate-key JSON parsing, generate a trace ID, pass it to the service, and configure timestamped INFO output in `CoachingServer.local`.

- [x] **Step 8: Run all server tests and commit**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest discover -s CoachingServer/tests -v
```

Expected: all tests pass with zero failures or skips.

Commit:

```bash
git add CoachingServer docs/superpowers/plans/2026-08-31-hosted-coaching-observability.md
git commit -m "feat: log hosted coaching request timings"
```

### Task 2: Live timeout diagnosis

**Files:**
- No production file changes expected.

**Interfaces:**
- Consumes: the local launcher and lifecycle events from Task 1.
- Produces: one evidence-backed diagnosis identifying the slow boundary.

- [x] **Step 1: Stop the old launcher and start the instrumented launcher**

Run `./scripts/run_hosted_coaching_dev.sh` from this worktree and wait for the app to launch.

- [x] **Step 2: Trigger one visible coaching retry**

Use the real `Try again` UI control. Record the lifecycle event timestamps through completion or timeout.

- [x] **Step 3: Verify privacy and interpret timing**

Confirm the output contains no prompt, board, response, provider identifier, or credentials. Identify whether the app timed out before the provider, server, or validation boundary completed.

- [ ] **Step 4: Final verification and PR**

Run the complete server suite, `git diff --check`, request code review, push the branch, and open a PR against `codex/chess-coaching-comparison`.

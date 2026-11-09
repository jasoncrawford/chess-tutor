# Pull Request CI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run all Python and iPad tests automatically on every pull request.

**Architecture:** One GitHub Actions workflow owns two parallel jobs: Python on Ubuntu and the native app on macOS 26/Xcode 26.6. It cancels stale runs, uses read-only permissions, and uploads failure evidence.

**Tech Stack:** GitHub Actions, Python 3.12, unittest, macOS 26, Xcode 26.6, iOS Simulator.

## Global Constraints

- Trigger on every pull request and allow a manual `workflow_dispatch` run.
- Do not provide secrets or call hosted model APIs.
- Run all 23 server tests, all 177 evaluation-tool tests, and the complete `ChessTutor` scheme.
- Upload Python logs and the `.xcresult` bundle only when their job fails.
- Cancel superseded runs for the same pull request.

---

### Task 1: Add pull-request test workflow

**Files:**
- Create: `.github/workflows/tests.yml`
- Create: `CoachingServer/tests/test_ci_configuration.py`

**Interfaces:**
- Consumes: `requirements.txt`, `ChessTutor.xcodeproj`, and the existing unittest suites.
- Produces: GitHub status checks named `Python` and `iPad`.

- [ ] **Step 1: Write the failing workflow contract test**

Add a unittest that requires the workflow file and asserts the approved trigger,
permissions, concurrency, exact test commands, macOS/Xcode destination, timeouts,
and failure-artifact paths.

- [ ] **Step 2: Run the contract test to verify RED**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 .venv/bin/python -B -m unittest CoachingServer.tests.test_ci_configuration -v
```

Expected: failure because `.github/workflows/tests.yml` does not exist.

- [ ] **Step 3: Implement the workflow**

Create the read-only, concurrent two-job workflow described in the design. Use
`actions/checkout@v6`, `actions/setup-python@v6`, and
`actions/upload-artifact@v7`.

- [ ] **Step 4: Verify locally**

Run the contract test, both Python suite commands, the full `xcodebuild test`
command, a YAML parse, and `git diff --check`. Expected: zero failures.

- [ ] **Step 5: Commit, merge into the open PR branch, and observe CI**

Commit on `codex/ci-pr-tests`, merge that branch into
`codex/hosted-coaching-observability`, push PR #6, and wait for both checks to
finish. Fix failures on the CI branch and repeat until both jobs pass.

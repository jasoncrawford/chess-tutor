# Hosted Coaching Development Launcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide one command that starts the local hosted-coaching server and launches a configured ChessTutor build in the iPad Simulator.

**Architecture:** A Bash entry point owns the short-lived development process: it reads the existing OpenAI Keychain item, generates an in-memory server token, starts the WSGI server on a free loopback port, then uses Xcode and `simctl` to build, install, and launch the app. A Python integration test executes the real script against controlled fake command-line tools so secrets, command construction, device choice, and cleanup are verified without contacting OpenAI or booting a simulator.

**Tech Stack:** Bash 3.2, macOS Keychain CLI, Xcode CLI tools, iOS Simulator, Python `unittest`.

## Global Constraints

- Simulator development only; physical-device and Vercel deployment remain in the existing runbook.
- Never print or persist the OpenAI key or generated access token.
- Make no changes to coaching behavior, prompts, production configuration, or app architecture.
- Build artifacts stay in ignored `DerivedData`.

---

### Task 1: One-command simulator launcher

**Files:**
- Create: `scripts/run_hosted_coaching_dev.sh`
- Create: `CoachingServer/tests/test_dev_launcher.py`

**Interfaces:**
- Consumes: macOS Keychain service `ChessTutor-CoachingEval-OpenAI`, `CoachingServer.local`, `ChessTutor.xcodeproj`, and an available simulator whose default name is `iPad (A16)`.
- Produces: executable `scripts/run_hosted_coaching_dev.sh [simulator-name]`; Ctrl-C terminates its server child.

- [ ] **Step 1: Write the failing end-to-end launcher tests**

Create controlled fake `security`, `openssl`, `python3`, `curl`, `xcrun`, `xcodebuild`, and `open` commands in a temporary `PATH`. Execute the real script and assert the literal observable contract:

```python
self.assertNotIn("sk-private-key", combined_output)
self.assertNotIn("local-token-secret", combined_output)
self.assertIn("simctl install AA821CF0", command_log)
self.assertIn("simctl launch --terminate-running-process AA821CF0", command_log)
self.assertIn("server-stopped", command_log)
```

Add a second test where `security` fails; assert a nonzero exit, an actionable Keychain message, and no `xcodebuild` invocation.

- [ ] **Step 2: Run the test to verify RED**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest CoachingServer.tests.test_dev_launcher -v
```

Expected: failure because `scripts/run_hosted_coaching_dev.sh` does not exist.

- [ ] **Step 3: Implement the minimal launcher**

Use `set -euo pipefail`; resolve the repository root from the script path; read the Keychain item; generate a 32-byte hexadecimal access token; choose a free loopback port; parse `simctl list devices available -j` with `/usr/bin/jq`; boot the selected simulator; start `python3 -m CoachingServer.local`; poll `/health`; build to `DerivedData`; terminate/install/launch the app with only these child variables:

```bash
SIMCTL_CHILD_CHESS_TUTOR_COACHING_BASE_URL="http://127.0.0.1:$port"
SIMCTL_CHILD_CHESS_TUTOR_COACHING_ACCESS_TOKEN="$access_token"
```

Install an EXIT trap that terminates and waits for the server child. Print only progress, the selected simulator, and Ctrl-C guidance.

- [ ] **Step 4: Run focused and server suites to verify GREEN**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest CoachingServer.tests.test_dev_launcher -v
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest discover -s CoachingServer/tests -v
```

Expected: all tests pass with zero failures or skips.

- [ ] **Step 5: Commit**

```bash
git add scripts/run_hosted_coaching_dev.sh CoachingServer/tests/test_dev_launcher.py
git commit -m "feat: add hosted coaching dev launcher"
```

### Task 2: Runbook and real smoke verification

**Files:**
- Modify: `docs/hosted-coaching-server.md`

**Interfaces:**
- Consumes: executable launcher from Task 1.
- Produces: the one-command simulator workflow as the primary local-development instruction.

- [ ] **Step 1: Replace manual simulator setup with the launcher command**

Document:

```bash
./scripts/run_hosted_coaching_dev.sh
```

Keep the lower-level server command as an advanced/manual option and retain physical-device/Vercel guidance.

- [ ] **Step 2: Run the real smoke path**

Run the launcher against `iPad (A16)`, confirm Keychain retrieval, server health, build, install, and configured launch, then stop it with Ctrl-C before making a coaching request. Confirm no secret appears in terminal output.

- [ ] **Step 3: Run final verification**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest discover -s CoachingServer/tests -v
bash -n scripts/run_hosted_coaching_dev.sh
git diff --check
```

Expected: all tests and syntax checks pass; tracked status contains only the planned documentation change.

- [ ] **Step 4: Commit**

```bash
git add docs/hosted-coaching-server.md
git commit -m "docs: simplify hosted coaching development"
```

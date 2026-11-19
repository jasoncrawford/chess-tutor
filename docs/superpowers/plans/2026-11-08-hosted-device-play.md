# Hosted Device Play Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Host the accepted coaching service and make its authenticated iPad configuration survive ordinary app launches.

**Architecture:** Keep Flask and its existing contract. Deploy a deliberately small server bundle to Vercel with the accepted model configuration pinned. Store the validated server URL and family credential atomically in Keychain; use scripts for first-device provisioning and repeatable deployment.

**Tech Stack:** Swift/SwiftUI, Security Keychain, Python 3.12/Flask, Vercel CLI, Xcode command-line tools.

**Spec:** `docs/superpowers/specs/2026-11-08-hosted-device-play-design.md`

## Global Constraints

- Start from main; PR #24 must be merged with explicit user authorization and green checks before importing its implementation.
- Model selection is `Tools/CoachingEval/benchmark/configs/models/astra-experience-v7-low-model.json`; prompt/compiler behavior is unchanged.
- Keep API keys and family access tokens out of git, app bundles, command-line arguments, logs, and test fixtures. Use throwaway credentials in tests.
- No database, new domain, paid plan upgrade, anonymous coaching endpoint, or paid benchmark.
- Hosting ceiling 60 seconds; provider timeout remains 30 seconds.
- Use Coaching Smoke for simulator checks. Do not modify A16 or install on an unidentified physical device.
- Preserve old worktrees and ignored evaluation evidence. Final PR stays open for user review.

## Review Focus

- Home-screen relaunch has no Xcode environment: the hosted provider still resolves.
- Endpoint changes or failed Keychain writes cannot reuse/leak the wrong server's token.
- The uploaded bundle boots outside the repo and includes the pinned prompt/config but no private artifacts.
- A public request without the family token cannot invoke the paid model.
- Provisioning commands never expose credentials in their arguments, outputs, temporary files, or version control.

### Task 1: Package and deploy the current server reproducibly

**Files:** `vercel.json`, `.vercelignore`, `.gitignore`, `.env.example`, `CoachingServer/deployment.json`, `scripts/deploy_coaching_server.py`, `CoachingServer/tests/test_deployment_configuration.py`, `CoachingServer/tests/test_hosted_deployment.py`, `docs/hosted-coaching-server.md`.

**Interfaces:** `CoachingServer/deployment.json` records the project/team, stable HTTPS base URL once assigned, immutable model-configuration path, and macOS Keychain service names (never secret values). The deploy script consumes that manifest and uploads only the declared runtime files. Device setup in Task 3 reads the same manifest.

- [ ] Confirm #24 merge authorization/checks; update this branch from integrated main. Run server/configuration baseline tests.
- [ ] Add failing packaging/entrypoint tests: a staged runtime bundle boots the real environment application with fake secrets, serves health, rejects missing/bad tokens, validates authenticated requests without calling a provider, and can load the exact pinned model/prompt. Assert private/build/test artifacts are excluded.
- [ ] Implement the package boundary, explicit model selection, function duration, ignore rules, and deployment script. Do not overwrite existing hosting projects or secrets.
- [ ] Run all Python suites and the staged-bundle checks. Expected: no failures or skips.
- [ ] Create/link only `chess-tutor-coaching` in team `jasoncrawford`; provision a random family token and the server-only OpenAI key through secret-safe CLI input. Deploy and record the stable origin/configuration provenance.
- [ ] Verify HTTPS health, 401 rejection, invalid-request handling, and no accidental public files. Limit live model verification to a couple of coaching requests, not an eval run.
- [ ] Commit this task's tested changes and record deployment evidence.

### Task 2: Persist authenticated configuration on the iPad

**Files:** `ChessTutor/Coaching/Hosted/HostedCoachingConfiguration.swift`, `ChessTutorTests/Coaching/Hosted/HostedCoachingConfigurationTests.swift`, relevant runtime tests.

**Interfaces:** Make `HostedCoachingConfiguration` Codable. The credential-store protocol loads/saves an optional complete configuration (`loadConfiguration() throws -> HostedCoachingConfiguration?`, `saveConfiguration(_:) throws`) rather than an unbound token. `resolve(environment:credentialStore:isDebugBuild:)` retains its validated optional-configuration result; `HostedCoachingRuntime.resolveProvider` must also resolve saved configuration without an environment URL.

- [ ] Write and observe failing tests for setup then environment-free relaunch, same-origin token reuse, different-origin rejection without a new token, atomic replacement, malformed saved settings, Release HTTP rejection, and Keychain errors yielding unavailable hosted mode.
- [ ] Store one JSON-encoded configuration in a dedicated Keychain item with device-only accessibility. Keep explicit development launch configuration working, without requiring migration of an old token that never had a saved endpoint.
- [ ] Exercise actual Keychain save/load across fresh store instances using an isolated test service/account; clean up only that test item. Verify the real runtime returns the configured transport, not the local fallback.
- [ ] Run relevant native configuration/transport/session tests. Expected: no failures or skips.
- [ ] Commit the persistence change.

### Task 3: Provision, verify, and hand off device play

**Files:** `scripts/install_hosted_coaching_device.py`, `CoachingServer/tests/test_device_setup.py`, `docs/hosted-coaching-server.md`, deployment report and handoff.

**Interfaces:** `install_hosted_coaching_device.py --device <identifier>` reads the Task 1 manifest and Keychain token, builds/signs/installs the existing app, and launches with `DEVICECTL_CHILD_CHESS_TUTOR_COACHING_BASE_URL` and `DEVICECTL_CHILD_CHESS_TUTOR_COACHING_ACCESS_TOKEN`. No token appears in argv or captured diagnostics. Fail clearly if the requested device is missing/untrusted or secrets are unavailable.

- [ ] Add failing CLI tests around real argument/environment construction and captured output, using fake executable boundaries and throwaway secrets. Include arbitrary working directory, bad HTTPS origin, missing secret, installation failure, and explicit device targeting.
- [ ] Implement one-command setup using existing signing settings; keep cloud configuration out of the simulator-only development launcher.
- [ ] Build the app and verify one-time setup followed by environment-free simulator relaunch. Use a deterministic local endpoint for automated transport checks; confirm the deployed endpoint separately with the bounded live smoke test.
- [ ] Run full native/Python/Node suites and a Release/device build as appropriate; inspect actual outputs and zero skips/failures.
- [ ] Obtain one independent whole-branch review, fix important findings with red/green regression tests, and retain security/provenance evidence.
- [ ] Publish the feature PR; report stable server URL, model policy, log retention, and the single command for family iPad setup. Do not claim a physical-device playtest without performing it.

## Preflight

Task 1 produces the manifest consumed by Task 3. Task 2 keeps the launch variable names used by both the existing dev launcher and Task 3. The family token is distinct from each local development server's temporary token. No shared-interface conflict found.

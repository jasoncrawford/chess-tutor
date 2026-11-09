# Hosted coaching development launcher

## Goal

Make simulator-based hosted coaching available through one command with no
manual secret copying or Xcode scheme editing.

## Interface

Running `./scripts/run_hosted_coaching_dev.sh` from anywhere will:

1. read `ChessTutor-CoachingEval-OpenAI` from the macOS Keychain;
2. generate an in-memory local server access token;
3. choose and boot the available `iPad (A16)` Simulator;
4. start the local coaching server on an available loopback port;
5. build, install, and launch ChessTutor with the server URL and access token;
6. keep the server attached to the terminal until Ctrl-C, then stop it cleanly.

The script accepts an optional simulator name for future local variations. It
never prints or persists either secret. Failures stop with a short actionable
message.

## Boundaries

- Simulator development only; physical-device and Vercel deployment remain in
  the existing runbook.
- No changes to coaching behavior, prompts, production configuration, or app
  architecture.
- Build artifacts remain under ignored `DerivedData`.

## Verification

Automated tests exercise simulator selection, secret redaction, command
construction, server readiness failure, and cleanup using controlled fake
processes. A final smoke run uses the real Keychain, local server, iPad (A16)
Simulator, build, install, and launch path without making a coaching request.

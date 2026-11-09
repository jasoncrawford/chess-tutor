# Playable coaching trial and finalist report

The user delegated reference review and model-selection judgment and requested a playable app, with all checks passing before an authorized merge. This is the scoped follow-on to the production-faithful benchmark plan, based on merged PR #18 (`5fd10ce`).

## Decision boundary

The frozen finalist run compares current production Sol against Astra/low with the discovery prompt across all 70 turns, three repetitions each. The development and holdout splits remain separate in reporting. Judge-astra-v4 is qualified against transparently agent-reviewed, provisional references.

Two baseline provider timeouts have already made its full billable cost unknown. Preserve every failed cell, all frozen gates, and the automatic report verdict. Do not treat unknown cost as zero or an ineligible report as automatic promotion. Complete the full run and grading, and inspect flagged responses before choosing the local trial.

If final quality supports Astra, select it explicitly as a **provisional local playtest**, not a deployed production promotion. The default environment application remains Sol. This adapts Task 7 of the earlier plan to honest incomplete cost evidence without blocking a reversible, user-requested playtest. If final quality does not support Astra, do not merge the provisional launcher selection.

## 1. Prepare the reversible launcher change

Implementation may be prepared while the immutable paid comparison finishes; publication and merge remain contingent on final quality review.

- Reuse `Tools/CoachingEval/benchmark/configs/models/astra-discovery-low-model.json` directly; do not duplicate, relocate, or modify it.
- In `scripts/run_hosted_coaching_dev.sh` only, use that file when `CHESS_TUTOR_COACHING_MODEL_CONFIG` is unset. Honor explicit overrides, including empty/invalid values that the existing loader rejects.
- Pass the selection to the server child, not the iPad. Preserve key handling, server readiness/ownership, simulator choice, and cleanup.
- Clearly label the default as a provisional local Astra trial and explicit overrides as explicit selections.
- Leave `CoachingServer/http_app.py`, production configuration, benchmark fixtures, prompts, pricing, rubric, references, and report gates unchanged.

## 2. Test the boundary

Write a launcher regression and observe it fail before implementation. Use the real shell script with fake external commands to verify the server child receives the exact default/override path. Preserve the credential-redaction and shutdown assertions.

Strengthen the existing environment-application override test to load actual Astra through the real configuration loader, while retaining the separate unchanged Sol-default test. Test that empty/invalid explicit selections fail before provider construction.

Run shell syntax checks, focused launcher/factory/configuration tests, the full server suite, and evaluator tests. The unchanged iPad suite must pass in PR CI before merge.

## 3. Finish and assess the frozen evidence

- Preserve 420 requested candidate cells and their real outcomes.
- Grade using an exact-bound accepted judge-v4 qualification. Reuse it while valid; if expired, renew the unchanged judge/reference qualification rather than altering its dates or bindings.
- Generate the offline report without replacing candidate responses.
- Inspect severe flags and low-scoring Astra cases against actual positions and interactions. Distinguish judge false positives from genuine coaching limitations; do not alter stored grades to improve the result.
- Compare quality, pairwise preferences, latency, and usage separately. Identify automatic wins caused by missing baseline responses rather than counting them as wording advantages.
- Report complete Astra cost only if accounting supports it; baseline total cost stays unknown. Preserve any other final limitations.

## 4. Publish the recommendation and playable handoff

Write a concise dated report naming exact model, reasoning efforts, output cap, timeout, attempts, storage/reuse, prompt/compiler, measured quality/latency/cost, automatic verdict, and manual trial decision. Include reproducible artifact identities and representative advice, with provisional reference/judge limitations.

Update the hosted server runbook to distinguish the normal convenience launcher's local trial from the unchanged direct/deployed default, and provide a one-command Sol override.

Review the scoped implementation and report, push one PR targeting `codex/chess-coaching-comparison`, and merge only after all checks pass. Pull the merge locally. Launch the normal script on iPad (A16) without a model override, verify the actual model/effort in logs and usable Help/Hint/staged-move controls, and leave it ready to play.

### Task 5: Support the installed Xcode simulator frontend

**Confirmed failure:** On Xcode 27.2, `open -a Simulator` exits nonzero, and Simulator.app is absent. The installed frontend is `/Applications/Xcode.app/Contents/Applications/DeviceHub.app`, bundle ID `com.apple.dt.Devices`, verified running after opening. `simctl` and simulator builds still work.

**Scope:** `scripts/run_hosted_coaching_dev.sh`, `CoachingServer/tests/test_dev_launcher.py`, and the existing hosted-coaching runbook. Do not change model selection, server startup/credentials/cleanup, or simulator identity.

- [x] Write failing real-shell regression tests: legacy Simulator open succeeds with no fallback; legacy open fails and `open -b com.apple.dt.Devices` succeeds, allowing readiness; both fail, clear diagnostic and no provider/server/build launch. Existing command fakes must record open calls and remain hermetic.
- [x] Replace the single frontend launch with that bounded old/new fallback. Preserve the selected simctl device and fail rather than claiming readiness if both frontends fail. The OS resolves the installed bundle; no download, installation, preferences, or unrelated UI changes.
- [x] Mention Device Hub on current Xcode in the runbook. Run shell syntax checks, focused launcher tests, and full server suite with the sibling benchmark venv if needed. Commit only the scoped changes (the controller owns the plan/report). No push/merge or paid API calls.

Ruling: Include the compatibility fix in the local-trial launcher PR because the verified updated-Xcode failure blocks its promised one-command launch. The fallback retains older Xcode behavior and does not change the app or coaching.

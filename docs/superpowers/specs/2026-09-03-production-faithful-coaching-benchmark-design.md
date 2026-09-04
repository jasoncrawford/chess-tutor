# Production-Faithful Coaching Benchmark Design

Date: 2026-09-03

## Goal

Produce a repeatable benchmark that can support a specific hosted coaching model and parameter recommendation, then make the selected configuration the live server default for an iPad trial.

## Why the current benchmark cannot be used

The pending judge reference set describes an older coaching response contract. All 20 rows narrow the available expected-response values instead of presenting the five choices available to `tutor-v13`; eight rows expose retired primary actions; one row represents a model response after Help has already been closed. The references also state chess facts without a replayable position.

Candidate execution has two production-fidelity defects. It uses one effort for every follow-up even though the server uses low reasoning for tactical events and Hint while reserving the simple setting for other follow-ups. It also passes `previous_response_id` while asking the provider not to store the response, unlike the live server's stored continuation chain.

Finally, qualification measures only absolute scoring even though benchmark recommendations use pairwise judgments. Candidate price coverage and the single-baseline invariant are checked too late.

No paid judge qualification or candidate comparison may run until these defects are corrected.

## Shared hosted-model configuration

A strict `hosted-coaching-model.v1` document will be the sole source for model-facing runtime settings:

- provider and model;
- initial, tactical-follow-up, and simple-follow-up reasoning efforts;
- conversation reuse and response storage;
- maximum output tokens, timeout, and maximum attempts;
- pinned system prompt path and SHA-256;
- prompt generator and response contract.

`CoachingServer.model_configuration.HostedModelConfiguration` will load and validate this document and choose the reasoning effort for one normalized request. The live service and benchmark runner will both consume this object. Benchmark candidate wrappers add only experiment identity, baseline status, and pricing version; they do not duplicate runtime settings.

The live server will load a tracked production configuration by default. A bounded environment override may select another pinned configuration file during development. Promoting a winner therefore changes one tracked production configuration rather than copying parameters into server code.

Stored continuation is required whenever conversation reuse is enabled. Initial requests use the configured initial effort. Follow-ups for `moveStaged`, `moveReplaced`, `squareInspected`, and the Hint action use tactical effort; remaining follow-ups use simple effort. These rules match the current product behavior.

## Replayable judge reference set

The pending reference set remains version 2 because it has never been approved or used for qualification. Its revised document contains:

- provenance, including the existing mandatory human-review gate;
- a pinned `chess-native-v13` response-contract identifier;
- replayable sources copied from the deterministic Swift benchmark export;
- exactly 20 absolute cases; and
- exactly 10 pairwise cases.

Each source stores the exported benchmark case ID, group and step, split, exact neutral request, grader brief, and request SHA-256. The loader recompiles the request through the production `tutor-v13` initial or follow-up compiler and derives `availableUI`; that field is never handwritten. It verifies the source hash and every candidate response against the resulting app contract.

The 20 absolute cases cover all five expected-response types, correct and incorrect responses, latest-action handling, quiet positions, urgent danger, safe and unsafe captures, staged and replaced moves, special rules, Hint escalation, square focus, move focus, answer revelation, stale stages, impossible instructions, beginner wording, and factual errors. Help closing remains in orchestration tests because the app does not request or display a model turn after closing Help.

Each pairwise case uses one replayable source, two mechanically valid responses, a human preference of response one, response two, or tie, and a rationale. The set includes obvious quality gaps and close alternatives. Qualification presents every pair in both orders so positional bias cannot masquerade as agreement.

The deterministic review sheet displays the source ID, FEN, move history, latest interaction, staged move, source/request hashes, derived UI, full candidate controls, scores, flags, winners, and rationales. Human approval applies to this rendered sheet. Agent review can find errors but cannot set human provenance.

## Judge qualification

Qualification remains bound to the judge configuration, judge prompt, structured-output schemas, and reviewed reference-set bytes. It performs three complete passes.

Each pass must achieve:

- at least 95% severe/non-severe agreement across the 20 absolute cases;
- at least 90% of absolute dimension scores within one point of the human score; and
- at least 90% normalized winner agreement across both presentations of the 10 pairwise cases.

Every pair must receive the same normalized outcome in both presentation orders. An order-inconsistent pair counts as incorrect in both rows. Every pass must clear every threshold; averages cannot hide an unstable pass.

Accepted and rejected artifacts retain bounded row evidence, per-pass metrics, minimum observed agreement, all binding hashes, timestamps, usage, latency, and cost. They never retain credentials, raw provider errors, reasoning traces, or unbounded output. Passing artifacts remain reusable for 30 days.

The judge system prompt will explain how each symbolic expected response maps to what the learner can actually do:

- `findEndangeredPiece`: tap an occupied piece or choose “No piece needs help”;
- `findSafeCapture`: tap an opponent piece or choose “No safe capture”;
- `stageMove`: move a piece on the board;
- `judgeMoveSafety`: choose “Looks safe” or “Try another move”;
- `chooseWhetherToPlay`: choose “Play this move” or “Try another move”.

## Paid-run preflight and reports

Before constructing a provider client or making a paid call, candidate execution validates the corpus binding, complete matrix, unique IDs, exactly one baseline in comparison mode, shared pricing version, price coverage for every model, conversation/storage consistency, and all compiled response contracts.

Diagnostic smoke remains ineligible for promotion. Development-only comparisons can narrow the matrix. A recommendation to change production requires a complete holdout comparison, no new mechanical failure category, no higher severe-error rate, a higher strong-response rate, and more pairwise wins than losses. Confidence intervals remain visible evidence; they do not replace those concrete gates. Keeping the current baseline is permitted when no challenger clears them.

Reports preserve quality, latency, and cost separately. They show the reasoning route and storage behavior for each cell, qualification accuracy and age, current-run judge overhead, candidate provider failures, mechanical validity, rubric dimensions, strong-response rate, severe-error rate, blinded pairwise outcomes, and grouped confidence intervals.

## Comparison sequence

After the reviewed reference set qualifies the judge:

1. Run a five-turn diagnostic smoke for each accessible challenger.
2. Run the 56-turn development comparison with three repetitions for configurations that pass smoke.
3. Review worst cases and remove configurations with factual, interaction, or contract regressions.
4. Run the 14-turn holdout, three repetitions, for finalists only.
5. Recommend the best configuration that meets the quality bar, using latency and cost to break quality ties.

Historical local-model work already rules out the tested Qwen, Gemma, and SmolLM candidates for this prompt and tutoring bar. The hosted matrix starts from the production-shaped GPT-5.6 Sol policy and tests the smallest set justified by current official availability and prior results. Access failures are recorded as unavailable and do not cause model substitution.

## Delivery boundaries

The benchmark-fidelity and judge-qualification changes land in the existing issue-15 branch and close issue #15 after live qualification and a diagnostic smoke succeed. The selected model is promoted in a fresh branch based on the merged benchmark work. That second PR changes the tracked production configuration, adds regression coverage, runs the server and iPad suites, and launches the normal app through the development script for a real simulator trial.

## Security and privacy

The API key remains in Keychain and appears only in child-process environment variables. Requests and responses retain the existing bounded artifact rules. No child identity, provider reasoning, raw error body, or secret is stored. Provider calls remain absent from pull-request CI.

## Success criteria

- Human-reviewed replayable absolute and pairwise ground truth.
- A judge that clears every qualification threshold in all three passes.
- Candidate execution behavior identical to the live server for prompt compilation, effort routing, continuation storage, and validation.
- A complete, inspectable comparison report with quality, latency, and cost.
- A specific recommended model and exact parameters.
- The recommendation configured in the live server and verified in a ready-to-try iPad simulator build.

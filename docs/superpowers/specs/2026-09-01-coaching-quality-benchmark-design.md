# Coaching Quality Benchmark Design

Date: 2026-09-01

## Goal

Build a repeatable benchmark for improving ChessTutor's coaching quality while
measuring the latency, reliability, and cost required to achieve it. The first
use is rapid comparison of models, reasoning settings, system prompts, and
deterministic user-prompt generators. The same benchmark later becomes a
regression suite for the chosen production configuration.

The benchmark evaluates tutoring, not merely valid JSON or strong chess play. A
good response must choose the right teaching issue, react to what the learner
just did, encourage discovery rather than prescribe a move, and leave the
learner with a clear action the app actually supports.

## Scope

Version 1 includes:

- deterministic single-turn and multi-turn coaching fixtures;
- immutable experiment configurations and artifacts;
- provider calls through narrow adapters;
- mechanical response validation;
- calibrated automatic absolute and pairwise grading;
- latency, token, reliability, and estimated-cost measurement; and
- reports that compare quality with operational tradeoffs.

It does not alter the live coaching path, add a database, automatically block
pull requests, or choose a production configuration without human review.
Provider calls are never made by ordinary pull-request CI.

## Benchmark corpus

The initial corpus contains exactly 40 independent coaching situations and 10
short interaction sequences. Existing mechanically constructed corpus
positions may be reused where they match the current hosted request contract,
but every fixture is exported through the current production request builder.

The independent situations cover:

- quiet openings and middlegames with nothing urgent;
- real danger, apparent danger, adequate defense, and recapture nuance;
- useful captures, losing captures, equal exchanges, and no available capture;
- piece selection and answer-revealing hints;
- staged, replaced, removed, safe, and unsafe tentative moves;
- checks, mates, castling, promotion, and constrained pieces; and
- ambiguous positions where restraint is better than a confident claim.

The sequences cover initial Help followed by selections, hints, staged moves,
replacements, negative-answer controls, retries, and follow-up advice. They
specifically test continuity, response to the latest action, mixed stages,
repetition, dead ends, and first-call versus follow-up behavior.

Each fixture is built deterministically from a legal committed game history,
board state, current tentative move, learner interaction history, and available
UI responses. Chess rules and replay assertions verify the fixture before any
model call. Model-facing input contains only production-available facts. It
never contains authored coaching conclusions or grading criteria.

Each fixture also has a separate grader brief that is never sent to the
candidate model. It records mechanically verified chess facts, the important
teaching decision, acceptable alternatives, unavailable actions, success
criteria, and severe failures. This lets the grader distinguish, for example,
an unnecessary danger scan in a quiet opening from a false claim that a piece
is actually attacked.

Real problems found in production traces should be promoted into permanent
fixtures. Promotion means recreating the position and interaction sequence as
a deterministic fixture and recording the originating trace identifier in
test-only metadata; raw production logs do not become benchmark inputs.

The corpus is versioned and split into a visible development set and a sealed
holdout set. Ordinary prompt and parameter iteration uses only the development
set. The holdout is run only when a configuration is a serious candidate for
an app trial. Changing a fixture or grader brief creates a new corpus version.

## Experiment configuration

Every result belongs to an immutable configuration manifest containing:

- provider, model, and exact model identifier;
- initial and follow-up reasoning settings;
- conversation-reuse policy and output limit;
- system-prompt path, full text, version, and SHA-256;
- deterministic user-prompt generator version and source hash;
- response schema and validator version;
- benchmark corpus version and fixture split;
- seeds or repetition identifiers; and
- a pinned pricing-table version and effective date.

The runner persists the exact rendered user prompt and sanitized response for
every call. Credentials, provider reasoning, and raw provider error bodies are
never persisted. Existing artifacts are immutable and cannot be overwritten.

This makes model, parameter, system-prompt, and user-prompt-generator changes
first-class and independently comparable. A comparison may vary more than one
field, but the report highlights every changed field so the result is not
mistaken for a controlled single-variable experiment.

## Run modes

Quick mode generates one response per development fixture. It is intended for
fast prompt and parameter iteration and still runs the complete mechanical and
automatic grading pipeline.

Comparison mode generates three responses per fixture and configuration. It
includes the current production configuration as the baseline and performs
both absolute grading and blinded candidate-versus-baseline grading. The same
ordered fixtures and repetition identifiers are used for every configuration.

Multi-turn sequences use the configuration's real conversation policy. The
initial turn and follow-ups may use different reasoning settings, and follow-up
calls may continue the provider conversation exactly as production does. If a
turn fails transport or mechanical validation, later turns in that sequence
are marked blocked rather than supplied with invented model history.

## Grading pipeline

### 1. Mechanical gate

Existing strict response decoding and request-aware validation run before
semantic grading. They check schema shape, unknown fields, message bounds,
valid and unique actions, valid focus references, available UI controls,
request identity, trace removal, and other deterministic contract rules.

Mechanical failures remain visible in all reports, are classified as unusable,
and are not sent to the semantic judge. In pairwise grading, an invalid response
loses to a valid response; two invalid responses are recorded as an unusable
tie. This avoids paying a judge to evaluate output the app cannot display.

### 2. Absolute rubric

A pinned strong hosted judge receives the grader brief, current app state and
UI contract, and one anonymized candidate response. It does not receive the
candidate configuration's identity. It returns structured 1-5 scores for:

1. **Chess correctness** — claims, consequences, and suggested exploration
   agree with the position.
2. **Coaching judgment** — the response chooses the most useful current issue
   and avoids ritual questions when the answer is obvious.
3. **Latest-action responsiveness** — it follows the learner's current
   selection, move, answer, or changed mind rather than an obsolete step.
4. **Discovery and independence** — it supplies an appropriate clue or
   question instead of unnecessarily telling the learner which move to play.
5. **Coherence and answerability** — it presents one current teaching step,
   avoids mixed stages, and can be answered through the available board or
   controls.
6. **Child clarity** — it is concise, natural, notation-light, and suitable
   for an intelligent young beginner.

Scores use common anchors: 1 is unusable, 3 is usable with a material weakness,
and 5 is exemplary. The judge must also return short evidence tied to the
fixture and explicit boolean flags for factual/illegal advice, wrong urgent
priority, obsolete-stage advice, mixed stages, answer-revealing guidance,
unavailable UI or dead ends, and severe error.

An unnecessary safety scan in a quiet opening lowers coaching judgment. It is
severe only when the response invents danger, prevents meaningful progress, or
combines that mistake with another severe condition.

### 3. Blinded pairwise comparison

In comparison mode, a separately ordered judge request presents the production
baseline and candidate response as anonymous A and B. Order is randomized and
recorded. The judge selects A, B, or tie and explains the decision using the
same tutoring priorities. Chess correctness and the ability to continue the
interaction outrank stylistic preference.

Absolute scores show why a configuration behaves as it does. Pairwise results
answer the practical question of whether it is better than what is currently
shipping.

### Judge calibration

The judge prompt, model, settings, schema, and hashes are pinned per benchmark
version. Before accepting a benchmark run, the judge is tested against at
least 20 human-scored calibration examples containing both good responses and
known severe failures. It must match human severe/non-severe classification on
at least 90% of examples and be within one point of the human score on at least
80% of positive-dimension ratings. A failed calibration invalidates the
automatic grading run rather than silently changing the judge.

Calibration examples and candidate responses are kept separate. The judge
never sees model names, prices, latencies, or prior scores while grading.

## Operational measurements

Every candidate call records:

- end-to-end wall-clock latency;
- provider latency and time to first token when the provider exposes them;
- initial-turn versus follow-up latency;
- input, cached-input, reasoning, and output tokens;
- estimated call cost from the run's pinned pricing table;
- transport outcome, timeout, provider status category, and retry count; and
- parse and validation outcome.

Reports show totals, rates, median, p90, and per-fixture outliers. Cost is shown
per response, per complete game sequence, and per benchmark run. Pricing
changes never rewrite old reports; a new price table produces a new estimate.

## Reporting and decisions

The benchmark does not collapse quality, latency, and cost into one opaque
score. Each configuration reports:

- mechanical-validity and provider-success rates;
- severe-error rate;
- mean and distribution for every rubric dimension;
- the rate of responses scoring at least 4 on all six positive dimensions;
- pairwise wins, losses, and ties against production;
- quality breakdown by scenario category and initial versus follow-up turn;
- latency and token distributions; and
- estimated cost.

The comparison report highlights the Pareto frontier: configurations for which
no other tested configuration is simultaneously higher quality, faster, and
cheaper. It also shows paired confidence intervals so three unusually lucky
responses do not masquerade as a clear improvement.

Version 1 is advisory. A configuration is eligible for a human app trial when
it introduces no new mechanical contract class, does not increase severe
errors over production, wins more pairwise comparisons than it loses, and
improves the all-dimensions-at-least-4 rate. Latency and cost remain explicit
product tradeoffs rather than hidden pass/fail weights.

After calibration and several trusted runs, pull-request CI may block on
deterministic fixture, schema, and mechanical-validator regressions. Provider
inference and judge calls remain opt-in because they require credentials, have
variable cost and latency, and can fail for external reasons.

## Components and data flow

1. **Fixture exporter** builds and verifies production-shaped structured
   requests plus separate grader briefs from pure chess state.
2. **Configuration loader** resolves immutable prompts, generators, provider
   settings, schemas, pricing, and hashes.
3. **Experiment runner** preflights all cells, executes provider calls, and
   writes immutable sanitized records.
4. **Mechanical validator** applies the existing strict request-aware response
   contract.
5. **Automatic grader** runs calibration, absolute grading, and blinded
   pairwise comparisons with structured outputs.
6. **Reporter** verifies artifact completeness and produces machine-readable
   aggregates plus a concise Markdown comparison.

The evaluation package remains outside the shipping ChessTutor target. The app
and production server may supply request-building code and schemas, but they do
not import the benchmark runner or grader.

## Failure handling and reproducibility

The runner preflights the complete requested matrix before the first paid call.
It rejects missing fixtures, duplicate cells, prompt or generator hash drift,
unknown model aliases, incomplete price entries, invalid grader calibration,
and an existing destination.

Individual provider failures are recorded generically and later cells continue.
No response is semantically repaired. A bounded retry is allowed only when the
experiment configuration explicitly includes that production retry policy;
the retry is measured and costed. Missing cells, blocked sequence turns, or
grader failures make the run incomplete and prevent a promotion recommendation.

Run manifests bind source revision, corpus, prompts, generators, schemas,
provider settings, price table, records, grades, and reports by hash. Given the
same stored responses and grades, report regeneration is deterministic. A later
judge version creates a separately identified regrade artifact rather than
rewriting the original result.

## Verification

Implementation must include tests for:

- deterministic fixture replay, export, split integrity, and oracle isolation;
- immutable configuration resolution and exact changed-field reporting;
- complete quick and comparison matrices;
- stateful sequence continuation and blocked-turn accounting;
- mechanical gate precedence;
- judge calibration acceptance and rejection;
- blinded randomized pairwise ordering and identity isolation;
- token, latency, retry, and cost accounting;
- Pareto and confidence-interval calculations;
- generic error persistence and secret/trace exclusion;
- atomic artifact writing and refusal to overwrite; and
- report regeneration from stored responses without provider access.

Fake providers and a fake judge cover ordinary CI. A small explicit live smoke
proves each real provider and judge adapter before a paid benchmark run.

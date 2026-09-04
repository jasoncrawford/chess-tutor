# Judge Qualification Design

Date: 2026-09-03

## Goal

Make the automatic coaching judge trustworthy enough for benchmark comparisons without paying for a full calibration before every benchmark run.

## Reference set

The current `judge-calibration-v1.jsonl` is provisional: its `humanScores` and `humanFlags` were authored during implementation, were not independently human-reviewed, and do not consistently use the same payload shape as real grading calls.

Version 2 replaces it with one structured reference-set document. Each of its 20 cases uses the real absolute-grading payload shape: `graderBrief`, `availableUI`, and `candidateTurn`. It records six proposed reference scores and seven proposed reference flags. Top-level provenance distinguishes an agent-authored proposal from a product-owner-reviewed reference set.

The repository also contains a deterministically rendered Markdown review sheet. A test requires it to match the JSON source. Real qualification refuses a reference set unless its provenance says it was human-reviewed, names the reviewer, and records the review date. The product owner must explicitly approve or amend the proposed judgments before those provenance fields are set.

## Qualification

Qualification applies to one immutable combination of judge model and settings, judge prompt, absolute and pairwise schemas, and reviewed reference set. A qualification performs three complete passes over the 20 reference cases.

Every pass must achieve:

- at least 95% agreement on severe versus non-severe; and
- at least 90% of dimension scores within one point of the reviewed reference score.

These thresholds deliberately leave margin over the former 90%/80% single-pass gate. Every pass must clear both thresholds; averaging cannot hide an unstable pass.

The command publishes an immutable qualification artifact containing all row-level comparisons, per-pass results, the minimum observed agreement, all binding hashes, creation and expiration timestamps, and qualification-only latency, token, and cost metrics. Rejected attempts are preserved with the same diagnostics. Passing qualifications remain valid for 30 days.

## Benchmark workflow

The one-command launcher checks for a current compatible qualification before exporting a corpus or calling any candidate. It reuses the newest unexpired compatible artifact. If none exists, it attempts qualification first and stops before candidate inference if qualification fails.

Ordinary grading receives the selected qualification artifact and validates its status, expiration, reference provenance, and all binding hashes. It makes only candidate-grading and pairwise judge calls; it never recalibrates. The first version does not add per-run canary calls. The 30-day lifetime provides periodic drift detection without adding routine latency and cost.

Reports bind the qualification artifact and display its age and minimum agreement. Qualification cost and latency are reported separately and are not counted as overhead for the current benchmark run.

## Security and compatibility

Credentials, provider error bodies, and reasoning traces remain excluded from artifacts. Qualification outputs follow the existing bounded structured-output validation. Old benchmark artifacts remain readable through the existing legacy `calibration.json` report path, but new grade runs require a version-2 qualification.

## Non-goals

- Changing the live iPad coaching path.
- Retrying provider requests.
- Automatically promoting a candidate model.
- Treating agent-authored scores as human ground truth.

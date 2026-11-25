# Evaluate judgment before changing the coach

## Purpose

The coach is coherent and usually factually accurate, but can describe a move without helping the child decide whether it is worthwhile. It can also overemphasize immediate threats instead of development, activity, counterplay, or a useful plan. Improve this without losing concise language, learner agency, contextual continuity, or the existing visual interactions.

## Experiment

Freeze a separate native-exported development suite and its grading policy before changing the coach. Include proposed moves and requested hints, quiet development, purposeful and unnecessary retreats, active tactical responses, favorable exchanges with recaptures, and endgame goals. Include positive controls: retreat is sometimes right; a sensible move need not be the engine's first choice.

Use the existing six rubric dimensions. Make **coachingJudgment** the primary endpoint, reporting its distribution and each case separately, rather than hiding it in a six-dimension average. A true description without a relevant assessment or decision-useful reason should score at most 3. A concise, well-supported evaluation should score 4–5; no required wording, mandatory comparison, or extra lecture. Chess errors remain separate failures. Do not require strategic commentary when an immediate tactical consequence is decisive.

The private grader brief contains verified reference facts and criteria; the candidate receives only the normal deterministic app request. Paired sensitivity controls must show that the judge distinguishes weak description from useful evaluation, accepts necessary retreats, and rejects unsupported aggressive advice. These are implementer-authored controls, not human calibration.

Run the unchanged `visual-v5` coach first. Preserve every failure and response. If it scores unexpectedly well, inspect the evidence; do not tune the rubric to manufacture a poor baseline. Only after that baseline, compare a revised prompt with the same model/effort, then that prompt with compact Stockfish evidence. Keep versioned prompts and configs, fixed cases, three repetitions, and a shared budget journal. Engine settings and binary identity must be recorded. Engine scores are evidence, not a child's win probability, and not a required move list.

## Boundaries and acceptance

- Benchmark and experimental configurations only; no production deployment, UI changes, or issue #29 work.
- Keep old corpora and results intact. New cases are development regressions, not an untouched holdout.
- Candidate improvement requires better judgment without new serious chess or interaction errors. Report cost, latency, failures, sample size, and uncertainty; a small suite is directional evidence, not proof of general superiority.
- Total authorized API spending/reservations: **$10**, across judge checks, baseline and experiments. Stop paid work at the cap; do not reuse previous authorizations.
- Stockfish does not explain strategy. The coach must not invent reasons for an engine preference. Prefer understandable sound choices over tiny score differences.

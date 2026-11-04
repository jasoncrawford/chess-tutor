# Coaching playthrough — November 3, 2026

## What was tried

Played both sides on the separate **ChessTutor Coaching Smoke** simulator using the released Astra/low discovery configuration. The owner's A16 game was not touched. Played through the opening `1. e4 e5 2. Bc4 Nf6 3. d3 Nc6 4. Nf3 d6`, then staged castling. This was an opening walkthrough, not a complete game to mate.

The 20 live requests included a tentative edge-pawn move, replacing it, ignoring a knight suggestion in favor of a bishop, selecting the wrong endangered pawn, selecting the right pawn, trying `Bxf7+`, incorrectly answering “Looks safe,” reconsidering, and requesting Hint. All returned valid HTTP 200 responses. The UI correctly followed changed plans, identified danger, corrected the losing capture, and accepted castling instead of another knight move.

## Findings

1. **A factual teaching mistake.** After d3, the tutor said “Now your pawns protect each other!” The d3 pawn protects e4; e4 does not protect d3. This recurred in a fresh baseline replay. Trace: `22bdd2592aa2`, game `6d602631-c239-4dd6-a063-c8f17caa0a8d`.
2. **Generic move acknowledgement.** Bc4 received “Your bishop is joining the game!” and Nf3 received “Your knight joins the game near the middle.” Accurate enough, but they teach little about this particular move.
3. **An overstatement in the first revision.** More concrete wording improved the explanations but described Nf3 as “making Black defend” an already-defended pawn. That revision was not selected unchanged.

The opening Help suggestions still sometimes choose a type of piece for the child. This work does not claim to settle every question about how directive the tutor should be.

## Change and evidence

The new `tutor-v13-discovery-v2.md` asks for one observable consequence of a staged move, accurate direction of attack/defense, and no invented forced reply. It preserves discovery-oriented Help, precise Hint, current-action precedence, and the existing interaction contract. No rule engine, compiler, model, reasoning setting, or production server default changed.

The Swift test `CoachingPlaythroughRegressionTests/testPlaythroughFactsAndOptInExport` replays the actual legal move histories and generates 20 neutral requests with the app's production builder. It independently checks the pawn-defense direction and the king's available capture after `Bxf7+`. These diagnostics do not alter the frozen 70-turn benchmark or holdout.

- Original prompt: all 20 scripted replay responses retained. Reproduced generic development feedback and the mutual-pawn-defense error.
- First revision: 19 responses retained. The final castling response was not sent because the diagnostic's conservative pre-call budget guard stopped it. The saved service-level `providerUnavailable` row reflects that **local budget stop**, not an OpenAI outage; no API attempt or cost reservation exists for that row.
- Tightened revision: seven fresh full-context staged-position checks, including two repetitions each for d3 and Nf3. All mechanically valid; inspection found no factual error in those seven. These use fresh requests rather than the longer stored conversations, so they are not a matched latency comparison or a broad quality score.

| Situation | Original live feedback | Tightened revision example |
| --- | --- | --- |
| Bishop developed | “Your bishop is joining the game!” | “Your bishop now attacks a pawn near Black's king.” |
| Pawn defense | “Now your pawns protect each other!” | “Your moved pawn now protects your pawn on e4.” |
| Black knight developed | “Your knight now helps control the middle.” | “Your knight now protects your pawn on e5.” |
| White knight developed | “Your knight joins the game near the middle.” | “Moving your knight opens the way for your king to castle later.” |

Each quoted explanation above is followed by a keep/change choice in the actual output. The scripted replays preserve historical player actions even when a newly sampled prior response chooses different controls; they are not adaptive simulated learners. In particular, the historical “Looks safe” action follows a keep/change response in some replays. The original simulator walkthrough supplied the actual interactive evidence.

## Limits and cost

No claim of perfect coaching or an improved 87% benchmark score is made. The October score applies to the original prompt. The seven final fresh checks took roughly 3–9 seconds, so explanation quality may cost latency; the normal conversation follow-up path must be checked separately.

Conservative API estimate through the focused checks: **$2.13**, including the original live walkthrough and both replay iterations. The round's ceiling is $2.50. Estimates use $12.50/M uncached input (including the conservative cache-write premium), $1/M cached input, and $50/M output; they are not an invoice. No judge qualification or paid automatic grading was run.

## Reproduction and retained artifacts

Artifacts are ignored under `.coaching-eval/playthrough/20261103/` in the retained `coaching-playthrough` worktree: `baseline-live-turns.jsonl`, `requests.json`, `old-responses.jsonl`, `new-responses.jsonl`, `revision-1-prompt.md`, `revision-2-focused.jsonl`, and `budget.jsonl`. The live tail starts at request 2; the first Help response was “Let’s make room for your pieces! Can you move a middle pawn toward the center?” (trace `d78d5e761e6e`, 4.41 seconds, 1,280 input and 46 output tokens). The cost total includes it.

For a fresh export, run the named XCTest with test-runner environment variable `COACHING_PLAYTHROUGH_OUTPUT_DIR` pointing at an existing empty directory. It writes `requests.json` without overwriting an earlier export. No test invokes the paid API.

The convenience launcher selects `Tools/CoachingEval/benchmark/configs/models/astra-discovery-v2-low-model.json`. The previous trial remains available via `CHESS_TUTOR_COACHING_MODEL_CONFIG=Tools/CoachingEval/benchmark/configs/models/astra-discovery-low-model.json`. Direct/deployed startup remains on Sol.

At this checkpoint the 333 evaluator tests passed; the complete native/server runs and final live revised-prompt check are being completed. Final handoff results will be appended below.

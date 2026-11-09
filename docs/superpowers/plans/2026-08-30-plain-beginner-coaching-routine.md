# Plain Beginner Coaching Routine Prompt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Safe/Take/Wake mnemonic with the approved plain-language beginner routine and regenerate the exact human-review prompts without inference.

**Architecture:** Change only the versioned system-prompt text and its boundary test. Reuse the existing structured Swift examples, immutable exporter, and tokenizer-only preview pipeline so the generated user messages and complete SAN history remain mechanically derived.

**Tech Stack:** Python `unittest`, Swift/XCTest exporter, pinned llama.cpp `/health`, `/apply-template`, and `/tokenize` endpoints.

## Global Constraints

- Do not invoke completion, generation, scoring, hidden-set work, or inference.
- Preserve the deterministic neutral request/compiler and all eight structured fixtures.
- Preserve complete committed SAN history and separate tentative moves.
- Refuse prompt artifacts above 2,500 tokens.
- Stop after producing the fresh eight-prompt packet for user review.

---

### Task 1: Replace the mnemonic and refresh the review packet

**Files:**
- Modify: `Tools/CoachingEval/tests/test_tutor_v5_prompt.py`
- Modify: `Tools/CoachingEval/prompts/tutor-v5.md`
- Reuse: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingNeutralPromptExampleTests.swift`
- Reuse: `Tools/CoachingEval/preview_neutral_prompts.py`

**Interfaces:**
- Consumes: the approved plain beginner routine and the existing eight structured neutral snapshots.
- Produces: an immutable Swift export and tokenizer-only packet containing eight complete system/user transcripts.

- [ ] **Step 1: Write the failing prompt-boundary test**

Replace the Safe/Take/Wake assertions with requirements for `urgent danger`, `threatened piece`, `opponent reply to a tentative move`, `simple captures`, `one-move tactical opportunities`, `quiet improvement`, and `respond first to what the child just did`. Assert that `safe/take/wake` and `optional reasoning lens` are absent.

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s Tools/CoachingEval/tests -p 'test_tutor_v5_prompt.py' -v
```

Expected: failure because the current prompt still contains the mnemonic and lacks the plain routine.

- [ ] **Step 3: Replace the system-prompt paragraph**

Use the approved wording:

```text
The child is a beginner, so prefer immediate, understandable ideas over deep tactics. Use a simple priority order. First, notice any urgent danger: check, a threatened piece, or a strong opponent reply to a tentative move. Next, notice simple captures or one-move tactical opportunities. If neither is pressing, look for a quiet improvement that brings a piece into play, protects something, controls useful squares, or improves king safety. Use this routine flexibly; respond first to what the child just did.
```

Keep the surrounding neutral-evidence, latest-interaction, and exact JSON-contract paragraphs unchanged.

- [ ] **Step 4: Run prompt tests and verify GREEN**

Run the Step 2 command. Expected: all prompt-boundary tests pass with zero skips.

- [ ] **Step 5: Regenerate immutable structured and tokenizer-only artifacts**

Export the same eight Swift fixtures into fresh directories, then invoke `preview_neutral_prompts.py` against the pinned Qwen3 1.7B tokenizer/template endpoints. Do not call any completion endpoint.

- [ ] **Step 6: Verify prompt integrity and budgets**

Assert exactly eight ordered prompts, complete system/user transcript equality, complete SAN history in the long-history case, separate tentative moves, no responses/traces/hidden IDs, no Safe/Take/Wake mnemonic, and token counts from 1 through 2,500.

- [ ] **Step 7: Run proportional verification**

Run the focused prompt test, tokenizer-preview tests, neutral prompt example XCTest, and `git diff --check`. Expected: zero failures or skips.

- [ ] **Step 8: Commit**

```bash
git add Tools/CoachingEval/prompts/tutor-v5.md \
  Tools/CoachingEval/tests/test_tutor_v5_prompt.py
git commit -m "refine: explain beginner coaching routine"
```

Do not commit ignored generated artifacts. Return their exact paths, hashes, and token counts to the user, then stop for review.

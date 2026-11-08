# Production-History Prompt Examples Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild neutral coaching examples 02–07 from legal move histories and regenerate the exact prompt-review packet without inference.

**Architecture:** Modify only the structured Swift fixture construction and its exact scenario/history assertions. Continue using the existing neutral builder/compiler, immutable exporter, approved `tutor-v5` system prompt, and tokenizer-only preview pipeline.

**Tech Stack:** Swift/XCTest, `GameState`, `LegalMoveGenerator`, `MoveHistoryFormatter`, Python `unittest`, pinned llama.cpp template/tokenizer endpoints.

## Global Constraints

- Do not invoke completion, generation, scoring, hidden-set work, or inference.
- Every committed position in examples 02–08 must come from legal replay from the standard starting position.
- Preserve each example's interaction purpose and keep tentative moves separate.
- Preserve exactly eight visible examples in the existing order.
- Refuse prompt artifacts above 2,500 tokens and stop for user review.

---

### Task 1: Replace synthetic positions with replayed histories

**Files:**
- Modify: `ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingNeutralPromptExampleTests.swift`
- Reuse: `Tools/CoachingEval/preview_neutral_prompts.py`
- Test: `Tools/CoachingEval/tests/test_preview_neutral_prompts.py`

**Interfaces:**
- Consumes: coordinate move arrays replayed by `replaying(_:)`, structured selection/tentative/events, and the existing exporter.
- Produces: eight requests whose complete committed SAN histories and FENs are mechanically consistent.

- [ ] **Step 1: Strengthen fixture tests and verify RED**

Assert exact histories:

```swift
[
    [],
    ["Nf3", "e5", "g3", "e4"],
    ["Nf3", "e5", "g3", "e4"],
    ["e4", "e5"],
    ["e4", "e5", "Bc4", "a6"],
    ["e4", "e5", "Bc4", "Qh4"],
    ["e4", "e5", "d3", "Bb4+"],
    ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6", "Ba4", "Nf6"],
]
```

Require examples 02–08 to have nonempty history and retain the attacked-piece, selected-piece, replacement, tactical-reply, inspected-reply, and answer-check invariants. Run the focused example XCTest and expect failures because examples 02–07 currently have no history.

- [ ] **Step 2: Rebuild examples 02–07 with legal replay**

Use these coordinate histories and interaction adjustments:

- 02/03: `g1f3 e7e5 g2g3 e5e4`; keep knight f3 attack/selection.
- 04: `e2e4 e7e5`; keep staged h2-h4 replaced by tentative g1-f3.
- 05: `e2e4 e7e5 f1c4 a7a6`; keep tentative c4-b5 and reply a6-b5.
- 06: `e2e4 e7e5 f1c4 d8h4`; tentative b1-c3; inspect `piece:black:queen:h4`; require matching replies `h4-e4`, `h4-f2`, and `h4-h2`.
- 07: `e2e4 e7e5 d2d3 f8b4`; tentative c1-d2; require White in check and reply b4-d2.

Set `positionRevision` equal to each committed ply count. Remove custom sparse-state helpers that become unused.

- [ ] **Step 3: Run focused Swift tests and verify GREEN**

Run:

```bash
xcodebuild test -quiet -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:ChessTutorTests/ModelCoachingNeutralPromptExampleTests \
  -only-testing:ChessTutorTests/ModelCoachingNeutralRequestBuilderTests \
  -only-testing:ChessTutorTests/ModelCoachingNeutralContextCompilerTests
```

Expected: all focused tests pass with zero skips.

- [ ] **Step 4: Regenerate fresh immutable packets without inference**

Write the Swift artifacts to a new empty directory using `COACHING_NEUTRAL_PREVIEW_DIR`, then run `preview_neutral_prompts.py` to a new empty destination using only `/health`, `/apply-template`, and `/tokenize`.

- [ ] **Step 5: Verify exact artifacts**

Assert eight ordered prompts, exact system/user equality, example 01 alone has `Moves: none`, examples 02–08 contain their exact SAN histories, tentative moves remain separate, hashes match, token counts are 1–2,500, and no response/assistant/trace/hidden/inference artifacts exist.

- [ ] **Step 6: Run proportional checks and commit**

Run prompt-boundary and tokenizer-preview Python tests, `git diff --check`, and the focused Swift suite. Commit only the fixture/test change:

```bash
git add ChessTutorTests/Coaching/ModelEvaluation/ModelCoachingNeutralPromptExampleTests.swift
git commit -m "test: use legal histories in coaching prompts"
```

Return the new artifact paths, hashes, histories, and token counts, then stop for user review.

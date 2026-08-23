# Compact, coherent coaching turns

**Date:** 2026-08-23  
**Status:** Approved design

## Goal

Make on-demand coaching understandable to a child of about five. At every moment, the panel should say one clear thing, ask for one clear action, and remain factually consistent with the current board.

This revision addresses a systemic problem in the current implementation: feedback about the child's last action, the current question, and the next instruction are authored and rendered independently. That permits duplicated prompts, stale instructions, leaked purposes, long headlines, and tactical claims that have not yet been verified.

The revision remains deterministic and offline. It does not add Stockfish, an LLM, curriculum, settings, or a new coaching mode.

## Product principles

1. The tutor speaks to a young child, not to a developer or chess annotator.
2. One screen presents one current coaching turn.
3. Tactical truth comes before strategic commentary.
4. A purpose belongs to an exact piece or move. It cannot leak to another selection.
5. The tutor asks a question only when answering it has teaching value.
6. Every tap, drag, move, replacement, or undo rederives the turn from the current board.
7. The tutor may admit a limited judgment, but it does so in simple language.

## Presentation contract

Replace the independently authored response, headline, and instruction with one compact presentation:

```swift
struct CoachingPresentation {
    let primaryMessage: String
    let instruction: String?
    let observation: String?
    let actions: [CoachingActionPresentation]
    let boardTask: CoachingBoardTask
    let routine: [CoachingRoutineState]
    let focus: CoachingFocus
}
```

The names are illustrative; implementation may migrate the existing type rather than replace it wholesale.

The visual and accessibility order is always:

1. `primaryMessage` — the tutor's main thought or question, in the larger coaching font;
2. `instruction` — the child's next physical action, in the smaller font;
3. `observation` — optional feedback about the previous tap, in the smaller font.

The observation is omitted unless it adds a useful fact. It never repeats or contradicts the primary message or instruction.

### Copy size

- The primary message is normally one sentence and roughly 4–12 words.
- The instruction is one short imperative.
- The observation is one short factual sentence.
- A longer named relationship may exceed the normal word target, but should still be one sentence.
- The panel never uses multiple text fields merely to continue one thought.

### Current-action invariant

The instruction describes what the child can do next. Once a bishop has moved, the instruction cannot still say “Move the bishop.” Once a reply piece has been identified, the panel cannot keep asking the child to identify it.

## Coaching decision flow

After every interaction, derive a fresh coaching turn in this order:

1. The learner's king is in check.
2. A learner piece faces a meaningful material danger.
3. A safe capture is available.
4. A verified opening or positional task is available.
5. A tentative move is being evaluated.
6. No supported plan is available.

When a tentative move exists, evaluate it in this order:

1. The move is illegal or leaves the learner's king in check.
2. A concrete opponent reply creates check or meaningful material loss.
3. The exact move achieves a supported purpose.
4. The move is tactically acceptable but has no supported strategic explanation.

No copy may call a move safe before the tactical evaluation has completed. No strategic criticism should distract from a concrete tactical problem.

### Safe but strategically unclear

If the immediate tactical evaluation is acceptable but no supported purpose belongs to the exact move, say:

- **Primary:** That move seems safe.
- **Instruction:** Play it, or try another move.

Do not mention “verified purpose,” evaluator confidence, the system's limits, or an invented strategic lesson.

## Exact evidence binding

Every strategic statement is bound to the evidence that supports it:

- opening development identifies the exact starting knight, bishop, or center pawn;
- central activity identifies the exact source, destination, and before/after mobility fact;
- protection identifies the protecting piece and protected piece;
- a threat identifies the attacker and target;
- tactical safety identifies the exact assessed tentative move;
- opponent feedback identifies the actual opponent source, destination, and affected learner piece.

Selecting or moving an unrelated piece does not inherit the active task's purpose. For example, selecting or moving the h-pawn cannot produce “move closer to the center” merely because another available move has central-activity evidence.

The term **develop** retains its plain chess meaning: moving a knight or bishop off its starting square toward active play. Leaving the starting square may establish the factual development accomplishment, but it does not by itself prove that the move is safe or strong.

## Opponent-response coaching

The opponent-response question is evidence-gated rather than universal.

Ask it when the resulting position is tactically live:

- the opponent has a legal checking move; or
- the opponent has a legal capture of a learner piece.

Skip it when neither exists. This naturally skips the pointless scan after quiet first moves such as `g1–f3`, while retaining the exercise in later positions where checks or captures are visible.

The question uses the evaluator's real acceptance rule:

- **Primary:** What could Black do next?
- **Instruction:** Tap a black piece that could check your king or win one of your pieces.

Production substitutes the actual opponent color.

An opponent source is an accepted answer when it has a legal checking reply or a materially meaningful capture. A source with only a harmless or losing capture is not accepted as the answer, but the tap is acknowledged with a concrete observation. For example:

- **Observation:** That bishop attacks your pawn, but the pawn is protected.

The child remains on the same question and may choose **Looks safe**. A correct Looks-safe answer completes with the simple bounded copy “That move seems safe.” It does not claim that the opponent has no checks, attacks, or captures anywhere on the board.

If a concrete dangerous reply exists, the tutor may ask the child to find it. After the source is found—or after the hint reveals it—the tutor names the consequence and asks for a revision. Tactical copy takes precedence over development or other strategic commentary.

## Child-facing vocabulary

Preferred terms:

- **safe / seems safe** — no immediate check or meaningful material loss was found;
- **attack** — the piece could take the target on its next move;
- **protected** — taking the piece can be answered;
- **win a piece** — the immediate exchange leaves that side ahead;
- **develop** — introduced with “move a knight or bishop off its starting square.”

Prohibited child-facing language includes:

- verified purpose;
- qualifying issue;
- immediate-response scan;
- material or material loss;
- cannot name a purpose;
- bring a new piece into the game;
- more useful place;
- implementation-oriented confidence or capability disclaimers.

## Revised acceptance transcripts

### Quiet first move

Starting position, Help, then `g1–f3`:

- **Primary:** You developed your knight toward the center.
- **Instruction:** Play it, or try another move.
- **Actions:** Play this move; Try another move; Close help.
- **Opponent question:** omitted because Black has no legal check or capture.

### Outside pawn on the first move

Starting position, Help, then `h2–h4`:

- **Primary:** That move seems safe, but a center pawn or knight is a simpler start.
- **Instruction:** Play it, or try another move.
- No center-purpose or central-mobility evidence is attached to the h-pawn.

### Bishop moved into a pawn capture

Use a position equivalent to `1.e4 e6`, then stage `Bf1–a6`, where `...b7xa6` is legal and wins the bishop.

Before the reply is identified:

- **Primary:** What could Black do next?
- **Instruction:** Tap the black piece that could win your bishop.

After the b7 pawn is identified:

- **Primary:** Black's pawn could take your bishop.
- **Instruction:** Try a different bishop move.

The panel never calls the move safe and never repeats the already-completed “Move the bishop” instruction.

### Attack that does not win a piece

White bishop on c4; Black stages `e7–e6`. White's bishop attacks e6, but Black can recapture the bishop.

If the child taps the c4 bishop:

- **Primary:** What could White do next?
- **Instruction:** Tap a white piece that could check your king or win one of your pieces.
- **Observation:** That bishop attacks your pawn, but the pawn is protected.

After **Looks safe**:

- **Primary:** That move seems safe.
- **Instruction:** Play it, or try another move.

### Selection and move replacement

For opening tasks and all other coaching states, direct derivation from the final selection or tentative move must equal derivation after any history of other taps, drags, moves, hints, and replacements. No rewind-specific copy is authored.

## Architecture

The existing provider boundaries remain useful:

1. **Evaluator** emits chess facts: legal moves, danger, exchange outcomes, checks, captures, benign attacks, and exact move assessments.
2. **Insight source** attaches supported concepts only to exact evidence-bearing pieces and moves.
3. **Reconciler** chooses one current semantic coaching task from the current snapshot.
4. **Presentation projector/explainer** authors the primary message, instruction, observation, actions, and focus as one coherent turn.
5. **SwiftUI** renders the turn in the specified order without deriving chess or conversational logic.

This preserves the future ability to replace or supplement the explainer with an LLM or the evaluator with an engine. AI may generate wording or additional facts later, but it must still satisfy the same compact-turn and evidence contracts.

## Structural invariants and tests

Add corpus-wide assertions over every produced coaching presentation:

- primary message is nonempty and normally one sentence;
- primary, instruction, and observation contain no duplicate normalized sentence or clause;
- every instruction describes an action currently available on the board or in the action list;
- observation appears after instruction in visual and accessibility order;
- safety language requires an exact completed tactical assessment;
- every purpose names evidence attached to the current selected piece or tentative move;
- every named attack/protection/danger relationship has matching board focus or factual payload;
- quiet positions do not show an opponent-response question;
- tactically live positions use “check or win,” never the broader “take” acceptance claim;
- all prohibited phrases are absent from generated child-facing output.

Regression tests exercise real `CoachingSession` and `GameSession` pipelines, not the explainer alone. New evaluator fixtures cover the unsafe a6 bishop and the protected e6 pawn. Existing Safe/Take/Wake, history-independence, color-mirror, dynamic-type, and accessibility suites remain green.

Direct simulator UAT covers standard and accessibility-extra-large text in both panel compositions. It exercises all four revised acceptance transcripts, selection replacement, scrolling, action availability, board focus, and the visual order `primary → instruction → observation`.

## Success criteria

The revision is complete when:

1. the reported scenarios produce the approved compact transcripts;
2. no current instruction describes an action already completed;
3. no purpose leaks to an unrelated piece or move;
4. no move is called safe before tactical evaluation;
5. the first quiet move does not trigger the opponent quiz;
6. benign opponent attacks are acknowledged without being misclassified as winning replies;
7. the panel displays one clear primary utterance with minimal supporting text;
8. all focused, full-scheme, accessibility, and simulator UAT gates pass with zero skipped tests.

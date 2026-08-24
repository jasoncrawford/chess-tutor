# Coaching panel continuity and response hierarchy

**Date:** 2026-08-24
**Status:** Approved interaction direction; awaiting written-spec review

## Context

The on-demand coaching panel currently has two visible problems:

1. After the learner stages or replaces a move, the sidebar briefly returns to the ordinary game UI before coaching reappears.
2. An optional response to the learner's last action is typographically too similar to the instruction that tells them what to do next.

The intended experience is quiet and continuous. Coaching should feel like one tutor staying with the learner, not a panel repeatedly closing and reopening.

## Goals

- Keep the coaching panel physically present for the entire active coaching episode.
- Replace one complete coaching turn with the next as a single visible update.
- Do not show an intermediate "checking" message for the fast local evaluator.
- Make an optional response visibly different from the instruction without adding words or another control.
- Preserve the established order: primary message, instruction, optional response.
- Preserve board-native interaction, truthful derived state, Dynamic Type, and VoiceOver order.

## Non-goals

- No online-AI loading treatment.
- No debounce, throttle, spinner, progress animation, or artificial delay in this revision.
- No change to coaching copy or chess evaluation.
- No redesign of the routine tokens or action buttons.

## Interaction continuity

### Stable coaching shell

Entering Help may replace the ordinary sidebar with coaching, and leaving Help may restore it. Between those boundaries, the coaching shell must remain mounted. A move, selection change, tentative-move replacement, hint, or answer must never expose the ordinary sidebar, even for one rendered frame.

The UI must key the shell's presence to the active coaching episode, not to the temporary availability of a newly derived presentation.

### Atomic content replacement

For the local evaluator, the currently rendered coaching turn remains visible until the next complete `CoachingPresentation` is ready. The new primary message, instruction, optional response, actions, routine, board task, and focus then become visible together, without a crossfade or insertion/removal animation.

The model continues to derive validity from the current authoritative interaction snapshot. A stale visible action attempted during the very short evaluation gap must not act on an obsolete board state or reopen an obsolete coaching step.

If a future online advisor creates a noticeable delay, a delayed pending treatment may be designed separately. It is intentionally not part of this revision.

## Response hierarchy

The three text roles remain semantic rather than positional accidents:

1. **Primary message:** the current question, conclusion, or main fact; large semibold serif.
2. **Instruction:** the next action the learner should take; regular rounded body text.
3. **Response:** optional factual feedback about the learner's preceding action; regular rounded body text inside a quiet warm note.

The response note:

- appears only when `observation` is present;
- remains below the instruction;
- uses existing warm panel colors, a slightly deeper inset tint, and a narrow warm left rule;
- uses compact padding and the existing body type scale;
- has no icon, heading, label, quotation marks, or additional wording;
- is not styled like a button and does not accept input;
- disappears whenever the next authoritative presentation has no response.

A completion such as "That move seems safe." remains the primary message, because it is the current conclusion rather than a response attached to another task.

## Accessibility and layout

- VoiceOver order remains primary message, instruction, response, routine, actions.
- The warm note is ordinary semantic text, not a separate control or accessibility group that adds verbosity.
- The note must wrap and scroll with the conversation at Large and Accessibility Extra Large.
- Tall, clockwise-wide, and counterclockwise-wide compositions must keep conversation, routine, and actions contained and non-overlapping.
- The visual treatment must preserve adequate contrast in the existing warm palette.

## Architecture boundary

- `GameSession` and `CoachingSession` own active-episode and authoritative-presentation continuity.
- `SidePanelView` chooses ordinary versus coaching structure from episode activity, not from a transient optional presentation.
- `CoachingPanelView` renders the three semantic text roles and owns only their visual treatment.
- Chess evaluation and authored copy remain unchanged.

Before implementing, reproduce the flicker and trace the exact state transition that makes the ordinary sidebar render. Fix that source transition rather than masking the result with animation.

## Verification

### Automated

- A controlled delayed-advisor test stages and replaces a move while coaching is active and proves the coaching shell never yields to ordinary sidebar state.
- Session tests prove stale advice and stale actions remain inapplicable after the interaction changes.
- Presentation tests prove response presence/absence tracks `observation` exactly and the text order is unchanged.
- Rendered UI tests cover response-note containment and full accessibility order at Large and Accessibility Extra Large in tall and both wide rotations.
- Existing coaching golden, session, GameSession, accessibility, and full suites remain green with zero skipped tests.

### Direct simulator UAT

- Record or frame-sample Help → select → stage move → replace move and confirm no ordinary-sidebar frame appears.
- Inspect a turn with a response and one without it in tall and wide layouts.
- Repeat the response layout at Accessibility Extra Large.
- Restore content size to Large and leave the normal verified app open.

## Success criteria

- No visible sidebar flicker during an active coaching episode.
- No intermediate "checking" copy.
- The response is immediately distinguishable from the instruction.
- The panel contains no new labels, icons, or redundant text.
- All advice, actions, board tasks, and focus still change as one truthful presentation.

# Coaching Scaffolding Revision Design

## Status and relationship to v1

This design revises the interaction, language, hinting, board emphasis, and responsive presentation of On-Demand Coaching V1 after direct simulator testing. It supplements `2026-08-13-on-demand-coaching-v1-design.md`. The original spec remains authoritative for chess evaluation, accepted-move policy, Safe–Take–Wake priority, session ownership, cancellation, and the source-independent coaching architecture unless this document explicitly changes a behavior.

The revision does not add chess concepts or broader coaching modes. It makes the existing v1 promise understandable and useful to a young child who has asked for help because they do not know what to do.

## Problems observed in UAT

Direct use exposed five related problems:

1. Help sometimes begins with abstract language instead of useful scaffolding. In the starting position, the child is asked to “help the center,” “wake up a piece,” and give a piece a “job,” but the first actionable narrowing arrives only after two Hint presses.
2. Some instructions do not define an answer. “Tap the problem” does not say whether to tap the attacker, the threatened piece, or a square.
3. Feedback classifies an answer without teaching from it. “That piece isn’t part of this problem,” “it isn’t in big danger,” a bare “Yes,” and “that works too” are vague or misleading.
4. Hint copy can refer to visual clues that do not exist yet. Movement markers do not appear until a source piece is selected, so they cannot help the child decide which source piece to select.
5. The combined coaching panel is not resilient. The large question and fixed action area can clip the Safe–Take–Wake tokens, and the calculated physical axis does not currently change the panel's internal composition.

## Goals

- Begin with an open question when noticing the answer is worthwhile practice.
- Skip questions whose answer is mechanically empty or obvious in the current context.
- Make the required response explicit for every prompt.
- Give factual, contrastive feedback rather than generic correctness labels.
- Make optional help prominent after the first miss without automatically revealing a hint.
- Ensure every hint's words and board emphasis describe the same available clue.
- Preserve relevant target–attacker context across adjacent questions.
- Make the combined coaching panel genuinely adaptive in tall and wide forms.
- Keep Safe–Take–Wake visible as a quiet progress aid whenever it meaningfully describes the current scan.

## Non-goals

- No changes to piece values, the urgent-loss threshold, exchange evaluation, candidate ranking, or move acceptance.
- No new strategic or tactical insight categories.
- No engine, language model, network dependency, or generated copy.
- No proactive coaching, blunder alert, game review, or position-evaluation mode.
- No redesign of the ambient danger, defense, coverage, or movement-marker grammar.
- No new tutorial, curriculum, learner profile, or reward system.
- No broad redesign of ordinary turn controls or captured-piece panels.

## Tutoring policy

### Open questions are conditional, not universal

The tutor uses an open question when finding the answer is itself useful practice and the child can understand how to answer. It compresses a stage when there is literally nothing to inspect.

Examples:

- On White's first move, Safe and Take are structurally empty. They appear cleared and the tutor begins with opening Wake.
- If a position contains a meaningful Safe scan, the tutor asks the child to find the endangered piece rather than highlighting the answer immediately.
- If a legal tentative move already exists, Help starts with the opponent-reply check rather than replaying Safe–Take–Wake.

The tutor does not compress a nontrivial scan merely because the correct answer is “I don't see one.” Recognizing that nothing useful is available remains a worthwhile observation when captures or threats are present to inspect.

### Prompt contract

Every coaching presentation contains:

1. one short question or factual feedback headline;
2. an instruction that names one expected interaction, or explicitly enumerates every valid answer form when the question accepts more than one;
3. only actions that are valid answers to the current question;
4. board emphasis that supports, but never contradicts, the words.

The instruction uses one of these explicit response forms:

- “Tap your piece.”
- “Tap the black piece.”
- “Tap the piece you want to move.”
- “Make a move on the board.”
- “Make the capture, or choose I don't see one.”
- “Choose Looks safe if neither happens.”

When two tap categories are valid in the opponent-reply check, both are named explicitly.

### Opening flow

From the starting position, the initial presentation is:

> **A good first step is to move a center pawn or bring out a knight. Which would you like to try?**  
> Tap the piece you want to move.

Safe and Take are shown as cleared; Wake is current. Candidate pieces are not highlighted at level zero.

After the child selects a qualifying source, the tutor names why that piece is relevant and ordinary movement guidance appears:

- Knight: “This knight can come into the game.”
- Center pawn: “This pawn can help in the center.”

The instruction is:

> Move it on the board.

After an accepted developing move, completion may introduce vocabulary in context:

> That works. Your knight came into the game. Chess players call that developing a piece.

The existing completion concepts for center-pawn moves and castling remain factual and do not use “job.”

### Safe flow

The initial Safe question is:

> **Which of your pieces needs help most?**  
> Tap your piece.

Ambient danger markers remain visible. The tutor does not add candidate rings at level zero.

After a correct target tap:

> **You found the {target}. What black piece is attacking it?**  
> Tap the black piece.

After a correct attacker tap:

> **Yes—that {attacker} is attacking your {target}. How could you help your {target}?**  
> Make a move that gets it safe.

The identified target and attacker remain subtly emphasized through the resolution question. A staged move that fails to resolve the selected danger says:

> **The {attacker} could still take your {target} after that move.**  
> Change your move so the {target} is safe.

If several attackers create the selected urgent problem, naming any valid attacker advances the flow. The persisted relationship shows the attacker the child identified; later evaluation still requires the move to satisfy the original v1 urgent-problem policy.

### Take flow

The Take question remains open:

> **Can one of your pieces make a useful capture?**  
> Make the capture, or choose I don't see one.

Level-zero copy does not mention capture markers because no source piece may be selected. A child may explore pieces using ordinary selection and movement guidance while the tutor observes the staged capture.

Existing concrete recapture and material-consequence explanations remain, with the instruction “Change your move, or choose I don't see one” when the capture is not useful.

### General Wake flow

The word “job” is removed. The initial question names the existing verified purpose selected by the advisor:

- Opening development: “Which knight or center pawn would you like to move?”
- Add a defender: “Which piece could help protect another piece?”
- Create a threat: “Which piece could safely attack something?”
- Improve central activity: “Which piece could move closer to the center?”
- Castle: “Which piece would you move to castle?”

The instruction is “Tap the piece you want to move.” For castling it is “Tap your king.” After the king is selected, the tutor says “Move it two squares toward a rook.”

If the advisor has no verified purpose, the existing fallback remains:

> Nothing urgent stands out. Try a move you like, and we'll check it together.

The fallback does not invent a strategic reason after success.

### Opponent-reply flow

When Help begins with a tentative move, or after the child stages a coached move, the question is:

> **Could {opponent} check your king or win one of your pieces?**  
> Tap the black checking piece, or tap your piece {opponent} could take. Otherwise choose Looks safe.

The tutor never uses “Tap the problem.”

If the child taps a real issue, feedback names the concrete reply and affected piece. If a harmless check is found, the existing policy may acknowledge the check and still accept the move. If Looks safe is correct, completion names the move's verified purpose. If Looks safe is incorrect, the tutor states the concrete reply before returning to the same question.

## Feedback policy

### Factual feedback

Feedback must state one fact the current analysis supports. Generic `.correct`, `.correctAlternative`, and `.unrelatedTap` text are not child-facing explanations.

Required cases include:

- Correct Safe target: “You found the {piece}.”
- Correct attacker: “Yes—that {attacker} is attacking your {target}.”
- Correct Wake source: name its verified purpose, such as “This knight can come into the game.”
- Own piece that is safe during Safe locate: “That {piece} is safe right now.”
- Lower-priority threatened piece: “Yes, that {piece} is threatened. Your {urgentPiece} is worth more, so help the {urgentPiece} first.”
- Wrong opponent piece during attacker identification: “That {piece} isn't attacking your {target}.”
- Empty square or wrong-color answer: restate the requested category, such as “Tap one of your pieces” or “Tap a black piece attacking your knight.”
- Blocked opening source when a single blocker is mechanically identifiable: “That {piece} can't come out yet because your {blocker} is in the way.”
- Source without a qualifying move and without a more specific verified fact: restate the current goal without blame.
- Unresolved danger: name the attacker and target that remain connected after the proposed move.

The explanation source must not claim that a threat is unimportant merely because it falls below the urgent-loss threshold. It describes relative priority instead.

### Tone

- Use familiar chess terms: check, threat, attack, capture, protect, safe, center, and develop.
- Introduce a new term by pairing it with an immediately understandable explanation.
- Prefer piece names over notation.
- Do not use “problem,” “job,” “big danger,” “wrong,” “best,” or a bare “Yes.”
- Do not imply a move is an alternative with “too” unless the child actually made an earlier accepted choice in the same comparison.

## Hint policy

### Escalation

Each question begins at level zero. A miss:

1. produces factual feedback;
2. leaves the question and hint level unchanged;
3. immediately promotes the existing Hint action visually.

The tutor never reveals a hint automatically. Choosing Hint advances exactly one available step and clears the prior miss feedback. Hint progress resets when the instructional question changes.

### One semantic clue drives words and visuals

Each available hint step is a semantic clue that owns both its authored instruction and its board emphasis. Text is not selected from a generic numeric hint level independently of the focus presentation. This prevents instructions from mentioning movement, capture, check, or danger markers that are absent.

Representative ladders are:

| Question | Level zero | First Hint | Stronger Hint |
| --- | --- | --- | --- |
| Opening source | Open category question; no rings | Ring the qualifying knights and center pawns; say “Try one of the highlighted pieces.” | Show candidate source-to-destination paths |
| Safe target | Use ambient danger markers | Say “Look for the red danger marker” and retain the marker | Emphasize the highest-priority target |
| Safe attacker | Retain the selected target | Show attacker–target connection | Emphasize the valid attacker or attackers |
| Safe resolution | Retain target and attacker | Explain “Move it, protect it, or take the attacker” | Show qualifying candidate paths |
| Take | Open capture question; no claim about markers | Emphasize pieces with a qualifying capture | Show qualifying capture paths |
| Wake destination | Ordinary markers exist because the source is selected | Refer to those movement markers | Show qualifying candidate destinations |
| Opponent reply | Use ambient tentative-position check and danger markers | Refer to the visible red/check markers | Emphasize the relevant reply relationship |

A ladder ends at the strongest clue the board can truthfully represent. Questions do not manufacture empty levels to reach a fixed count.

## Board-focus lifecycle

Coach focus remains separate from ambient `BoardGuidancePresentation` semantics.

- Level-zero opening Wake has no coach candidate focus.
- Correctly identifying a Safe target creates persistent target emphasis.
- Correctly identifying its attacker adds the attacker–target path.
- That relationship survives the transition into Safe resolution and remains until a new tentative move is staged, the focused danger becomes invalid, or coaching ends.
- Hint-only candidate rings and paths are cleared when their question changes.
- Ordinary movement markers appear only after the ordinary selection path has selected a source piece.
- Stop, completion exit, game commit, reset, remote replacement, and game end remove all coach focus.

Coach focus never stages, moves, or selects a piece on the child's behalf.

## Responsive coaching panel

The combined coaching region continues to replace the ordinary message/control and selected-piece segments while leaving captured pieces visible.

### Compact progress header

The approved layout uses one reserved horizontal Safe–Take–Wake strip. It is visually secondary to the question but is never clipped.

- In opening Wake, Safe and Take are cleared and Wake is current.
- During Safe or Take, all three labels remain visible with current, cleared, and pending states.
- The strip is omitted during opponent reply, completion, check-only flow, and low-confidence fallback when showing it would not describe the current task accurately.
- Completed and current states are exposed to accessibility without relying on color.

### Tall physical form

The panel is composed vertically:

1. compact progress header, when present;
2. flexible conversation area;
3. bottom-anchored action area.

### Wide physical form

The progress header spans the full width. Below it, conversation appears on the left and actions on the right. The action column is wide enough to display “I don't see one,” “Keep looking,” and “Looks safe” without truncation.

`CoachingPanelLayout.physicalAxis` must select the composition; it is not merely stored for tests.

### Overflow and typography

- The question uses a smaller adaptive title style than the ordinary turn-status panel.
- The instruction remains visually subordinate but readable.
- The conversation area scrolls when its content exceeds the available region at any Dynamic Type size.
- The progress strip and actions remain visible while conversation scrolls.
- No standard supported size may clip the question, instruction, routine labels, or action titles without a way to reveal the complete text.
- VoiceOver reads the question, instruction, routine state, and actions in that semantic order regardless of physical axis.

## Architecture changes

The original dependency direction remains unchanged.

### Semantic prompt and feedback context

`CoachingPrompt` must carry the verified purpose needed for context-specific general Wake wording. `CoachingFeedback` must carry the pieces and relationship needed for factual feedback rather than reducing them to `.correct`, `.correctAlternative`, or `.unrelatedTap` before explanation.

The session may derive simple mechanical feedback facts from the committed board and existing Core movement analysis, such as a selected own piece being safe, an opponent piece not attacking the chosen target, or a home piece having one clear blocker. These facts do not change evaluation or recommendation policy.

When no specific fact is supported, feedback carries the expected answer category so the explanation source can restate it precisely.

### Semantic hint steps

The session exposes the current semantic hint step, rather than asking the explanation source to infer a clue from `hintLevel` alone. The same hint step supplies:

- authored instruction intent;
- candidate or emphasized squares;
- attacker or candidate paths;
- maximum available escalation for the question.

The presentation remains source-independent. SwiftUI receives final text, actions, board task, routine state, focus, and physical layout inputs; it does not decide chess meaning.

### Panel composition

`CoachingPanelView` uses `CoachingPanelLayout.physicalAxis` to choose tall or wide composition. Conversation scrolling, progress-strip reservation, and action placement are presentation concerns and remain in SwiftUI.

## Testing strategy

### Explanation tests

Assert exact canonical text and expected-answer instructions for:

- starting-position opening prompt;
- each general Wake purpose;
- Safe target, attacker, and resolution prompts;
- opponent-reply prompt;
- correct target and attacker;
- safe own piece;
- lower-priority threatened piece compared with the focused urgent piece;
- nonattacking opponent piece;
- wrong-color and empty-square answer categories;
- mechanically blocked opening source;
- unresolved danger naming attacker and target;
- completion vocabulary for development.

Add a prohibited-copy assertion covering child-facing coaching strings: “job,” “part of this problem,” “big danger,” “Tap the problem,” and bare “Yes.”

### Transcript tests

Drive full session transcripts for:

- opening question, unrelated source, promoted Hint, candidate reveal, accepted source, move, reply check, and completion;
- two threatened pieces with different priorities, including selection of the lower-priority piece first;
- Safe target and attacker identification with persistent focus;
- a resolution move that leaves the selected danger present;
- Take with no source selected at level zero;
- help on an existing safe tentative move;
- help on a tentative move with a concrete reply issue.

Assert that the first miss promotes Hint without incrementing the hint level, and that choosing Hint advances exactly one semantic step.

### Hint/focus consistency tests

For every prompt and hint step, assert that:

- marker-referencing text has corresponding ambient or coach focus evidence;
- source-selection hints never refer to movement markers;
- candidate-square text has nonempty candidate squares;
- relationship text has a nonempty path;
- persistent Safe context survives target-to-attacker-to-resolution transitions;
- hint-only focus clears at question changes and all focus clears on Stop.

### Presentation tests

Assert that:

- the physical axis selects tall or wide composition;
- the compact strip always contains Safe, Take, and Wake when present;
- the strip is omitted in the explicitly listed flows;
- semantic accessibility order is stable in both axes;
- action labels are never shortened in presentation values.

Simulator UAT must exercise tall and wide physical forms at the standard text size and one accessibility Dynamic Type size. The UAT positions are the starting position and a position with a lower-value threatened pawn plus a higher-priority threatened knight. Screenshots must confirm that routine tokens, long factual feedback, instructions, and actions remain available without clipping.

## Acceptance criteria

The revision is complete when:

- first-move Help skips empty Safe and Take questions and begins with the approved concrete opening choice;
- a child always knows whether to tap their piece, tap the opponent's piece, make a move, or choose an action;
- opening candidates remain unhighlighted until Hint;
- the first miss gives factual feedback and promotes Hint without revealing it;
- no hint mentions a clue that is absent from the board;
- lower-priority threats are acknowledged and compared rather than described as “not in big danger”;
- no child-facing coaching copy uses “job,” “part of this problem,” “big danger,” or “Tap the problem”;
- a selected Safe target and attacker remain visually connected through the resolution question;
- Safe–Take–Wake is a compact, unclipped header whenever the routine is relevant;
- tall and wide forms use distinct internal compositions;
- long text and accessibility text sizes remain readable without hiding the routine or actions;
- evaluator behavior and accepted-move policy remain unchanged;
- existing coaching, rules, tentative-move, local-play, and remote-play tests continue to pass.

# Judge reference set v2

Status: **pending human review**

Proposed by: Codex implementation agent on 2026-09-03

Review each context, candidate response, score, flag, and rationale. Approval of this sheet is required before these judgments become qualification ground truth.

## ref-01

**Facts:** White is to move in a quiet opening. White is not in check. No white piece is in immediate danger and no safe capture is available.

**Purpose:** Invite a useful opening idea without prescribing a move or inventing danger.

**Acceptable alternatives:** Ask about bringing a piece toward the center. | Ask what piece could join the game.

**Success criteria:** Leaves the move choice to the learner. | Uses language a young beginner can understand.

**Severe-failure criteria:** Invents an urgent threat. | Prevents the learner from making a move.

**Candidate:** “What could you develop toward the center?”

**Available UI:** actions=["hint"]; expectedResponses=["stageMove"]; allowableMoveFocus=[].

**Candidate controls:** actions=["hint"]; focus=[]; expects="stageMove".

**Scores:** Chess correctness: 5; Coaching judgment: 4; Latest-action responsiveness: 5; Discovery and independence: 5; Coherence and answerability: 4; Child clarity: 3.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** The question preserves agency and fits the quiet position. Develop is useful chess language but may need simpler wording for a five-year-old.

## ref-02

**Facts:** A pawn attacks the learner's knight. Several safe knight moves exist. The current interaction asks the learner to identify the endangered piece before solving the danger.

**Purpose:** Help the learner notice which piece needs help before choosing a response.

**Acceptable alternatives:** Ask the learner to tap the endangered piece without naming it.

**Success criteria:** Does not reveal the endangered piece. | Stays on the identification step.

**Severe-failure criteria:** Claims the knight is safe. | Creates a dead end that prevents progress.

**Candidate:** “Your knight is attacked. Can you find a square where it will be safer?”

**Available UI:** actions=["noPieceNeedsHelp"]; expectedResponses=["findEndangeredPiece"]; allowableMoveFocus=[].

**Candidate controls:** actions=[]; focus=[]; expects="findEndangeredPiece".

**Scores:** Chess correctness: 5; Coaching judgment: 2; Latest-action responsiveness: 2; Discovery and independence: 2; Coherence and answerability: 2; Child clarity: 5.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: true; answerRevealingGuidance: true; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** It states the endangered piece instead of letting the learner find it. It also jumps from identifying the piece to choosing its destination while declaring a different expected response.

## ref-03

**Facts:** The learner staged a move that leaves the queen capturable by Black. It is still the learner's tentative move and has not been committed.

**Purpose:** Help the learner discover the opponent's immediate reply before deciding whether to keep the move.

**Acceptable alternatives:** Ask what Black could capture next. | Ask whether the queen will be safe after the move.

**Success criteria:** Focuses on the staged move's immediate safety. | Does not reveal the answer unnecessarily.

**Severe-failure criteria:** Approves the losing move. | Discusses an unrelated earlier stage.

**Candidate:** “Before keeping that move, what could Black capture next?”

**Available UI:** actions=["tryAnotherMove"]; expectedResponses=["judgeMoveSafety"]; allowableMoveFocus=[].

**Candidate controls:** actions=["tryAnotherMove"]; focus=[]; expects="judgeMoveSafety".

**Scores:** Chess correctness: 5; Coaching judgment: 5; Latest-action responsiveness: 5; Discovery and independence: 5; Coherence and answerability: 5; Child clarity: 5.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** It asks one answerable question about the staged move's decisive flaw and preserves discovery.

## ref-04

**Facts:** The learner's pawn is attacked. If the attacking piece captures it, the learner's king can recapture safely. The pawn is therefore not simply lost.

**Purpose:** Distinguish being attacked from being lost and let the learner decide whether to continue.

**Acceptable alternatives:** Explain that the king protects the pawn. | Ask what can recapture the attacker.

**Success criteria:** Accurately explains the recapture. | Leaves a usable next choice.

**Severe-failure criteria:** Claims the pawn is undefended or inevitably lost.

**Candidate:** “That pawn is attacked, but your king protects it. Nothing is lost yet.”

**Available UI:** actions=["looksSafe"]; expectedResponses=["chooseWhetherToPlay"]; allowableMoveFocus=[].

**Candidate controls:** actions=["looksSafe"]; focus=[]; expects="chooseWhetherToPlay".

**Scores:** Chess correctness: 5; Coaching judgment: 5; Latest-action responsiveness: 5; Discovery and independence: 3; Coherence and answerability: 4; Child clarity: 5.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** The explanation is accurate and concise, although it tells rather than helps the learner discover the recapture.

## ref-05

**Facts:** The learner replaced a previously staged pawn move with a legal knight move. The knight move is not immediately losing and helps control central squares.

**Purpose:** Follow the replacement and help the learner evaluate the new move.

**Acceptable alternatives:** Ask what the knight now attacks or protects. | Ask whether the knight is safe on its new square.

**Success criteria:** Responds to the replacement rather than the old pawn move. | Prompts useful evaluation of the knight move.

**Severe-failure criteria:** Continues discussing the replaced pawn move.

**Candidate:** “You changed to the knight move. What does that knight now help control?”

**Available UI:** actions=["hint"]; expectedResponses=["judgeMoveSafety"]; allowableMoveFocus=[].

**Candidate controls:** actions=["hint"]; focus=[]; expects="judgeMoveSafety".

**Scores:** Chess correctness: 5; Coaching judgment: 4; Latest-action responsiveness: 5; Discovery and independence: 5; Coherence and answerability: 4; Child clarity: 4.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** It explicitly follows the replacement and prompts thought about the new move. Control is somewhat abstract and does not directly ask for the requested safety judgment.

## ref-06

**Facts:** The learner reported that no safe capture is available. The position is quiet and the learner can stage a developing move.

**Purpose:** Accept the learner's answer and move on to choosing a useful move.

**Acceptable alternatives:** Ask what piece could join the game. | Ask how the learner could help control the center.

**Success criteria:** Does not repeat the capture search. | Leaves the move choice open.

**Severe-failure criteria:** Insists that a nonexistent capture exists. | Blocks progress after the answer.

**Candidate:** “You found there is no safe capture. What kind of piece could you bring into the game?”

**Available UI:** actions=["hint"]; expectedResponses=["stageMove"]; allowableMoveFocus=[].

**Candidate controls:** actions=["hint"]; focus=[]; expects="stageMove".

**Scores:** Chess correctness: 5; Coaching judgment: 5; Latest-action responsiveness: 5; Discovery and independence: 5; Coherence and answerability: 5; Child clarity: 4.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** It accepts the latest answer, advances naturally, and asks a non-prescriptive question.

## ref-07

**Facts:** The learner staged legal kingside castling. Castling moves the king and rook in one move and generally improves king shelter.

**Purpose:** Explain the unfamiliar special move simply before the learner chooses whether to play it.

**Acceptable alternatives:** Briefly explain that both the king and rook move.

**Success criteria:** Explains castling accurately. | Supports the play-or-retry choice.

**Severe-failure criteria:** Calls the move illegal. | Describes the king or rook moving incorrectly.

**Candidate:** “Castling moves your king and rook together and helps shelter your king.”

**Available UI:** actions=["playMove"]; expectedResponses=["chooseWhetherToPlay"]; allowableMoveFocus=[].

**Candidate controls:** actions=["playMove"]; focus=[]; expects="chooseWhetherToPlay".

**Scores:** Chess correctness: 5; Coaching judgment: 4; Latest-action responsiveness: 5; Discovery and independence: 3; Coherence and answerability: 4; Child clarity: 5.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** A direct explanation is appropriate for a special rule, and the available action supports the next choice.

## ref-08

**Facts:** The learner staged a legal en-passant capture. The pawn moves diagonally to an empty square while capturing the opposing pawn that just advanced two squares.

**Purpose:** Explain the unusual capture accurately before the learner chooses whether to play it.

**Acceptable alternatives:** Explain that the pawn captures the pawn that just passed beside it.

**Success criteria:** Accurately describes which pawn is captured. | Uses simple language.

**Severe-failure criteria:** Claims the move is illegal. | Identifies the wrong captured pawn.

**Candidate:** “The pawn moved diagonally to take the pawn that just passed it.”

**Available UI:** actions=["playMove"]; expectedResponses=["chooseWhetherToPlay"]; allowableMoveFocus=[].

**Candidate controls:** actions=["playMove"]; focus=[]; expects="chooseWhetherToPlay".

**Scores:** Chess correctness: 5; Coaching judgment: 4; Latest-action responsiveness: 5; Discovery and independence: 3; Coherence and answerability: 4; Child clarity: 4.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** The explanation is accurate and suitably direct for an unusual rule, though just passed it could be slightly clearer.

## ref-09

**Facts:** The learner's bishop is under a real one-move threat. The learner staged an unrelated pawn move that leaves the bishop endangered.

**Purpose:** Respond to the staged move by returning attention to the unresolved urgent danger.

**Acceptable alternatives:** Ask whether the bishop is still safe after the pawn move. | Ask how the learner could help the attacked bishop.

**Success criteria:** Prioritizes the bishop over unrelated opportunities. | Connects the question to the staged move.

**Severe-failure criteria:** Approves the pawn move while ignoring the loose bishop.

**Candidate:** “Your bishop is still attacked after that pawn move. How could you help it?”

**Available UI:** actions=["tryAnotherMove"]; expectedResponses=["stageMove"]; allowableMoveFocus=[].

**Candidate controls:** actions=["tryAnotherMove"]; focus=[]; expects="stageMove".

**Scores:** Chess correctness: 5; Coaching judgment: 5; Latest-action responsiveness: 5; Discovery and independence: 5; Coherence and answerability: 5; Child clarity: 5.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** It responds to the learner's latest move, keeps the urgent threat central, and asks the learner to solve it.

## ref-10

**Facts:** The learner just closed coaching help. No coaching response buttons remain visible. The app's global Help control remains available if the learner later wants help again.

**Purpose:** Respect the close action without continuing the lesson.

**Acceptable alternatives:** Acknowledge that help is closed. | Say nothing further.

**Success criteria:** Does not ask another coaching question. | Does not imply that play is blocked.

**Severe-failure criteria:** Continues forcing the learner through coaching steps.

**Candidate:** “You closed help. Tap Help whenever you want another thought.”

**Available UI:** actions=[]; expectedResponses=[]; allowableMoveFocus=[].

**Candidate controls:** actions=[]; focus=[]; expects=null.

**Scores:** Chess correctness: 5; Coaching judgment: 4; Latest-action responsiveness: 5; Discovery and independence: 4; Coherence and answerability: 5; Child clarity: 5.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** It directly respects the close action and accurately refers to the separate global Help control.

## ref-11

**Facts:** White is to move in a quiet opening with several useful legal moves. Moving the central pawn to d4 is legal and reasonable. The board accepts staged moves directly.

**Purpose:** Encourage independent opening thought rather than prescribe one move.

**Acceptable alternatives:** Ask what piece or pawn could help the center. | Ask what the learner wants to develop.

**Success criteria:** Leaves the choice among several good moves to the learner.

**Severe-failure criteria:** Invents danger or gives an illegal move.

**Candidate:** “Move your pawn to d4 now.”

**Available UI:** actions=["hint"]; expectedResponses=["stageMove"]; allowableMoveFocus=[].

**Candidate controls:** actions=[]; focus=[]; expects="stageMove".

**Scores:** Chess correctness: 4; Coaching judgment: 2; Latest-action responsiveness: 4; Discovery and independence: 1; Coherence and answerability: 4; Child clarity: 4.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** The move is legal and understandable, but the command is unnecessarily prescriptive and teaches no decision-making process.

## ref-12

**Facts:** An opposing pawn attacks the learner's knight. The knight is loose and can be won if the learner ignores the threat.

**Purpose:** Help the learner recognize and solve the urgent danger.

**Acceptable alternatives:** Ask which piece is attacked. | Ask how the knight could become safe.

**Success criteria:** Treats the knight as genuinely endangered.

**Severe-failure criteria:** Claims the knight is safe. | Tells the learner to ignore the attack.

**Candidate:** “Your knight is safe, so ignore the pawn attacking it.”

**Available UI:** actions=["noPieceNeedsHelp"]; expectedResponses=["findEndangeredPiece"]; allowableMoveFocus=[].

**Candidate controls:** actions=["noPieceNeedsHelp"]; focus=[]; expects="findEndangeredPiece".

**Scores:** Chess correctness: 1; Coaching judgment: 1; Latest-action responsiveness: 2; Discovery and independence: 2; Coherence and answerability: 1; Child clarity: 4.

**Flags:** factualOrIllegalAdvice: true; wrongUrgentPriority: true; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: true.

**Rationale:** It reverses the decisive chess fact and directs the learner to ignore a piece-losing threat.

## ref-13

**Facts:** The learner staged a bishop capture. An opposing pawn can immediately recapture the bishop. The exchange loses material for the learner.

**Purpose:** Help the learner evaluate the staged capture before committing it.

**Acceptable alternatives:** Ask what can recapture the bishop. | Suggest trying another move after the learner sees the recapture.

**Success criteria:** Does not approve the losing capture.

**Severe-failure criteria:** Calls the capture good and recommends keeping it.

**Candidate:** “Great capture! Keep it.”

**Available UI:** actions=["tryAnotherMove"]; expectedResponses=["judgeMoveSafety"]; allowableMoveFocus=[].

**Candidate controls:** actions=[]; focus=[]; expects="judgeMoveSafety".

**Scores:** Chess correctness: 1; Coaching judgment: 1; Latest-action responsiveness: 4; Discovery and independence: 1; Coherence and answerability: 2; Child clarity: 4.

**Flags:** factualOrIllegalAdvice: true; wrongUrgentPriority: true; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: true.

**Rationale:** It directly approves a move that the verified facts say loses material.

## ref-14

**Facts:** The learner needs an answerable next step. The rook on a8 is not a learner piece and is not an available answer or move focus.

**Purpose:** Give an instruction the learner can complete through the current board or controls.

**Acceptable alternatives:** Ask the learner to stage a legal move. | Offer the available hint action.

**Success criteria:** References only available interactions.

**Severe-failure criteria:** Directs the learner to an unavailable target and leaves no workable continuation.

**Candidate:** “Tap the rook on a8.”

**Available UI:** actions=["hint"]; expectedResponses=["stageMove"]; allowableMoveFocus=[].

**Candidate controls:** actions=[]; focus=[{"type": "square", "square": "a8"}]; expects="stageMove".

**Scores:** Chess correctness: 2; Coaching judgment: 1; Latest-action responsiveness: 2; Discovery and independence: 1; Coherence and answerability: 1; Child clarity: 4.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: true; severeError: true.

**Rationale:** The instruction is clear but cannot be completed through the available interaction and prevents progress.

## ref-15

**Facts:** There is no queen on f6. The learner's queen is not exposed to capture on the next move.

**Purpose:** Keep the advice grounded in the supplied position.

**Acceptable alternatives:** Discuss only verified threats. | Ask a restrained question if no urgent fact is available.

**Success criteria:** Does not invent a piece or threat.

**Severe-failure criteria:** Invents an opponent queen and a false immediate threat.

**Candidate:** “The queen on f6 can take your queen next.”

**Available UI:** actions=["hint"]; expectedResponses=["stageMove"]; allowableMoveFocus=[].

**Candidate controls:** actions=[]; focus=[]; expects="stageMove".

**Scores:** Chess correctness: 1; Coaching judgment: 1; Latest-action responsiveness: 2; Discovery and independence: 2; Coherence and answerability: 1; Child clarity: 4.

**Flags:** factualOrIllegalAdvice: true; wrongUrgentPriority: true; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: true.

**Rationale:** It invents both a piece and an urgent threat, making the chess advice unusable.

## ref-16

**Facts:** The knight on f3 is endangered. The current step asks the learner to identify the endangered piece by tapping it.

**Purpose:** Let the learner find the endangered piece rather than revealing it.

**Acceptable alternatives:** Ask which piece the opponent can win next without naming or circling it.

**Success criteria:** Does not name, locate, or focus the answer.

**Severe-failure criteria:** Reveals the answer while simultaneously asking the learner to find it.

**Candidate:** “Look for the endangered knight. It is the knight on f3.”

**Available UI:** actions=["noPieceNeedsHelp"]; expectedResponses=["findEndangeredPiece"]; allowableMoveFocus=[].

**Candidate controls:** actions=[]; focus=[]; expects="findEndangeredPiece".

**Scores:** Chess correctness: 5; Coaching judgment: 2; Latest-action responsiveness: 3; Discovery and independence: 1; Coherence and answerability: 2; Child clarity: 5.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: true; unavailableUIOrDeadEnd: false; severeError: true.

**Rationale:** It explicitly names the answer while telling the learner to look for it, defeating the teaching interaction.

## ref-17

**Facts:** The learner first staged a pawn move, then replaced it with a knight move. Only the knight move is currently staged.

**Purpose:** Respond to and evaluate the learner's current knight move.

**Acceptable alternatives:** Acknowledge the knight move and ask whether it is safe. | Ask what the knight now attacks or protects.

**Success criteria:** Does not discuss the replaced pawn move as current.

**Severe-failure criteria:** Gives stale advice about the removed move and blocks the current interaction.

**Candidate:** “That first pawn move looks safe.”

**Available UI:** actions=["looksSafe"]; expectedResponses=["judgeMoveSafety"]; allowableMoveFocus=[].

**Candidate controls:** actions=["looksSafe"]; focus=[]; expects="judgeMoveSafety".

**Scores:** Chess correctness: 3; Coaching judgment: 1; Latest-action responsiveness: 1; Discovery and independence: 2; Coherence and answerability: 2; Child clarity: 5.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: true; mixedStages: true; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: true.

**Rationale:** It ignores the learner's replacement and evaluates a move that is no longer staged.

## ref-18

**Facts:** The learner's king is in check but is not checkmated. The staged bishop move is legal and resolves the check.

**Purpose:** Evaluate the legal response to check accurately.

**Acceptable alternatives:** Explain that the bishop move gets the king out of check. | Invite the learner to keep the legal response.

**Success criteria:** Distinguishes check from checkmate.

**Severe-failure criteria:** Calls the position checkmate while also claiming a legal move exists.

**Candidate:** “Your king is checkmated, but you can move your bishop.”

**Available UI:** actions=["playMove"]; expectedResponses=["chooseWhetherToPlay"]; allowableMoveFocus=[].

**Candidate controls:** actions=["playMove"]; focus=[]; expects="chooseWhetherToPlay".

**Scores:** Chess correctness: 1; Coaching judgment: 1; Latest-action responsiveness: 3; Discovery and independence: 1; Coherence and answerability: 1; Child clarity: 3.

**Flags:** factualOrIllegalAdvice: true; wrongUrgentPriority: true; obsoleteStage: false; mixedStages: true; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: true.

**Rationale:** The statement contradicts both the verified position and itself: a checkmated player has no legal move.

## ref-19

**Facts:** Moving the learner's knight to c3 is legal and safe. The move develops the knight with tempo in this position. The learner is an early beginner who is not expected to know algebraic notation or advanced terminology.

**Purpose:** Use clear beginner language and preserve agency while discussing a reasonable move.

**Acceptable alternatives:** Refer to the knight and square c3 in plain language. | Ask what the knight could do from its new square.

**Success criteria:** Avoids unexplained notation and jargon. | Does not simply prescribe the move.

**Severe-failure criteria:** Gives an illegal move or makes progress impossible.

**Candidate:** “The knight's move to c3 is legal and safe, and develops with tempo.”

**Available UI:** actions=["hint"]; expectedResponses=["stageMove"]; allowableMoveFocus=[].

**Candidate controls:** actions=[]; focus=[]; expects="stageMove".

**Scores:** Chess correctness: 5; Coaching judgment: 2; Latest-action responsiveness: 3; Discovery and independence: 2; Coherence and answerability: 3; Child clarity: 1.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** The chess content is accurate, but the redundant legal and safe wording and tempo jargon are poorly suited to the learner.

## ref-20

**Facts:** The learner has already staged a specific move. The current coaching step is to judge that move's safety. The available controls let the learner mark it safe or try another move.

**Purpose:** Help evaluate the current staged move rather than restart broad move selection.

**Acceptable alternatives:** Ask what the opponent could do after the staged move. | Ask whether the moved piece remains safe.

**Success criteria:** Directly addresses the staged move and the available judgment controls.

**Severe-failure criteria:** Ignores the staged move and leaves the learner unable to answer through the current interaction.

**Candidate:** “Think about everything on the board and choose the best move.”

**Available UI:** actions=["looksSafe", "tryAnotherMove"]; expectedResponses=["judgeMoveSafety"]; allowableMoveFocus=[].

**Candidate controls:** actions=[]; focus=[]; expects="judgeMoveSafety".

**Scores:** Chess correctness: 3; Coaching judgment: 1; Latest-action responsiveness: 1; Discovery and independence: 3; Coherence and answerability: 1; Child clarity: 3.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: true; mixedStages: true; answerRevealingGuidance: false; unavailableUIOrDeadEnd: true; severeError: true.

**Rationale:** The generic instruction discards the current staged move and does not connect to the available safety judgment.

# Judge reference set v2

Status: **pending human review**

Proposed by: Codex implementation agent on 2026-09-03

Review each context, candidate response, score, flag, and rationale. Approval of this sheet is required before these judgments become qualification ground truth.

## ref-01

**Facts:** White is to move in a quiet opening. White is not in check. No white piece is in immediate danger and no safe capture is available.

**Purpose:** Invite a useful opening idea without prescribing a move or inventing danger.

**Candidate:** “What could you develop toward the center?”

**Available actions:** hint; expected response: stageMove.

**Scores:** Chess correctness: 5; Coaching judgment: 4; Latest-action responsiveness: 5; Discovery and independence: 5; Coherence and answerability: 4; Child clarity: 3.

**True flags:** none.

**Rationale:** The question preserves agency and fits the quiet position. Develop is useful chess language but may need simpler wording for a five-year-old.

## ref-02

**Facts:** A pawn attacks the learner's knight. Several safe knight moves exist. The current interaction asks the learner to identify the endangered piece before solving the danger.

**Purpose:** Help the learner notice which piece needs help before choosing a response.

**Candidate:** “Your knight is attacked. Can you find a square where it will be safer?”

**Available actions:** noPieceNeedsHelp; expected response: findEndangeredPiece.

**Scores:** Chess correctness: 5; Coaching judgment: 2; Latest-action responsiveness: 2; Discovery and independence: 2; Coherence and answerability: 2; Child clarity: 5.

**True flags:** mixedStages, answerRevealingGuidance.

**Rationale:** It states the endangered piece instead of letting the learner find it. It also jumps from identifying the piece to choosing its destination while declaring a different expected response.

## ref-03

**Facts:** The learner staged a move that leaves the queen capturable by Black. It is still the learner's tentative move and has not been committed.

**Purpose:** Help the learner discover the opponent's immediate reply before deciding whether to keep the move.

**Candidate:** “Before keeping that move, what could Black capture next?”

**Available actions:** tryAnotherMove; expected response: judgeMoveSafety.

**Scores:** Chess correctness: 5; Coaching judgment: 5; Latest-action responsiveness: 5; Discovery and independence: 5; Coherence and answerability: 5; Child clarity: 5.

**True flags:** none.

**Rationale:** It asks one answerable question about the staged move's decisive flaw and preserves discovery.

## ref-04

**Facts:** The learner's pawn is attacked. If the attacking piece captures it, the learner's king can recapture safely. The pawn is therefore not simply lost.

**Purpose:** Distinguish being attacked from being lost and let the learner decide whether to continue.

**Candidate:** “That pawn is attacked, but your king protects it. Nothing is lost yet.”

**Available actions:** looksSafe; expected response: chooseWhetherToPlay.

**Scores:** Chess correctness: 5; Coaching judgment: 5; Latest-action responsiveness: 5; Discovery and independence: 3; Coherence and answerability: 4; Child clarity: 5.

**True flags:** none.

**Rationale:** The explanation is accurate and concise, although it tells rather than helps the learner discover the recapture.

## ref-05

**Facts:** The learner replaced a previously staged pawn move with a legal knight move. The knight move is not immediately losing and helps control central squares.

**Purpose:** Follow the replacement and help the learner evaluate the new move.

**Candidate:** “You changed to the knight move. What does that knight now help control?”

**Available actions:** hint; expected response: judgeMoveSafety.

**Scores:** Chess correctness: 5; Coaching judgment: 4; Latest-action responsiveness: 5; Discovery and independence: 5; Coherence and answerability: 4; Child clarity: 4.

**True flags:** none.

**Rationale:** It explicitly follows the replacement and prompts thought about the new move. Control is somewhat abstract and does not directly ask for the requested safety judgment.

## ref-06

**Facts:** The learner reported that no safe capture is available. The position is quiet and the learner can stage a developing move.

**Purpose:** Accept the learner's answer and move on to choosing a useful move.

**Candidate:** “You found there is no safe capture. What kind of piece could you bring into the game?”

**Available actions:** hint; expected response: stageMove.

**Scores:** Chess correctness: 5; Coaching judgment: 5; Latest-action responsiveness: 5; Discovery and independence: 5; Coherence and answerability: 5; Child clarity: 4.

**True flags:** none.

**Rationale:** It accepts the latest answer, advances naturally, and asks a non-prescriptive question.

## ref-07

**Facts:** The learner staged legal kingside castling. Castling moves the king and rook in one move and generally improves king shelter.

**Purpose:** Explain the unfamiliar special move simply before the learner chooses whether to play it.

**Candidate:** “Castling moves your king and rook together and helps shelter your king.”

**Available actions:** playMove; expected response: chooseWhetherToPlay.

**Scores:** Chess correctness: 5; Coaching judgment: 4; Latest-action responsiveness: 5; Discovery and independence: 3; Coherence and answerability: 4; Child clarity: 5.

**True flags:** none.

**Rationale:** A direct explanation is appropriate for a special rule, and the available action supports the next choice.

## ref-08

**Facts:** The learner staged a legal en-passant capture. The pawn moves diagonally to an empty square while capturing the opposing pawn that just advanced two squares.

**Purpose:** Explain the unusual capture accurately before the learner chooses whether to play it.

**Candidate:** “The pawn moved diagonally to take the pawn that just passed it.”

**Available actions:** playMove; expected response: chooseWhetherToPlay.

**Scores:** Chess correctness: 5; Coaching judgment: 4; Latest-action responsiveness: 5; Discovery and independence: 3; Coherence and answerability: 4; Child clarity: 4.

**True flags:** none.

**Rationale:** The explanation is accurate and suitably direct for an unusual rule, though just passed it could be slightly clearer.

## ref-09

**Facts:** The learner's bishop is under a real one-move threat. The learner staged an unrelated pawn move that leaves the bishop endangered.

**Purpose:** Respond to the staged move by returning attention to the unresolved urgent danger.

**Candidate:** “Your bishop is still attacked after that pawn move. How could you help it?”

**Available actions:** tryAnotherMove; expected response: stageMove.

**Scores:** Chess correctness: 5; Coaching judgment: 5; Latest-action responsiveness: 5; Discovery and independence: 5; Coherence and answerability: 5; Child clarity: 5.

**True flags:** none.

**Rationale:** It responds to the learner's latest move, keeps the urgent threat central, and asks the learner to solve it.

## ref-10

**Facts:** The learner just closed coaching help. No coaching response buttons remain visible. The app's global Help control remains available if the learner later wants help again.

**Purpose:** Respect the close action without continuing the lesson.

**Candidate:** “You closed help. Tap Help whenever you want another thought.”

**Available actions:** none; expected response: none.

**Scores:** Chess correctness: 5; Coaching judgment: 4; Latest-action responsiveness: 5; Discovery and independence: 4; Coherence and answerability: 5; Child clarity: 5.

**True flags:** none.

**Rationale:** It directly respects the close action and accurately refers to the separate global Help control.

## ref-11

**Facts:** White is to move in a quiet opening with several useful legal moves. Moving the central pawn to d4 is legal and reasonable. The board accepts staged moves directly.

**Purpose:** Encourage independent opening thought rather than prescribe one move.

**Candidate:** “Move your pawn to d4 now.”

**Available actions:** hint; expected response: stageMove.

**Scores:** Chess correctness: 4; Coaching judgment: 2; Latest-action responsiveness: 4; Discovery and independence: 1; Coherence and answerability: 4; Child clarity: 4.

**True flags:** none.

**Rationale:** The move is legal and understandable, but the command is unnecessarily prescriptive and teaches no decision-making process.

## ref-12

**Facts:** An opposing pawn attacks the learner's knight. The knight is loose and can be won if the learner ignores the threat.

**Purpose:** Help the learner recognize and solve the urgent danger.

**Candidate:** “Your knight is safe, so ignore the pawn attacking it.”

**Available actions:** noPieceNeedsHelp; expected response: findEndangeredPiece.

**Scores:** Chess correctness: 1; Coaching judgment: 1; Latest-action responsiveness: 2; Discovery and independence: 2; Coherence and answerability: 1; Child clarity: 4.

**True flags:** factualOrIllegalAdvice, wrongUrgentPriority, severeError.

**Rationale:** It reverses the decisive chess fact and directs the learner to ignore a piece-losing threat.

## ref-13

**Facts:** The learner staged a bishop capture. An opposing pawn can immediately recapture the bishop. The exchange loses material for the learner.

**Purpose:** Help the learner evaluate the staged capture before committing it.

**Candidate:** “Great capture! Keep it.”

**Available actions:** tryAnotherMove; expected response: judgeMoveSafety.

**Scores:** Chess correctness: 1; Coaching judgment: 1; Latest-action responsiveness: 4; Discovery and independence: 1; Coherence and answerability: 2; Child clarity: 4.

**True flags:** factualOrIllegalAdvice, wrongUrgentPriority, severeError.

**Rationale:** It directly approves a move that the verified facts say loses material.

## ref-14

**Facts:** The learner needs an answerable next step. The rook on a8 is not a learner piece and is not an available answer or move focus.

**Purpose:** Give an instruction the learner can complete through the current board or controls.

**Candidate:** “Tap the rook on a8.”

**Available actions:** hint; expected response: stageMove.

**Scores:** Chess correctness: 2; Coaching judgment: 1; Latest-action responsiveness: 2; Discovery and independence: 1; Coherence and answerability: 1; Child clarity: 4.

**True flags:** unavailableUIOrDeadEnd, severeError.

**Rationale:** The instruction is clear but cannot be completed through the available interaction and prevents progress.

## ref-15

**Facts:** There is no queen on f6. The learner's queen is not exposed to capture on the next move.

**Purpose:** Keep the advice grounded in the supplied position.

**Candidate:** “The queen on f6 can take your queen next.”

**Available actions:** hint; expected response: stageMove.

**Scores:** Chess correctness: 1; Coaching judgment: 1; Latest-action responsiveness: 2; Discovery and independence: 2; Coherence and answerability: 1; Child clarity: 4.

**True flags:** factualOrIllegalAdvice, wrongUrgentPriority, severeError.

**Rationale:** It invents both a piece and an urgent threat, making the chess advice unusable.

## ref-16

**Facts:** The knight on f3 is endangered. The current step asks the learner to identify the endangered piece by tapping it.

**Purpose:** Let the learner find the endangered piece rather than revealing it.

**Candidate:** “Look for the endangered knight. It is the knight on f3.”

**Available actions:** noPieceNeedsHelp; expected response: findEndangeredPiece.

**Scores:** Chess correctness: 5; Coaching judgment: 2; Latest-action responsiveness: 3; Discovery and independence: 1; Coherence and answerability: 2; Child clarity: 5.

**True flags:** answerRevealingGuidance, severeError.

**Rationale:** It explicitly names and highlights the answer while telling the learner to look for it, defeating the teaching interaction.

## ref-17

**Facts:** The learner first staged a pawn move, then replaced it with a knight move. Only the knight move is currently staged.

**Purpose:** Respond to and evaluate the learner's current knight move.

**Candidate:** “That first pawn move looks safe.”

**Available actions:** looksSafe; expected response: judgeMoveSafety.

**Scores:** Chess correctness: 3; Coaching judgment: 1; Latest-action responsiveness: 1; Discovery and independence: 2; Coherence and answerability: 2; Child clarity: 5.

**True flags:** obsoleteStage, mixedStages, severeError.

**Rationale:** It ignores the learner's replacement and evaluates a move that is no longer staged.

## ref-18

**Facts:** The learner's king is in check but is not checkmated. The staged bishop move is legal and resolves the check.

**Purpose:** Evaluate the legal response to check accurately.

**Candidate:** “Your king is checkmated, but you can move your bishop.”

**Available actions:** playMove; expected response: chooseWhetherToPlay.

**Scores:** Chess correctness: 1; Coaching judgment: 1; Latest-action responsiveness: 3; Discovery and independence: 1; Coherence and answerability: 1; Child clarity: 3.

**True flags:** factualOrIllegalAdvice, wrongUrgentPriority, mixedStages, severeError.

**Rationale:** The statement contradicts both the verified position and itself: a checkmated player has no legal move.

## ref-19

**Facts:** Moving the learner's knight to c3 is legal and safe. The move develops the knight with tempo in this position. The learner is an early beginner who is not expected to know algebraic notation or advanced terminology.

**Purpose:** Use clear beginner language and preserve agency while discussing a reasonable move.

**Candidate:** “Nc3 is a legal safe square and develops with tempo.”

**Available actions:** hint; expected response: stageMove.

**Scores:** Chess correctness: 5; Coaching judgment: 2; Latest-action responsiveness: 3; Discovery and independence: 2; Coherence and answerability: 3; Child clarity: 1.

**True flags:** none.

**Rationale:** The chess content is accurate, but the notation, redundant legal safe wording, and tempo jargon are poorly suited to the learner.

## ref-20

**Facts:** The learner has already staged a specific move. The current coaching step is to judge that move's safety. The available controls let the learner mark it safe or try another move.

**Purpose:** Help evaluate the current staged move rather than restart broad move selection.

**Candidate:** “Think about everything on the board and choose the best move.”

**Available actions:** looksSafe, tryAnotherMove; expected response: judgeMoveSafety.

**Scores:** Chess correctness: 3; Coaching judgment: 1; Latest-action responsiveness: 1; Discovery and independence: 3; Coherence and answerability: 1; Child clarity: 3.

**True flags:** obsoleteStage, mixedStages, unavailableUIOrDeadEnd, severeError.

**Rationale:** The generic instruction discards the current staged move and does not connect to the available safety judgment.

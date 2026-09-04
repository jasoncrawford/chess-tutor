# Judge reference set v2

Status: **pending human review**

Proposed by: Codex implementation agent on 2026-09-03

Response contract: `chess-native-v13`

Source Git SHA: `29d24c8bc081fe17431d0e88ab5a0e085c3f1b20`

Source corpus cases SHA-256: `d882d31605462b856266e6578ddfd2eec37dfbbd6d329150ae4b997398465afb`

Source corpus manifest SHA-256: `17b55d3222dadc818b738a0994b523b791b839015cdedbd184582b7bfccb9213`

Review every replayed context, candidate response, score, flag, preference, and rationale. Approval of this sheet is required before these judgments become qualification ground truth.

The raw source requests remain in the JSON reference set. This sheet renders the bounded facts needed for review.

## Absolute ref-01

**Source:** `q01-starting-position`; group=`q01-starting-position`; step=1; split=development; category=quiet; requestKind=initial.

**Request SHA-256:** `77808753061c1d93c3f32778deef8f888886339db8ef35688988f269fb41d727`

**FEN:** `rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1`

**Move history:** none

**Latest interaction:** helpOpened; references=[].

**Staged move:** none

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 0 plies. Latest learner event: helpOpened. Legal learner moves: 20. Legal learner captures: 0. Attacked learner pieces: none. Selected piece: none. Tentative move: none.

**Purpose:** Offer one useful beginner thought without inventing urgency or prescribing an exact move.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response encourages discovery and fits a position with no immediate emergency.

**Severe-failure criteria:** The response invents a hanging piece, forced tactic, check, or mandatory move.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[].

**Candidate:** “Which knight could you bring toward the middle, where it may have more choices?”

**Candidate controls:** actions=["hint"]; focus=[]; expects="stageMove".

**Scores:** Chess correctness: 5; Coaching judgment: 5; Latest-action responsiveness: 5; Discovery and independence: 5; Coherence and answerability: 5; Child clarity: 5.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** The position is quiet, and the question offers one useful idea without prescribing a move. It leaves the learner free to choose and stage a knight move.

## Absolute ref-02

**Source:** `d01-loose-bishop`; group=`d01-loose-bishop`; step=1; split=development; category=danger; requestKind=initial.

**Request SHA-256:** `63b0dc41eacd8dc78632654c24a270576458d7fbaf501daeb13a972c81546005`

**FEN:** `rnbqkbnr/ppp2ppp/8/3pp3/3P1B2/8/PPP1PPPP/RN1QKBNR w KQkq e6 0 3`

**Move history:** d4 d5 Bf4 e5

**Latest interaction:** helpOpened; references=[].

**Staged move:** none

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 4 plies. Latest learner event: helpOpened. Legal learner moves: 30. Legal learner captures: 2. Attacked learner pieces: bishop on f4, pawn on d4. Selected piece: none. Tentative move: none.

**Purpose:** Help the learner notice and reason about the most relevant immediate danger.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response accurately distinguishes a real threat from a defended or harmless attack.

**Severe-failure criteria:** The response misses check, claims a safe piece is lost, or identifies the wrong color or piece.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[].

**Candidate:** “Black's pawn is attacking two of your pieces. Can you find the more valuable one?”

**Candidate controls:** actions=[]; focus=[]; expects="findEndangeredPiece".

**Scores:** Chess correctness: 5; Coaching judgment: 5; Latest-action responsiveness: 5; Discovery and independence: 5; Coherence and answerability: 5; Child clarity: 5.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** The pawn attacks both the bishop and the pawn, and the bishop is the more valuable urgent target. The prompt preserves discovery and matches the declared identification response.

## Absolute ref-03

**Source:** `s01-danger-selection-response-02`; group=`s01-danger-selection-response`; step=2; split=development; category=danger; requestKind=followUp.

**Request SHA-256:** `508734253e6b68367c9a7d0842687b766c9dc7e9832032564fb8240d3c0e1efe`

**FEN:** `rnbqkbnr/pppp1ppp/8/8/4p3/5NP1/PPPPPP1P/RNBQKB1R w KQkq - 0 3`

**Move history:** Nf3 e5 g3 e4

**Latest interaction:** pieceSelected; references=["piece:white:knight:f3"].

**Staged move:** none

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 4 plies. Latest learner event: pieceSelected. Legal learner moves: 22. Legal learner captures: 0. Attacked learner pieces: knight on f3. Selected piece: piece:white:knight:f3. Tentative move: none.

**Purpose:** Help the learner notice and reason about the most relevant immediate danger.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response accurately distinguishes a real threat from a defended or harmless attack.

**Severe-failure criteria:** The response misses check, claims a safe piece is lost, or identifies the wrong color or piece.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[["f3", "d4"], ["f3", "e5"], ["f3", "g1"], ["f3", "g5"], ["f3", "h4"]].

**Candidate:** “Yes, that knight needs help. Where could you move it so the pawn cannot take it?”

**Candidate controls:** actions=[]; focus=[]; expects="stageMove".

**Scores:** Chess correctness: 5; Coaching judgment: 5; Latest-action responsiveness: 5; Discovery and independence: 4; Coherence and answerability: 5; Child clarity: 5.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** The response confirms the learner's correct selection and advances to an answerable move choice. Naming the already-selected knight does not remove the learner's remaining decision.

## Absolute ref-04

**Source:** `c01-safe-queen-capture`; group=`c01-safe-queen-capture`; step=1; split=development; category=capture; requestKind=initial.

**Request SHA-256:** `db51b3d7caafbf6d2db8cbfb1204af3afa703514229919c00f7cf1f389f5406b`

**FEN:** `rnb1kbnr/pppp1ppp/8/4p3/4P2q/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3`

**Move history:** e4 e5 Nf3 Qh4

**Latest interaction:** helpOpened; references=[].

**Staged move:** none

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 4 plies. Latest learner event: helpOpened. Legal learner moves: 26. Legal learner captures: 2. Attacked learner pieces: pawn on e4, pawn on f2, pawn on h2. Selected piece: none. Tentative move: none.

**Purpose:** Help the learner assess whether a capture is available and what the opponent can do next.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response treats recaptures and exchanges accurately without revealing more than needed.

**Severe-failure criteria:** The response invents a capture, overlooks an encoded recapture, or calls a losing capture safe.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[].

**Candidate:** “Can you find the valuable black piece your knight can capture safely?”

**Candidate controls:** actions=[]; focus=[]; expects="findSafeCapture".

**Scores:** Chess correctness: 5; Coaching judgment: 5; Latest-action responsiveness: 5; Discovery and independence: 5; Coherence and answerability: 5; Child clarity: 5.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** The knight has a safe capture of Black's queen, but the response does not reveal its square. The question directly matches the declared safe-capture discovery response.

## Absolute ref-05

**Source:** `s03-capture-none-02`; group=`s03-capture-none`; step=2; split=development; category=capture; requestKind=followUp.

**Request SHA-256:** `edb7e604268c72b53967f361bedbbbfcbe5be5fe9e32209def7ad2eb674b74d7`

**FEN:** `rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1`

**Move history:** none

**Latest interaction:** actionChosen; references=["action:noSafeCapture"].

**Staged move:** none

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 0 plies. Latest learner event: actionChosen. Legal learner moves: 20. Legal learner captures: 0. Attacked learner pieces: none. Selected piece: none. Tentative move: none.

**Purpose:** Help the learner assess whether a capture is available and what the opponent can do next.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response treats recaptures and exchanges accurately without revealing more than needed.

**Severe-failure criteria:** The response invents a capture, overlooks an encoded recapture, or calls a losing capture safe.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[].

**Candidate:** “Right, there is no capture yet. Which piece could you move toward the middle?”

**Candidate controls:** actions=["hint"]; focus=[]; expects="stageMove".

**Scores:** Chess correctness: 5; Coaching judgment: 5; Latest-action responsiveness: 5; Discovery and independence: 5; Coherence and answerability: 5; Child clarity: 5.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** The response accepts the learner's correct no-capture answer and advances to a useful move. It does not repeat the resolved capture search.

## Absolute ref-06

**Source:** `s04-safe-move-confirm-02`; group=`s04-safe-move-confirm`; step=2; split=development; category=tentativeMove; requestKind=followUp.

**Request SHA-256:** `4c7c1862726cd1415669306a59a98ee9579db905e9f86d3da8686d893a987ce9`

**FEN:** `rnbqkb1r/ppp1pppp/5n2/3p4/3P4/5N2/PPP1PPPP/RNBQKB1R w KQkq - 2 3`

**Move history:** d4 d5 Nf3 Nf6

**Latest interaction:** moveStaged; references=["move:b1-c3"].

**Staged move:** b1c3 (Nc3; special=none; legal=true)

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 4 plies. Latest learner event: moveStaged. Legal learner moves: 29. Legal learner captures: 0. Attacked learner pieces: none. Selected piece: piece:white:knight:b1. Tentative move: b1c3; legal: true. Forcing immediate replies: 0.

**Purpose:** Respond to the currently staged move and help the learner evaluate it before committing.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response follows the latest move and gives one answerable next step.

**Severe-failure criteria:** The response discusses a superseded move or approves a move contradicted by an immediate reply.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[["b1", "c3"]].

**Candidate:** “Your knight move has no immediate forcing reply. Does it look safe?”

**Candidate controls:** actions=[]; focus=[{"from": "b1", "to": "c3", "type": "move"}]; expects="judgeMoveSafety".

**Scores:** Chess correctness: 5; Coaching judgment: 5; Latest-action responsiveness: 5; Discovery and independence: 4; Coherence and answerability: 5; Child clarity: 5.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** The response evaluates the actual staged knight move and uses its allowable move focus. It gives a grounded clue while leaving the learner to judge safety.

## Absolute ref-07

**Source:** `s04-safe-move-confirm-03`; group=`s04-safe-move-confirm`; step=3; split=development; category=tentativeMove; requestKind=followUp.

**Request SHA-256:** `a8c26069b7594f309206c95e54dd2210e7f6f2eae093779872f38deebebc942a`

**FEN:** `rnbqkb1r/ppp1pppp/5n2/3p4/3P4/5N2/PPP1PPPP/RNBQKB1R w KQkq - 2 3`

**Move history:** d4 d5 Nf3 Nf6

**Latest interaction:** actionChosen; references=["action:looksSafe"].

**Staged move:** b1c3 (Nc3; special=none; legal=true)

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 4 plies. Latest learner event: actionChosen. Legal learner moves: 29. Legal learner captures: 0. Attacked learner pieces: none. Selected piece: piece:white:knight:b1. Tentative move: b1c3; legal: true. Forcing immediate replies: 0.

**Purpose:** Respond to the currently staged move and help the learner evaluate it before committing.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response follows the latest move and gives one answerable next step.

**Severe-failure criteria:** The response discusses a superseded move or approves a move contradicted by an immediate reply.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[["b1", "c3"]].

**Candidate:** “Yes, it looks safe. Would you like to play this move or try another one?”

**Candidate controls:** actions=[]; focus=[{"from": "b1", "to": "c3", "type": "move"}]; expects="chooseWhetherToPlay".

**Scores:** Chess correctness: 5; Coaching judgment: 5; Latest-action responsiveness: 5; Discovery and independence: 5; Coherence and answerability: 5; Child clarity: 5.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** The response acknowledges the learner's positive safety judgment and asks for the next available decision. Its move focus points to the current staged move rather than an earlier stage.

## Absolute ref-08

**Source:** `c02-poisoned-bishop-capture`; group=`c02-poisoned-bishop-capture`; step=1; split=development; category=capture; requestKind=initial.

**Request SHA-256:** `b9626025d4450585fb33b9c4ef362b9654b0eaaad162fa39d1ebb6164744c70f`

**FEN:** `rnbqkb1r/pppp1ppp/5n2/4p3/2B1P3/8/PPPP1PPP/RNBQK1NR w KQkq - 2 3`

**Move history:** e4 e5 Bc4 Nf6

**Latest interaction:** moveStaged; references=["move:c4-f7"].

**Staged move:** c4f7 (Bxf7+; special=none; legal=true)

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 4 plies. Latest learner event: moveStaged. Legal learner moves: 33. Legal learner captures: 1. Attacked learner pieces: pawn on e4. Selected piece: piece:white:bishop:c4. Tentative move: c4f7; legal: true. Forcing immediate replies: 1.

**Purpose:** Help the learner assess whether a capture is available and what the opponent can do next.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response treats recaptures and exchanges accurately without revealing more than needed.

**Severe-failure criteria:** The response invents a capture, overlooks an encoded recapture, or calls a losing capture safe.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[["c4", "f7"], ["e8", "f7"]].

**Candidate:** “After this bishop capture, Black's king can take your bishop. Does the capture still look safe?”

**Candidate controls:** actions=[]; focus=[{"from": "c4", "to": "f7", "type": "move"}]; expects="judgeMoveSafety".

**Scores:** Chess correctness: 5; Coaching judgment: 4; Latest-action responsiveness: 5; Discovery and independence: 2; Coherence and answerability: 5; Child clarity: 5.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: true; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** The stated recapture is factually correct and the question remains answerable in the declared stage. It reveals the decisive reply, so pedagogy and discovery score lower without reducing chess correctness.

## Absolute ref-09

**Source:** `s05-unsafe-move-retry-03`; group=`s05-unsafe-move-retry`; step=3; split=development; category=tentativeMove; requestKind=followUp.

**Request SHA-256:** `711a3a1b742388f74e413abb55233b8ab47398130de3beb38523322c3807f8a6`

**FEN:** `rnbqkbnr/ppp1ppp1/7p/3p2B1/3P4/8/PPP1PPPP/RN1QKBNR w KQkq - 0 3`

**Move history:** d4 d5 Bg5 h6

**Latest interaction:** actionChosen; references=["action:tryAnotherMove"].

**Staged move:** a2a3 (a3; special=none; legal=true)

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 4 plies. Latest learner event: actionChosen. Legal learner moves: 31. Legal learner captures: 2. Attacked learner pieces: bishop on g5. Selected piece: piece:white:pawn:a2. Tentative move: a2a3; legal: true. Forcing immediate replies: 1.

**Purpose:** Respond to the currently staged move and help the learner evaluate it before committing.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response follows the latest move and gives one answerable next step.

**Severe-failure criteria:** The response discusses a superseded move or approves a move contradicted by an immediate reply.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[["a2", "a3"], ["h6", "g5"]].

**Candidate:** “Good choice to try again. Move your bishop somewhere the pawn cannot take it.”

**Candidate controls:** actions=[]; focus=[]; expects="stageMove".

**Scores:** Chess correctness: 5; Coaching judgment: 5; Latest-action responsiveness: 5; Discovery and independence: 4; Coherence and answerability: 5; Child clarity: 5.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** The learner chose to retry, and the response returns to resolving the still-urgent bishop danger. It constrains the goal without prescribing an exact move.

## Absolute ref-10

**Source:** `s06-replace-move-03`; group=`s06-replace-move`; step=3; split=development; category=tentativeMove; requestKind=followUp.

**Request SHA-256:** `748c45853832ffbe91eb082b8e647ce981118662bacc88fbc887ababf4f1ca57`

**FEN:** `rnbqkbnr/ppp1p1pp/5p2/3pN3/8/8/PPPPPPPP/RNBQKB1R w KQkq - 0 3`

**Move history:** Nf3 d5 Ne5 f6

**Latest interaction:** moveReplaced; references=["move:e5-f3"].

**Staged move:** e5f3 (Nf3; special=none; legal=true)

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 4 plies. Latest learner event: moveReplaced. Legal learner moves: 27. Legal learner captures: 0. Attacked learner pieces: knight on e5. Selected piece: piece:white:knight:e5. Tentative move: e5f3; legal: true. Forcing immediate replies: 0.

**Purpose:** Respond to the currently staged move and help the learner evaluate it before committing.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response follows the latest move and gives one answerable next step.

**Severe-failure criteria:** The response discusses a superseded move or approves a move contradicted by an immediate reply.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[["e5", "f3"]].

**Candidate:** “You changed to the knight move. Does this new move look safe?”

**Candidate controls:** actions=[]; focus=[{"from": "e5", "to": "f3", "type": "move"}]; expects="judgeMoveSafety".

**Scores:** Chess correctness: 5; Coaching judgment: 5; Latest-action responsiveness: 5; Discovery and independence: 5; Coherence and answerability: 5; Child clarity: 5.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** The response follows the replacement event and evaluates the current staged move. The move focus is the allowable focus for the new move, not the superseded move.

## Absolute ref-11

**Source:** `h05-stale-selection-replaced`; group=`h05-stale-selection-replaced`; step=1; split=holdout; category=interaction; requestKind=initial.

**Request SHA-256:** `0815d0e931f691c746abc67c65a1ab48b586cdb5b30d3be2e29692ff23e7f2e0`

**FEN:** `rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2`

**Move history:** e4 e5

**Latest interaction:** moveReplaced; references=["move:g1-f3"].

**Staged move:** g1f3 (Nf3; special=none; legal=true)

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 2 plies. Latest learner event: moveReplaced. Legal learner moves: 29. Legal learner captures: 0. Attacked learner pieces: none. Selected piece: piece:white:knight:g1. Tentative move: g1f3; legal: true. Forcing immediate replies: 0.

**Purpose:** Follow the learner's latest tap, answer, revision, or help action without repeating a resolved step.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response acknowledges the latest interaction and advances one coherent step.

**Severe-failure criteria:** The response ignores the latest event, repeats a resolved question, or offers no possible next action.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[["g1", "f3"]].

**Candidate:** “Your earlier pawn move looks safe. Would you like to play it?”

**Candidate controls:** actions=[]; focus=[]; expects="chooseWhetherToPlay".

**Scores:** Chess correctness: 5; Coaching judgment: 1; Latest-action responsiveness: 1; Discovery and independence: 2; Coherence and answerability: 1; Child clarity: 5.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: true; mixedStages: true; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: true.

**Rationale:** The sentence can be factually true about the earlier move, so chess correctness remains separate from pedagogy. It ignores the latest knight replacement and asks the learner to act on an obsolete stage, which is a severe coherence failure.

## Absolute ref-12

**Source:** `s07-inspect-reply-03`; group=`s07-inspect-reply`; step=3; split=development; category=tentativeMove; requestKind=followUp.

**Request SHA-256:** `d03c87f1e8ed7d31fa49b036402dd2f7562c419845893e6ff65d4be11658cedc`

**FEN:** `rnb1kbnr/pppp1ppp/5q2/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3`

**Move history:** e4 e5 Nf3 Qf6

**Latest interaction:** squareInspected; references=["piece:black:queen:f6"].

**Staged move:** d2d3 (d3; special=none; legal=true)

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 4 plies. Latest learner event: squareInspected. Legal learner moves: 27. Legal learner captures: 1. Attacked learner pieces: knight on f3. Selected piece: piece:white:pawn:d2. Tentative move: d2d3; legal: true. Forcing immediate replies: 2.

**Purpose:** Respond to the currently staged move and help the learner evaluate it before committing.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response follows the latest move and gives one answerable next step.

**Severe-failure criteria:** The response discusses a superseded move or approves a move contradicted by an immediate reply.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[["d2", "d3"], ["f6", "f3"]].

**Candidate:** “Look again at the queen you tapped. Does your pawn move still look safe?”

**Candidate controls:** actions=[]; focus=[{"square": "f6", "type": "square"}]; expects="judgeMoveSafety".

**Scores:** Chess correctness: 5; Coaching judgment: 5; Latest-action responsiveness: 5; Discovery and independence: 5; Coherence and answerability: 5; Child clarity: 5.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** The response acknowledges the inspected black queen and reconnects it to the staged pawn move's safety. Its square focus identifies the square the learner just inspected without revealing the reply.

## Absolute ref-13

**Source:** `s08-hint-then-act-02`; group=`s08-hint-then-act`; step=2; split=development; category=interaction; requestKind=followUp.

**Request SHA-256:** `dbca335d20d7fb9a00e2021409f98e77cae03eb4d3253a3af143d07834865c46`

**FEN:** `rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1`

**Move history:** none

**Latest interaction:** actionChosen; references=["action:hint"].

**Staged move:** none

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 0 plies. Latest learner event: actionChosen. Legal learner moves: 20. Legal learner captures: 0. Attacked learner pieces: none. Selected piece: none. Tentative move: none.

**Purpose:** Follow the learner's latest tap, answer, revision, or help action without repeating a resolved step.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response acknowledges the latest interaction and advances one coherent step.

**Severe-failure criteria:** The response ignores the latest event, repeats a resolved question, or offers no possible next action.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[].

**Candidate:** “Here is a hint: a knight near the middle often has more choices. Which knight could you move there?”

**Candidate controls:** actions=["hint"]; focus=[]; expects="stageMove".

**Scores:** Chess correctness: 5; Coaching judgment: 5; Latest-action responsiveness: 5; Discovery and independence: 4; Coherence and answerability: 5; Child clarity: 5.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** The response follows the learner's Hint action and provides a useful quiet-position idea. It narrows the idea to knights but preserves the exact move choice.

## Absolute ref-14

**Source:** `m07-castling`; group=`m07-castling`; step=1; split=development; category=specialRule; requestKind=initial.

**Request SHA-256:** `81d16055d66103c0a1417f83e392b9b00c9559b3a8fba5f98a00a55a3baf20f6`

**FEN:** `r1bqkb1r/1ppp1ppp/p1n2n2/4p3/B3P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 2 5`

**Move history:** e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6

**Latest interaction:** moveStaged; references=["move:e1-g1:castle-kingside"].

**Staged move:** e1g1 (O-O; special=castle-kingside; legal=true)

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 8 plies. Latest learner event: moveStaged. Legal learner moves: 27. Legal learner captures: 2. Attacked learner pieces: pawn on e4. Selected piece: piece:white:king:e1. Tentative move: e1g1; legal: true. Forcing immediate replies: 1.

**Purpose:** Explain the relevant check, mate, castling, en-passant, or promotion consequence simply and accurately.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response handles the special rule correctly in beginner-friendly language.

**Severe-failure criteria:** The response misstates legality, check, checkmate, castling, en-passant, or promotion.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[["e1", "g1"], ["f6", "e4"]].

**Candidate:** “This castle would move your king toward shelter and bring your rook out. Does the move look safe?”

**Candidate controls:** actions=[]; focus=[{"from": "e1", "to": "g1", "type": "move"}]; expects="judgeMoveSafety".

**Scores:** Chess correctness: 5; Coaching judgment: 5; Latest-action responsiveness: 5; Discovery and independence: 4; Coherence and answerability: 5; Child clarity: 5.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** The response explains both piece movements and the usual purpose of the legal staged castle. It uses the current move focus and asks for the learner's safety judgment.

## Absolute ref-15

**Source:** `c06-en-passant`; group=`c06-en-passant`; step=1; split=development; category=specialRule; requestKind=initial.

**Request SHA-256:** `2a91b99f33a8b8ed6bb1259f2cfa477462e3f0ebf01a95a913b7d78cfe498153`

**FEN:** `rnbqkbnr/1pp1pppp/p7/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3`

**Move history:** e4 a6 e5 d5

**Latest interaction:** moveStaged; references=["move:e5-d6:en-passant"].

**Staged move:** e5d6 (exd6; special=en-passant; legal=true)

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 4 plies. Latest learner event: moveStaged. Legal learner moves: 31. Legal learner captures: 2. Attacked learner pieces: none. Selected piece: piece:white:pawn:e5. Tentative move: e5d6; legal: true. Forcing immediate replies: 3.

**Purpose:** Explain the relevant check, mate, castling, en-passant, or promotion consequence simply and accurately.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response handles the special rule correctly in beginner-friendly language.

**Severe-failure criteria:** The response misstates legality, check, checkmate, castling, en-passant, or promotion.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[["e5", "d6"], ["c7", "d6"], ["d8", "d6"], ["e7", "d6"]].

**Candidate:** “This special capture takes the pawn that just moved two squares, even though it stands beside your pawn. Does the capture look safe?”

**Candidate controls:** actions=[]; focus=[{"from": "e5", "to": "d6", "type": "move"}]; expects="judgeMoveSafety".

**Scores:** Chess correctness: 5; Coaching judgment: 5; Latest-action responsiveness: 5; Discovery and independence: 3; Coherence and answerability: 5; Child clarity: 4.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** The explanation accurately describes the legal staged en-passant capture in plain terms. The rule explanation is somewhat long but leaves the safety judgment to the learner.

## Absolute ref-16

**Source:** `m06-promotion`; group=`m06-promotion`; step=1; split=development; category=specialRule; requestKind=initial.

**Request SHA-256:** `42168807db82be1ebcb7ee8090b14517781e749489a9dc1b2cf1a11b076609d7`

**FEN:** `rnbqkbnr/pPppppp1/8/8/8/8/1PPPPPpP/RNBQKBNR w KQkq - 0 5`

**Move history:** a4 h5 a5 h4 a6 h3 axb7 hxg2

**Latest interaction:** moveStaged; references=["move:b7-a8:promote-queen"].

**Staged move:** b7a8q (bxa8=Q; special=promote-queen; legal=true)

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 8 plies. Latest learner event: moveStaged. Legal learner moves: 31. Legal learner captures: 10. Attacked learner pieces: bishop on f1, pawn on b7, pawn on h2, rook on h1. Selected piece: piece:white:pawn:b7. Tentative move: b7a8q; legal: true. Forcing immediate replies: 9.

**Purpose:** Explain the relevant check, mate, castling, en-passant, or promotion consequence simply and accurately.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response handles the special rule correctly in beginner-friendly language.

**Severe-failure criteria:** The response misstates legality, check, checkmate, castling, en-passant, or promotion.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[["b7", "a8"], ["g2", "f1"], ["g2", "h1"], ["h8", "h2"]].

**Candidate:** “This pawn would reach the back rank and become a queen. Does the move look safe?”

**Candidate controls:** actions=[]; focus=[{"from": "b7", "to": "a8", "type": "move"}]; expects="judgeMoveSafety".

**Scores:** Chess correctness: 5; Coaching judgment: 5; Latest-action responsiveness: 5; Discovery and independence: 3; Coherence and answerability: 5; Child clarity: 5.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** The response accurately describes the selected queen promotion and points to the staged move. It explains the consequence before asking the learner to judge the move's safety.

## Absolute ref-17

**Source:** `c05-mating-capture`; group=`c05-mating-capture`; step=1; split=development; category=specialRule; requestKind=initial.

**Request SHA-256:** `24b90eccd8619f23494646500a953f55ff26833cfd8a4f792f3509e3bd73aeb1`

**FEN:** `r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4`

**Move history:** e4 e5 Bc4 Nc6 Qh5 Nf6

**Latest interaction:** helpOpened; references=[].

**Staged move:** none

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 6 plies. Latest learner event: helpOpened. Legal learner moves: 43. Legal learner captures: 4. Attacked learner pieces: pawn on e4, queen on h5. Selected piece: none. Tentative move: none.

**Purpose:** Explain the relevant check, mate, castling, en-passant, or promotion consequence simply and accurately.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response handles the special rule correctly in beginner-friendly language.

**Severe-failure criteria:** The response misstates legality, check, checkmate, castling, en-passant, or promotion.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[].

**Candidate:** “Black has already checkmated your king, so you cannot move.”

**Candidate controls:** actions=[]; focus=[]; expects="stageMove".

**Scores:** Chess correctness: 1; Coaching judgment: 1; Latest-action responsiveness: 3; Discovery and independence: 1; Coherence and answerability: 1; Child clarity: 4.

**Flags:** factualOrIllegalAdvice: true; wrongUrgentPriority: true; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: true; severeError: true.

**Rationale:** The position is ongoing and White has legal moves, so the checkmate claim is factually false. It says no move is possible while declaring a move-staging response, creating a severe dead end.

## Absolute ref-18

**Source:** `h01-quiet-black-opening`; group=`h01-quiet-black-opening`; step=1; split=holdout; category=quiet; requestKind=initial.

**Request SHA-256:** `b28f405c82c2eb7bc02fd2e43c4d553b3b07a92f4daeea18726d243a81fee8f6`

**FEN:** `rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1`

**Move history:** e4

**Latest interaction:** helpOpened; references=[].

**Staged move:** none

**Facts:** Side to move: black. Position status: ongoing. Committed history length: 1 plies. Latest learner event: helpOpened. Legal learner moves: 20. Legal learner captures: 0. Attacked learner pieces: none. Selected piece: none. Tentative move: none.

**Purpose:** Offer one useful beginner thought without inventing urgency or prescribing an exact move.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response encourages discovery and fits a position with no immediate emergency.

**Severe-failure criteria:** The response invents a hanging piece, forced tactic, check, or mandatory move.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[].

**Candidate:** “Move the pawn in front of your king two squares, then type done in the answer box.”

**Candidate controls:** actions=[]; focus=[]; expects="stageMove".

**Scores:** Chess correctness: 5; Coaching judgment: 1; Latest-action responsiveness: 4; Discovery and independence: 1; Coherence and answerability: 1; Child clarity: 4.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: true; unavailableUIOrDeadEnd: true; severeError: true.

**Rationale:** The prescribed pawn move is legal, so answer revealing is scored separately from chess correctness. The response also requires a nonexistent answer box that the declared stageMove interaction cannot accept, making it a severe dead end.

## Absolute ref-19

**Source:** `q02-quiet-midgame`; group=`q02-quiet-midgame`; step=1; split=development; category=quiet; requestKind=initial.

**Request SHA-256:** `bc5b9c2668a702b2b928f60a95d612269630ae6ca31aa13779210553fe07bc3d`

**FEN:** `r1bq1rk1/ppppbppp/2n2n2/4p3/2B1P3/3P1N2/PPP2PPP/RNBQ1RK1 w - - 3 6`

**Move history:** e4 e5 Nf3 Nc6 Bc4 Nf6 d3 Be7 O-O O-O

**Latest interaction:** helpOpened; references=[].

**Staged move:** none

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 10 plies. Latest learner event: helpOpened. Legal learner moves: 35. Legal learner captures: 2. Attacked learner pieces: pawn on e4. Selected piece: none. Tentative move: none.

**Purpose:** Offer one useful beginner thought without inventing urgency or prescribing an exact move.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response encourages discovery and fits a position with no immediate emergency.

**Severe-failure criteria:** The response invents a hanging piece, forced tactic, check, or mandatory move.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[].

**Candidate:** “You have legal choices here. Pick one that seems useful.”

**Candidate controls:** actions=[]; focus=[]; expects="stageMove".

**Scores:** Chess correctness: 5; Coaching judgment: 2; Latest-action responsiveness: 5; Discovery and independence: 3; Coherence and answerability: 3; Child clarity: 2.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** The message is factually true and mechanically answerable, so it keeps full chess correctness and no error flags. It is too vague to provide much coaching value or child-friendly direction, so clarity and judgment score poorly.

## Absolute ref-20

**Source:** `s10-close-and-reopen-03`; group=`s10-close-and-reopen`; step=3; split=holdout; category=interaction; requestKind=followUp.

**Request SHA-256:** `537daecfde1e905302449f97d513a8ee788326e0f50a0776d952933051cb38a9`

**FEN:** `rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1`

**Move history:** none

**Latest interaction:** helpReopened; references=[].

**Staged move:** none

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 0 plies. Latest learner event: helpReopened. Legal learner moves: 20. Legal learner captures: 0. Attacked learner pieces: none. Selected piece: none. Tentative move: none.

**Purpose:** Follow the learner's latest tap, answer, revision, or help action without repeating a resolved step.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response acknowledges the latest interaction and advances one coherent step.

**Severe-failure criteria:** The response ignores the latest event, repeats a resolved question, or offers no possible next action.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[].

**Candidate:** “Welcome back. Which knight could you bring toward the middle?”

**Candidate controls:** actions=["hint"]; focus=[]; expects="stageMove".

**Scores:** Chess correctness: 5; Coaching judgment: 5; Latest-action responsiveness: 5; Discovery and independence: 5; Coherence and answerability: 5; Child clarity: 5.

**Flags:** factualOrIllegalAdvice: false; wrongUrgentPriority: false; obsoleteStage: false; mixedStages: false; answerRevealingGuidance: false; unavailableUIOrDeadEnd: false; severeError: false.

**Rationale:** The response follows the hosted helpReopened turn and restarts with one useful quiet-position question. It is a real response-bearing turn rather than an acknowledgment after Help has closed.

## Pairwise pair-01

**Source:** `q01-starting-position`; group=`q01-starting-position`; step=1; split=development; category=quiet; requestKind=initial.

**Request SHA-256:** `77808753061c1d93c3f32778deef8f888886339db8ef35688988f269fb41d727`

**FEN:** `rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1`

**Move history:** none

**Latest interaction:** helpOpened; references=[].

**Staged move:** none

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 0 plies. Latest learner event: helpOpened. Legal learner moves: 20. Legal learner captures: 0. Attacked learner pieces: none. Selected piece: none. Tentative move: none.

**Purpose:** Offer one useful beginner thought without inventing urgency or prescribing an exact move.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response encourages discovery and fits a position with no immediate emergency.

**Severe-failure criteria:** The response invents a hanging piece, forced tactic, check, or mandatory move.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[].

**Response one:** “Which knight could you bring toward the middle, where it may have more choices?”

**Response one controls:** actions=["hint"]; focus=[]; expects="stageMove".

**Response two:** “Move a knight.”

**Response two controls:** actions=[]; focus=[]; expects="stageMove".

**Reference preference:** responseOne

**Rationale:** Response one supplies a useful beginner reason while preserving the same move choice.

## Pairwise pair-02

**Source:** `d01-loose-bishop`; group=`d01-loose-bishop`; step=1; split=development; category=danger; requestKind=initial.

**Request SHA-256:** `63b0dc41eacd8dc78632654c24a270576458d7fbaf501daeb13a972c81546005`

**FEN:** `rnbqkbnr/ppp2ppp/8/3pp3/3P1B2/8/PPP1PPPP/RN1QKBNR w KQkq e6 0 3`

**Move history:** d4 d5 Bf4 e5

**Latest interaction:** helpOpened; references=[].

**Staged move:** none

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 4 plies. Latest learner event: helpOpened. Legal learner moves: 30. Legal learner captures: 2. Attacked learner pieces: bishop on f4, pawn on d4. Selected piece: none. Tentative move: none.

**Purpose:** Help the learner notice and reason about the most relevant immediate danger.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response accurately distinguishes a real threat from a defended or harmless attack.

**Severe-failure criteria:** The response misses check, claims a safe piece is lost, or identifies the wrong color or piece.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[].

**Response one:** “Black's pawn is attacking two of your pieces. Can you find the more valuable one?”

**Response one controls:** actions=[]; focus=[]; expects="findEndangeredPiece".

**Response two:** “Your bishop is endangered. Tap it.”

**Response two controls:** actions=[]; focus=[]; expects="stageMove".

**Reference preference:** responseOne

**Rationale:** Response one preserves discovery and aligns its question with its expected response; response two reveals the answer and declares the wrong next interaction.

## Pairwise pair-03

**Source:** `c01-safe-queen-capture`; group=`c01-safe-queen-capture`; step=1; split=development; category=capture; requestKind=initial.

**Request SHA-256:** `db51b3d7caafbf6d2db8cbfb1204af3afa703514229919c00f7cf1f389f5406b`

**FEN:** `rnb1kbnr/pppp1ppp/8/4p3/4P2q/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3`

**Move history:** e4 e5 Nf3 Qh4

**Latest interaction:** helpOpened; references=[].

**Staged move:** none

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 4 plies. Latest learner event: helpOpened. Legal learner moves: 26. Legal learner captures: 2. Attacked learner pieces: pawn on e4, pawn on f2, pawn on h2. Selected piece: none. Tentative move: none.

**Purpose:** Help the learner assess whether a capture is available and what the opponent can do next.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response treats recaptures and exchanges accurately without revealing more than needed.

**Severe-failure criteria:** The response invents a capture, overlooks an encoded recapture, or calls a losing capture safe.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[].

**Response one:** “Can you find the valuable black piece your knight can capture safely?”

**Response one controls:** actions=[]; focus=[]; expects="findSafeCapture".

**Response two:** “Capture the black queen with your knight.”

**Response two controls:** actions=[]; focus=[]; expects="findSafeCapture".

**Reference preference:** responseOne

**Rationale:** Both are mechanically valid and factually grounded, but response one lets the learner discover the safe capture.

## Pairwise pair-04

**Source:** `s04-safe-move-confirm-02`; group=`s04-safe-move-confirm`; step=2; split=development; category=tentativeMove; requestKind=followUp.

**Request SHA-256:** `4c7c1862726cd1415669306a59a98ee9579db905e9f86d3da8686d893a987ce9`

**FEN:** `rnbqkb1r/ppp1pppp/5n2/3p4/3P4/5N2/PPP1PPPP/RNBQKB1R w KQkq - 2 3`

**Move history:** d4 d5 Nf3 Nf6

**Latest interaction:** moveStaged; references=["move:b1-c3"].

**Staged move:** b1c3 (Nc3; special=none; legal=true)

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 4 plies. Latest learner event: moveStaged. Legal learner moves: 29. Legal learner captures: 0. Attacked learner pieces: none. Selected piece: piece:white:knight:b1. Tentative move: b1c3; legal: true. Forcing immediate replies: 0.

**Purpose:** Respond to the currently staged move and help the learner evaluate it before committing.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response follows the latest move and gives one answerable next step.

**Severe-failure criteria:** The response discusses a superseded move or approves a move contradicted by an immediate reply.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[["b1", "c3"]].

**Response one:** “Your knight move has no immediate forcing reply. Does it look safe?”

**Response one controls:** actions=[]; focus=[{"from": "b1", "to": "c3", "type": "move"}]; expects="judgeMoveSafety".

**Response two:** “Your knight is in the middle now. What do you notice?”

**Response two controls:** actions=[]; focus=[]; expects="judgeMoveSafety".

**Reference preference:** responseOne

**Rationale:** Response one asks the declared safety question and grounds it in the actual staged move; response two is less answerable.

## Pairwise pair-05

**Source:** `s04-safe-move-confirm-03`; group=`s04-safe-move-confirm`; step=3; split=development; category=tentativeMove; requestKind=followUp.

**Request SHA-256:** `a8c26069b7594f309206c95e54dd2210e7f6f2eae093779872f38deebebc942a`

**FEN:** `rnbqkb1r/ppp1pppp/5n2/3p4/3P4/5N2/PPP1PPPP/RNBQKB1R w KQkq - 2 3`

**Move history:** d4 d5 Nf3 Nf6

**Latest interaction:** actionChosen; references=["action:looksSafe"].

**Staged move:** b1c3 (Nc3; special=none; legal=true)

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 4 plies. Latest learner event: actionChosen. Legal learner moves: 29. Legal learner captures: 0. Attacked learner pieces: none. Selected piece: piece:white:knight:b1. Tentative move: b1c3; legal: true. Forcing immediate replies: 0.

**Purpose:** Respond to the currently staged move and help the learner evaluate it before committing.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response follows the latest move and gives one answerable next step.

**Severe-failure criteria:** The response discusses a superseded move or approves a move contradicted by an immediate reply.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[["b1", "c3"]].

**Response one:** “Yes, it looks safe. Would you like to play this move or try another one?”

**Response one controls:** actions=[]; focus=[{"from": "b1", "to": "c3", "type": "move"}]; expects="chooseWhetherToPlay".

**Response two:** “That was a good move.”

**Response two controls:** actions=[]; focus=[]; expects="chooseWhetherToPlay".

**Reference preference:** responseOne

**Rationale:** Response one acknowledges the answer and gives the learner the declared choice; response two does not ask for a choice.

## Pairwise pair-06

**Source:** `c02-poisoned-bishop-capture`; group=`c02-poisoned-bishop-capture`; step=1; split=development; category=capture; requestKind=initial.

**Request SHA-256:** `b9626025d4450585fb33b9c4ef362b9654b0eaaad162fa39d1ebb6164744c70f`

**FEN:** `rnbqkb1r/pppp1ppp/5n2/4p3/2B1P3/8/PPPP1PPP/RNBQK1NR w KQkq - 2 3`

**Move history:** e4 e5 Bc4 Nf6

**Latest interaction:** moveStaged; references=["move:c4-f7"].

**Staged move:** c4f7 (Bxf7+; special=none; legal=true)

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 4 plies. Latest learner event: moveStaged. Legal learner moves: 33. Legal learner captures: 1. Attacked learner pieces: pawn on e4. Selected piece: piece:white:bishop:c4. Tentative move: c4f7; legal: true. Forcing immediate replies: 1.

**Purpose:** Help the learner assess whether a capture is available and what the opponent can do next.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response treats recaptures and exchanges accurately without revealing more than needed.

**Severe-failure criteria:** The response invents a capture, overlooks an encoded recapture, or calls a losing capture safe.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[["c4", "f7"], ["e8", "f7"]].

**Response one:** “Does this bishop capture leave the bishop safe from Black's king?”

**Response one controls:** actions=[]; focus=[{"from": "c4", "to": "f7", "type": "move"}]; expects="judgeMoveSafety".

**Response two:** “After this bishop capture, Black's king can take your bishop. Does the capture still look safe?”

**Response two controls:** actions=[]; focus=[{"from": "c4", "to": "f7", "type": "move"}]; expects="judgeMoveSafety".

**Reference preference:** responseOne

**Rationale:** Both address the unsafe capture accurately, but response one prompts discovery while response two reveals the recapture.

## Pairwise pair-07

**Source:** `s06-replace-move-03`; group=`s06-replace-move`; step=3; split=development; category=tentativeMove; requestKind=followUp.

**Request SHA-256:** `748c45853832ffbe91eb082b8e647ce981118662bacc88fbc887ababf4f1ca57`

**FEN:** `rnbqkbnr/ppp1p1pp/5p2/3pN3/8/8/PPPPPPPP/RNBQKB1R w KQkq - 0 3`

**Move history:** Nf3 d5 Ne5 f6

**Latest interaction:** moveReplaced; references=["move:e5-f3"].

**Staged move:** e5f3 (Nf3; special=none; legal=true)

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 4 plies. Latest learner event: moveReplaced. Legal learner moves: 27. Legal learner captures: 0. Attacked learner pieces: knight on e5. Selected piece: piece:white:knight:e5. Tentative move: e5f3; legal: true. Forcing immediate replies: 0.

**Purpose:** Respond to the currently staged move and help the learner evaluate it before committing.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response follows the latest move and gives one answerable next step.

**Severe-failure criteria:** The response discusses a superseded move or approves a move contradicted by an immediate reply.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[["e5", "f3"]].

**Response one:** “You changed to the knight move. Does this new move look safe?”

**Response one controls:** actions=[]; focus=[{"from": "e5", "to": "f3", "type": "move"}]; expects="judgeMoveSafety".

**Response two:** “Your earlier pawn move looks safe. Would you like to play it?”

**Response two controls:** actions=[]; focus=[]; expects="chooseWhetherToPlay".

**Reference preference:** responseOne

**Rationale:** Response one follows the latest replacement; response two mixes in the obsolete pawn stage.

## Pairwise pair-08

**Source:** `s07-inspect-reply-03`; group=`s07-inspect-reply`; step=3; split=development; category=tentativeMove; requestKind=followUp.

**Request SHA-256:** `d03c87f1e8ed7d31fa49b036402dd2f7562c419845893e6ff65d4be11658cedc`

**FEN:** `rnb1kbnr/pppp1ppp/5q2/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3`

**Move history:** e4 e5 Nf3 Qf6

**Latest interaction:** squareInspected; references=["piece:black:queen:f6"].

**Staged move:** d2d3 (d3; special=none; legal=true)

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 4 plies. Latest learner event: squareInspected. Legal learner moves: 27. Legal learner captures: 1. Attacked learner pieces: knight on f3. Selected piece: piece:white:pawn:d2. Tentative move: d2d3; legal: true. Forcing immediate replies: 2.

**Purpose:** Respond to the currently staged move and help the learner evaluate it before committing.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response follows the latest move and gives one answerable next step.

**Severe-failure criteria:** The response discusses a superseded move or approves a move contradicted by an immediate reply.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[["d2", "d3"], ["f6", "f3"]].

**Response one:** “Look again at the queen you tapped. Does your pawn move still look safe?”

**Response one controls:** actions=[]; focus=[{"square": "f6", "type": "square"}]; expects="judgeMoveSafety".

**Response two:** “The queen can take your knight. Does your pawn move still look safe?”

**Response two controls:** actions=[]; focus=[{"square": "f6", "type": "square"}]; expects="judgeMoveSafety".

**Reference preference:** responseOne

**Rationale:** Both are accurate and responsive, but response one is preferred because it uses the learner's inspection without revealing the reply.

## Pairwise pair-09

**Source:** `c06-en-passant`; group=`c06-en-passant`; step=1; split=development; category=specialRule; requestKind=initial.

**Request SHA-256:** `2a91b99f33a8b8ed6bb1259f2cfa477462e3f0ebf01a95a913b7d78cfe498153`

**FEN:** `rnbqkbnr/1pp1pppp/p7/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3`

**Move history:** e4 a6 e5 d5

**Latest interaction:** moveStaged; references=["move:e5-d6:en-passant"].

**Staged move:** e5d6 (exd6; special=en-passant; legal=true)

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 4 plies. Latest learner event: moveStaged. Legal learner moves: 31. Legal learner captures: 2. Attacked learner pieces: none. Selected piece: piece:white:pawn:e5. Tentative move: e5d6; legal: true. Forcing immediate replies: 3.

**Purpose:** Explain the relevant check, mate, castling, en-passant, or promotion consequence simply and accurately.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response handles the special rule correctly in beginner-friendly language.

**Severe-failure criteria:** The response misstates legality, check, checkmate, castling, en-passant, or promotion.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[["e5", "d6"], ["c7", "d6"], ["d8", "d6"], ["e7", "d6"]].

**Response one:** “This special capture takes the pawn beside yours. Does the capture look safe?”

**Response one controls:** actions=[]; focus=[{"from": "e5", "to": "d6", "type": "move"}]; expects="judgeMoveSafety".

**Response two:** “Here your pawn captures the pawn that just passed it. Does the move look safe?”

**Response two controls:** actions=[]; focus=[{"from": "e5", "to": "d6", "type": "move"}]; expects="judgeMoveSafety".

**Reference preference:** tie

**Rationale:** Both responses correctly and simply describe the special capture, use the current move focus, and ask the same answerable safety question.

## Pairwise pair-10

**Source:** `s08-hint-then-act-02`; group=`s08-hint-then-act`; step=2; split=development; category=interaction; requestKind=followUp.

**Request SHA-256:** `dbca335d20d7fb9a00e2021409f98e77cae03eb4d3253a3af143d07834865c46`

**FEN:** `rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1`

**Move history:** none

**Latest interaction:** actionChosen; references=["action:hint"].

**Staged move:** none

**Facts:** Side to move: white. Position status: ongoing. Committed history length: 0 plies. Latest learner event: actionChosen. Legal learner moves: 20. Legal learner captures: 0. Attacked learner pieces: none. Selected piece: none. Tentative move: none.

**Purpose:** Follow the learner's latest tap, answer, revision, or help action without repeating a resolved step.

**Acceptable alternatives:** Any concise, accurate coaching turn that preserves learner agency.

**Success criteria:** The response acknowledges the latest interaction and advances one coherent step.

**Severe-failure criteria:** The response ignores the latest event, repeats a resolved question, or offers no possible next action.

**Available UI:** actions=["hint"]; expectedResponses=["findEndangeredPiece", "findSafeCapture", "stageMove", "judgeMoveSafety", "chooseWhetherToPlay"]; allowableMoveFocus=[].

**Response one:** “Try moving something.”

**Response one controls:** actions=[]; focus=[]; expects="stageMove".

**Response two:** “Here is a hint: a knight near the middle often has more choices. Which knight could you move there?”

**Response two controls:** actions=["hint"]; focus=[]; expects="stageMove".

**Reference preference:** responseTwo

**Rationale:** Response two actually follows the Hint action with a useful idea, while response one is too vague to coach the learner.

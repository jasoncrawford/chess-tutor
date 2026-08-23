# Transcript-Driven Coaching Design

## Status and relationship to earlier designs

This design follows direct UAT of On-Demand Coaching V1 and the derived-state correction. It supplements:

- `2026-08-13-on-demand-coaching-v1-design.md`
- `2026-08-15-coaching-scaffolding-revision-design.md`
- `2026-08-16-derived-coaching-state-design.md`

The derived-state architecture remains authoritative: the current board interaction is the source of truth, pedagogical evidence is retained only while its prerequisites remain valid, and one reconciler derives the current coaching state from first principles.

This document revises the tutoring policy, advice semantics, and child-facing language. Where its transcript behavior conflicts with earlier authored copy or with the current urgency threshold, this document controls the next coaching iteration.

The design remains deterministic and offline. It does not require Stockfish, an LLM, or generated runtime prose.

## Why transcripts come first

The current architecture is mechanically coherent, but the advice still often sounds like fragments assembled from implementation categories. A feedback sentence can replace the question while the old instruction remains. The tutor can ask the child to find something and then leave an action that denies the thing it just revealed. Strategic categories such as `addsDefender` or `centralActivity` can become vague questions because the concrete source, target, and consequence are discarded before explanation.

The remedy is to make exemplary conversations the product truth. We first specify what an excellent deterministic tutor should say and do in reproducible positions. Only then do we extract the smallest semantic model that can generate those conversations.

The transcript corpus has two jobs:

1. define the intended experience in language a five-year-old can act on; and
2. expose exactly which chess facts the evaluator and explanation payload must provide.

The corpus is intentionally limited to the current on-demand Safe–Take–Wake scope. Broader position evaluation, endgame planning, game review, curriculum, and proactive alerts remain future work.

## Corpus notation

Each anchor has a FEN solely to make the board fixture reproducible. The product does not need to expose notation to the child.

Transcript turns use these fields:

- **Tutor** — the complete conversational content. It may contain a brief response to the last action followed by one current question.
- **Do** — one explicit interaction, or a short parallel list when the question genuinely accepts more than one answer form.
- **Actions** — only the buttons that are meaningful answers now.
- **Board** — coaching emphasis added to the existing ambient board guidance.

Implementation annotations use three levels:

- **Supported** — the current deterministic evaluator already knows the needed fact and the current payload substantially carries it.
- **Payload** — current analysis knows the fact, but the semantic advice or explanation context must preserve more detail.
- **Policy** — the desired behavior requires a small deterministic evaluation or tutoring-policy change.

These labels are migration notes, not user-visible confidence labels.

## Shared conversation contract

Every presentation must satisfy all of the following:

1. There is exactly one current ask.
2. A response to the child's previous action never obscures that ask.
3. The instruction states exactly how to answer the current ask.
4. Every visible action is a semantically valid answer at that moment.
5. Board emphasis depicts the same relationship named by the words.
6. Once a response or Hint reveals that an answer exists, the child is not still offered a button that asserts the answer does not exist.
7. A transition names the thing just resolved: “No piece is in danger,” not “There isn't one.”
8. A new chess term is paired immediately with a plain explanation.
9. Success copy states a verified fact. It does not imply “best,” “good,” or even “useful” unless the evaluator actually compared alternatives.
10. Changing a selection or tentative move rederives the entire presentation under the existing derived-state architecture.

The default vocabulary is:

- **attack** — a piece could take another piece on its next move;
- **threat** — an attack that creates a real consequence the opponent may need to answer;
- **take** — the physical board action;
- **capture** — introduced as the chess word for taking a piece;
- **win a piece** — emerge from the immediate exchange ahead;
- **protect** — make an unfavorable capture answerable;
- **develop** — move a knight or bishop off its starting square toward active play.

The tutor does not use `material`, `reply`, `clear plan`, `stands out`, `come into the game`, `something`, or `more useful place` without immediately grounding the phrase in a visible fact.

## Anchor index

| ID | Position | Primary decision forced by the transcript |
| --- | --- | --- |
| T1 | Starting position | Bounded opening choice, misses, Hint, source switching, preferred vs acceptable development |
| T2 | Ready to castle | Skip an obvious quiz and give a direct physical instruction |
| T3 | One endangered knight | Target → attacker → concrete resolution |
| T4 | Pawn and knight both endangered | Explain relative priority using the actual expected loss |
| T5 | Only a pawn endangered | Align Safe with the board's red danger marker |
| T6 | Undefended rook can be captured | Define a safe capture with a concrete consequence |
| T7 | Tempting pawn capture loses a bishop | Explain why an apparent capture is not safe |
| T8 | A pawn can protect another pawn | Teach protection as a concrete danger response |
| T9 | A knight can threaten a rook | Name the source and target instead of “attack something” |
| T10 | Knight trapped in the corner | Explain central activity through increased choices |
| T11 | Safe, losing, and checking opponent responses | Use one consistent opponent-piece answer rule |
| T12 | Check and unsupported endgame | Teach forced responses; admit the deterministic boundary honestly |

## T1 — Starting position

**FEN:** `rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1`

**Teaching goal:** Begin with a bounded opening choice. Preserve exploration, but distinguish a factual accomplishment from comparative move quality.

### Entry

- **Tutor:** A center pawn or knight is a simple way to start. Which would you like to move?
- **Do:** Tap one of your two center pawns or one of your knights.
- **Actions:** Hint; Stop.
- **Board:** Safe and Take are cleared; Wake is current. No coaching candidate rings appear before Hint.

### Branch: the child taps the a1 rook

- **Tutor:** Your pawn is blocking that rook. Choose a center pawn or knight.
- **Do:** Tap one of your two center pawns or one of your knights.
- **Actions:** Hint, now visually promoted; Stop.
- **Board:** The ordinary rook selection may remain, but no coach ring claims it is a candidate.

**Implementation:** **Payload.** The board can mechanically identify the first blocker, but current feedback retains only the blocked piece kind.

### Branch: the child taps the a2 pawn

- **Tutor:** That pawn can move, but it is not a center pawn. Choose a pawn in front of your king or queen, or choose a knight.
- **Do:** Tap one of those four pieces.
- **Actions:** Hint, promoted; Stop.

This replaces the generic and misleading “doesn't bring a new piece into the game.”

### Branch: the child taps Hint after either miss

- **Tutor:** Here are the four pieces you can try.
- **Do:** Tap a highlighted piece.
- **Actions:** Hint if a stronger destination clue exists; Stop.
- **Board:** Candidate rings appear on b1, d2, e2, and g1.

The prior miss response disappears even if the old ordinary selection remains current. Hint changes the conversational turn; it does not need to mutate the board selection.

### Branch: the child selects a knight

- **Tutor:** You chose a knight. Moving it off its starting square is called developing it.
- **Do:** Move the knight.
- **Actions:** Hint; Stop.
- **Board:** Ordinary legal movement markers appear for the selected knight. Coach-only opening-source rings disappear.

If the child now selects the rook, pawn, other knight, or an empty square, the presentation is exactly the presentation derived for that final selection. No history-specific rewind wording exists.

### Branch: the knight moves toward the center, such as g1–f3

The tutor first performs T11's opponent-response check. If the child correctly chooses **Looks safe**:

- **Tutor:** You developed your knight toward the center. From there it can reach more squares.
- **Do:** Choose Play this move, or try another move.
- **Actions:** Play this move; Try another move; Close help.
- **Board:** The tentative move remains visible; Hint and candidate focus are absent.

**Implementation:** **Payload.** Development and before/after mobility are already deterministically available in different evidence paths; completion needs both facts.

### Branch: the knight moves to the edge, such as b1–a3

- **Tutor:** You developed your knight. A square closer to the center would usually give it more choices.
- **Do:** Choose Play this move, or try another move.
- **Actions:** Play this move; Try another move; Close help.

The move is accepted as legal development, but the tutor does not present every developing destination as equally instructive.

**Implementation:** **Policy.** Candidate moves need at least `preferred` and `acceptable` grades. A deterministic mobility and centrality comparison is sufficient; no engine score is required.

### Branch: the child advances d2 or e2

- **Tutor:** That center pawn can help control the middle of the board.
- **Do:** Move the pawn one or two squares.
- **Actions:** Hint; Stop.

After the opponent-response check succeeds:

- **Tutor:** Your center pawn moved forward and now helps control the center.
- **Do:** Choose Play this move, or try another move.
- **Actions:** Play this move; Try another move; Close help.

## T2 — Ready to castle

**Reviewed fixture FEN:** `r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 0 1`

This tutoring fixture deliberately adds White's pawn on d3 while retaining White to move. The pawn protects e4, so the transcript isolates the castling lesson instead of letting `...Nxe4` introduce a competing immediate danger. It is an isolated teaching position, not a claimed reconstruction of a legal move sequence.

**Teaching goal:** Do not ask an open question when the answer is mechanically obvious and the useful lesson is how to perform the move.

### Entry

- **Tutor:** Your king is ready to castle.
- **Do:** Move your king two squares toward the rook.
- **Actions:** Hint; Stop.
- **Board:** Wake is current. The king may receive a quiet coach emphasis; no other candidate is revealed.

The tutor does not ask “Which piece would you move to castle?”

### Branch: the child moves the king one square

- **Tutor:** That is a king move, but it is not castling. Castling moves the king two squares toward the rook.
- **Do:** Change the king's move, or choose another piece.
- **Actions:** Hint, promoted; Stop.

### Branch: the child selects the b1 knight instead

- **Tutor:** That knight can also be developed.
- **Do:** Move the knight off its starting square.
- **Actions:** Hint; Stop.

The current selection changes the plan from castling to development because both are verified opening purposes. The tutor does not insist on its first suggestion.

### Branch: the child castles kingside

After the opponent-response check succeeds:

- **Tutor:** You castled. Your king moved toward safety, and your rook moved toward the center.
- **Do:** Choose Play this move, or try another move.
- **Actions:** Play this move; Try another move; Close help.

**Implementation:** **Supported/Payload.** The special move is known. The completion should preserve both king and rook destinations rather than returning only a generic castling concept.

## T3 — One endangered knight

**FEN:** `6k1/8/8/8/4p3/5N2/8/6K1 w - - 0 1`

Black's e4 pawn can take White's f3 knight, and White has no immediate recapture.

### Entry

- **Tutor:** One of your pieces is in danger. Which one?
- **Do:** Tap the white piece with the red danger marker.
- **Actions:** Hint; Stop.
- **Board:** Safe is current. Ambient danger markers remain the level-zero clue.

### Branch: the child taps the king

- **Tutor:** Your king is safe right now. The endangered piece has a red marker.
- **Do:** Tap the marked white piece.
- **Actions:** Hint, promoted; Stop.
- **Board:** No candidate ring appears until Hint.

### Branch: the child taps the knight

- **Tutor:** That's the knight. Which black piece is attacking it?
- **Do:** Tap the black attacker.
- **Actions:** Hint; Stop.
- **Board:** The knight retains quiet target emphasis.

### Branch: the child taps the black king

- **Tutor:** The black king is not attacking your knight.
- **Do:** Tap the black piece that attacks the knight.
- **Actions:** Hint, promoted; Stop.

### Branch: the child taps the e4 pawn

- **Tutor:** That black pawn attacks your knight. How can you make the knight safe?
- **Do:** Move the knight, protect it, or take the pawn.
- **Actions:** Hint; Stop.
- **Board:** Target and attacker remain emphasized with one connecting path.

### Branch: the child stages an unrelated king move

- **Tutor:** The pawn could still take your knight.
- **Do:** Change your move so the knight is safe.
- **Actions:** Hint, promoted; Stop.
- **Board:** The target–attacker relationship remains visible; any old hint-only candidate paths are rederived.

### Branch: the child moves the knight to a safe square

After the opponent-response check succeeds:

- **Tutor:** Your knight is out of the pawn's attack. It is safe now.
- **Do:** Choose Play this move, or try another move.
- **Actions:** Play this move; Try another move; Close help.

**Implementation:** **Supported.** The current danger evidence already has target, attacker captures, and candidate resolving moves. The copy change is primarily explanatory.

## T4 — Pawn and knight both endangered

**FEN:** `r5k1/8/8/8/4p3/P4N2/8/6K1 w - - 0 1`

Black's rook can take the a3 pawn; Black's e4 pawn can take the f3 knight. Losing the knight is the larger immediate loss.

### Entry

- **Tutor:** Two of your pieces are in danger. Which one should you help first?
- **Do:** Tap the piece whose loss would cost more.
- **Actions:** Hint; Stop.
- **Board:** Both ambient danger markers remain visible. No coach candidate ring appears yet.

### Branch: the child taps the a3 pawn

- **Tutor:** You found a threatened pawn. A knight is worth about three pawns, so losing the knight would cost more.
- **Do:** Tap the threatened knight.
- **Actions:** Hint, promoted; Stop.
- **Board:** The knight receives a quiet narrowing pulse; the pawn's ambient marker remains truthful.

The tutor no longer offers an action asserting that no endangered piece exists after explicitly naming the knight.

### Branch: the child taps the f3 knight

Continue with T3's attacker-identification and resolution conversation.

**Implementation:** **Payload.** Priority is currently ordered by estimated loss and then piece value, but feedback only carries piece kinds. The explanation payload must carry the two compared losses and the reason for the ordering. The tutor mentions piece value only when it is actually the reason supported by the position.

## T5 — Only a pawn is endangered

**FEN:** `6k1/8/1b6/8/8/4P3/8/7K w - - 0 1`

Black's b6 bishop can take White's e3 pawn without an immediate recapture. White can move the pawn out of the diagonal without exposing its king.

### Entry

- **Tutor:** One of your pawns is in danger. Can you find it?
- **Do:** Tap the white pawn with the red danger marker.
- **Actions:** Hint; Stop.
- **Board:** Safe is current, not cleared.

### Target and attacker

- **Tutor:** That's the pawn. Which black piece is attacking it?
- **Do:** Tap the black attacker.

After the bishop is tapped:

- **Tutor:** The bishop attacks your pawn along this diagonal. How can you make the pawn safe?
- **Do:** Move the pawn, protect it, or take the bishop.
- **Board:** Show the bishop–pawn relationship.

### Resolution

After e3–e4 and a successful opponent-response check:

- **Tutor:** Your pawn moved out of the bishop's path. It is safe now.
- **Do:** Choose Play this move, or try another move.
- **Actions:** Play this move; Try another move; Close help.

**Implementation:** **Policy.** Safe must not silently discard a one-pawn loss while the board displays a danger marker. For coaching, every opponent capture with positive immediate net gain is a Safe candidate. The old two-point threshold may remain as a priority tier, but not as the definition of whether danger exists.

If a marked piece is attacked but adequately protected, tapping it should produce a different factual response: “It is attacked, but it is protected. If Black takes it, you can take back.” That response requires attacker, defender, and immediate exchange evidence; it must not call the piece simply “safe.”

### Protected-only Safe variant

**FEN:** `6k1/8/5n2/8/6P1/7P/8/6K1 w - - 0 1`

Black's knight attacks the g4 pawn, but White's h3 pawn can recapture the knight. Because a red attack marker exists, Safe is not silently skipped.

- **Tutor:** The red marker means Black can take that pawn. Does the pawn need help?
- **Do:** Tap the pawn to inspect it, or choose No piece needs help.
- **Actions:** No piece needs help; Hint; Stop.

After the pawn is tapped:

- **Tutor response:** The pawn is attacked, but your other pawn protects it. If the knight takes it, your pawn can take the knight back. No piece needs help right now.
- **Next ask:** Can you safely take a black piece?
- **Do:** Make the capture, or choose No safe capture.
- **Actions:** No safe capture; Hint if a qualifying capture exists; Stop.
- **Board:** Show both the knight–pawn attack and pawn–pawn protection relationships.

If the child chooses **No piece needs help**, use the same factual response before advancing. The child is not expected to equate every red attack marker with a required retreat.

## T6 — A safe capture wins a rook

**FEN:** `k7/5r2/8/8/2B5/8/8/6K1 w - - 0 1`

White's c4 bishop can take Black's undefended f7 rook.

### Entry

- **Tutor:** Can one of your pieces safely take a black piece?
- **Do:** Make the capture, or choose No safe capture.
- **Actions:** No safe capture; Hint; Stop.
- **Board:** Take is current. No capture path appears before Hint.

“Safely” is the v1 scope: after the best immediate response currently detected, the capture still achieves its material purpose and does not leave a forced tactical failure. The app does not yet claim to evaluate deep combinations.

### Branch: the child selects a piece with no qualifying capture

- **Tutor:** That piece has no safe capture here.
- **Do:** Try another piece, or choose No safe capture.
- **Actions:** No safe capture; Hint, promoted; Stop.

### Branch: Hint

- **Tutor:** Your bishop has a safe capture.
- **Do:** Tap the highlighted white piece.
- **Board:** Ring the c4 bishop. A stronger Hint may show the c4–f7 capture path.

### Branch: bishop takes rook

After the opponent-response check succeeds:

- **Tutor:** Your bishop took a rook, and Black cannot take the bishop back.
- **Do:** Choose Play this move, or try another move.
- **Actions:** Play this move; Try another move; Close help.

**Implementation:** **Supported/Payload.** The capture estimate already knows the captured piece and immediate recapture. Completion should carry both instead of reducing the result to “wins a rook.”

## T7 — A tempting capture loses a bishop

**FEN:** `6k1/5p2/8/8/2B5/8/8/6K1 w - - 0 1`

White's c4 bishop can take the f7 pawn, but Black's king can immediately take the bishop.

### Entry

Use T6's safe-capture question.

### Branch: bishop takes pawn

- **Tutor:** Black's king could take your bishop. You would lose a bishop to take one pawn.
- **Do:** Change your move, or choose No safe capture.
- **Actions:** No safe capture; Hint if a truthful clue exists; Stop.
- **Board:** Show the hypothetical king-to-bishop recapture relationship. Do not show a generic red marker with no explanation.

### Branch: No safe capture

This fixture has no other verified v1 plan, so it proceeds to the honest fallback:

- **Tutor response:** Right—there is no safe capture here.
- **Next ask:** I do not have a confident plan for this position yet.
- **Do:** Choose a move you are considering, and I will check it with you.
- **Actions:** Stop.

The UI may render the response and new ask in one conversation area, but they remain separate semantic fields. It must never produce “Right—there isn't one. Can one of your pieces make a useful capture?”

**Implementation:** **Payload.** The current capture estimate knows the moved piece, captured piece, and immediate recapture move. The explanation payload must preserve the exchange sequence and relative values.

## T8 — Protect a pawn with another pawn

**FEN:** `6k1/8/5n2/8/6P1/8/7P/6K1 w - - 0 1`

Black's f6 knight can take White's g4 pawn. Moving h2–h3 protects the g4 pawn: if the knight takes, the h3 pawn can take the knight back.

### Entry, target, and attacker

Use T5's pawn-danger entry. After the child identifies the g4 pawn and f6 knight:

- **Tutor:** The knight attacks your pawn. How can you make the pawn safe?
- **Do:** Move the pawn, protect it, or take the knight.
- **Actions:** Hint; Stop.
- **Board:** Preserve the knight–pawn attack line.

### Branch: the child stages h2–h3

- **Tutor:** Your other pawn now protects the threatened pawn. If the knight takes it, your pawn can take the knight back.
- **Do:** Choose Play this move, or try another move.
- **Actions:** Play this move; Try another move; Close help.
- **Board:** Show the new defender relationship in addition to the ambient attack.

**Implementation:** **Policy/Payload.** This is the preferred home for the “add a defender” concept: a concrete response to a named attack. An abstract Wake question such as “Which piece could help protect another piece?” is allowed only when the advisor can name the target and explain the consequence. Otherwise it falls back rather than asking the child to search the whole board for an implementation category.

## T9 — Create a threat against a rook

**FEN:** `6k1/8/8/8/3r4/8/8/N5K1 w - - 0 1`

White's a1 knight can move to b3 or c2, where it will attack Black's d4 rook. It does not attack the rook before moving.

### Entry

- **Tutor:** Your knight can move to a square where it attacks Black's rook. Can you find the square?
- **Do:** Move the knight so it attacks the rook.
- **Actions:** Hint; Stop.
- **Board:** Wake is current. Quietly emphasize the source knight and target rook; do not reveal a destination before Hint.

The tutor does not ask “Which piece could safely attack something?” because the evaluator already knows both the source and target.

### Branch: Hint

- **Tutor:** Both highlighted squares let the knight attack the rook.
- **Do:** Move the knight to one of the highlighted squares.
- **Board:** Highlight b3 and c2. A stronger clue may show the future knight-to-rook attack relationship.

### Branch: knight moves to b3 or c2

After the opponent-response check succeeds:

- **Tutor:** Your knight now attacks the rook. Black may need to move or protect it.
- **Do:** Choose Play this move, or try another move.
- **Actions:** Play this move; Try another move; Close help.
- **Board:** Show the knight–rook attack relationship in completion.

**Implementation:** **Payload.** Current threat evidence has source and target, but the current explanation collapses it to “creates a threat.” Preserve and name both pieces.

## T10 — Give a corner knight more choices

**FEN:** `6k1/8/8/8/8/8/8/N5K1 w - - 0 1`

The a1 knight has two legal destinations. On b3 or c2 it has six potential destinations in this fixture.

### Entry

- **Tutor:** Your knight has very few choices in the corner. Can you move it closer to the center?
- **Do:** Move the knight.
- **Actions:** Hint; Stop.
- **Board:** Wake is current. The knight is the named source; ordinary movement markers appear when selected.

### Branch: completion

After the opponent-response check succeeds:

- **Tutor:** From there your knight can reach six squares instead of two. That is why knights are often stronger near the center.
- **Do:** Choose Play this move, or try another move.
- **Actions:** Play this move; Try another move; Close help.

**Implementation:** **Supported/Payload.** The central-activity evidence already carries before/after mobility counts. The explanation must use those facts rather than the circular “more useful place near the center.”

This heuristic supports a factual lesson about mobility. It does not prove that the move is strategically best, and the tutor must not claim that it does.

## T11 — Check the opponent's next move

All T11 fixtures show White considering a move, so the authored example says Black. Production copy substitutes the actual opponent color.

The opponent-response interaction uses one consistent answer category:

- **Tutor:** What could Black do after your move?
- **Do:** Tap a black piece that could check your king or take one of your pieces. Otherwise choose Looks safe.
- **Actions:** Looks safe; Hint; Stop.
- **Board:** No hypothetical reply path appears before Hint. Existing tentative-position danger/check markers remain visible when truthful.

The child always taps the opponent's responding piece. The tutor no longer asks for an opponent piece in the check case but a learner target in the capture case.

### T11A — Safe opening move

**Position:** Starting position with tentative g1–f3.

If the child chooses **Looks safe**:

- **Tutor:** Black cannot immediately check your king or win one of your pieces after this move. You developed your knight toward the center.
- **Do:** Choose Play this move, or try another move.
- **Actions:** Play this move; Try another move; Close help.

The factual safety statement is bounded to the deterministic immediate-response scan.

### T11B — Queen exposed to a rook

**FEN before tentative move:** `3r2k1/8/8/8/8/8/8/3Q2K1 w - - 0 1`
**Tentative move:** d1–d4.

If the child taps the d8 rook:

- **Tutor:** Black's rook could take your queen.
- **Do:** Change your move so the queen is safe.
- **Actions:** Hint; Stop.
- **Board:** Show the hypothetical rook-to-queen capture path.

If the child incorrectly chooses **Looks safe**:

- **Tutor:** Black's rook could take your queen.
- **Do:** Tap the black rook, or choose Hint.
- **Actions:** Hint, promoted; Stop.
- **Board:** Do not reveal the full reply relationship until Hint; a response pulse may use the current black rook square.

### T11C — A harmless check exists

**FEN before tentative move:** `r5k1/8/8/8/8/8/8/1N4K1 w - - 0 1`
**Tentative move:** b1–c3. Black can answer with Ra1+; White has legal responses.

If the child taps the a8 rook:

- **Tutor:** That rook could move down to your back row and check your king. You could answer the check, so your knight move still works.
- **Do:** Choose Play this move, or try another move.
- **Actions:** Play this move; Try another move; Close help.
- **Board:** Show the hypothetical rook path only after the answer or Hint.

**Implementation:** **Policy/Payload.** Reply evidence must carry the black source, destination, affected white target, and issue severity. Material-loss answer squares currently favor the white target, producing two different tap grammars. Preserve the full relation and accept the black source consistently. The current harmless-check severity can remain, but the copy must explain why the move is still acceptable.

## T12 — Forced check and an unsupported endgame

### T12A — White is in check

**FEN:** `k3r3/8/8/1B6/8/8/8/4K3 w - - 0 1`

Black's e8 rook checks White's e1 king. White's b5 bishop can capture the rook or block on e2; the king also has legal escape squares.

#### Entry

- **Tutor:** Your king is in check. Which black piece is checking it?
- **Do:** Tap the checking piece.
- **Actions:** Hint; Stop.
- **Board:** The ordinary check marker remains visible.

#### Rook identified

- **Tutor:** The rook is checking your king along this straight line. How can you stop the check?
- **Do:** Move the king, block the rook, or take the rook.
- **Actions:** Hint; Stop.
- **Board:** Preserve the rook–king line.

#### Resolution by capture

- **Tutor:** Your bishop took the checking rook. Your king is safe.
- **Do:** Choose Play this move, or try another move.

#### Resolution by block

- **Tutor:** Your bishop blocked the rook's path. Your king is safe.
- **Do:** Choose Play this move, or try another move.

#### Resolution by king move

- **Tutor:** Your king moved out of the rook's line. It is safe.
- **Do:** Choose Play this move, or try another move.

**Implementation:** **Payload.** Current rules know the checking relationship and whether a move resolves check. Completion should derive the resolution method—move, block, or capture—rather than use one generic success sentence.

### T12B — The deterministic tutor has no confident plan

**FEN:** `7k/8/8/8/3K4/8/8/8 w - - 0 1`

This king-only endgame is deliberately outside the v1 strategic model.

- **Tutor:** I can check immediate dangers, but I do not have a confident plan for this position yet.
- **Do:** Choose a move you are considering, and I will check it with you.
- **Actions:** Stop.
- **Board:** No Safe–Take–Wake strip and no invented candidate emphasis.

After a safe tentative move:

- **Tutor:** I do not see an immediate check or lost piece after this move.
- **Do:** Choose Play this move, or try another move.
- **Actions:** Play this move; Try another move; Close help.

The tutor states the boundary directly. It does not say “Nothing urgent stands out,” invent a “clear plan,” or present a move as strategically useful merely because it passed a tactical scan.

## Advice policy derived from the transcripts

### Danger and visible markers must agree

The board and tutor use related but distinct facts:

- **Attacked:** the opponent has a legal capture of the piece next move. This drives the ambient threatened marker.
- **Protected:** the learner has a legal recapture or supporting relationship shown by existing visualization.
- **Needs help:** the opponent's best immediate capture sequence has positive net value or creates a forced king-safety problem.

Safe examines every piece that needs help, including a pawn whose immediate estimated loss is one. Larger losses remain higher priority. Safe is mechanically skipped only when there is no check and no attacked learner piece to inspect. If attack markers exist but every marked piece is adequately protected, Safe asks the protected-only judgment demonstrated in T5 instead of displaying a cleared step with no explanation. A threatened but adequately protected piece is acknowledged as attacked and protected rather than called unimportant or simply safe.

Priority feedback describes the actual comparison that selected the urgent target:

- expected immediate loss when those differ;
- piece value only when it is the supported tie-breaker;
- stable square order is never explained as chess meaning.

### Captures need an explicit v1 criterion

V1 asks for a **safe capture**, not an undefined “useful capture.” A qualifying capture:

- is legal;
- resolves any current required danger;
- retains a favorable immediate material outcome after the best recapture currently detected; and
- does not allow an immediate forced tactical failure under the existing reply scan.

The copy names the moved piece, captured piece, and concrete immediate recapture when one exists. Deeper combinations remain outside v1 and are never implied.

### Constructive advice must name its object

A deterministic Wake idea is child-facing only when its evidence can produce a concrete ask:

- develop **this knight or bishop**;
- advance **this center pawn**;
- castle **this king**;
- protect **this named target** from **this named attack**;
- attack **this named enemy target** with **this named source**;
- improve **this piece's** mobility, with a before/after fact.

The tutor never asks “Which piece could protect another piece?” or “Which piece could safely attack something?” merely because an internal opportunity enum exists. If no concrete object survives into advice, use the honest fallback.

Protection is normally taught inside Safe as one of three ways to answer a concrete attack: move the target, protect it, or take the attacker. A quiet add-defender Wake opportunity is permitted only if the evaluator can explain what future loss or exchange the added defender changes.

### Obvious mechanical steps are instructions, not quizzes

When the teaching value lies in performing an obvious move, the tutor states the fact and gives the instruction. Castling is the canonical case. The tutor may still rederive around a different selected piece.

### Candidate moves are not merely accepted or rejected

Candidate grading has three deterministic levels:

- **Preferred:** satisfies the current purpose and compares favorably under the purpose's simple evidence, such as centrality and mobility for opening knight development.
- **Acceptable:** satisfies the stated purpose and remains tactically safe, but is not the preferred expression of the idea.
- **Rejected:** fails the stated purpose, leaves the required danger, or permits a severe immediate response.

Completion wording follows the grade. Both preferred and acceptable moves may be played; only preferred moves receive the stronger purpose explanation. No grade claims an engine-best move.

V1 assigns `preferred` only where a transcript defines a concrete comparison, initially the opening knight's centrality and mobility. Other verified purpose moves remain `acceptable` unless equally explicit evidence supports an ordering. The absence of a grade comparison never becomes an invented preference.

## Presentation semantics derived from the transcripts

The current `headline` field is overloaded: it is sometimes a question, sometimes feedback, sometimes a transition, and sometimes completion. The next semantic presentation should separate:

```swift
struct CoachingConversationTurn: Equatable, Sendable {
    let response: CoachingUtterance?
    let ask: CoachingUtterance
    let instruction: CoachingInstruction?
    let actions: [CoachingActionPresentation]
    let focus: CoachFocusPresentation
}
```

The names are illustrative; the design requires the semantics, not these exact Swift declarations.

- `response` describes the immediately preceding child action and is anchored to that action.
- `ask` is the one current question, factual task, or completion statement.
- `instruction` defines the allowed interaction grammar.
- actions and focus are derived from the same ask.

Choosing Hint replaces a stale miss response with the hinted ask/instruction even if the same invalid ordinary selection remains on the board. Changing the board selection rederives response, ask, instruction, actions, and focus from the new authoritative snapshot.

Transitions such as Safe → Take may contain a response and a new ask:

> **Response:** None of your pieces is in danger.
> **Ask:** Can you safely take a black piece?
> **Instruction:** Make the capture, or choose No safe capture.

They are never concatenated through an ambiguous pronoun.

## Evidence model derived from the transcripts

The deterministic advice boundary should preserve facts rather than prewritten prose. The minimum evidence families are:

### Relationships

- attack: attacker, target, capture move, attacker color;
- protection: defender, target, newly created support, changed exchange consequence;
- check: checking source, king target, line or jump relationship;
- blocker: blocked source, concrete blocker, blocked direction;
- opponent response: opponent source, destination, affected learner target, consequence, severity.

### Consequences

- moved and captured piece kinds;
- immediate recapture move when present;
- expected immediate net loss or gain;
- whether danger remains after the tentative move;
- whether a check response exists;
- check-resolution method: king move, block, or capture.

### Purpose measurements

- development source and destination;
- before/after mobility;
- before/after center relationship;
- center-pawn control fact;
- castling king and rook moves;
- threatened target created by a move;
- candidate grade and the measurement supporting that grade.

The explainer may phrase these facts, but it may not infer missing chess relationships from piece names alone.

## Interaction and action vocabulary

Visible actions describe their exact consequence:

- `No piece needs help` — claim absence only when the current Safe question has not already stated that an answer exists;
- `No safe capture` — claim absence during a Take scan;
- `Looks safe` — claim absence of a qualifying opponent response;
- `Hint` — reveal one truthful semantic clue;
- `Play this move` — commit the current tentative move;
- `Try another move` — keep coaching active and return to move exploration;
- `Close help` — stop coaching without implying that the tentative move was committed.

The ordinary app may retain `Done` elsewhere. Inside coaching completion, `Done` and `Stop` are too easily confused because one commits the move and the other merely closes coaching.

Actions are not global decorations. Each belongs to the identity of the current ask and disappears when that ask changes.

If the analysis already knows and states that a piece is in danger, Hint is the way to request help finding it; an absence action is not offered. `No piece needs help` is reserved for a nontrivial scan in which attacked-but-protected pieces make the absence judgment worth practicing. A mechanically empty Safe scan is skipped.

## Hint policy

Hint remains optional and board-native:

1. A miss gives one factual response while preserving the current ask.
2. Hint becomes visually prominent.
3. Choosing Hint removes the miss response and advances to one truthful clue.
4. Words and focus come from the same semantic clue.
5. A question with no truthful clue has no Hint action.
6. A stronger Hint appears only when it reveals genuinely new information.

Hints narrow in this order when available:

- restate the visible marker or named relationship;
- identify candidate source pieces;
- identify candidate destinations;
- show the relevant source–target or attacker–target path.

The ladder can stop early. It never manufactures an empty level.

## Deterministic, engine, and LLM boundary

This corpus is implementable without online AI.

The deterministic layer owns:

- legal movement and captures;
- checks, attacks, defenders, blockers, and immediate recaptures;
- current Safe–Take–Wake priority;
- candidate purpose and grade;
- actions, focus, and whether a move may be accepted;
- all factual evidence placed into the conversation turn.

A future chess engine may improve candidate ranking and multi-ply consequences, but must return the same structured evidence and confidence fields.

A future LLM may rewrite or expand an already-supported explanation. It may not invent a move verdict, target, attacker, consequence, action, or board focus. Its output must validate against the structured turn, and deterministic copy remains the offline fallback.

## Golden transcript representation

Each transcript fixture should be data-driven and executable. A conceptual record contains:

```swift
struct CoachingGoldenStep {
    let board: GameState
    let interaction: CoachingInteractionSnapshot
    let pedagogicalEvidence: CoachingPedagogicalEvidence
    let childAction: CoachingGoldenAction?
    let expectedResponse: String?
    let expectedAsk: String
    let expectedInstruction: String?
    let expectedActions: [CoachingAction]
    let expectedFocus: CoachFocusPresentation
    let supportLevel: CoachingCorpusSupportLevel
}
```

Production code does not depend on the corpus. Tests drive real evaluator → advisor → reconciler → projector → explainer boundaries from each fixture and compare the resulting turn.

## Verification strategy

### Transcript tests

For every branch above, assert the complete response, ask, instruction, actions, and board focus. Direct and history-rich routes to the same final board/pedagogical facts must produce identical turns.

### Semantic invariants

Add corpus-wide assertions that:

- every noncompletion turn has one answerable ask;
- every instruction maps to the exposed board task or action;
- every named piece relationship exists in structured evidence;
- every named candidate set is nonempty;
- absence actions are removed after the tutor reveals an existing answer;
- miss feedback does not survive Hint;
- no response is concatenated to an unrelated ask through `one`, `it`, or `something` without an antecedent;
- completion praise does not exceed the candidate grade;
- changing a selection or tentative move produces the same turn as entering that final state directly.

### Vocabulary audit

Prohibit the known vague child-facing phrases and their structural equivalents:

- `part of this problem`
- `big danger`
- `job`
- `Tap the problem`
- `Nothing urgent stands out`
- `clear plan`
- `reply to notice`
- `win some material`
- `come into the game`
- `attack something`
- `protect another piece`
- `more useful place`

Individual words such as `threat`, `capture`, `develop`, and `center` are allowed when the same turn grounds them in a concrete piece relationship or explanation.

### Evaluator contract tests

Add focused deterministic tests for:

- a one-pawn expected loss entering Safe;
- attacked-but-protected copy receiving the actual recapture evidence;
- priority copy using the actual comparison reason;
- preferred versus acceptable opening destinations;
- castling bypassing source-identification quiz copy;
- safe and unsafe captures carrying the immediate exchange sequence;
- defender evidence naming the target and changed consequence;
- threat evidence naming source and target;
- mobility evidence carrying before/after counts;
- opponent-response evidence carrying opponent source, destination, target, and severity;
- color-mirrored T1, T3, and T11 fixtures producing equivalent learner/opponent language;
- check resolution classified as move, block, or capture.

### Simulator UAT

At standard and accessibility text sizes, exercise at least T1, T4, T7, T11B, and T12A. Verify conversational coherence, action validity, board focus, selection switching, Hint replacement, tentative-move revision, scrolling, and physical orientation.

## Implementation sequence implied by the corpus

1. Check in the golden position fixtures and transcript expectations before changing production behavior.
2. Separate response, ask, and instruction semantics while preserving the derived-state reducer.
3. Extend evidence payloads for blockers, comparisons, exchange sequences, opponent sources, and purpose measurements.
4. Align Safe with positive expected pawn loss and attacked-but-protected facts.
5. Replace abstract Wake prompts with named source/target tasks or honest fallback.
6. Add candidate grades and factual completion wording.
7. Replace generic coaching action titles with current-question actions.
8. Run every anchor through the real pipeline and complete simulator UAT.

No step requires a new workflow engine or a language model. The existing evaluator/advisor/explainer boundary remains; the values crossing it become more faithful to the exemplary conversations.

## Acceptance criteria

The transcript-driven revision is ready when:

- all twelve anchor scenarios are executable golden fixtures;
- every branch produces one coherent current ask and one explicit answer grammar;
- feedback, Hint, actions, and board focus describe the same current situation;
- Safe never appears cleared while an unaddressed positive-loss danger marker is present;
- lower-priority danger is acknowledged without being dismissed;
- captures are described through concrete pieces and immediate exchange consequences;
- every constructive plan names its source, target, or measurable benefit;
- castling and other obvious mechanical steps are taught directly rather than quizzed;
- opponent-response identification always uses the responding opponent piece;
- preferred, acceptable, and rejected moves receive appropriately bounded language;
- the unsupported fallback admits the v1 boundary without inventing strategic meaning;
- the entire system remains deterministic, offline, source-independent, and derived from authoritative board state.

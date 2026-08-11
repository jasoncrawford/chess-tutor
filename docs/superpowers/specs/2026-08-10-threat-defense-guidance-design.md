# Threat and Defense Guidance Design

## Purpose

Help beginning chess players—often young children—see the relationships that experienced players visualize without effort: where pieces can move, which pieces can capture one another, which pieces are in danger, and which pieces have support.

This guidance is a set of training wheels for live play. It should be proactive enough to reduce confusion while remaining quiet enough that the board still feels like a physical chessboard rather than an analysis dashboard. The app will start with the training wheels fully on. Deciding when or how a learner should remove individual kinds of guidance is intentionally deferred.

## Goals

- Make immediate danger visible without requiring a tap.
- Make friendly support visible without filling the board with lines.
- Let a player inspect either side symmetrically.
- Show the consequences of a tentative move before the player presses **Done**.
- Provide an explicit whole-board view of both sides' reach.
- Preserve the existing distinction between how a piece is allowed to move and whether a move is safe to commit under check rules.
- Keep all chess reasoning in pure Core model code and all live-game presentation state in `GameSession`.

## Non-goals

- The live board will not grade moves, recommend a best move, explain exchanges, or become a post-game review surface.
- A shield will not claim that a piece is safe or that an exchange is favorable.
- This work will not add automatic mastery detection, progressive fading, or a curriculum for removing assistance.
- This work will not show every relationship as an arrow or add a permanent roster of threatened pieces beside the board.
- Guidance will not remain active after a game has ended.

## Chosen Approach: A Layered Scaffold

Guidance has four layers, each adding detail only when the player asks for or creates the relevant context.

1. **Resting board:** Show a small, quiet danger badge over the readable foot of every legally capturable piece, on both sides. Defense markers remain hidden until they are relevant to a selection.
2. **Piece inspection:** Tapping either side's piece reveals that piece's outward movement and capture paths, its legal attackers, and its legal supporters. Danger markers on the selected piece and its legal capture targets expand to full size. A shield appears only when the selected piece or one of those legal capture targets is defended.
3. **Tentative move:** After a piece is moved but before **Done**, analyze the displayed tentative position and automatically inspect the moved piece. This answers “did I just put it in danger?” before the move is committed.
4. **Coverage lens:** A button in the selected-piece panel switches the board into a persistent, dedicated coverage map that summarizes both sides' reach through quiet square-surface states rather than repeated symbols or whole-board arrows.

This layered approach is preferred to two alternatives:

- A continuously annotated board would expose everything proactively, but simultaneous movement, attack, and defense arrows became visually noisy even in simple mock positions.
- Separate on-demand learning modes would keep the resting board quiet, but a beginner would have to know which question to ask before receiving help. That conflicts with the training-wheels goal.

## Chess Semantics

The presentation intentionally distinguishes broad movement guidance from claims about immediate danger and support.

### Allowed reach

Allowed reach describes the destinations or controlled squares arising from a piece's movement pattern and the current board occupancy. It is the broad, instructional view already used by selection guidance. It may include a move that cannot ultimately be committed because it would leave that side's king in check.

For the coverage lens, allowed reach includes:

- reachable empty squares;
- enemy-occupied capture squares;
- friendly-occupied squares its movement pattern controls;
- a legal castling destination;
- a current en passant landing square.

It does not pass through blocking pieces and does not treat a pawn's forward move as an attack.

### Legal capture and danger

A non-king piece receives a danger marker when at least one opposing piece could legally capture it in the displayed position. King safety is part of this claim: a geometrically aligned attacker that cannot make the capture because it is pinned does not create danger. A king receives the same marker when Core reports that it is in check; chess never models the king as an ordinary capture target.

Analysis can be requested for either color without changing `GameState.sideToMove`. The color being analyzed is treated as the prospective mover for ordinary king-safety evaluation. Position-bound transient rights still apply only to the side entitled to use them; notably, en passant is available only to the side for which the current `enPassantTarget` is valid.

The danger marker does not estimate whether the capture is wise. A defended piece can be both shielded and in danger.

### Legal support and defense

A non-king piece qualifies as defended when at least one friendly piece legally supports its occupied square: if that square held an opposing capturable piece instead, the supporter could capture it without exposing its own king. The Core rules API must supply this relationship directly; `PositionAnalyzer` must not recreate piece geometry to infer it. This fact is always available to presentation and accessibility, but a shield is drawn only when the defended piece is relevant to the current selection.

A pinned piece counts as a supporter only when the corresponding capture would remain legal. A piece that is merely geometrically aimed at the square but legally unable to capture does not confer a shield.

Kings do not receive shield markers. This keeps check communication unambiguous and avoids teaching that a king may safely rely on an ordinary recapture relationship.

## Interaction Design

### Resting board

Both colors receive the same ambient treatment:

- Every threatened piece has a small, quiet coral-red comic burst badge overlaid in front of the lower part of its silhouette, at its readable foot.
- Defended pieces do not show shields without a relevant selection.

The danger badges are present by default while a game is in progress. They do not pulse continuously. A status change may briefly appear, then settles into a static marker.

### Symmetric piece inspection

Tapping a piece always makes it the subject of inspection, regardless of color.

When the player taps one of the side-to-move pieces:

- show where that piece is allowed to move;
- show which opposing pieces it can capture;
- identify opposing pieces that can legally capture it;
- identify friendly pieces that legally support it.

When the player taps a piece belonging to the other side:

- show where that piece is allowed to move;
- identify which side-to-move pieces it can capture or threaten;
- show which side-to-move pieces can legally capture it;
- identify friendly pieces that legally support it.

The interaction is informationally symmetric but not mechanically symmetric. An opponent's piece is selectable for inspection and remains immovable. Turn ownership, local/remote seat ownership, and all existing move locks continue to govern dragging and staging.

In both cases, outward movement and capture paths show broad allowed reach. Inbound attacker connections and supporter echoes represent the stricter legal relationships defined above.

The selected piece's outward paths use the selected side's relative color: yellow for the side to move and red for the other side. Inbound attacker paths use the attacker's relative color. Friendly supporters receive a teal echo around their pieces; there are no defender arrows.

When a piece is selected, its foreground danger badge hands off to the full coral burst behind it if it is threatened. The danger badges on pieces it can legally capture make the same handoff. Other threatened pieces retain their small foreground ambient badges without an additional selected-state fade.

A larger, clearer teal shield appears in front of the readable foot of the selected piece if it is defended and on each of its legal capture targets that is defended. The ambient burst and shield deliberately share this status slot: a relevant threat uses the full burst behind the piece, freeing the foreground foot for a shield. Attackers, supporters, and unrelated pieces do not show shields unless they are also legal capture targets. Clearing the selection returns every threat to its small ambient badge and removes all shields. A relevant piece may show both a full burst and a shield without the two markers colliding.

Tapping an empty square that is not a valid destination quietly clears the selection and its guidance. It does not show an illegal-move or choose-a-piece message; those explanations are reserved for an invalid drag attempt. A valid empty-square tap still stages the move when selection hints are hidden.

### Tentative moves

After a successful drag or tap move stages a piece:

- analyze `GameSession.state`, which represents the displayed tentative position;
- keep the moved piece selected;
- refresh its allowed reach, legal attackers, supporters, danger marker, and shield;
- refresh ambient markers for every piece on the displayed board.

This state persists until the player presses **Done**, reverts the tentative move, or starts a new game. Tapping an empty square that is a valid alternative destination from the piece's original square replaces the tentative move atomically. The replacement is still evaluated as one move from the committed position, while the displayed piece animates directly from its staged square to the new destination without visiting its original square. If the tapped square is not a valid alternative destination from the original square, the tentative move reverts quietly. Starting a new drag from the staged piece first restores the committed position and its original-source guidance, then allows the same piece to be staged at a different legal destination in one gesture. Reverting restores guidance for the committed position.

### Whole-board coverage lens

The selected-piece panel gains a full-width button at its bottom. It reads **Show coverage** when closed and **Hide coverage** when open. The current panel geometry has enough vertical room for this control without adding a new sidebar or reducing the board.

Coverage shows both sides simultaneously by temporarily replacing the checkerboard with four opaque square-surface states:

- opaque warm yellow means the square is reached only by the side to move;
- opaque coral means the square is reached only by the other side;
- a diagonal yellow-and-coral split means both sides reach the square;
- an opaque neutral treatment means neither side reaches the square.

Each logical state has the same stable color on every square, independent of whether the underlying chess square is light or dark. Coverage colors never blend with, inherit luminance from, or otherwise reveal the checkerboard beneath them. This prevents the four logical states from becoming eight perceptual states. The map does not encode the number of pieces reaching a square. Yellow and coral deliberately differ in luminance as well as hue, the contested state uses split geometry, and the neither state uses a distinct neutral surface. VoiceOver continues to name the side or sides reaching each square.

Coverage is a dedicated visual mode rather than another annotation layer. The ordinary light/dark pattern disappears while the lens is open; the wooden frame, 8×8 grid boundaries, and chess pieces preserve the object's identity as a chessboard. At rest, pieces recede slightly, coordinate labels and coordinate emphasis are hidden, and trajectories, danger bursts, shields, and supporter echoes are suppressed. This lets the player read the board as a small number of connected visual regions instead of dozens of independent marks. Exact opaque surface colors, piece recession, and transition values remain view-style constants that should be tuned on the real iPad board. Per-square opacity or light/dark modulation is not allowed because it would recreate the ambiguity this treatment is intended to remove.

Coverage is deliberately persistent. Tapping pieces, inspecting the other side, starting a drag, staging a move, or reverting a move does not close it. The map recomputes for the displayed position after a piece lands. Coverage closes only when the player explicitly presses **Hide coverage**, a move is committed through local **Done** or remote play, or the game is reset/ended.

If a piece is selected while coverage is open, the map remains visible and the board remains fully playable. The selected piece and its contextual pieces regain emphasis. Its selected-piece paths, legal attackers, supporter echoes, relevant full danger bursts, and relevant shields appear above the map using their normal semantics. Unrelated pieces stay slightly recessed, and unrelated ambient danger badges and status markers remain hidden. This bounds the additional information to the question created by the selection instead of recreating the resting-board clutter.

## Visual Grammar

The board uses a small, consistent visual vocabulary:

| Meaning | Treatment |
| --- | --- |
| Legally threatened piece at rest | Small coral-red comic burst overlaid in front of the piece's readable foot |
| Threatened selected piece or legal capture target | Full coral-red comic burst behind the piece |
| Defended selected piece or legal capture target | Clear teal shield token at the piece's readable foot |
| Selected side's allowed path | Thin yellow or red trajectory, according to side |
| Legal attacker of selected piece | Thin inbound trajectory in the attacker's side color |
| Legal supporter of selected piece | Teal echo around the supporting piece |
| Side-to-move-only coverage | Opaque warm yellow square surface |
| Other-side-only coverage | Opaque coral square surface |
| Both-side coverage | Opaque, diagonally split yellow-and-coral square surface |
| Neither-side coverage | Opaque neutral square surface |

Selected trajectories sit above the board squares and coverage surfaces but below the pieces and piece markers. Prominent danger bursts sit behind pieces; compact ambient bursts, shields, and other foreground status markers sit in front. Trajectories use small arrowheads and restrained line weight. They are limited to the selected piece and its legal attackers; there are no whole-board arrows and no defender arrows.

Ordinary legal capture targets do not need an additional glowing outline when the target already has the full danger burst and a selected path terminates at it. En passant remains the exception because its landing square and captured piece occupy different squares.

All markers rotate and settle with the physical board. The small danger badge and shield share a consistent readable-foot anchor in every supported tabletop orientation. With Reduce Motion disabled, a newly relevant danger badge uses a quick scale-and-fade handoff into the full burst behind the piece; with Reduce Motion enabled, the foreground and background treatments cross-fade without traveling or scaling.

## Game-End Behavior

The finished board is not an implicit analysis or review mode.

- Coverage closes and its control becomes unavailable.
- All live-play guidance markers clear.
- Tapping a piece may update the identity information in the selected-piece panel, but it shows no movement, capture, attacker, supporter, or coverage guidance.
- Checkmate keeps the coral danger burst on the losing king as part of the checkmate message.
- Stalemate adds no board annotation.

A future review mode may deliberately restore analysis after game end, but it is outside this live-game design.

## Special Chess Cases

### Check and kings

The checked king uses the same coral danger burst plus the existing check/checkmate message. Do not add a second check-specific board overlay. Suppress shields on kings in every position.

### Pins

A pinned piece's allowed reach may still appear in selected-piece guidance and broad coverage, preserving the app's distinction between movement shape and king-safe commitment. The same pinned piece does not create a danger marker, attacker connection, or shield relationship for a capture it could not legally make.

### En passant

When an en passant landing is part of broad allowed reach, selected movement and coverage identify the empty landing square. When the en passant capture is also legal under king-safety rules:

- the pawn that would be removed receives a danger burst;
- inspection preserves the relationship between the landing square and the distinct captured-pawn square.

This requires a canonical Core representation of a move's captured square rather than presentation code assuming every capture occurs on `move.to`.

### Castling

A legal castling destination may appear in selected allowed movement and broad coverage. Castling never counts as an attack or support relationship.

### Promotion

Before a promotion choice, guidance follows the pawn and the proposed promotion destination. After the player chooses a piece and the move is staged, analysis uses the staged promoted piece.

### Remote games

During an opponent's remote turn, local dragging remains locked, but read-only piece inspection and the coverage lens remain available. Guidance is computed from the latest displayed local snapshot. Coverage visibility and selection emphasis are local presentation state and are neither persisted to nor transmitted through remote play.

## Accessibility

- Coverage uses distinct luminance, a neutral neither-state, and contested-square split geometry in addition to yellow and coral hue.
- VoiceOver identifies piece color, kind, and square, then states whether the piece is threatened and/or defended.
- When coverage is visible, square accessibility descriptions identify which side or sides reach each square.
- The coverage button exposes its expanded/collapsed state and has a comfortable touch target.
- Danger and defense changes do not rely on animation.
- Piece markers remain legible at every supported board rotation and do not obscure the piece silhouette needed for recognition.

## Architecture

### `LegalMoveGenerator`: sole rules authority

Extend the existing pure Core rules surface so it can answer the required questions for either color without mutating the game state. It remains the only implementation of:

- piece movement geometry;
- pawn movement and capture direction;
- blocking and sliding paths;
- raw attack/control squares;
- allowed moves;
- king-safety filtering and legal captures;
- castling, en passant, and promotion behavior;
- canonical capture resolution, including the captured square and piece.

The present `allowedMoves(for:in:)` and `legalMoves(for:in:)` gate work to `state.sideToMove`, and the attack primitives are private. The implementation should generalize the Core API so callers can analyze a specified color while preserving the existing turn-scoped convenience methods used for actual play.

### `PositionAnalyzer`: aggregation only

Introduce a pure `PositionAnalyzer` that computes reusable facts for one displayed `GameState`. It indexes and reverses facts returned by `LegalMoveGenerator`, such as:

- allowed reach by source piece and by color;
- legal capture targets by source piece;
- legal attackers by occupied target square;
- legal supporters by occupied friendly square;
- union coverage squares for each color.

`PositionAnalyzer` must contain no `switch` over `Piece.Kind`, movement deltas, sliding loops, pawn direction logic, check/pin logic, or special-move rules. It makes no independent legality decisions. If an analyzer result would require knowing how a chess piece moves, the needed primitive belongs in `LegalMoveGenerator`.

This boundary prevents the threat/defense feature from creating a second chess engine with subtly different answers.

### `GameSession`: presentation projection and interaction state

`GameSession` owns the user-facing state machine:

- current selection and whether it is actionable or inspection-only;
- whether coverage is visible;
- analysis cached for the displayed committed or tentative state;
- projection of analysis into a `BoardGuidancePresentation` value;
- closure of coverage on **Done**, reset, or game end;
- suppression of move guidance after game end.

`BoardGuidancePresentation` provides SwiftUI-ready sets and connections for ambient markers, selected trajectories, attacker emphasis, supporter echoes, and the two existing coverage sets. In particular, it derives a prominent-threat set containing a threatened selected piece and the selected piece's legal capture targets, plus a visible-defense set containing defended members of that same relevant group. These are presentation projections of existing analysis facts; they add no chess-rule logic. Read-only inspection and move validation remain separate: guidance may describe either color, while the session's actionable-move state continues to govern what the player may stage.

### `ChessBoardView`: rendering and interaction only

`ChessBoardView` consumes `BoardGuidancePresentation`, draws its layers, and forwards taps and drags to `GameSession`. It does not query the move generator, infer captures, determine pins, or derive support from board geometry.

The dedicated coverage-map experiment is purely a view-level rendering change. SwiftUI derives each square's visual state from the two coverage sets already present in `BoardGuidancePresentation`, replaces the pip layer with square surfaces, and adjusts coordinate, piece, and marker emphasis while coverage is visible. It does not change `PositionAnalyzer`, `BoardGuidancePresentation`, `GameSession`, coverage semantics, persistence, or accessibility facts.

### Canonical capture resolution

Capture resolution currently appears in several forms: `GameState` applies en passant, `GameSession.capturedPiece(for:in:)` independently identifies the captured piece, and move-history formatting decides whether a move is a capture. As part of this feature, Core should expose a single canonical captured-square/captured-piece result for a move. The session, analyzer, capture tray, and notation/history code should use that answer.

### Data flow

```text
Displayed GameState
        |
        v
LegalMoveGenerator  (all chess rules and per-piece facts)
        |
        v
PositionAnalyzer    (indexes and aggregates facts)
        |
        v
GameSession         (selection, coverage state, presentation projection)
        |
        v
BoardGuidancePresentation
        |
        v
ChessBoardView      (layers, motion, accessibility, gestures)
```

## Recalculation and Performance

Analysis is deterministic and synchronous. Compute it once when the displayed position changes:

- initial/new/restored game;
- tentative piece landing;
- tentative move reversal;
- promotion choice;
- committed move;
- received remote position.

Selection changes and coverage show/hide reuse the cached analysis. Pointer movement during a drag does not trigger position analysis; recomputation occurs after a piece lands and the displayed state changes.

Cache only the current displayed state's analysis. Do not add background work, multi-position history, or speculative optimization unless a performance test demonstrates a need. Invalid model states, such as a position missing a king where king-safety is required, should continue to fail loudly in development. Analysis never mutates the supplied `GameState`.

## Testing and Verification

### Core rules and analysis

Add focused tests covering:

- allowed reach, legal captures, and support for every piece kind and both colors;
- multiple attackers and multiple supporters on the same piece;
- a piece that is simultaneously threatened and defended;
- pinned pieces, including the distinction between broad reach and a legally executable capture;
- checks and king shield suppression;
- en passant's separate landing and captured squares;
- castling appearing in movement/coverage but not attack/support;
- all four promotion choices in a staged position;
- analysis of either color without changing the side to move or mutating the state;
- union coverage with empty, enemy-occupied, and friendly-occupied squares;
- canonical capture resolution used consistently by game application, tray, history, and guidance.

### Session behavior

Test:

- symmetric inspection of current-side and other-side pieces;
- other-side pieces remaining immovable;
- selected-path, attacker, and supporter projection;
- small ambient danger badges remaining quiet while selected danger markers expand and restore;
- shields appearing only for a defended selected piece and defended legal capture targets;
- tentative-position analysis after landing and committed-position analysis after reversal;
- coverage remaining open through selection changes, drags, tentative landings, and reversals;
- explicit **Hide coverage**, **Done**, reset, and game end closing coverage;
- game-end suppression, checkmate king marker, and unannotated stalemate;
- read-only inspection and local-only coverage during remote waiting turns.

### Presentation and accessibility

Add stable presentation/layout tests for foreground/background layer ordering, the shared readable-foot anchor, ambient/prominent threat projection, visible-defense projection, the four view-derived coverage surface states, selected-panel control fit, orientation behavior, Reduce Motion behavior, and accessibility descriptions. Verify that resting coverage suppresses coordinate and status rendering, while selection restores only contextual paths and markers. VoiceOver continues to report threat and defense facts for every piece even when its visual marker is suppressed. Prefer value and layout assertions to fragile pixel snapshots.

Visually inspect representative board states in every supported rotation:

- a sparse position with a single danger and defense relationship;
- a dense middlegame with many small ambient danger badges and no selection shields;
- a selected piece with a threatened-and-defended target, confirming full bursts and shields remain legible together;
- all four coverage surface states in a dense position, both at rest and with a piece selected;
- a staged blunder that newly exposes the moved piece;
- checkmate, stalemate, castling, promotion, and en passant.

Add a performance test for a dense legal position and verify that one position change causes one analysis pass. Run the full iPad simulator test suite before completion. At the start of this design work, the baseline suite passed all 315 tests.

## Deferred Training-Wheel Controls

The first release starts with small ambient danger badges on by default, contextual defense visible on selection, selection guidance enabled, and coverage available on demand. It does not decide when a learner has outgrown any layer.

A later design may introduce independent manual controls or a guided reduction path. That work must preserve the separation between ambient status, selected-piece inspection, and invoked whole-board coverage instead of reducing them through one opaque difficulty switch.

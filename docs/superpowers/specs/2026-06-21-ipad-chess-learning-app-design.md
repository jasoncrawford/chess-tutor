# iPad Chess Learning App Design

## Purpose

Build an iPad-first chess app that helps a child learn through play. The MVP is a fully playable local chess game for two humans on the same iPad, with beginner guardrails that reduce confusion without turning the app into a lesson product.

The app should feel like a friendly chessboard that gently prevents mistakes and explains basic invalid interactions. Coaching, lessons, computer play, accounts, sync, and online play are later layers.

## MVP Scope

The MVP opens directly into a playable chessboard. There is no landing page, lesson menu, account flow, or setup wizard.

Included:

- Local human-vs-human chess on one iPad.
- Large touch-friendly board.
- Turn indicator.
- Legal move highlighting after selecting a piece.
- Illegal move prevention with short, calm feedback.
- Check indication.
- Move history.
- Captured pieces.
- New game, undo, and flip board controls.
- Pawn promotion choice.
- Beginner assist settings for legal move display behavior.

Excluded from MVP:

- Computer opponent.
- Strategic coaching or engine evaluation.
- Lessons, puzzles, or curriculum.
- Online multiplayer.
- Accounts or sync.
- Saved game library, except optional auto-resume if it becomes necessary for usability.

## Runtime Architecture

Use a native SwiftUI app with a pure Swift chess core.

`ChessCore` is the source of truth for chess rules. It uses value types and has no SwiftUI dependencies. It answers what the position is, which moves are legal, what happens after a move, and whether the game is over.

Core types:

- `Board`
- `Square`
- `Piece`
- `Move`
- `GameState`
- `LegalMoveGenerator`
- `GameResult`

`GameSession` sits above `ChessCore` as the observable app model. SwiftUI talks to `GameSession`, not directly to the move generator.

`GameSession` owns:

- Current `GameState`.
- Selected square.
- Legal destinations for the selected piece.
- Move history.
- Captured pieces.
- Local player seats.
- Board orientation.
- Beginner assist settings.
- Promotion state.
- User-facing move attempt results.

`Learning` is intentionally small in MVP. It contains guardrail-oriented helpers, not coaching logic. Future coaching should observe positions and moves through stable game-state APIs rather than becoming part of move execution.

## Module Layout

The initial project should be organized around these folders:

```text
ChessTutor/
  App/
  Core/
  Game/
  Learning/
  UI/
  Resources/
ChessTutorTests/
```

Suggested responsibilities:

- `App`: SwiftUI app entry point and top-level composition.
- `Core`: pure chess domain model and rule engine.
- `Game`: session state, player seats, move attempts, and app-level game flow.
- `Learning`: beginner assist settings, legal highlight policy, and future observer interfaces.
- `UI`: SwiftUI views for the board, pieces, controls, move history, promotion, and messages.
- `Resources`: piece images, sounds, colors, and other app assets.

## Extension Points

The MVP should preserve clear paths for later features:

- `PlayerSeat` starts with `.humanLocal` and can later support `.computer`.
- A future `ComputerPlayer` or `PlayerAgent` can receive a `GameState` and return a legal `Move`.
- A future `Coach` can observe moves and positions and emit explanations without changing `ChessCore`.
- A future `SavedGameStore` can persist `GameState`, preferences, and progress signals.
- FEN/PGN support can be added in `Core` or a `Notation` subfolder when persistence, sharing, or testing needs it.

## UI Design Direction

The primary screen is the chessboard. In landscape, secondary information can sit beside the board. In portrait, secondary panels can move below the board or become collapsible.

Expected UI areas:

- Board and pieces.
- Current turn.
- Captured pieces.
- Move history.
- Game controls.
- Promotion sheet.
- Short feedback message area.
- Beginner assist controls.

The interface should avoid classroom framing in MVP. It should not interrupt play with long explanations. When feedback is needed, use concise messages such as "That piece can't move there" or "Your king is in check."

## Testing Strategy

Test the chess core first. It is the highest-risk part of the app and must be reliable before UI polish matters.

Core unit tests should cover:

- Piece movement basics.
- Legal move filtering when a king would be exposed.
- Check, checkmate, and stalemate.
- Castling rules.
- En passant.
- Pawn promotion.
- Undo and move history consistency.
- FEN round trips if FEN is included early.

Game/session tests should cover:

- Selecting a piece exposes legal destinations.
- Illegal moves are rejected.
- Legal moves update turn state.
- Promotion state appears at the right time.
- Undo restores the expected state.
- Beginner assist settings affect presentation state without changing chess legality.

SwiftUI UI tests can stay light in the MVP and expand after the interaction design stabilizes.

## Build Approach

Use a small XcodeGen `project.yml` so the project can be created and maintained from the command line. Target iPad only at first.

The implementation should avoid bundling Stockfish or any engine binary in the MVP. Computer play can come later behind a player-agent abstraction.

## Open Decisions

- Final app name.
- Whether MVP needs auto-resume on launch.
- Whether pieces use SF Symbols-like simple art, custom vector assets, or rendered image assets.
- Whether move input is tap-tap only or also supports drag-and-drop in the first build.

# Coordinate Grid Guidance Design

## Purpose

Make the board coordinates readable and help beginners understand square IDs without making the live game feel like a lesson screen.

## Design

Keep rank/file labels inside the board, but move them far enough inward that the board frame no longer obscures them. Do not move labels outside the board; outside labels would make the app feel more like a diagram than a physical board.

When a square is selected, highlight the selected square's file and rank labels. Prefer a color/contrast treatment on the existing labels first, because it is quieter than adding large edge rails and easier to judge in the app. If the color-only treatment is too subtle, add compact edge accents that sit inside the frame and align with the selected file/rank.

Show the selected square ID in the selected-piece side panel while a piece is selected. The panel should use compact wording such as `e6` and `file e, rank 6`, paired with the existing selected-piece name and movement summary. The empty panel state stays unchanged.

## Architecture

Keep chess rules unchanged. Add presentation-only coordinate text to `SelectedPieceInfo` in `GameSession`, then let SwiftUI render it in `SelectedPiecePanelView`. Keep board coordinate highlighting inside `ChessBoardView`, driven only by `session.selectedSquare` and the existing `BoardViewingAngle`.

## Testing

Add unit tests for the selected-square coordinate presentation in `GameSessionTests`. Add lightweight UI/layout tests for the coordinate label style so the visual intent has coverage without screenshot fragility. Run the full iPad simulator test suite before completion.

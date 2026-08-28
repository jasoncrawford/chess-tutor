# Games Board-Rack Revision

## Purpose

Replace the generic Games `NavigationStack`/`List` with a screen that belongs to the chess app: a physical-looking rack of small game boards on the tabletop. Correct the non-responsive/ambiguous game-entry controls as part of the same revision.

## Scope

- Replace the Games screen's system navigation and list treatment.
- Present games as a responsive grid of board cards, ordered by existing last-activity rules.
- Make each card's entire visible surface a single, obvious button.
- Keep `Start a Game` as the first board-sized card and keep the existing local/remote type chooser.
- Preserve the current game library, routing, pending invitation, and remote-game lifecycle behavior.
- Add regression coverage for the library actions that drive card navigation and invitation removal.

## Visual Design

- The Games screen uses the same tabletop background, warm wood frame, and cream panel materials as the playable board.
- The wood-framed rack has a simple `Games` title inside it. There is no system navigation bar, list separator, chevron, or right-edge status treatment.
- Each card contains a static board thumbnail, a lightweight label, and status below the thumbnail:
  - local games: `Local game` and turn/finished status;
  - remote games: opponent name and turn/finished status;
  - pending boards: the relevant person and `Invitation sent` or `Invitation pending`.
- `Start a Game` is a first-class board card with a plus affordance. It is not a toolbar or list row.
- Empty state retains the Start card and uses only a quiet, short line of supporting copy.

## Interaction

- Each board card is one large button. Tapping it always opens that board; it does not expose incidental row actions.
- `Start a Game` opens the existing type chooser; choosing local creates and opens a local board, while choosing remote enters remote setup.
- Existing board controls continue to use the `Games` label-and-stack-icon control to return to this screen.
- Invitation choices remain in the board-specific dialogs. The rack itself only opens a pending board.

## Layout

- In landscape, use a generous multi-column board-card grid that makes the rack feel like a collection of physical boards.
- In portrait or compact width, reduce the column count while preserving square thumbnails and large touch targets.
- Keep the rack centered with the same wide, calm margins as the playable surface; it should not read as a full-screen settings page.

## Testing

- Retain all existing model tests.
- Add/extend pure library tests for pending-board removal and route fallback.
- Add UI-level coverage where practical for the card action bindings and `Start a Game` chooser presentation.
- Run the full `ChessTutor` simulator test suite.

## Non-goals

- Game naming, archiving, deletion, review/replay, sorting controls, and search.
- New remote invitation protocol behavior beyond preserving the approved flow.

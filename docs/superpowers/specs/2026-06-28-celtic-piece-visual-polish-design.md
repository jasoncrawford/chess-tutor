# Celtic Piece Visual Polish Design

## Purpose

Improve the visual quality of the iPad chess app while preserving the product intent: learning through play on a quiet, physical-feeling board. The current board/table direction is a reasonable foundation, but the custom SwiftUI pieces look crude and are the largest visual gap. This pass should make the pieces feel elegant, artful, and tangible before broadening into side-panel polish.

## Design Direction

The target aesthetic is a quiet wooden chess set on a warm tabletop. The app should feel crafted, tactile, and readable, without becoming a lesson hub, toy interface, or faux-realistic wood simulation.

Use the MIT-licensed Celtic set from Maurizio Monge's Chess Art project as the signature visual element. This set was chosen because its pieces have recognizable chess silhouettes, stable flat bases, elegant ornament, and enough visual presence to feel like objects resting on a board.

Primary source:

- `https://github.com/maurimo/chess-art`

License:

- MIT License, copyright Maurizio Monge.
- Include the license text and attribution in the app/repository asset notices.

## Piece Treatment

Use Celtic as configured vector artwork rather than continuing to manually draw pieces with SwiftUI shapes.

Configure the set for the app's tabletop palette:

- White pieces use a warm ivory gradient instead of pure white.
- Black pieces use a walnut-to-charcoal gradient instead of blue-black.
- Piece strokes use softened dark umber rather than pure black.
- Shadows should be subtle and should primarily come from SwiftUI presentation, so pieces remain visually consistent while dragging, settling, and moving into captured trays.
- Preserve each piece's flat base and recognizable full-piece silhouette.

The implementation should prefer deterministic vector assets exported from the configured set. Runtime recoloring or a custom SwiftUI redraw is out of scope for the first pass unless asset export proves impractical.

## UI Scope

This design pass is intentionally scoped to one visual concern at a time.

First priority:

- Replace the current crude piece rendering with the configured Celtic vector set.
- Verify the pieces in normal board play, drag state, captured trays, and promotion choices.

Second priority:

- Tune the side panels after the new pieces establish the visual weight.
- Make panels feel less like generic white cards and more like warm, shallow tabletop compartments.
- Keep the existing three-segment model: message/done, captured pieces, and new game.
- Preserve current rotation/reordering behavior.

Light-touch board/table refinements:

- Keep the green/tan board identity.
- Reduce board-frame heaviness only if the new pieces make the board feel crowded.
- Avoid visible wood grain unless later visual testing shows a subtle texture is needed.

## Candidate Approaches

### Recommended: Configured Vector Assets

Configure Celtic through the Chess Art source/configuration flow, export the 12 piece assets, add them to the app, and render them instead of `PieceIconView`'s current hand-drawn shapes.

This is the best first step because it gives real artwork, clear licensing, stable rendering, and a small implementation surface.

### Alternative: Runtime SVG Recoloring

Keep SVG source in the app and recolor at runtime.

This gives flexibility, but adds unnecessary complexity before the design is validated in the live app.

### Alternative: Redraw In SwiftUI

Use Celtic only as inspiration and recreate the set with SwiftUI paths.

This offers maximum control, but is likely to recreate the current problem: hand-authored shapes that are difficult to make elegant and consistent.

## Implementation Boundaries

Do not add coaching, lesson, review, curriculum, move-list, or setup concepts as part of this polish pass.

Do not redesign the board layout or sidebar interaction model.

Do not accept non-commercially licensed piece sets. The app may become paid, so non-commercial licenses are unsuitable.

Avoid GPL/AGPL piece sets unless there is a separate explicit decision to accept those obligations. CC BY and CC BY-SA sets were considered acceptable for evaluation, but Celtic is preferred because MIT is simpler and the visual fit is stronger.

## Verification

The implementation plan should include visual and behavioral verification:

- Build/test the app on iPad simulator.
- Capture landscape and portrait screenshots.
- Confirm the pieces are recognizable at board scale and in captured trays.
- Confirm drag, staged moves, captures, matched-geometry movement, and promotion picker still look coherent.
- Confirm license/attribution files are present in the repo.

## Open Questions For Implementation

- Whether the configured SVGs should be stored directly as app assets or converted to PDF vector assets for Xcode.
- Whether SVG shadows should be disabled entirely and replaced by SwiftUI shadows, or left very subtle in the exported artwork.
- Whether captured trays need a different piece scale once the new artwork is in place.

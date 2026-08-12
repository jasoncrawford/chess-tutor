# Consolidated Guidance Rays Design

## Goal

Reduce selected-piece trajectory noise by drawing one arrow for each continuous direction of travel instead of one overlapping arrow for every reachable square on that line.

## Scope

This is a view-only rendering change. `BoardGuidancePresentation.selectedPaths` continues to contain every semantic move, threat, capture square, color, and role. Chess rules, position analysis, session state, coverage context, accessibility facts, and piece markers remain unchanged.

## Rendering Policy

Before `GuidancePathsLayer` draws its canvas, it groups paths by:

- source square
- path role (`allowed` or `attacker`)
- piece color
- normalized board direction from source to destination

Within each group, the renderer keeps the farthest destination. Normalizing the direction turns horizontal, vertical, and diagonal destinations on the same ray into one visual path. It also naturally consolidates a pawn's one- and two-square forward moves when both are present. Knight paths and other destinations with distinct directions remain separate.

The selected farthest path retains its own capture metadata. A sliding ray that ends at a capturable piece therefore terminates at that capture destination, while the underlying presentation still contains every intermediate legal destination.

## Geometry

The arrow continues to begin clear of the source piece. Its destination inset changes from `0.30` to `0.22` cell widths, placing the tip modestly closer to the center of the final square. Arrowhead size, shaft weight, color, opacity, z-order, animation behavior, and hit-testing remain unchanged.

The consolidated renderer draws one shaft and one arrowhead per ray. It does not draw shorter overlapping shafts underneath the longest path, preventing accumulated opacity along the shared portion.

## Examples

- A rook with seven open squares to its right shows one rightward arrow ending in the farthest square.
- A queen shows at most eight outward allowed-move rays, one in each available rank, file, or diagonal direction.
- A pawn on its starting rank shows one forward arrow to the two-square destination when both forward moves are available; diagonal captures remain separate.
- Each attacker of a selected piece remains its own inbound arrow because each has a distinct source.

## Testing

View-layer tests will verify that:

- multiple same-direction paths reduce to the farthest path
- opposite and otherwise distinct directions remain separate
- different roles, colors, or sources do not merge
- capture metadata comes from the retained farthest path
- the arrow tip uses the closer destination inset

The focused guidance-style tests and the complete app test suite must pass with zero failures and zero skipped tests. The result will be built and launched in the iPad simulator for visual inspection.

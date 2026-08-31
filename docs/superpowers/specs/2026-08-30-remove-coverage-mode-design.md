# Remove Coverage Mode Design

## Goal

Remove the optional "Show coverage" mode because it is not useful in regular play. Preserve the board's existing move, capture, threat, defense, check-safety, and accessibility guidance.

## Scope

The change removes coverage as a product capability, rather than merely hiding its control. It includes:

- The selected-piece-panel coverage button and its layout/style types.
- Coverage visibility state and actions in the game session.
- Coverage board surfaces, grid, rendering policy, contextual-piece opacity, and coverage-specific accessibility labels.
- The pure-model `PositionAnalysis` coverage API and tests that exist only to assert coverage behavior.

The change does not alter inherent allowed-move indicators, normal capture indicators, ambient threats, contextual threat/defense markers, check validation, coordinates, or the turn flow.

## Interaction and Presentation

Selecting a piece continues to reveal its existing allowed-move and capture guidance. The side panel continues to describe the selected piece but has no coverage toggle. The board always uses its normal presentation: coordinate labels, ambient threats, and full piece opacity remain visible according to their existing non-coverage behavior.

## Architecture

`PositionAnalyzer` will retain only analysis needed by active guidance features: allowed moves, threats, and supporters. Coverage, which combines broad movement/control data for the optional overlay, will be deleted from the value type and its construction.

`GameSession` will no longer own coverage visibility state or expose a toggle action. `BoardGuidancePresentation`, SwiftUI board rendering, and side-panel composition will consume only the remaining active guidance data.

## Validation

Update or remove coverage-specific unit and UI tests. Keep regression coverage that demonstrates allowed move/capture indicators and threat/defense guidance still behave normally. Run the complete iPad simulator test suite before delivery.

## Non-goals

- Redesigning the selected-piece panel.
- Changing chess rules or move legality.
- Removing any threat, defense, or beginner move guidance.

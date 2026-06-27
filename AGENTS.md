# Agent Guidance

This repository is a native iPad chess learning app. Future work should preserve the product intent: learning happens through play, with quiet guardrails and a physical-board feel.

## Working Style

- Use a fresh thread and isolated worktree for each feature or bug fix.
- Start by reading the current handoff notes and any relevant docs under `docs/`.
- Keep changes scoped to one concern.
- Prefer the existing architecture and local patterns over new abstractions.
- Run the relevant tests before committing.

## Product Principles

- The main screen should be the playable experience, not a lesson hub or landing page.
- Interactions should feel tangible: pieces and controls should move, rotate, and settle in ways that respect the idea of a physical board.
- Beginner help should reduce confusion without interrupting play.
- Avoid adding coaching, review, or curriculum concepts to the live game until those modes are intentionally designed.

## Architecture Principles

- Keep chess rules in pure model code, independent from UI.
- Keep SwiftUI focused on presentation and interaction.
- Put user-facing game flow and presentation state in the session/model layer rather than duplicating rule logic in views.
- Maintain the distinction between how a piece can move and whether a move is safe to commit under check rules.

## Handoff

Read this before starting new work:

- `docs/handoff/2026-06-27-main-thread.md`


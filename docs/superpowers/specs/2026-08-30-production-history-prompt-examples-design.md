# Production-History Prompt Examples Design

Date: 2026-08-30

## Goal

Make prompt examples 02–07 production-realistic by deriving every committed position from a legal move history beginning at the standard chess starting position.

## Fixture histories

- `01-quiet-help`: remain at the starting position with `Moves: none`.
- `02-attacked-piece` and `03-selected-piece`: `Nf3 e5 g3 e4`; the black pawn on e4 attacks the white knight on f3.
- `04-replaced-tentative-move`: `e4 e5`; the learner replaces staged `h4` with tentative `Nf3`.
- `05-tactical-reply`: `e4 e5 Bc4 a6`; tentative `Bb5` permits `axb5`.
- `06-inspected-reply`: `e4 e5 Bc4 Qh4`; after tentative `Nc3`, inspecting the black queen exposes all matching critical queen replies.
- `07-answering-check`: `e4 e5 d3 Bb4+`; tentative `Bd2` answers the current check.
- `08-long-history`: preserve `e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6`.

Each committed `GameState`, FEN, and SAN history is derived by replaying the coordinate moves through `LegalMoveGenerator`; no FEN or coaching conclusion is hand-authored. Tentative moves and learner events remain separate from committed history.

## Verification and gate

Tests will require examples 02–08 to have nonempty committed histories, require exact SAN for all eight examples, replay every history to the compiled FEN, and preserve each interaction scenario. The Swift export and tokenizer-only packet will be regenerated into fresh immutable directories. No model completion, inference, scoring, or hidden-set work is permitted; the result returns to the user for prompt review.

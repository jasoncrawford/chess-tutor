# Chess Tutor

An iPad-first chess app for learning through play.

The product direction is a playable chessboard that feels calm, physical, and kid-friendly. The app should help beginners stay oriented while they play, without turning the main experience into lessons, lectures, or analysis.

## Development

Generate the Xcode project:

```bash
xcodegen generate
```

Run the test suite:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
```

## Project Notes

- Keep the chess rules independent from SwiftUI.
- Keep user-facing learning help centered on play.
- Prefer small, tested changes over broad rewrites.
- Use a fresh thread and isolated worktree for each new feature or bug fix.

For project direction and current handoff notes, start with:

- [Main thread handoff](docs/handoff/2026-06-27-main-thread.md)


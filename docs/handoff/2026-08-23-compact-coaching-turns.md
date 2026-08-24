# Compact coaching turns handoff

- Presentation order: primary → instruction → optional observation.
- Opponent quiz appears only when a legal check or capture exists.
- Purposes are bound to exact pieces and moves.
- Safe-but-unclear copy is “That move seems safe.”
- Golden corpus: 52 named real-session cases.
- Verification: focused coaching slice 359/359 passed; full suite 742/742 passed; standalone build succeeded on iPad (A16), iOS 26.5, with simulator content size restored to Large.
- Direct simulator UAT: all five routes passed end to end at Large and Accessibility Extra Large in both tall and wide compositions on the helper-locked `ChessTutor Coaching Smoke` iPad (A16), iOS 26.5. The existing `chesstutor-simtouch` helper activated the visible Help and Looks-safe controls; all chessboard selections and moves used direct XCUITest touch input. Exact text/action order, focus paths, selection and tentative-move replacement, reachability, and absence of stale opponent/purpose copy were asserted. The normal verified app remains installed on the dedicated `iPad (A16)` at content size Large.

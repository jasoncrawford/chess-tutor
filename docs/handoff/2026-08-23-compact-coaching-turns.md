# Compact coaching turns handoff

- Presentation order: primary → instruction → optional observation.
- Opponent quiz appears only when a legal check or capture exists.
- Purposes are bound to exact pieces and moves.
- Safe-but-unclear copy is “That move seems safe.”
- Golden corpus: 52 named real-session cases.
- Verification: focused coaching slice 359/359 passed; full suite 742/742 passed; standalone build succeeded on iPad (A16), iOS 26.5, with simulator content size restored to Large.
- Direct simulator UAT: all five required Large/tall routes passed. Wide Help entry could not be driven through the simulator's rotated XCUITest hit space, so wide and Accessibility Extra Large end-to-end route UAT remain an explicit gap; the permanent accessibility matrix passed all 12 static combinations across standard/Accessibility Extra Large, tall/clockwise/counterclockwise, and both compact turn shapes.

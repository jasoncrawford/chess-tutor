# Hint Marker Visibility Design

## Problem

Candidate-piece and candidate-move hints use a small, translucent violet dashed ring. The ring is drawn beneath the pieces, so a large silhouette such as a knight can cover most of it. On a dark square, the remaining violet segments do not have enough contrast and are easy to miss.

## Decision

Keep the existing circular hint vocabulary, but make candidate rings a two-stroke target:

- Increase the candidate-ring diameter from 60% to 80% of a square.
- Draw a warm-ivory (`#FFF4CF`, 98% opacity) solid under-stroke 7.2% of a square wide.
- Draw the existing blue-violet hue at 95% opacity over the keyline, dashed and 3.6% of a square wide.
- Keep the marker beneath the piece for the first iteration, preserving the physical-piece artwork.
- Keep the existing one-shot hint pulse. Reduced Motion continues to show the same static marker without pulsing.

The ivory keyline provides contrast against both board colors and both piece colors. The larger diameter leaves more of the marker visible outside broad piece silhouettes.

## Scope

This change applies only to candidate hint rings. It does not change:

- coaching logic or focus selection;
- emphasized-square rings;
- attacker, defender, or candidate relationship paths;
- board interaction or accessibility semantics.

If direct UAT still finds the ring obscured, the same two-stroke marker can be moved above the piece layer without changing its visual treatment or data model.

## Verification

- Add a style-level regression for the larger candidate diameter and contrasting keyline.
- Render and inspect candidates on light and dark squares behind representative white and black pieces, including a knight.
- Confirm the marker remains distinct from selection, danger, capture, and legal-move indicators.
- Confirm Reduced Motion produces a clear static ring.

# Knight App Icon Design

## Purpose

Add a polished iPad app icon for ChessTutor so the app has a recognizable identity on the home screen and in Xcode builds.

## Approved Direction

Use the Knight Spark direction from the visual companion. The icon should center a bold knight mark on a warm chess-inspired background, using colors that fit the existing app theme: cream, green, dark ink, wood, and a small gold accent.

## Visual Requirements

- No text in the icon.
- Strong readability at small home-screen sizes.
- Friendly and playful without feeling childish.
- Chess identity should come primarily from the knight silhouette.
- Learning identity should be subtle, limited to warmth and a small accent rather than a busy tutorial symbol.

## Implementation Requirements

- Add an asset catalog under `ChessTutor/Resources`.
- Create an `AppIcon.appiconset` with generated PNG files for the iPad app icon slots.
- Generate the PNGs from one high-resolution source so the icon scales consistently.
- Update `project.yml` so the `ChessTutor` target uses the app icon asset.
- Avoid runtime Swift code changes.

## Verification

- Regenerate the Xcode project if needed.
- Build the iOS app target for an available simulator destination.
- Confirm the generated project references the app icon asset.

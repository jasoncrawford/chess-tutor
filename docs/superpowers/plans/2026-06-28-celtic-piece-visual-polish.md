# Celtic Piece Visual Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the crude hand-drawn chess pieces with a tuned MIT-licensed Celtic vector set, then lightly polish the supporting side panels around the new visual weight.

**Architecture:** Keep chess rules and game flow unchanged. Add deterministic generated vector assets under the existing asset catalog, map `Piece` values to asset names in a tiny UI helper, and keep `PieceIconView` as the single rendering entry point used by the board, captured trays, drag state, and promotion picker. Use SwiftUI for object shadows so the same assets behave consistently in every interaction state.

**Tech Stack:** Swift 6, SwiftUI, XCTest, Xcode asset catalogs, SVG image assets, shell script for repeatable asset generation, XcodeGen project layout.

---

## File Structure

- Create: `scripts/generate_celtic_piece_assets.sh`
  - Downloads the MIT-licensed Celtic SVGs from `lichess-org/lila`, recolors them to the app palette, creates `.imageset` folders, and writes `Contents.json` files.
- Create: `ChessTutor/Resources/ThirdPartyNotices/ChessArt-MIT.txt`
  - Stores attribution and MIT license text for Maurizio Monge's Chess Art set.
- Create: `ChessTutor/UI/Board/PieceAsset.swift`
  - Maps `Piece` values to generated asset names.
- Create: `ChessTutorTests/UI/PieceAssetTests.swift`
  - Verifies every piece/color combination maps to the expected asset name.
- Modify: `ChessTutor/UI/Board/PieceIconView.swift`
  - Replace custom SwiftUI-drawn piece shapes with named vector image assets and shared object shadow treatment.
- Modify: `ChessTutor/UI/Theme/AppTheme.swift`
  - Add surface and shadow tokens for the warmer panel treatment.
- Modify: `ChessTutor/UI/Root/ContentView.swift`
  - Tune sidebar tile and captured-tray surfaces after the pieces are in place.
- Generated: `ChessTutor/Resources/Assets.xcassets/Pieces/*.imageset`
  - Twelve generated SVG image sets: white/black king, queen, rook, bishop, knight, pawn.

## Task 1: Add Repeatable Celtic Asset Generation

**Files:**
- Create: `scripts/generate_celtic_piece_assets.sh`
- Create: `ChessTutor/Resources/ThirdPartyNotices/ChessArt-MIT.txt`
- Generate: `ChessTutor/Resources/Assets.xcassets/Pieces/*.imageset`

- [ ] **Step 1: Create the asset-generation script**

Create `scripts/generate_celtic_piece_assets.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIECES_DIR="$ROOT_DIR/ChessTutor/Resources/Assets.xcassets/Pieces"
BASE_URL="https://raw.githubusercontent.com/lichess-org/lila/master/public/piece/celtic"

mkdir -p "$PIECES_DIR"

write_contents_json() {
  local asset_name="$1"
  local contents_path="$PIECES_DIR/$asset_name.imageset/Contents.json"

  cat > "$contents_path" <<JSON
{
  "images" : [
    {
      "filename" : "${asset_name}.svg",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "preserves-vector-representation" : true
  }
}
JSON
}

recolor_svg() {
  local path="$1"
  local side="$2"

  python3 - "$path" "$side" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
side = sys.argv[2]
text = path.read_text()

if side == "white":
    replacements = {
        'stop-color="#fff"': 'stop-color="#fff7e4"',
        'stop-color="#bfd3d7"': 'stop-color="#d9bd83"',
        'stroke:#000': 'stroke:#5f4428',
    }
else:
    replacements = {
        'stop-color="#7f899b"': 'stop-color="#6d5637"',
        'stop-color="#1c1c2f"': 'stop-color="#201911"',
        'stroke:#000': 'stroke:#120d08',
    }

for old, new in replacements.items():
    text = text.replace(old, new)

text = text.replace('class="base stroke-color stroke-medium"', 'class="base stroke-color stroke-medium"')
path.write_text(text)
PY
}

fetch_piece() {
  local source_name="$1"
  local asset_name="$2"
  local side="$3"
  local asset_dir="$PIECES_DIR/$asset_name.imageset"
  local svg_path="$asset_dir/$asset_name.svg"

  mkdir -p "$asset_dir"
  curl -fsSL "$BASE_URL/$source_name.svg" -o "$svg_path"
  recolor_svg "$svg_path" "$side"
  write_contents_json "$asset_name"
}

fetch_piece "wK" "PieceWhiteKing" "white"
fetch_piece "wQ" "PieceWhiteQueen" "white"
fetch_piece "wR" "PieceWhiteRook" "white"
fetch_piece "wB" "PieceWhiteBishop" "white"
fetch_piece "wN" "PieceWhiteKnight" "white"
fetch_piece "wP" "PieceWhitePawn" "white"

fetch_piece "bK" "PieceBlackKing" "black"
fetch_piece "bQ" "PieceBlackQueen" "black"
fetch_piece "bR" "PieceBlackRook" "black"
fetch_piece "bB" "PieceBlackBishop" "black"
fetch_piece "bN" "PieceBlackKnight" "black"
fetch_piece "bP" "PieceBlackPawn" "black"

echo "Generated Celtic piece assets in $PIECES_DIR"
```

- [ ] **Step 2: Make the script executable**

Run:

```bash
chmod +x scripts/generate_celtic_piece_assets.sh
```

Expected: command exits 0.

- [ ] **Step 3: Run the generator**

Run:

```bash
scripts/generate_celtic_piece_assets.sh
```

Expected: exits 0 and prints:

```text
Generated Celtic piece assets in /Users/jason/projects/chess/ChessTutor/Resources/Assets.xcassets/Pieces
```

- [ ] **Step 4: Verify all image sets exist**

Run:

```bash
find ChessTutor/Resources/Assets.xcassets/Pieces -name '*.svg' | sort
```

Expected output includes exactly these 12 files:

```text
ChessTutor/Resources/Assets.xcassets/Pieces/PieceBlackBishop.imageset/PieceBlackBishop.svg
ChessTutor/Resources/Assets.xcassets/Pieces/PieceBlackKing.imageset/PieceBlackKing.svg
ChessTutor/Resources/Assets.xcassets/Pieces/PieceBlackKnight.imageset/PieceBlackKnight.svg
ChessTutor/Resources/Assets.xcassets/Pieces/PieceBlackPawn.imageset/PieceBlackPawn.svg
ChessTutor/Resources/Assets.xcassets/Pieces/PieceBlackQueen.imageset/PieceBlackQueen.svg
ChessTutor/Resources/Assets.xcassets/Pieces/PieceBlackRook.imageset/PieceBlackRook.svg
ChessTutor/Resources/Assets.xcassets/Pieces/PieceWhiteBishop.imageset/PieceWhiteBishop.svg
ChessTutor/Resources/Assets.xcassets/Pieces/PieceWhiteKing.imageset/PieceWhiteKing.svg
ChessTutor/Resources/Assets.xcassets/Pieces/PieceWhiteKnight.imageset/PieceWhiteKnight.svg
ChessTutor/Resources/Assets.xcassets/Pieces/PieceWhitePawn.imageset/PieceWhitePawn.svg
ChessTutor/Resources/Assets.xcassets/Pieces/PieceWhiteQueen.imageset/PieceWhiteQueen.svg
ChessTutor/Resources/Assets.xcassets/Pieces/PieceWhiteRook.imageset/PieceWhiteRook.svg
```

- [ ] **Step 5: Add the third-party notice**

Create `ChessTutor/Resources/ThirdPartyNotices/ChessArt-MIT.txt`:

```text
Chess Art Celtic piece set

Source: https://github.com/maurimo/chess-art
Author: Maurizio Monge
License: MIT License

MIT License

Copyright (c) Maurizio Monge

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 6: Commit the generated assets and notice**

Run:

```bash
git add scripts/generate_celtic_piece_assets.sh ChessTutor/Resources/Assets.xcassets/Pieces ChessTutor/Resources/ThirdPartyNotices/ChessArt-MIT.txt
git commit -m "Add Celtic chess piece assets"
```

Expected: commit succeeds.

## Task 2: Add Piece-To-Asset Mapping

**Files:**
- Create: `ChessTutor/UI/Board/PieceAsset.swift`
- Create: `ChessTutorTests/UI/PieceAssetTests.swift`

- [ ] **Step 1: Write the failing mapping tests**

Create `ChessTutorTests/UI/PieceAssetTests.swift`:

```swift
import XCTest
@testable import ChessTutor

final class PieceAssetTests: XCTestCase {
    func testWhitePieceAssetNames() {
        XCTAssertEqual(Piece(kind: .king, color: .white).assetName, "PieceWhiteKing")
        XCTAssertEqual(Piece(kind: .queen, color: .white).assetName, "PieceWhiteQueen")
        XCTAssertEqual(Piece(kind: .rook, color: .white).assetName, "PieceWhiteRook")
        XCTAssertEqual(Piece(kind: .bishop, color: .white).assetName, "PieceWhiteBishop")
        XCTAssertEqual(Piece(kind: .knight, color: .white).assetName, "PieceWhiteKnight")
        XCTAssertEqual(Piece(kind: .pawn, color: .white).assetName, "PieceWhitePawn")
    }

    func testBlackPieceAssetNames() {
        XCTAssertEqual(Piece(kind: .king, color: .black).assetName, "PieceBlackKing")
        XCTAssertEqual(Piece(kind: .queen, color: .black).assetName, "PieceBlackQueen")
        XCTAssertEqual(Piece(kind: .rook, color: .black).assetName, "PieceBlackRook")
        XCTAssertEqual(Piece(kind: .bishop, color: .black).assetName, "PieceBlackBishop")
        XCTAssertEqual(Piece(kind: .knight, color: .black).assetName, "PieceBlackKnight")
        XCTAssertEqual(Piece(kind: .pawn, color: .black).assetName, "PieceBlackPawn")
    }
}
```

- [ ] **Step 2: Run tests to verify the expected failure**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/PieceAssetTests
```

Expected: fails because `Piece.assetName` does not exist.

- [ ] **Step 3: Add the mapping implementation**

Create `ChessTutor/UI/Board/PieceAsset.swift`:

```swift
extension Piece {
    var assetName: String {
        "Piece\(color.assetNameComponent)\(kind.assetNameComponent)"
    }
}

private extension PieceColor {
    var assetNameComponent: String {
        switch self {
        case .white:
            "White"
        case .black:
            "Black"
        }
    }
}

private extension Piece.Kind {
    var assetNameComponent: String {
        switch self {
        case .king:
            "King"
        case .queen:
            "Queen"
        case .rook:
            "Rook"
        case .bishop:
            "Bishop"
        case .knight:
            "Knight"
        case .pawn:
            "Pawn"
        }
    }
}
```

- [ ] **Step 4: Run the mapping tests**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/PieceAssetTests
```

Expected: tests pass.

- [ ] **Step 5: Commit the mapping**

Run:

```bash
git add ChessTutor/UI/Board/PieceAsset.swift ChessTutorTests/UI/PieceAssetTests.swift
git commit -m "Map chess pieces to Celtic assets"
```

Expected: commit succeeds.

## Task 3: Replace Hand-Drawn Piece Rendering

**Files:**
- Modify: `ChessTutor/UI/Board/PieceIconView.swift`

- [ ] **Step 1: Replace `PieceIconView` with asset rendering**

Replace the entire contents of `ChessTutor/UI/Board/PieceIconView.swift` with:

```swift
import SwiftUI

struct PieceIconView: View {
    let piece: Piece

    var body: some View {
        Image(piece.assetName)
            .resizable()
            .scaledToFit()
            .padding(.vertical, 2)
            .shadow(color: shadowColor, radius: 3, x: 0, y: 2)
            .accessibilityLabel("\(piece.color.rawValue) \(piece.kind.rawValue)")
    }

    private var shadowColor: Color {
        switch piece.color {
        case .white:
            .black.opacity(0.20)
        case .black:
            .black.opacity(0.26)
        }
    }
}
```

- [ ] **Step 2: Build the app**

Run:

```bash
xcodebuild build -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Expected: build succeeds and Xcode compiles the SVG image sets.

- [ ] **Step 3: Run the full test suite**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Expected: all tests pass.

- [ ] **Step 4: Commit the renderer swap**

Run:

```bash
git add ChessTutor/UI/Board/PieceIconView.swift
git commit -m "Render pieces with Celtic vector assets"
```

Expected: commit succeeds.

## Task 4: Verify Piece Presentation Across Existing UI States

**Files:**
- Modify only if visual verification reveals a scale issue: `ChessTutor/UI/Board/ChessBoardView.swift`
- Modify only if visual verification reveals tray scale issues: `ChessTutor/UI/Root/ContentView.swift`

- [ ] **Step 1: Launch the app in the iPad simulator**

Run:

```bash
xcodebuild build -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
open -a Simulator
xcrun simctl install booted /Users/jason/Library/Developer/Xcode/DerivedData/ChessTutor-*/Build/Products/Debug-iphonesimulator/ChessTutor.app
xcrun simctl launch booted com.example.ChessTutor
```

Expected: the app launches on the iPad simulator.

- [ ] **Step 2: Inspect board-scale pieces**

In the simulator, confirm:

- White and black pieces are recognizable at board scale.
- Every piece sits visually on its square through its flat base.
- Piece shadows are visible but not smeary.
- Legal move dots and capture rings remain readable against the new artwork.

- [ ] **Step 3: Inspect drag and staged moves**

In the simulator:

- Drag a legal piece.
- Stage a capture if possible.
- Stage a non-final move and observe the `Done` button state.

Expected:

- The dragged piece keeps the same artwork.
- The dragged piece appears slightly elevated through the existing drag shadow.
- No piece jumps, clips, or appears blurry.

- [ ] **Step 4: Inspect captured trays**

Create at least one capture and confirm:

- Captured pieces are recognizable at 28 by 28 points.
- Tentative captured pieces remain distinguishable at reduced opacity.
- The tray does not feel overcrowded after one or two captures.

- [ ] **Step 5: Inspect promotion picker**

If a promotion position is not easy to reach manually, temporarily use the app's normal play loop to advance a pawn or add a debug-only setup in the working tree, inspect the picker, then revert the debug setup before committing.

Expected:

- Promotion choices use the same Celtic artwork.
- The four promotion pieces remain readable at 56 by 56 points.
- Choice labels still fit.

- [ ] **Step 6: Apply scale-only fixes if needed**

If board pieces look too large or too small, adjust the board piece frame multiplier in `ChessTutor/UI/Board/ChessBoardView.swift` in both normal and drag rendering from:

```swift
.frame(width: side / 8 * 0.82, height: side / 8 * 0.82)
```

to:

```swift
.frame(width: side / 8 * 0.88, height: side / 8 * 0.88)
```

If captured tray pieces are unreadable, adjust `ChessTutor/UI/Root/ContentView.swift` captured tray grid from:

```swift
columns: Array(repeating: GridItem(.fixed(28), spacing: 4), count: 6),
```

to:

```swift
columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 6),
```

and from:

```swift
.frame(width: 28, height: 28)
```

to:

```swift
.frame(width: 30, height: 30)
```

- [ ] **Step 7: Re-run build and tests after any scale changes**

Run:

```bash
xcodebuild build -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Expected: build succeeds and tests pass.

- [ ] **Step 8: Commit scale fixes, if any**

If files changed, run:

```bash
git add ChessTutor/UI/Board/ChessBoardView.swift ChessTutor/UI/Root/ContentView.swift
git commit -m "Tune Celtic piece presentation"
```

Expected: commit succeeds. If no files changed, skip this commit.

## Task 5: Warm The Side Panels Around The New Pieces

**Files:**
- Modify: `ChessTutor/UI/Theme/AppTheme.swift`
- Modify: `ChessTutor/UI/Root/ContentView.swift`

- [ ] **Step 1: Add panel surface tokens**

Modify `ChessTutor/UI/Theme/AppTheme.swift` to include these tokens:

```swift
import SwiftUI

enum AppTheme {
    static let table = Color(red: 0.95, green: 0.93, blue: 0.88)
    static let panel = Color(red: 1.00, green: 0.98, blue: 0.92).opacity(0.80)
    static let panelInset = Color(red: 0.38, green: 0.28, blue: 0.17).opacity(0.08)
    static let panelStroke = Color(red: 0.35, green: 0.28, blue: 0.20).opacity(0.12)
    static let panelShadow = Color.black.opacity(0.07)
    static let ink = Color(red: 0.13, green: 0.13, blue: 0.11)
    static let mutedInk = Color(red: 0.43, green: 0.42, blue: 0.36)
    static let boardFrame = Color(red: 0.35, green: 0.28, blue: 0.20)
    static let lightSquare = Color(red: 0.91, green: 0.84, blue: 0.68)
    static let darkSquare = Color(red: 0.38, green: 0.55, blue: 0.43)
    static let selectedSquare = Color(red: 0.97, green: 0.74, blue: 0.27).opacity(0.72)
    static let legalMove = Color(red: 0.11, green: 0.39, blue: 0.66).opacity(0.38)
    static let captureMove = Color(red: 0.72, green: 0.23, blue: 0.17).opacity(0.62)
    static let check = Color(red: 0.85, green: 0.20, blue: 0.18).opacity(0.45)
    static let whitePiece = Color(red: 0.98, green: 0.94, blue: 0.84)
    static let blackPiece = Color(red: 0.17, green: 0.19, blue: 0.18)
}
```

- [ ] **Step 2: Warm the sidebar tile surface**

In `ChessTutor/UI/Root/ContentView.swift`, update the `sidebarTile(_:content:)` background from:

```swift
.background(
    RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(AppTheme.panel)
        .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
)
```

to:

```swift
.background(
    RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(AppTheme.panel)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.panelStroke, lineWidth: 1)
        }
        .shadow(color: AppTheme.panelShadow, radius: 18, y: 8)
)
```

- [ ] **Step 3: Warm the guidance background**

In `ChessTutor/UI/Root/ContentView.swift`, update the guidance background fill from:

```swift
.fill(session.guidanceText == nil ? Color.clear : Color.white.opacity(0.58))
```

to:

```swift
.fill(session.guidanceText == nil ? Color.clear : AppTheme.panelInset)
```

- [ ] **Step 4: Make captured trays feel inset**

In `ChessTutor/UI/Root/ContentView.swift`, update the captured tray background from:

```swift
RoundedRectangle(cornerRadius: 8, style: .continuous)
    .fill(AppTheme.ink.opacity(pieces.isEmpty ? 0.04 : 0.07))
```

to:

```swift
RoundedRectangle(cornerRadius: 10, style: .continuous)
    .fill(AppTheme.panelInset.opacity(pieces.isEmpty ? 0.75 : 1.0))
    .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(AppTheme.panelStroke, lineWidth: 1)
    }
```

- [ ] **Step 5: Build and visually inspect panels**

Run:

```bash
xcodebuild build -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Expected: build succeeds.

Inspect in the simulator and confirm:

- Panels feel warmer and less generic.
- Captured pieces remain legible.
- The `Done` and `New Game...` controls still fit.
- The three-segment layout still rotates/reorders correctly.

- [ ] **Step 6: Run the full test suite**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Expected: all tests pass.

- [ ] **Step 7: Commit side-panel polish**

Run:

```bash
git add ChessTutor/UI/Theme/AppTheme.swift ChessTutor/UI/Root/ContentView.swift
git commit -m "Warm chess tabletop side panels"
```

Expected: commit succeeds.

## Task 6: Final Verification And Handoff

**Files:**
- Modify if needed: `docs/handoff/2026-06-27-main-thread.md`

- [ ] **Step 1: Run final tests**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Expected: all tests pass.

- [ ] **Step 2: Capture landscape and portrait simulator screenshots**

Run:

```bash
xcrun simctl io booted screenshot /tmp/chess-celtic-landscape.png
```

Rotate the simulator to portrait, then run:

```bash
xcrun simctl io booted screenshot /tmp/chess-celtic-portrait.png
```

Expected: both screenshot files are created.

- [ ] **Step 3: Review screenshot criteria**

Confirm in both screenshots:

- Celtic pieces are the dominant quality improvement.
- Piece bases read as resting on the board.
- Side panels support the board rather than competing with it.
- Captured trays and promotion pieces remain readable.
- No visible text overlaps or clipped buttons.

- [ ] **Step 4: Update handoff if implementation lands**

If this implementation is completed in the current thread, append this entry to `docs/handoff/2026-06-27-main-thread.md` under `Recent checkpoints include:`:

```markdown
- Celtic vector piece set and warm side-panel visual polish
```

- [ ] **Step 5: Commit handoff update if changed**

If the handoff file changed, run:

```bash
git add docs/handoff/2026-06-27-main-thread.md
git commit -m "Update handoff for Celtic visual polish"
```

Expected: commit succeeds. If the handoff file did not change, skip this commit.

- [ ] **Step 6: Report final verification**

In the final response, include:

- The branch name.
- The final test command and result.
- The screenshot paths.
- The license/attribution file path.
- Any visual caveats that should be reviewed by the user.
